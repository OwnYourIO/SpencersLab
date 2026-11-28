using System.Diagnostics;
using System.Threading.Channels;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace AudioAdDetection;

/// <summary>
/// Launches and supervises the snapclient file-player child. stdout is the
/// 5512/16/stereo PCM pipe (the file player is a recorder: 50 ms ticks,
/// silence-on-underrun — R2 §1); stderr is drained on a background thread
/// and a byte-cadence watchdog catches the #1563 hang (the process stays
/// alive at 100% CPU while the server still shows connected — R2 §2).
/// </summary>
public sealed class SnapClientSupervisor : BackgroundService
{
    // startup grace: 15 s (the ruled 10-30 s window: connect + hello +
    // ServerSettings + CodecHeader land before the first 50 ms tick)
    private const int StartupGraceSeconds = 15;

    // ms of zero stdout bytes that trips a kill (10 x the 50 ms tick)
    private const int KillThresholdMs = 500;

    // While stderr recently logged a reconnect keyword the threshold widens
    // to minutes: a server outage is a legitimate silence (R2 §2 case d).
    private const int OutageToleranceMs = 300_000;
    private const int ReconnectKeywordRecencyMs = 300_000;

    // kill escalation: >=3 kills within 5 minutes -> alert log + 45 s
    // respawn delay (the ruled 30-60 s band) against hot loops
    private const int EscalationKillThreshold = 3;
    private const int EscalationWindowMinutes = 5;
    private const int EscalatedRespawnDelaySeconds = 45;

    private const int NormalRespawnDelayMs = 1_000;
    private const int TermWaitMs = 5_000;
    private const int AssignLeadSeconds = 5;

    // a stereo s16 frame = 4 bytes; the pipe has no message boundaries, so
    // the read loop tracks frame offset mod 4 across reads (a short read is
    // never EOF — only child death closes the writer)
    private const int FrameBytes = 4;

    private static readonly string[] StderrTailKeywords =
    {
        "Version ", "Connected to", "Reconnecting", "Snapclient terminated.",
    };

    private readonly WorkerConfig _config;
    private readonly StreamAssigner _assigner;
    private readonly ILogger<SnapClientSupervisor> _logger;
    private readonly Channel<byte[]> _audio = Channel.CreateBounded<byte[]>(
        new BoundedChannelOptions(256)
        {
            // Drop the oldest on full: the read loop must never block the
            // child's pipe, and the buffer must stay bounded while no
            // consumer drains it.
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleReader = true,
        });

    private volatile Process? _child;
    // volatile is not legal on DateTime: the timestamps are 64-bit UTC
    // ticks kept atomic by Interlocked — the write side (child start,
    // read loop, stderr events) and the watchdog read side are different
    // threads, and a torn 64-bit read would skew the last-byte age.
    private long _lastByteAtTicks;
    private long _lastReconnectKeywordAtTicks;
    private volatile int _frameParity;
    private long _totalBytes;
    private int _killsTotal;
    private int _shutdownStarted;
    private CancellationTokenSource? _loopCts;
    private readonly List<DateTime> _killTimes = new();
    private readonly TaskCompletionSource _shutdownDone = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public SnapClientSupervisor(WorkerConfig config, StreamAssigner assigner, ILogger<SnapClientSupervisor> logger)
    {
        _config = config;
        _assigner = assigner;
        _logger = logger;
    }

    /// <summary>
    /// The PCM bytes the child wrote to stdout (5512/16/stereo). A respawn
    /// is a stream discontinuity: the pipe restarts at the new position
    /// (R2 implication 5) — consumers must not replay across it.
    /// </summary>
    public IAsyncEnumerable<byte[]> AudioBytes => _audio.Reader.ReadAllAsync();

    /// <summary>True while the child process is alive.</summary>
    public bool ChildAlive => _child is { HasExited: false };

    public bool PipeDelivering => Interlocked.Read(ref _totalBytes) > 0;

    /// <summary>Frame offset mod 4, tracked across pipe reads.</summary>
    public int FrameParity => _frameParity;

    public long TotalBytes => Interlocked.Read(ref _totalBytes);

    /// <summary>Watchdog kills so far (aad_snapclient_kills_total).</summary>
    public int KillsTotal => Volatile.Read(ref _killsTotal);

    /// <summary>Captured candidates so far (aad_capture_candidates_total); the auto-capture state machine increments it.</summary>
    public int CaptureCandidatesTotal => Volatile.Read(ref _captureCandidatesTotal);

    /// <summary>Registers one captured candidate (the auto-capture state machine calls it).</summary>
    public void IncrementCaptureCandidates() => Interlocked.Increment(ref _captureCandidatesTotal);

