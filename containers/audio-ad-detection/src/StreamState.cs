namespace AudioAdDetection;

/// <summary>
/// The stream's per-chunk bookkeeping: the last confident match (when +
/// which track) and the most recent chunk's RMS — the no-match span state
/// the capture state machine consumes.
/// </summary>
public interface IStreamState
{
    /// <summary>When the last confident match occurred (UTC); null = none since startup.</summary>
    DateTime? LastMatchAt { get; }

    /// <summary>Meta of the last matched track; null until the first match.</summary>
    string? LastMatchMeta { get; }

    /// <summary>RMS (dBFS) of the most recent chunk; NaN until the first chunk was processed.</summary>
    double CurrentRmsDb { get; }

    void SetMatch(DateTime matchedAtUtc, string meta);

    void SetRmsDb(double rmsDb);
}

/// <summary>
/// Thread-safe <see cref="IStreamState"/>: the query callback (thread pool)
/// writes, the producer and the metrics thread read.
/// </summary>
public sealed class StreamState : IStreamState
{
    private DateTime? _lastMatchAt;
    private string? _lastMatchMeta;
    private double _currentRmsDb = double.NaN;

    public DateTime? LastMatchAt => Volatile.Read(ref _lastMatchAt);

    public string? LastMatchMeta => Volatile.Read(ref _lastMatchMeta);

    public double CurrentRmsDb => Volatile.Read(ref _currentRmsDb);

    public void SetMatch(DateTime matchedAtUtc, string meta)
    {
        // Monotonicity clamp: a late callback must not rewind the
        // timestamp — the capture state machine keys the no-match span
        // length on it.
        var current = Volatile.Read(ref _lastMatchAt);
        if (current is { } last && matchedAtUtc < last)
            return;

        // Meta lands before the timestamp: a reader that sees the new
        // timestamp never sees a null meta (it may briefly see the old pair
        // — benign for telemetry).
        Volatile.Write(ref _lastMatchMeta, meta);
        Volatile.Write(ref _lastMatchAt, matchedAtUtc);
    }

    public void SetRmsDb(double rmsDb) => Volatile.Write(ref _currentRmsDb, rmsDb);
}
