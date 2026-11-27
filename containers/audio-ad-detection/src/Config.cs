namespace AudioAdDetection;

/// <summary>
/// The worker's env config surface: the snapcast leg, the broker, the
/// model dir, and the realtime query knobs the fingerprint engine
/// consumes.
/// </summary>
public sealed record WorkerConfig
{
    /// <summary>snapcast stream endpoint (the 1704 client leg).</summary>
    public string SnapUrl { get; init; } = "tcp://home-snapcast:1704";

    /// <summary>Pinned client identity; random pod MACs would otherwise mint
    /// a fresh group per pod recreation (R2 §3).</summary>
    public string SnapHostId { get; init; } = "audio-ad-detection";

    /// <summary>Sample format; channels must be <c>*</c> — the CLI rejects
    /// numeric channels at startup (R2 §1).</summary>
    public string SnapSampleFormat { get; init; } = "5512:16:*";

    // No worker default on purpose: the chart carries a REQUIRED value
    // (this run's documented placeholder is TBD-owner). Empty or TBD-owner
    // means "unassigned" — the group stays in config-order and readiness is
    // not blocked (Q2).
    public string SnapStreamId { get; init; } = string.Empty;

    /// <summary>snapcast JSON-RPC endpoint (the 1780 HTTP leg; open access
    /// on the deployed server without an [auth] section — R2 §5).</summary>
    public string SnapRpcUrl { get; init; } = "http://home-snapcast-snapcast-http:1780/jsonrpc";

    // The broker credentials stay an optional code path: the default broker
    // is anonymous, so they are set only when the broker requires auth.
    public string BrokerHost { get; init; } = "home-mosquitto";
    public int BrokerPort { get; init; } = 1883;
    public string BrokerUsername { get; init; } = string.Empty;
    public string BrokerPassword { get; init; } = string.Empty;

    /// <summary>Model snapshot + candidate dir (the PVC mount).</summary>
    public string ModelDir { get; init; } = "/models";

    public int HealthPort { get; init; } = 8080;

    // Realtime query knobs: seam-jump ceiling (a jump above it is another
    // occurrence — the library's own broadcast-agent value), the coverage
    // emission bar (the TVEyes 40%-coverage bar), and the ongoing
    // staleness ceiling so stale entries close promptly.
    public double NewOccurrenceAboveSeconds { get; init; } = 120;
    public int CoverageSeconds { get; init; } = 5;
    public double OngoingEntryStalenessCeilingSeconds { get; init; } = 120;

    // Capture + retention knobs (the auto-capture state machine): the
    // no-match span gate (30 s = a standard spot), the span cap (300 s =
    // the off-air boundary), the RMS floor — the machine consumes
    // IStreamState (LastMatchAt / LastMatchMeta / CurrentRmsDb) per chunk
    // and a span that dips below the floor is discarded on close, not
    // split — and the candidate retention policy (days-or-count, oldest
    // pruned first).
    public int CaptureMinSpanSeconds { get; init; } = 30;
    public int CaptureMaxSpanSeconds { get; init; } = 300;
    public double CaptureRmsFloorDb { get; init; } = -45;
    public int CaptureRetentionDays { get; init; } = 14;
    public int CaptureMaxCandidates { get; init; } = 200;

    public static WorkerConfig FromEnvironment() => new()
    {
        SnapUrl = Env("SNAP_URL", "tcp://home-snapcast:1704"),
        SnapHostId = Env("SNAP_HOST_ID", "audio-ad-detection"),
        SnapSampleFormat = Env("SNAP_SAMPLE_FORMAT", "5512:16:*"),
        SnapStreamId = Env("SNAP_STREAM_ID", string.Empty),
        SnapRpcUrl = Env("SNAP_RPC_URL", "http://home-snapcast-snapcast-http:1780/jsonrpc"),
        BrokerHost = Env("MQTT_BROKER_HOST", "home-mosquitto"),
        BrokerPort = int.TryParse(Env("MQTT_BROKER_PORT", "1883"), out var port) ? port : 1883,
        BrokerUsername = Env("MQTT_USERNAME", string.Empty),
        BrokerPassword = Env("MQTT_PASSWORD", string.Empty),
        ModelDir = Env("MODEL_DIR", "/models"),
        HealthPort = int.TryParse(Env("HEALTH_PORT", "8080"), out var healthPort) ? healthPort : 8080,
        NewOccurrenceAboveSeconds = double.TryParse(Env("NEW_OCCURRENCE_ABOVE", "120"), out var newOccurrenceAbove) ? newOccurrenceAbove : 120,
        CoverageSeconds = int.TryParse(Env("COVERAGE_SECONDS", "5"), out var coverageSeconds) ? coverageSeconds : 5,
        OngoingEntryStalenessCeilingSeconds = double.TryParse(Env("ONGOING_ENTRY_STALENESS_CEILING", "120"), out var stalenessCeiling) ? stalenessCeiling : 120,
        CaptureMinSpanSeconds = int.TryParse(Env("CAPTURE_MIN_SPAN_SECONDS", "30"), out var captureMinSpan) ? captureMinSpan : 30,
        CaptureMaxSpanSeconds = int.TryParse(Env("CAPTURE_MAX_SPAN_SECONDS", "300"), out var captureMaxSpan) ? captureMaxSpan : 300,
        CaptureRmsFloorDb = double.TryParse(Env("CAPTURE_RMS_FLOOR_DB", "-45"), out var captureRmsFloor) ? captureRmsFloor : -45,
        CaptureRetentionDays = int.TryParse(Env("CAPTURE_RETENTION_DAYS", "14"), out var retentionDays) ? retentionDays : 14,
        CaptureMaxCandidates = int.TryParse(Env("CAPTURE_MAX_CANDIDATES", "200"), out var maxCandidates) ? maxCandidates : 200,
    };

    private static string Env(string name, string fallback)
    {
        var value = Environment.GetEnvironmentVariable(name);
        return string.IsNullOrWhiteSpace(value) ? fallback : value;
    }
}