    private int _captureCandidatesTotal;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation(
            "snapclient supervisor starting (url={Url}, hostID={HostId}, sampleformat={Format})",
            _config.SnapUrl, _config.SnapHostId, _config.SnapSampleFormat);

        while (!stoppingToken.IsCancellationRequested)
        {
            // A shutdown in flight must not launch another child that the
            // ordered teardown has already stopped tracking.
            if (Interlocked.CompareExchange(ref _shutdownStarted, 0, 0) == 1)
                break;

            using var cts = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
            _loopCts = cts;

            Process? child = null;
            Task? readLoop = null;
            Task? assign = null;
            DateTime childStartedAtUtc = default;
            try
            {
                var spawned = StartChild();
                child = spawned;
                childStartedAtUtc = DateTime.UtcNow;
                readLoop = Task.Run(() => ReadLoopAsync(spawned, cts.Token), CancellationToken.None);
                assign = Task.Run(async () =>
                {
                    try
                    {
                        // Lead time for the child's connect + hello: the server
                        // only knows the hostID's group once the client has
                        // greeted it (R2 §5); the assignment itself is one-shot.
                        await Task.Delay(TimeSpan.FromSeconds(AssignLeadSeconds), cts.Token);
                        await _assigner.AssignOnceAsync(cts.Token);
                    }
                    catch (OperationCanceledException)
                    {
                        _logger.LogDebug("stream assignment cancelled (child shutdown)");
                    }
                }, CancellationToken.None);
            }
            catch (Exception ex)
            {
                // The binary can be absent (or momentarily unavailable):
                // a spawn failure is the child-death-shaped event the
                // respawn loop already handles — log, back off, respawn,
                // instead of letting it out and ending the host.
                _logger.LogWarning(ex, "snapclient spawn failed — backoff + respawn");
            }

            if (child is not null)
                await WaitChildOrWatchdogAsync(child, cts.Token);

            cts.Cancel();
            if (readLoop is not null)
                await AwaitTolerantAsync(readLoop, "read loop cancelled (child shutdown)");
            if (assign is not null)
                await AwaitTolerantAsync(assign, "stream assignment task cancelled (child shutdown)");

            // Must precede the dispose below: once disposed, the code is unknowable.
            int? exitCode = null;
            var lifetimeSeconds = 0.0;
            if (child is not null)
            {
                (exitCode, lifetimeSeconds) = ReadExitState(child, childStartedAtUtc);
            }

            child?.Dispose();
            _child = null;
            _loopCts = null;

            if (stoppingToken.IsCancellationRequested)
            {
                _logger.LogInformation("shutdown in progress — not respawning");
                break;
            }

            var delay = exitCode.HasValue
                ? RespawnDelay(exitCode.Value, lifetimeSeconds)
                : TimeSpan.FromMilliseconds(NormalRespawnDelayMs);
            try
            {
                await Task.Delay(delay, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    // At teardown the child's tasks are cancelled; the OCE is the expected
    // outcome, not a fault.
    private async Task AwaitTolerantAsync(Task task, string cancelledMessage)
    {
        try
        {
            await task;
        }
        catch (OperationCanceledException)
        {
            _logger.LogDebug(cancelledMessage);
        }
    }

    // Process throws InvalidOperationException on any member access once
    // disposed — a post-dispose ExitCode read stopped the host on the live
    // 2026-11-27 crash. The first value is the exit code (null = unknown:
    // a handle already gone mid-teardown, or a process that never ran to
    // exit); the second is the child's run length in seconds at this read.
    // An unknown code respawns on the normal delay.
    private static (int? ExitCode, double LifetimeSeconds) ReadExitState(Process child, DateTime startedAtUtc)
    {
        var lifetime = (DateTime.UtcNow - startedAtUtc).TotalSeconds;
        try
        {
            return child.HasExited ? (child.ExitCode, lifetime) : (null, lifetime);
        }
        catch (InvalidOperationException)
        {
            return (null, lifetime);
        }
    }

    /// <summary>
    /// The ordered child shutdown (the K8s stop path): stop the reader, send
    /// kill -TERM to the child, wait the 5 s grace, SIGKILL if it is still
    /// alive, and only then close the pipe read end — closing it first would
    /// race a SIGPIPE into the writer (R3 implication 7). Idempotent: the
    /// signal registration in Program triggers the same host stop the
    /// lifetime uses, so every entry lands on this one teardown — the guard
    /// makes a repeated entry re-enter the completed shutdown instead of
    /// re-running the kill sequence.
    /// </summary>
    public Task ShutdownChildAsync()
    {
        if (Interlocked.Exchange(ref _shutdownStarted, 1) != 0)
            return _shutdownDone.Task;

        _ = Task.Run(async () =>
        {
            try
            {
                _loopCts?.Cancel();

                var child = _child;
                if (child is not null && !child.HasExited)
                {
                    try
                    {
                        // .NET has no managed way to send the child a
                        // termination signal; `kill -TERM` is the portable
                        // shape (the runtime image ships coreutils).
                        using var term = Process.Start(new ProcessStartInfo("kill", $"-TERM {child.Id}")
                        {
                            UseShellExecute = false,
                        });
                        if (term is not null)
                        {
                            // Process only exposes WaitForExitAsync(CancellationToken):
                            // the timeout token carries the TermWaitMs grace, and a
                            // timeout falls through to the SIGKILL leg below.
                            using var exitCts = new CancellationTokenSource(TimeSpan.FromMilliseconds(TermWaitMs));
                            try
                            {
                                await term.WaitForExitAsync(exitCts.Token);
                            }
                            catch (OperationCanceledException)
                            {
                                // Grace window elapsed before the kill process exited.
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning(ex, "kill -TERM to the child failed");
                    }
                }

                if (child is not null)
                {
                    if (!child.HasExited)
                    {
                        try { child.Kill(entireProcessTree: true); }
                        catch (Exception ex) { _logger.LogWarning(ex, "SIGKILL to the child failed"); }
                    }
                    try { child.WaitForExit(1000); }
                    catch (Exception ex) { _logger.LogWarning(ex, "waiting for the child exit failed"); }
                }

                _audio.Writer.TryComplete();
            }
            finally
            {
                _shutdownDone.TrySetResult();
            }
        });
        return _shutdownDone.Task;
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        // base.StopAsync cancels ExecuteAsync's stoppingToken, which is
        // what unwinds the respawn loop: the while check, the linked
        // per-iteration CTS, and the respawn Task.Delay all break on it
        // (a loop mid-respawn delay leaves the delay immediately). The
        // _shutdownStarted guard stays the idempotency barrier: a
        // repeated call re-enters the same teardown instead of re-running
        // the kill sequence. Cancel first so the loop leaves any
        // in-flight child iteration before the ordered kill sequence
        // runs; the sequence owns the child-gone-before-pipe-close
        // ordering, and the stop stays ahead of Program's
        // post-RunAsync snapshot leg.
        await base.StopAsync(cancellationToken);
        await ShutdownChildAsync();
    }

    private Process StartChild()
    {
        var psi = new ProcessStartInfo
        {
            FileName = "snapclient",
            // Foreground child (R2 implication 1); the file player is a
            // recorder — 50 ms ticks, silence-on-underrun. Volume stays at
            // 100% (the player applies it before the write — R2 §1).
            Arguments =
                $"--player file:filename=stdout " +
                $"--sampleformat {_config.SnapSampleFormat} " +
                "--logsink stderr " +
                $"--hostID {_config.SnapHostId} " +
                "--volume 100 " +
                _config.SnapUrl,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        var child = Process.Start(psi) ?? throw new InvalidOperationException("snapclient failed to start");
        child.ErrorDataReceived += OnStderrLine;
        child.BeginErrorReadLine();
        _child = child;
        _lastByteAtTicks = Interlocked.Exchange(ref _lastByteAtTicks, DateTime.UtcNow.Ticks);
        _frameParity = 0;
        _logger.LogInformation("snapclient launched (pid {Pid})", child.Id);
        return child;
    }

    private async Task WaitChildOrWatchdogAsync(Process child, CancellationToken ct)
    {
        var startedAtUtc = DateTime.UtcNow;
        var exitTask = child.WaitForExitAsync(ct);
        while (!ct.IsCancellationRequested)
        {
            Task next;
            try
            {
                next = await Task.WhenAny(exitTask, Task.Delay(100, ct));
            }
            catch (OperationCanceledException)
            {
                return;
            }

            if (next == exitTask)
                break;

            if (ShouldKillUtc(startedAtUtc, DateTime.UtcNow))
            {
                RecordKill();
                _logger.LogWarning(
                    "watchdog: {Ms} ms of zero stdout bytes — SIGKILL + respawn (kill {Kills}; a #1563-hung process spins at 100% CPU, R2 §2)",
                    KillThresholdMs, KillsTotal);
                try
                {
                    child.Kill(entireProcessTree: true);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "watchdog SIGKILL failed");
                }

                try
                {
                    await Task.Delay(250);
                }
                catch (OperationCanceledException)
                {
                    _logger.LogDebug("shutdown during the watchdog kill settle");
                }

                break;
            }
        }

        try
        {
            await exitTask.WaitAsync(TimeSpan.FromSeconds(5));
        }
        catch (Exception ex)
        {
            // Deliberate boundary at process teardown: the child is gone or
            // the process is tearing down; either way the pipe read end
            // closes only after the child is handled.
            _logger.LogDebug(ex, "child exit wait interrupted (teardown)");
        }
    }

    private async Task ReadLoopAsync(Process child, CancellationToken ct)
    {
        var stdout = child.StandardOutput.BaseStream;
        var buffer = new byte[65_536];
        try
        {
            // Tight read loop: a blocking pipe read returns >=1 byte until
            // the writer closes, so a short read is NOT EOF (R2 §1 / R3 §3).
            while (true)
            {
                var n = await stdout.ReadAsync(buffer.AsMemory(0, buffer.Length), ct);
                if (n == 0)
                    break; // EOF = child death
                Interlocked.Add(ref _totalBytes, n);
                _lastByteAtTicks = Interlocked.Exchange(ref _lastByteAtTicks, DateTime.UtcNow.Ticks);
                _frameParity = (_frameParity + n) % FrameBytes;
                var chunk = new byte[n];
                Buffer.BlockCopy(buffer, 0, chunk, 0, n);
                _audio.Writer.TryWrite(chunk);
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogDebug("read loop cancelled (child shutdown)");
        }
        catch (IOException)
        {
            _logger.LogDebug("stdout pipe closed (child gone)");
        }
    }

    private void OnStderrLine(object? sender, DataReceivedEventArgs e)
    {
        var line = e.Data;
        if (line is null)
            return;

        // The outage-tolerance window keys on these (R2 §2 case d: the
        // client retries every fixed 1 s while the server is down — a
        // legitimate silence the watchdog must not kill).
        if (line.Contains("Reconnecting") || line.Contains("Connecting to host"))
            _lastReconnectKeywordAtTicks = Interlocked.Exchange(ref _lastReconnectKeywordAtTicks, DateTime.UtcNow.Ticks);

        if (StderrTailKeywords.Any(line.Contains))
            _logger.LogInformation("[snapclient] {Line}", line);
    }

    private bool ShouldKillUtc(DateTime startedAtUtc, DateTime nowUtc)
    {
        if ((nowUtc - startedAtUtc).TotalSeconds < StartupGraceSeconds)
            return false;

        var lastByteAt = new DateTime(Interlocked.Read(ref _lastByteAtTicks), DateTimeKind.Utc);
        var quietMs = (nowUtc - lastByteAt).TotalMilliseconds;
        var threshold = OutageTolerant(nowUtc) ? OutageToleranceMs : KillThresholdMs;
        return quietMs > threshold;
    }

    private bool OutageTolerant(DateTime nowUtc)
    {
        var lastKeywordAt = new DateTime(Interlocked.Read(ref _lastReconnectKeywordAtTicks), DateTimeKind.Utc);
        return (nowUtc - lastKeywordAt).TotalMilliseconds <= ReconnectKeywordRecencyMs;
    }

    private void RecordKill()
    {
        Interlocked.Increment(ref _killsTotal);
        var now = DateTime.UtcNow;
        lock (_killTimes)
        {
            _killTimes.Add(now);
            _killTimes.RemoveAll(t => (now - t).TotalMinutes > EscalationWindowMinutes);
        }
    }

    private bool EscalationDue()
    {
        lock (_killTimes)
        {
            return _killTimes.Count >= EscalationKillThreshold;
        }
    }

    private TimeSpan RespawnDelay(int exitCode, double lifetimeSeconds)
    {
        if (EscalationDue())
        {
            _logger.LogError(
                "kill escalation: {Kills} kills within {Min} minutes — respawn delayed {Sec} s",
                EscalationKillThreshold, EscalationWindowMinutes, EscalatedRespawnDelaySeconds);
            return TimeSpan.FromSeconds(EscalatedRespawnDelaySeconds);
        }

        // The cycle-5 discriminator: the exit code and the run length say
        // WHY the child died (0 = the server told it to stop, 139 = #1563).
        _logger.LogWarning(
            "snapclient exited code={Code} after {After:0.#}s — respawn in {Delay:0.#}s",
            exitCode, lifetimeSeconds, NormalRespawnDelayMs / 1000.0);
        return TimeSpan.FromMilliseconds(NormalRespawnDelayMs);
    }
}
