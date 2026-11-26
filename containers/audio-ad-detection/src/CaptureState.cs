using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using SoundFingerprinting.Audio;

namespace AudioAdDetection;

/// <summary>
/// The capture state machine (C02b): the exclusive consumer of
/// AudioPipeline.CaptureChunks — the producer fans each chunk out to
/// per-consumer bounded queues, and the query leg and the capture leg never
/// share a queue (a shared queue would split the stream: the query leg's
/// stream clock miscalibrates and the capture ring/span carry per-chunk
/// gaps). It turns no-match spans into candidate files on the PVC. Per chunk
/// it consumes C02a's IStreamState (LastMatchAt / LastMatchMeta / CurrentRmsDb),
/// appends the chunk to a rolling 5512 mono ring (10 s depth — 5 s pre +
/// 5 s post roll — plus 5 s margin), opens a span once the no-match stretch
/// reaches CAPTURE_MIN_SPAN_SECONDS (30 s) with CurrentRmsDb above the
/// CAPTURE_RMS_FLOOR_DB (-45 dBFS) gate, and closes it at the next confident
/// match or the CAPTURE_MAX_SPAN_SECONDS (300 s) cap. A span that dips below
/// the floor while open is discarded on close, not split. The 5 s pre-roll
/// covers the &lt;1.5 s MatchedAt edge jitter (R1 §1); the 5 s post-roll is
/// taken after a 5 s low-priority delay — the chunk loop keeps filling the
/// ring meanwhile, so the tail read at +5 s is exactly the post-close window.
/// </summary>
public sealed class CaptureMachine : BackgroundService
{
    private const int SampleRate = 5512;
    private const int RingSeconds = 10; // 5 s pre + 5 s post roll
    private const int RingMarginSeconds = 5;
    private const int RollSeconds = 5;

    private readonly WorkerConfig _config;
    private readonly AudioPipeline _pipeline;
    private readonly IStreamState _state;
    private readonly SnapClientSupervisor _supervisor;
    private readonly StreamAssigner _assigner;
    private readonly Curator _curator;
    private readonly ILogger<CaptureMachine> _logger;

    private readonly float[] _ring;
    private readonly object _ringGate = new();
    private int _ringPos;
    private long _ringTotal;

    private List<float> _spanBody = new();
    private float[]? _spanPreRoll;
    private DateTime _openAtUtc = DateTime.MinValue;
    private DateTime _noMatchSinceUtc = DateTime.MinValue;
    private DateTime? _lastSeenMatchAt;
    private bool _spanOpen;
    private bool _belowFloorMarked;

