using System.Collections.Concurrent;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using NAudio.Dsp;
using SoundFingerprinting.Audio;

namespace AudioAdDetection;

/// <summary>
/// The resample→chunk feeder. The per-chunk RMS lands on
/// IStreamState.CurrentRmsDb (the aad_audio_rms_db gauge); the match leg
/// (RealtimeQuery) writes IStreamState.LastMatchAt / LastMatchMeta — the
/// no-match span inputs the capture state machine reads. Each completed
/// 10,240-sample chunk is fanned out to two per-consumer bounded queues
/// (the query leg and the capture leg): one PCM chunk source never feeds
/// two Take-based consumers through a single queue — a shared queue would
/// split the stream and miscalibrate the stream clock / open gapped
/// rings.
/// </summary>
public sealed class AudioPipeline : BackgroundService
{
    /// <summary>
    /// The single chunking authority: exactly this many resampled mono
    /// floats per AudioSamples @5512. The SF library never resamples (it
    /// hard-checks SampleRate == 5512) and handles FFT continuity with its
    /// own internal prefix, so the producer never re-feeds a chunk tail.
    /// </summary>
    private const int ChunkSamples = 10240;
    private const int TargetRate = 5512;
    private const int FrameBytes = 4; // a stereo s16 frame

    private readonly WorkerConfig _config;
    private readonly SnapClientSupervisor _supervisor;
    private readonly IStreamState _state;
    private readonly ILogger<AudioPipeline> _logger;

    private readonly BlockingCollection<AudioSamples> _chunks;
    private readonly BlockingCollection<AudioSamples> _captureChunks;
    private readonly WdlResampler? _resampler;
    private readonly bool _resample;

    // Frame parity is tracked across pipe reads: a blocking pipe read has
    // no message boundaries and a short read is not end-of-stream (R2 §1).
    private readonly byte[] _frameCarry = new byte[FrameBytes - 1];
    private int _frameCarryCount;
    private readonly byte[] _frameBuf = new byte[FrameBytes - 1 + 65_536];
    private readonly float[] _monoBuf = new float[65_536 / 2 + 2];

    // Feed-mode resampling: a short ResamplePrepare acceptance carries its
    // tail into the next batch; the ResampleOut loop drains the buffered
    // remainder until 0.
    private readonly float[] _monoCarry = new float[65_536 / 2 + 2];
    private int _monoCarryCount;
    private readonly float[] _resampleInput = new float[65_536 / 2 + 2];
    private readonly float[] _resampleOut = new float[65_536];

    private readonly float[] _chunk = new float[ChunkSamples];
    private int _chunkPos;

    public AudioPipeline(WorkerConfig config, SnapClientSupervisor supervisor, IStreamState state, ILogger<AudioPipeline> logger)
    {
        _config = config;
        _supervisor = supervisor;
        _state = state;
        _logger = logger;

        // Bounded: backpressure on the query queue blocks the producer, so
        // drops happen at the supervisor channel's DropOldest — never in
        // unbounded growth. The capture queue is fed non-blocking (TryAdd):
        // a stalled capture consumer must never stall the query lane.
        _chunks = new BlockingCollection<AudioSamples>(256);
        _captureChunks = new BlockingCollection<AudioSamples>(256);

        var inputRate = ParseInputRate(config);
        // The resampler is live only when the input rate is not 5512; the
        // default 5512:16:* lane is a pass-through (no resampler in the hot
        // path).
        _resample = inputRate != 5512;
        if (_resample)
        {
            // The 48k lane is the real non-5512 alternative (the snapcast
            // broadcast rate); the ruled conversion is 48k→5512 Sinc64
            // (R3 §2 — the 3.3.0 provider wrapper is IIR-only, so the
            // low-level resampler is the contract).
            _resampler = new WdlResampler();
            _resampler.SetRates(48000, 5512);
            _resampler.SetFeedMode(true);
            _resampler.SetMode(false, 0, true, 64);
            _logger.LogInformation("resampling active: input rate {InputRate} != {TargetRate} (Sinc64, feed mode)", inputRate, TargetRate);
        }
    }

    /// <summary>
    /// The query leg's 10,240-sample chunk queue. Backed by a
    /// BlockingCollection (the query leg wraps it in a
    /// BlockingRealtimeCollection), this is the hot-source contract:
    /// re-enumeration resumes at the current position and never re-takes
    /// consumed chunks. A supervisor respawn is a stream discontinuity, not
    /// an end — the queue is only completed at host shutdown, so queued
    /// chunks are never replayed across a respawn.
    /// </summary>
    public BlockingCollection<AudioSamples> Chunks => _chunks;

    /// <summary>
    /// The capture leg's 10,240-sample chunk queue (fan-out twin of
    /// <see cref="Chunks"/>; the capture state machine is its only
    /// consumer — the two legs never share a queue).
    /// </summary>
    public BlockingCollection<AudioSamples> CaptureChunks => _captureChunks;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
        try
        {
            // The supervisor channel completes only on host shutdown, so one
            // enumeration spans child respawns (R2 implication 5).
            await foreach (var read in _supervisor.AudioBytes.WithCancellation(stoppingToken))
            {
                var monoCount = DecodeToMono(read);
                if (_resample)
                    await FeedResamplerAsync(monoCount, cts.Token);
                else
                    await AppendSamplesAsync(_monoBuf, monoCount, cts.Token);
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogDebug("audio pipeline stopped");
        }
        finally
        {
            // End both queues only when the producer truly stops (host
            // shutdown): the BlockingRealtimeCollection enumerator (query
            // queue) and the capture take-loop (capture queue) end here,
            // after the query leg is already cancelled.
            _chunks.CompleteAdding();
            _captureChunks.CompleteAdding();
        }
    }

