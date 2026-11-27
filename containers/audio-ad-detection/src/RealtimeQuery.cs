using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using SoundFingerprinting.Audio;
using SoundFingerprinting.Builder;
using SoundFingerprinting.Command;
using SoundFingerprinting.Configuration;
using SoundFingerprinting.DAO.Data;
using SoundFingerprinting.Query;

namespace AudioAdDetection;

/// <summary>
/// The query leg's running flag for /readyz: the hosted service is a
/// transient registration (AddHostedService&lt;T&gt;), so the metrics
/// surface must not resolve it directly (a second construction would start
/// a second query leg — the C01 latent bug) — the singleton flag is the
/// seam.
/// </summary>
public sealed class QueryStatus
{
    private int _running;

    /// <summary>True while the realtime query leg is executing.</summary>
    public bool Running => Volatile.Read(ref _running) == 1;

    public void SetRunning(bool running) => Interlocked.Exchange(ref _running, running ? 1 : 0);
}

/// <summary>
/// Runs the realtime query over the pipeline's chunk stream. The source is
/// a BlockingRealtimeCollection over the pipeline's BlockingCollection —
/// after a non-cancellation error the command re-enumerates it, resuming
/// at the current position and never replaying (the hot-source contract).
/// </summary>
public sealed class RealtimeQuery : BackgroundService
{
    private const string KindMetaField = "kind";
    private const string AdKind = "ad";

    private readonly ModelService _model;
    private readonly AudioPipeline _pipeline;
    private readonly QueryStatus _status;
    private readonly IStreamState _state;
    private readonly IAdEventSink _sink;
    private readonly WorkerConfig _config;
    private readonly ILogger<RealtimeQuery> _logger;

    public RealtimeQuery(
        ModelService model,
        AudioPipeline pipeline,
        QueryStatus status,
        IStreamState state,
        IAdEventSink sink,
        WorkerConfig config,
        ILogger<RealtimeQuery> logger)
    {
        _model = model;
        _pipeline = pipeline;
        _status = status;
        _state = state;
        _sink = sink;
        _config = config;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _status.SetRunning(true);
        try
        {
            // One command for the whole run: Query returns on host stop (the
            // command catches the cancellation), and a non-cancellation error
            // is handled inside the command (backoff + re-read of the source).
            IRealtimeQueryCommand command = QueryCommandBuilder.Instance
                .BuildRealtimeQueryCommand()
                .From(new BlockingRealtimeCollection<AudioSamples>(_pipeline.Chunks))
                .WithRealtimeQueryConfig(cfg => AmendConfig(cfg, stoppingToken))
                .UsingServices(_model.Inner);

            await command.Query(stoppingToken);
        }
        finally
        {
            _status.SetRunning(false);
        }
    }

    private RealtimeQueryConfiguration AmendConfig(RealtimeQueryConfiguration cfg, CancellationToken ct)
    {
        // The builder's default config is no-op callbacks, a PassThrough
        // result filter, and an ErrorCallback that rethrows (it would end
        // the query loop on the first storage error) — replace all of it
        // with the worker's shape.
        cfg.SuccessCallback = async result => await OnSuccessAsync(result, ct);
        cfg.DidNotPassFilterCallback = _ => Task.CompletedTask;
        cfg.ErrorCallback = (ex, _) =>
        {
            // The command applies the backoff before re-reading the source;
            // log here with the current stream state.
            _logger.LogWarning(ex,
                "realtime query error; state: LastMatchAt={LastMatchAt}, LastMatchMeta={LastMatchMeta}, CurrentRmsDb={CurrentRmsDb}",
                _state.LastMatchAt, _state.LastMatchMeta, _state.CurrentRmsDb);
        };
        cfg.RestoredAfterErrorCallback = () => _logger.LogInformation("realtime query storage restored");

        // waitTillCompletion=false: a continuous source emits the confident
        // match as soon as the coverage bar is met, not at track end.
        cfg.ResultEntryFilter = new TrackCoverageLengthEntryFilter(_config.CoverageSeconds, waitTillCompletion: false);
        cfg.OngoingResultEntryFilter = new TrackCoverageLengthEntryFilter(_config.CoverageSeconds, waitTillCompletion: false);
        cfg.OngoingCallback = async (streamId, entries) => await _sink.OnOngoingPlayingAsync(streamId, entries, ct);
        cfg.OngoingEntryStalenessCeiling = _config.OngoingEntryStalenessCeilingSeconds;
        cfg.SeamJumpPolicy = SeamJumpPolicy.NewOccurrenceAbove(_config.NewOccurrenceAboveSeconds);
        return cfg;
    }

    private async Task OnSuccessAsync(AVQueryResult result, CancellationToken ct)
    {
        // The best entry feeds the last-match state; every kind=ad entry
        // raises ad_detected (one result can carry several).
        var best = result.ResultEntries.FirstOrDefault();
        if (best is not null)
        {
            var bestEntry = best.Audio ?? best.Video;
            if (bestEntry is not null)
                _state.SetMatch(bestEntry.MatchedAt, TrackMeta(bestEntry.Track));
        }

        foreach (var entry in result.ResultEntries)
        {
            var re = entry.Audio ?? entry.Video;
            if (re is null || !IsAd(re.Track))
                continue;
            await _sink.OnAdDetectedAsync(new AdDetectedEvent(
                re.Track.Id,
                TrackMeta(re.Track),
                re.MatchedAt,
                re.TrackCoverageWithPermittedGapsLength,
                re.Confidence), ct);
        }
    }

    private static bool IsAd(TrackData track) =>
        track.MetaFields.TryGetValue(KindMetaField, out var kind) && kind == AdKind;

    private static string TrackMeta(TrackData track) =>
        track.MetaFields.TryGetValue(KindMetaField, out var kind)
            ? $"{track.Id} | {track.Artist} - {track.Title} | kind={kind}"
            : $"{track.Id} | {track.Artist} - {track.Title}";
}