    public CaptureMachine(
        WorkerConfig config,
        AudioPipeline pipeline,
        IStreamState state,
        SnapClientSupervisor supervisor,
        StreamAssigner assigner,
        Curator curator,
        ILogger<CaptureMachine> logger)
    {
        _config = config;
        _pipeline = pipeline;
        _state = state;
        _supervisor = supervisor;
        _assigner = assigner;
        _curator = curator;
        _logger = logger;
        _ring = new float[(RingSeconds + RingMarginSeconds) * SampleRate];
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _noMatchSinceUtc = DateTime.UtcNow;
        _logger.LogInformation(
            "capture machine started (min span {MinSpan}s, max span {MaxSpan}s, rms floor {Floor} dBFS, ring {Ring}s + {Margin}s margin)",
            _config.CaptureMinSpanSeconds, _config.CaptureMaxSpanSeconds, _config.CaptureRmsFloorDb, RingSeconds, RingMarginSeconds);

        try
        {
            while (true)
            {
                // BlockingCollection has no async TryTake: the Task.Run bridge
                // blocks until an item arrives or the producer completes the
                // queue at shutdown; the WhenAny race keeps the wait
                // cancellation-aware (a still-blocked TryTake returns false at
                // CompleteAdding, which surfaces as a null here).
                var takeTask = Task.Run(() =>
                    _pipeline.CaptureChunks.TryTake(out var item) ? item : null);
                if (await Task.WhenAny(takeTask, Task.Delay(Timeout.Infinite, stoppingToken)) != takeTask)
                    throw new OperationCanceledException(stoppingToken);
                var chunk = await takeTask;
                if (chunk is null)
                    break;
                ProcessChunk(chunk, stoppingToken);
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogDebug("capture machine stopped");
        }
    }

    private void ProcessChunk(AudioSamples chunk, CancellationToken ct)
    {
        var rmsDb = _state.CurrentRmsDb;
        var matchAt = _state.LastMatchAt;
        var nowUtc = DateTime.UtcNow;

        AppendToRing(chunk.Samples);

        // A confident match (a newer LastMatchAt than the last seen value)
        // closes the open span and restarts the no-match clock.
        if (matchAt is { } m && m != _lastSeenMatchAt)
        {
            if (_spanOpen)
                CloseSpan(nowUtc, "confident match", ct);
            _noMatchSinceUtc = m;
            _lastSeenMatchAt = m;
            return;
        }

        if (_spanOpen)
        {
            // Below-floor while open: mark the discard — the span closes
            // whole (at the match or the cap), it is not split.
            if (!double.IsNaN(rmsDb) && rmsDb < _config.CaptureRmsFloorDb)
                _belowFloorMarked = true;

            _spanBody.AddRange(chunk.Samples);

            if ((nowUtc - _openAtUtc).TotalSeconds >= _config.CaptureMaxSpanSeconds)
                CloseSpan(nowUtc, "span cap", ct);
            return;
        }

        // Open gate: the no-match stretch reached the min span and the
        // per-chunk RMS is above the floor (TV-off / source-off silence sits
        // far below it and must not fill the candidate dir). The opening
        // chunk is no-match audio, so it starts the span body.
        var noMatchSeconds = (nowUtc - _noMatchSinceUtc).TotalSeconds;
        if (noMatchSeconds >= _config.CaptureMinSpanSeconds && !double.IsNaN(rmsDb) && rmsDb > _config.CaptureRmsFloorDb)
            OpenSpan(chunk);
    }

    private void OpenSpan(AudioSamples chunk)
    {
        _spanOpen = true;
        _belowFloorMarked = false;
        _spanBody.Clear();
        _spanBody.AddRange(chunk.Samples);
        _openAtUtc = DateTime.UtcNow;
        // 5 s before the span start — the pre-roll (edge-jitter cover).
        _spanPreRoll = RingTail(RollSeconds);
        _logger.LogInformation("capture span opened (no-match for the gated stretch)");
    }

    private void CloseSpan(DateTime nowUtc, string reason, CancellationToken ct)
    {
        _spanOpen = false;
        var discard = _belowFloorMarked;
        var body = _spanBody;
        var pre = _spanPreRoll;
        _spanBody = new List<float>();
        _spanPreRoll = null;

        // Non-null by construction (OpenSpan sets the pre-roll before the
        // span opens); the guard keeps the path total.
        if (pre is null)
            return;

        if (discard)
        {
            _logger.LogInformation(
                "candidate discarded (rms dipped below the {Floor} dBFS floor while the span was open — {Reason})",
                _config.CaptureRmsFloorDb, reason);
            return;
        }

        var group = GroupLeg();
        var fileName = CandidateWriter.BuildFileName(
            group, nowUtc, (pre.Length + body.Count + RollSeconds * SampleRate) / SampleRate);
        var path = Path.Combine(CandidateWriter.CandidatesDir(_config), fileName);

        // Low-priority post-processing: wait 5 s (the chunk loop keeps
        // running and filling the ring), take the post-roll tail, write the
        // candidate, bump the counter, hand the samples to the curator.
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(RollSeconds), ct);
                var post = RingTail(RollSeconds);
                var samples = Concat(pre, body, post);
                if (!CandidateWriter.TryWrite(_config, fileName, samples, out var error))
                {
                    // A failed candidate write is logged, never fatal to the
                    // query loop (C02b AC7).
                    _logger.LogWarning("candidate write failed for {Path}: {Error}", path, error);
                    return;
                }
                _supervisor.IncrementCaptureCandidates();
                _logger.LogInformation("candidate written: {Path} ({Seconds}s, {Reason})",
                    path, samples.Length / SampleRate, reason);
                _curator.EnqueueCandidateClosedAsync(samples, path, group);
            }
            catch (OperationCanceledException)
            {
                _logger.LogDebug("candidate post-processing cancelled at shutdown");
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "candidate post-processing failed (non-fatal)");
            }
        }, CancellationToken.None);
    }

    /// <summary>
    /// The naming group leg: the tapped group's name (or id), falling back
    /// to the pinned hostID until the startup assignment has learned it.
    /// </summary>
    private string GroupLeg()
    {
        var raw = _assigner.GroupRef ?? _config.SnapHostId;
        var sanitized = new string(raw.ToLowerInvariant()
            .Select(c => char.IsLetterOrDigit(c) || c is '_' or '-' ? c : '_')
            .ToArray());
        return string.IsNullOrEmpty(sanitized) ? "unknown" : sanitized;
    }

    private void AppendToRing(float[] samples)
    {
        lock (_ringGate)
        {
            foreach (var sample in samples)
            {
                _ring[_ringPos] = sample;
                _ringPos = (_ringPos + 1) % _ring.Length;
                _ringTotal++;
            }
        }
    }

    /// <summary>The ring's most recent <paramref name="seconds"/> of audio (zero-padded front while still filling).</summary>
    private float[] RingTail(int seconds)
    {
        var n = seconds * SampleRate;
        var tail = new float[n];
        lock (_ringGate)
        {
            var len = _ring.Length;
            if (_ringTotal >= n)
            {
                var start = (int)((_ringTotal - n) % len);
                var first = len - start;
                Array.Copy(_ring, start, tail, 0, Math.Min(first, n));
                if (first < n)
                    Array.Copy(_ring, 0, tail, first, n - first);
            }
            else
            {
                // Not wrapped yet: the samples sit at the head.
                var have = (int)_ringTotal;
                Array.Copy(_ring, 0, tail, n - have, have);
            }
        }
        return tail;
    }

    private static float[] Concat(float[] pre, List<float> body, float[] post)
    {
        var all = new float[pre.Length + body.Count + post.Length];
        var pos = 0;
        pre.CopyTo(all, pos);
        pos += pre.Length;
        foreach (var sample in body)
            all[pos++] = sample;
        post.CopyTo(all, pos);
        return all;
    }
}