    /// <summary>
    /// Appends to the chunk accumulator and emits full chunks; the resampler
    /// path calls it per drain call so a batch whose output spans several
    /// ResampleOut invocations is never lost to buffer re-use.
    /// </summary>
    private async Task AppendSamplesAsync(float[] samples, int count, CancellationToken ct)
    {
        for (var i = 0; i < count; i++)
        {
            _chunk[_chunkPos++] = samples[i];
            if (_chunkPos == ChunkSamples)
            {
                await EmitChunkAsync(ct);
                _chunkPos = 0;
            }
        }
    }

    private async Task EmitChunkAsync(CancellationToken ct)
    {
        var rmsDb = ComputeRmsDb(_chunk);
        _state.SetRmsDb(rmsDb);
        // Clone: AudioSamples keeps the array, and _chunk is reused for the
        // next chunk. One sample feeds both queues (read-only on both
        // legs).
        var sample = new AudioSamples((float[])_chunk.Clone(), string.Empty, TargetRate);
        await _chunks.AddAsync(sample, ct);
        // Non-blocking with DropOldest: the capture leg must never stall the
        // query leg — a full capture queue sheds the oldest chunk.
        if (!_captureChunks.TryAdd(sample) && _captureChunks.TryTake(out _))
            _captureChunks.TryAdd(sample);
    }

    private static double ComputeRmsDb(float[] chunk)
    {
        var sum = 0.0;
        foreach (var s in chunk)
            sum += s * s;
        var rms = Math.Sqrt(sum / chunk.Length);
        return 20.0 * Math.Log10(Math.Max(rms, 1e-9));
    }

    /// <summary>
    /// s16le→float + stereo→mono per pipe read; the frame parity is
    /// carried across reads.
    /// </summary>
    private int DecodeToMono(byte[] read)
    {
        Buffer.BlockCopy(_frameCarry, 0, _frameBuf, 0, _frameCarryCount);
        Buffer.BlockCopy(read, 0, _frameBuf, _frameCarryCount, read.Length);
        var total = _frameCarryCount + read.Length;
        _frameCarryCount = total % FrameBytes;
        if (_frameCarryCount > 0)
            Buffer.BlockCopy(_frameBuf, total - _frameCarryCount, _frameCarry, 0, _frameCarryCount);

        var n = 0;
        for (var p = 0; p + FrameBytes <= total; p += FrameBytes)
        {
            var l = BitConverter.ToInt16LittleEndian(_frameBuf.AsSpan(p, 2));
            var r = BitConverter.ToInt16LittleEndian(_frameBuf.AsSpan(p + 2, 2));
            _monoBuf[n++] = ((l / 32768.0f) + (r / 32768.0f)) * 0.5f;
        }
        return n;
    }

    /// <summary>
    /// Feed-mode Sinc64: ResamplePrepare with the input you have, copy it
    /// into the returned buffer, then drain with ResampleOut until 0 — each
    /// call's output is consumed before the next call, so a batch whose
    /// output spans several invocations is intact. A partial acceptance
    /// carries its tail into the next batch (the library flush-pads the
    /// missing part, per its documented contract). A supervisor respawn
    /// boundary misaligns the frame stream by at most one 4-byte frame
    /// (~200 µs at 5512) — bounded and acoustically negligible, because
    /// the 4-byte cadence re-syncs immediately after.
    /// </summary>
    private async Task FeedResamplerAsync(int newCount, CancellationToken ct)
    {
        // Call site invariant: FeedResamplerAsync runs only when _resample,
        // and the constructor sets _resampler exactly then — the guard is
        // the proof for the analyzer.
        var resampler = _resampler
            ?? throw new InvalidOperationException("feed-mode resampling requested while the resampler is disabled");

        // Merge the carried tail (from a short prepare acceptance) with the
        // new batch decoded into _monoBuf.
        var total = _monoCarryCount + newCount;
        Array.Copy(_monoCarry, 0, _resampleInput, 0, _monoCarryCount);
        if (newCount > 0)
            Array.Copy(_monoBuf, 0, _resampleInput, _monoCarryCount, newCount);
        _monoCarryCount = 0;

        var accepted = resampler.ResamplePrepare(total, 1, out var inBuf);
        var feed = Math.Min(total, accepted);
        if (feed < total)
        {
            Array.Copy(_resampleInput, feed, _monoCarry, 0, total - feed);
            _monoCarryCount = total - feed;
        }
        _resampleInput.AsSpan(0, feed).CopyTo(inBuf);

        var firstCall = true;
        while (true)
        {
            // First call commits the fed input (a short feed flush-pads the
            // remainder, per the library contract); the drain calls pull
            // the buffered remainder until 0.
            var got = firstCall
                ? resampler.ResampleOut(_resampleOut, feed, _resampleOut.Length, 1)
                : resampler.ResampleOut(_resampleOut, 0, _resampleOut.Length, 1);
            if (got == 0)
                break;
            firstCall = false;
            await AppendSamplesAsync(_resampleOut, got, ct);
        }
    }

    private static int ParseInputRate(WorkerConfig config)
    {
        var rate = config.SnapSampleFormat.Split(':')[0];
        return int.TryParse(rate, out var r) ? r : TargetRate;
    }
}
