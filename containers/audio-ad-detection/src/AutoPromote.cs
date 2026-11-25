using System.Globalization;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using SoundFingerprinting;
using SoundFingerprinting.Audio;
using SoundFingerprinting.Builder;
using SoundFingerprinting.Data;
using System.Text.Json;

namespace AudioAdDetection;

/// <summary>
/// The auto-promotion guardrail knobs (owner override 2026-11-24): all env
/// config so threshold tweaks are value-only changes. A single sighting
/// NEVER promotes — the recurrence gate (>= 2 sightings, >= 24 h apart by
/// default) is the only door into the insert path.
/// </summary>
public sealed record AutoPromoteConfig
{
    /// <summary>Min distinct recurrences (a single sighting never promotes).</summary>
    public int MinSightings { get; init; } = 2;

    /// <summary>Qualifying sightings must be at least this many hours apart (cross-episode repetition, not back-to-back re-runs).</summary>
    public int MinGapHours { get; init; } = 24;

    /// <summary>Per-day auto-promotion cap (bounds drift-feeding; cap-hit skips count aad_auto_promotions_capped_total).</summary>
    public int MaxPerDay { get; init; } = 20;

    public static AutoPromoteConfig FromEnvironment() => new()
    {
        MinSightings = int.TryParse(Env("AUTO_PROMOTE_MIN_SIGHTINGS", "2"), out var minSightings) ? minSightings : 2,
        MinGapHours = int.TryParse(Env("AUTO_PROMOTE_MIN_GAP_HOURS", "24"), out var minGapHours) ? minGapHours : 24,
        MaxPerDay = int.TryParse(Env("AUTO_PROMOTE_MAX_PER_DAY", "20"), out var maxPerDay) ? maxPerDay : 20,
    };

    private static string Env(string name, string fallback)
    {
        var value = Environment.GetEnvironmentVariable(name);
        return string.IsNullOrWhiteSpace(value) ? fallback : value;
    }
}

/// <summary>
/// Fingerprint-proximity dedup: two candidates are the same ad when a large
/// share of the smaller bin set is shared — a known ad re-airing is not a
/// new one. Applied before insert, against both the existing catalogue and
/// previously promoted candidates (one entry per distinct ad).
/// </summary>
internal static class FingerprintDedup
{
    /// <summary>Min shared fraction (of the smaller bin set) that counts as the same ad.</summary>
    public const double ProximityThreshold = 0.5;

    public static HashSet<int> ExtractBins(AVHashes hashes)
    {
        var bins = new HashSet<int>();
        var audio = hashes.Audio;
        if (audio is null)
            return bins;
        foreach (var fingerprint in audio)
            foreach (var bin in fingerprint.HashBins)
                bins.Add(bin);
        return bins;
    }

    public static bool IsProximal(HashSet<int> a, HashSet<int> b)
    {
        if (a.Count == 0 || b.Count == 0)
            return false;
        var (smaller, larger) = a.Count <= b.Count ? (a, b) : (b, a);
        var shared = 0;
        foreach (var bin in smaller)
            if (larger.Contains(bin))
                shared++;
        return (double)shared / smaller.Count >= ProximityThreshold;
    }

    public static async Task<bool> IsDeduplicatedAsync(IModelService model, HashSet<int> bins, CancellationToken ct = default)
    {
        foreach (var trackId in await model.GetTrackIdsAsync(ct))
        {
            var known = ExtractBins(await model.ReadHashesByTrackIdAsync(trackId, ct));
            if (IsProximal(bins, known))
                return true;
        }
        return false;
    }
}

/// <summary>
/// The per-candidate sighting sidecar (a small JSON file next to the
/// candidate — it survives a worker restart without re-fingerprinting) and
/// the per-day promotion ledger (promotions.json in the candidate dir).
/// </summary>
internal static class SightingStore
{
    public const string PromotedFlag = "auto_promoted";
    public const string KindAd = "ad";
    public const string PromotionLedgerFile = "promotions.json";

