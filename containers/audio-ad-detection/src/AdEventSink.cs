using SoundFingerprinting.Query;

namespace AudioAdDetection;

/// <summary>
/// A confident ad match: a filter-passed entry whose track meta says
/// kind=ad.
/// </summary>
public sealed record AdDetectedEvent(
    string TrackId,
    string TrackMeta,
    DateTime MatchedAtUtc,
    double TrackCoverageSeconds,
    double Confidence);

/// <summary>
/// The event seam. The awaited success / ongoing callbacks (wired in
/// RealtimeQuery) are the backpressure point: the query command does not
/// consume the next chunk until the callback's task completes, so a sink
/// that performs I/O backpressures the stream (R1 implication 2).
/// </summary>
public interface IAdEventSink
{
    /// <summary>ad_detected: a confident match on a kind=ad track.</summary>
    Task OnAdDetectedAsync(AdDetectedEvent e, CancellationToken ct);

    /// <summary>What is playing right now: the entries that passed the ongoing filter (C03's HA media-state feed).</summary>
    Task OnOngoingPlayingAsync(string streamId, IEnumerable<AVResultEntry> entries, CancellationToken ct);
}

/// <summary>
/// The worker's only sink: log the events.
/// </summary>
public sealed class LoggingAdEventSink : IAdEventSink
{
    private readonly ILogger<LoggingAdEventSink> _logger;

    public LoggingAdEventSink(ILogger<LoggingAdEventSink> logger)
    {
        _logger = logger;
    }

    public Task OnAdDetectedAsync(AdDetectedEvent e, CancellationToken ct)
    {
        _logger.LogInformation(
            "ad_detected: {Meta} (coverage {Coverage:0.00}s, confidence {Confidence:0.00}, matchedAt {MatchedAt:O})",
            e.TrackMeta, e.TrackCoverageSeconds, e.Confidence, e.MatchedAtUtc);
        return Task.CompletedTask;
    }

    public Task OnOngoingPlayingAsync(string streamId, IEnumerable<AVResultEntry> entries, CancellationToken ct)
    {
        // Per-chunk cadence — debug level to keep the hot log quiet.
        var list = entries.ToList();
        var best = list.Count > 0 ? list[0].Audio ?? list[0].Video : null;
        _logger.LogDebug(
            "ongoing: {Count} entr(y/ies) (top: {Top}, coverage {Coverage:0.00}s)",
            list.Count,
            best is null ? "-" : $"{best.Track.Artist} - {best.Track.Title}",
            best?.TrackCoverageWithPermittedGapsLength ?? 0.0);
        return Task.CompletedTask;
    }
}
