using Microsoft.Extensions.Logging;

namespace AudioAdDetection;

/// <summary>
/// The on-demand retention + promoted-track delete lane (C02b): a bare
/// <c>prune</c> applies the candidate retention policy (--older-than
/// overrides the CAPTURE_RETENTION_DAYS default), and
/// <c>prune --track &lt;name&gt;</c> deletes a named auto-promoted track
/// (audit/prune of auto-promoted entries) + Snapshot($MODEL_DIR).
/// </summary>
public static class PruneCommand
{
    public static async Task<int> RunAsync(string[] args, WorkerConfig config, ILoggerFactory loggerFactory)
    {
        int? olderThan = null;
        string? track = null;
        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--older-than" when i + 1 < args.Length:
                    if (!int.TryParse(args[++i], out var days))
                    {
                        Console.Error.WriteLine("--older-than needs a whole number of days");
                        return 2;
                    }
                    olderThan = days;
                    break;
                case "--track" when i + 1 < args.Length:
                    track = args[++i];
                    break;
                default:
                    Console.Error.WriteLine($"unknown prune option '{args[i]}' (expected --older-than <days>, --track <name>)");
                    return 2;
            }
        }

        using var logger = loggerFactory.CreateLogger<PruneCommand>();
        var model = new ModelService(config, loggerFactory, loggerFactory.CreateLogger<ModelService>());
        var retentionDays = olderThan ?? config.CaptureRetentionDays;

        var dir = CandidateWriter.CandidatesDir(config);
        var pruned = Curator.PruneRetention(dir, retentionDays, config.CaptureMaxCandidates);
        Console.WriteLine($"retention pruned {pruned} candidate(s) (policy: {retentionDays} days / max {config.CaptureMaxCandidates})");

        if (track is not null)
        {
            var trackId = await ResolveTrackIdAsync(model, track);
            if (trackId is null)
            {
                Console.Error.WriteLine($"no auto-promoted track matches '{track}'");
                return 1;
            }
            await model.Inner.DeleteTrackAsync(trackId);
            Console.WriteLine($"deleted promoted track {trackId}");
        }

        model.Snapshot();
        Console.WriteLine("model snapshot written");
        return 0;
    }

    private static async Task<string?> ResolveTrackIdAsync(ModelService model, string name)
    {
        foreach (var trackId in await model.Inner.GetTrackIdsAsync())
        {
            var track = await model.Inner.ReadTrackByIdAsync(trackId);
            if (track is null)
                continue;
            // Only auto-promoted entries are prunable by name — the manual
            // lane's tracks stay human-decided.
            if (!track.MetaFields.TryGetValue(SightingStore.PromotedFlag, out var flag) || flag != "true")
                continue;
            if (trackId == name ||
                track.Title == name ||
                $"{track.Artist} - {track.Title}" == name ||
                track.Title.StartsWith(name, StringComparison.OrdinalIgnoreCase))
                return trackId;
        }
        return null;
    }
}