    public sealed record Sighting(string File, string Group, string CapturedAt, bool Promoted, string? TrackId, HashSet<int> Bins);
    public sealed record Promotion(string Day, string TrackId, string Title, string At);

    public static List<Sighting> LoadAll(string candidatesDir)
    {
        var result = new List<Sighting>();
        if (!Directory.Exists(candidatesDir))
            return result;
        foreach (var sidecar in Directory.EnumerateFiles(candidatesDir, "*.json"))
        {
            try
            {
                var doc = JsonSerializer.Deserialize<SightingDoc>(File.ReadAllText(sidecar));
                if (doc is null || string.IsNullOrEmpty(doc.file))
                    continue;
                result.Add(new Sighting(
                    doc.file, doc.group, doc.captured_at, doc.promoted, doc.track_id,
                    new HashSet<int>(doc.bins)));
            }
            catch (JsonException)
            {
                // A torn sidecar (mid-write at a crash) is skipped: its
                // candidate gets a fresh sidecar at the next close.
            }
        }
        return result;
    }

    public static void Save(string candidatesDir, Sighting sighting)
    {
        var doc = new SightingDoc
        {
            file = sighting.File,
            group = sighting.Group,
            captured_at = sighting.CapturedAt,
            promoted = sighting.Promoted,
            track_id = sighting.TrackId,
            bins = sighting.Bins.OrderBy(b => b).ToArray(),
        };
        File.WriteAllText(Path.Combine(candidatesDir, sighting.File + ".json"), JsonSerializer.Serialize(doc));
    }

    private sealed class SightingDoc
    {
        public string file { get; set; } = "";
        public string group { get; set; } = "";
        public string captured_at { get; set; } = "";
        public bool promoted { get; set; }
        public string? track_id { get; set; }
        public int[] bins { get; set; } = [];
    }

    public static List<Promotion> LoadPromotions(string candidatesDir)
    {
        var path = Path.Combine(candidatesDir, PromotionLedgerFile);
        if (!File.Exists(path))
            return [];
        try
        {
            return JsonSerializer.Deserialize<List<PromotionDoc>>(File.ReadAllText(path)) is { } docs
                ? docs.Select(d => new Promotion(d.day, d.track_id, d.title, d.at)).ToList()
                : [];
        }
        catch (JsonException)
        {
            return [];
        }
    }

    public static void AppendPromotion(string candidatesDir, Promotion promotion)
    {
        var existing = LoadPromotions(candidatesDir);
        existing.Add(promotion);
        var docs = existing.Select(p => new PromotionDoc
        {
            day = p.Day,
            track_id = p.TrackId,
            title = p.Title,
            at = p.At,
        }).ToList();
        File.WriteAllText(Path.Combine(candidatesDir, PromotionLedgerFile), JsonSerializer.Serialize(docs));
    }

    private sealed class PromotionDoc
    {
        public string day { get; set; } = "";
        public string track_id { get; set; } = "";
        public string title { get; set; } = "";
        public string at { get; set; } = "";
    }
}

/// <summary>
/// The low-priority curator path (C02b): candidate fingerprinting +
/// sighting tracking, the auto-promotion evaluation, and the candidate
/// retention pass — at startup, on an hourly timer, and on demand. Never
/// on the hot chunk loop.
/// </summary>
public sealed class Curator : BackgroundService
{
    private readonly WorkerConfig _config;
    private readonly ModelService _model;
    private readonly AutoPromoteConfig _autoPromote;
    private readonly ILogger<Curator> _logger;
    private readonly SemaphoreSlim _passGate = new(1, 1);
    private long _autoPromotionsTotal;
    private long _autoPromotionsCappedTotal;

    public Curator(WorkerConfig config, ModelService model, ILogger<Curator> logger)
    {
        _config = config;
        _model = model;
        _autoPromote = AutoPromoteConfig.FromEnvironment();
        _logger = logger;
    }

    /// <summary>Auto-promotions so far (aad_auto_promotions_total).</summary>
    public long AutoPromotionsTotal => Interlocked.Read(ref _autoPromotionsTotal);

