using Microsoft.Extensions.Logging;

namespace AudioAdDetection;

/// <summary>
/// The human audit surface (C02b): candidates (name, size, age,
/// auto_promoted flag + the promoted track reference) plus the
/// auto-promoted tracks (name, meta, promotion time, sightings) — what
/// keeps the human in the loop after the fact.
/// </summary>
public static class ListCommand
{
    public static async Task<int> RunAsync(string[] args, WorkerConfig config, ILoggerFactory loggerFactory)
    {
        var model = new ModelService(config, loggerFactory, loggerFactory.CreateLogger<ModelService>());
        var dir = CandidateWriter.CandidatesDir(config);

        Console.WriteLine($"candidates ({dir}):");
        if (Directory.Exists(dir))
        {
            var sightings = SightingStore.LoadAll(dir);
            foreach (var path in Directory.EnumerateFiles(dir, "*" + CandidateWriter.CandidateExt).OrderBy(p => p))
            {
                var info = new FileInfo(path);
                var ageDays = (DateTime.UtcNow - info.LastWriteTimeUtc).TotalDays;
                var sighting = sightings.FirstOrDefault(s => s.File == info.Name);
                var trackRef = sighting is { Promoted: true, TrackId: not null } ? $" -> {sighting.TrackId}" : "";
                Console.WriteLine(
                    "  {Name}  {Size} KB  {Age:0.0} d  auto_promoted={Flag}{TrackRef}",
                    info.Name, info.Length / 1024, ageDays, sighting is { Promoted: true }, trackRef);
            }
        }
        else
        {
            Console.WriteLine("  (none)");
        }

        Console.WriteLine("auto-promoted tracks:");
        var any = false;
        foreach (var trackId in await model.Inner.GetTrackIdsAsync())
        {
            var track = await model.Inner.ReadTrackByIdAsync(trackId);
            if (track is null)
                continue;
            if (!track.MetaFields.TryGetValue(SightingStore.PromotedFlag, out var promotedFlag) || promotedFlag != "true")
                continue;
            any = true;
            // MetaFields is an IDictionary (no GetValueOrDefault): the
            // TryGetValue form is the interface-stable read.
            var capturedAt = track.MetaFields.TryGetValue("captured_at", out var ca) ? ca : "-";
            var sourceGroup = track.MetaFields.TryGetValue("source_group", out var sg) ? sg : "-";
            var sightings = track.MetaFields.TryGetValue("sightings", out var sn) ? sn : "-";
            Console.WriteLine(
                "  {Id}  {Title}  captured_at={CapturedAt}  group={Group}  sightings={Sightings}",
                track.Id, track.Title,
                capturedAt, sourceGroup, sightings);
        }
        if (!any)
            Console.WriteLine("  (none)");

        return 0;
    }
}