    /// <summary>Auto-promotions skipped on the per-day cap (aad_auto_promotions_capped_total).</summary>
    public long AutoPromotionsCappedTotal => Interlocked.Read(ref _autoPromotionsCappedTotal);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation(
            "curator started (hourly retention + auto-promotion pass; a single sighting never promotes)");
        while (true)
        {
            try
            {
                await RunPassAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "curator pass failed (non-fatal)");
            }

            try
            {
                await Task.Delay(TimeSpan.FromHours(1), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    /// <summary>One retention + auto-promotion pass (single-flight).</summary>
    public async Task RunPassAsync(CancellationToken ct = default)
    {
        await _passGate.WaitAsync(ct);
        try
        {
            var dir = CandidateWriter.CandidatesDir(_config);
            var pruned = PruneRetention(dir, _config.CaptureRetentionDays, _config.CaptureMaxCandidates);
            if (pruned > 0)
                _logger.LogInformation("retention pruned {Pruned} candidate(s)", pruned);
            await EvaluateAutoPromotionAsync(dir, ct);
        }
        finally
        {
            _passGate.Release();
        }
    }

    /// <summary>
    /// Called by the capture machine when a candidate file has been
    /// written: fingerprints the in-memory samples (no re-read), records
    /// the sighting sidecar, then runs the evaluation — all off the hot
    /// chunk loop.
    /// </summary>
    public void EnqueueCandidateClosedAsync(float[] samples, string candidatePath, string group)
    {
        _ = Task.Run(async () =>
        {
            try
            {
                var dir = Path.GetDirectoryName(candidatePath);
                if (dir is null)
                    return;
                var hashes = await FingerprintCommandBuilder.Instance
                    .BuildFingerprintCommand()
                    .From(new AudioSamples(samples, candidatePath, 5512))
                    .Hash();
                var fileName = Path.GetFileName(candidatePath);
                SightingStore.Save(dir, new SightingStore.Sighting(
                    fileName, group, DateTime.UtcNow.ToString("O"), false, null,
                    FingerprintDedup.ExtractBins(hashes)));
                await RunPassAsync();
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "candidate post-processing failed (non-fatal)");
            }
        });
    }

    private async Task EvaluateAutoPromotionAsync(string dir, CancellationToken ct)
    {
        var all = SightingStore.LoadAll(dir);
        var pending = all.Where(s => !s.Promoted).ToList();
        if (pending.Count == 0)
            return;

        var groups = GroupByProximity(pending);

        var catalogue = new Dictionary<string, HashSet<int>>();
        foreach (var trackId in await _model.Inner.GetTrackIdsAsync(ct))
            catalogue[trackId] = FingerprintDedup.ExtractBins(await _model.Inner.ReadHashesByTrackIdAsync(trackId, ct));
        var promotedBins = all.Where(s => s.Promoted).Select(s => s.Bins).ToList();

        foreach (var group in groups)
        {
            // Recurrence gate (the only door into the insert path): >=
            // MinSightings distinct recurrences with qualifying sightings
            // MinGapHours apart.
            if (group.Count < _autoPromote.MinSightings)
                continue;
            if (!HasQualifiedGap(group))
                continue;

            var representative = group[0].Bins;
            // Dedup before insert: a known ad re-airing is not a new one
            // (catalogue), and one entry per distinct ad (previously
            // promoted candidates).
            if (catalogue.Values.Any(known => FingerprintDedup.IsProximal(known, representative)))
                continue;
            if (promotedBins.Any(known => FingerprintDedup.IsProximal(known, representative)))
                continue;

            // Per-day cap (bounds drift-feeding; a cap-hit skip counts).
            var today = DateTime.UtcNow.ToString("yyyy-MM-dd");
            if (SightingStore.LoadPromotions(dir).Count(p => p.Day == today) >= _autoPromote.MaxPerDay)
            {
                Interlocked.Increment(ref _autoPromotionsCappedTotal);
                _logger.LogInformation("auto-promotion skipped on the per-day cap ({Cap}/day)", _autoPromote.MaxPerDay);
                continue;
            }

            if (!CandidateWriter.TryReadSamples(Path.Combine(dir, group[0].File), out var repSamples, out _))
            {
                _logger.LogWarning("auto-promotion skipped: could not decode {File}", group[0].File);
                continue;
            }
            var hashes = await FingerprintCommandBuilder.Instance
                .BuildFingerprintCommand()
                .From(new AudioSamples(repSamples, group[0].File, 5512))
                .Hash();

            var utcNow = DateTime.UtcNow;
            var trackId = $"ad-auto-{utcNow:yyyyMMdd-HHmmss}";
            var meta = new Dictionary<string, string>
            {
                ["kind"] = SightingStore.KindAd,
                [SightingStore.PromotedFlag] = "true",
                ["captured_at"] = utcNow.ToString("O"),
                ["source_group"] = group[0].Group,
                ["sightings"] = group.Count.ToString(),
            };
            var track = new TrackInfo(
                trackId,
                $"{group[0].Group} auto-promoted {utcNow:yyyy-MM-dd}",
                "audio-ad-detection",
                meta);
            var insert = await _model.Inner.InsertAsync(track, hashes, ct);
            if (insert.DuplicatePrevented)
            {
                // Library-side dedup backstop (this 18.0.0 build normally
                // returns Inserted/Updated) — treat as a dedup skip.
                continue;
            }

            _model.Snapshot();
            SightingStore.AppendPromotion(dir, new SightingStore.Promotion(today, trackId, track.Title, utcNow.ToString("O")));
            foreach (var sighting in group)
                SightingStore.Save(dir, sighting with { Promoted = true, TrackId = trackId });
            Interlocked.Increment(ref _autoPromotionsTotal);
            _logger.LogInformation(
                "auto-promoted {TrackId} (group {Group}, {Sightings} sightings, gap gate {Gap}h)",
                trackId, group[0].Group, group.Count, _autoPromote.MinGapHours);
        }
    }

    private static List<List<SightingStore.Sighting>> GroupByProximity(List<SightingStore.Sighting> items)
    {
        var groups = new List<List<SightingStore.Sighting>>();
        foreach (var item in items)
        {
            var home = groups.FirstOrDefault(g => g.Any(existing => FingerprintDedup.IsProximal(existing.Bins, item.Bins)));
            if (home is null)
            {
                home = new List<SightingStore.Sighting>();
                groups.Add(home);
            }
            home.Add(item);
        }
        return groups;
    }

    private bool HasQualifiedGap(List<SightingStore.Sighting> group)
    {
        var times = group.Select(s => DateTime.Parse(s.CapturedAt, CultureInfo.InvariantCulture))
            .OrderBy(t => t)
            .ToList();
        // Qualifying pair: the earliest sighting vs the latest, at least
        // the ruled gap apart (cross-episode, not back-to-back re-runs).
        return times.Count >= 2 &&
            times[^1] - times[0] >= TimeSpan.FromHours(_autoPromote.MinGapHours);
    }

    /// <summary>
    /// The candidate retention policy (days-or-count, whichever trips
    /// first; oldest pruned first) — deletes the file and its sidecar.
    /// Shared by the periodic pass and the on-demand <c>prune</c> lane.
    /// </summary>
    public static int PruneRetention(string candidatesDir, int retentionDays, int maxCandidates)
    {
        if (!Directory.Exists(candidatesDir))
            return 0;
        var files = Directory.EnumerateFiles(candidatesDir, "*" + CandidateWriter.CandidateExt)
            .Select(p => new FileInfo(p))
            .OrderBy(f => f.LastWriteTimeUtc)
            .ToList();
        var remaining = files.Count;
        var pruned = 0;
        foreach (var file in files)
        {
            var expired = (DateTime.UtcNow - file.LastWriteTimeUtc).TotalDays > retentionDays;
            if (!expired && remaining <= maxCandidates)
                break;
            try
            {
                file.Delete();
                File.Delete(file.FullName + ".json");
            }
            catch (IOException)
            {
                // A racing delete (already gone) is a no-op for the policy.
            }
            remaining--;
            pruned++;
        }
        return pruned;
    }
}
