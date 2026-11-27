using System.Diagnostics;
using System.Globalization;
using Microsoft.Extensions.Logging;
using SoundFingerprinting;
using SoundFingerprinting.Audio;
using SoundFingerprinting.Builder;
using SoundFingerprinting.Data;

namespace AudioAdDetection;

/// <summary>
/// The manual promote lane (C02b, stays — the manual path for single-shot
/// candidates or owner-dropped files): <c>promote --file &lt;candidate&gt;</c>
/// decodes the worker's own 44-byte-header s16le files directly (no
/// FFmpeg); <c>promote --dir &lt;dir&gt;</c> handles arbitrary owner-dropped
/// formats via the CLI-backed FFmpegAudioService (the R1 §4 canonical
/// insert shape). Fingerprint + insert with kind=ad meta (manual origin —
/// the auto-promotion flag is not set) + proximity dedup skip before
/// insert + Snapshot($MODEL_DIR); per-file failure exits non-zero.
/// </summary>
public static class PromoteCommand
{
    public static async Task<int> RunAsync(string[] args, WorkerConfig config, ILoggerFactory loggerFactory)
    {
        var (file, dir, parseError) = ParseArgs(args);
        if (parseError != 0)
            return parseError;

        using var logger = loggerFactory.CreateLogger<PromoteCommand>();
        var model = new ModelService(config, loggerFactory, loggerFactory.CreateLogger<ModelService>());
        var ffmpeg = new FFmpegAudioService();

        var files = new List<string>();
        if (file is not null)
            files.Add(file);
        else if (dir is not null)
            // No extension filter: candidate files decode directly (the
            // 44-byte-header path) and anything else falls through to the
            // FFmpegAudioService — a per-file failure surfaces either way.
            files.AddRange(Directory.EnumerateFiles(dir, "*.*", SearchOption.AllDirectories));

        var failures = 0;
        var promoted = 0;
        foreach (var path in files)
        {
            try
            {
                var (hashes, group) = await FingerprintAsync(path, ffmpeg, config);
                if (hashes is null)
                {
                    Console.Error.WriteLine($"failure {path}: not a decodable candidate or supported format");
                    failures++;
                    continue;
                }
                // Dedup guard: skip-if-already-known, before insert (a
                // known ad re-airing is not a new one).
                if (await FingerprintDedup.IsDeduplicatedAsync(model.Inner, FingerprintDedup.ExtractBins(hashes)))
                {
                    Console.WriteLine($"dedup skip: {path} is within proximity of an already-known ad");
                    continue;
                }

                var utcNow = DateTime.UtcNow;
                var meta = new Dictionary<string, string>
                {
                    ["kind"] = "ad",
                    ["captured_at"] = utcNow.ToString("O"),
                    ["source_group"] = group,
                    ["source_file"] = Path.GetFileName(path),
                };
                var trackId = $"ad-manual-{utcNow:yyyyMMdd-HHmmss}";
                var track = new TrackInfo(trackId, $"{group} manual {utcNow:yyyy-MM-dd}", "audio-ad-detection", meta);
                var insert = await model.Inner.InsertAsync(track, hashes);
                if (insert.DuplicatePrevented)
                {
                    Console.WriteLine($"dedup skip: {path} was suppressed as a known duplicate");
                    continue;
                }
                promoted++;
                Console.WriteLine($"promoted {path} as {trackId} (kind=ad)");
            }
            catch (Exception ex)
            {
                failures++;
                logger.LogError(ex, "promote failed for {Path} (per-file failure — the remaining files still run)", path);
            }
        }

        model.Snapshot();
        Console.WriteLine($"promoted {promoted} file(s); model snapshot written");
        if (failures > 0)
        {
            Console.Error.WriteLine($"{failures} file(s) failed");
            return 1;
        }
        return 0;
    }

    private static (string? File, string? Dir, int Error) ParseArgs(string[] args)
    {
        string? file = null;
        string? dir = null;
        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--file" when i + 1 < args.Length:
                    file = args[++i];
                    break;
                case "--dir" when i + 1 < args.Length:
                    dir = args[++i];
                    break;
                default:
                    Console.Error.WriteLine($"unknown promote option '{args[i]}' (expected --file <candidate>, --dir <dir>)");
                    return (null, null, 2);
            }
        }
        if (file is null && dir is null)
        {
            Console.Error.WriteLine("promote needs --file <candidate> or --dir <dir>");
            return (null, null, 2);
        }
        return (file, dir, 0);
    }

    private static async Task<(AVHashes? Hashes, string Group)> FingerprintAsync(
        string path, FFmpegAudioService ffmpeg, WorkerConfig config)
    {
        var group = GroupFromSidecar(path, config);

        // Candidate files decode directly (the 44-byte-header s16le read);
        // anything else — the owner-dropped --dir formats — goes through
        // the FFmpegAudioService.
        if (CandidateWriter.TryReadSamples(path, out var samples, out var sampleRate))
        {
            var hashes = await FingerprintCommandBuilder.Instance
                .BuildFingerprintCommand()
                .From(new AudioSamples(samples, path, sampleRate))
                .Hash();
            return (hashes, group);
        }

        try
        {
            var hashes = await FingerprintCommandBuilder.Instance
                .BuildFingerprintCommand()
                .From(path)
                .UsingServices(ffmpeg)
                .Hash();
            return (hashes, group);
        }
        catch (IOException ex)
        {
            Console.Error.WriteLine($"decode failed for {path}: {ex.Message}");
            return (null, group);
        }
    }

    private static string GroupFromSidecar(string path, WorkerConfig config)
    {
        var dirName = Path.GetDirectoryName(path) ?? "";
        if (!dirName.StartsWith(CandidateWriter.CandidatesDir(config), StringComparison.Ordinal))
            return "manual";
        var sighting = SightingStore.LoadAll(dirName).FirstOrDefault(s => s.File == Path.GetFileName(path));
        return sighting is { Group.Length: > 0 } ? sighting.Group : "manual";
    }
}

/// <summary>
/// A CLI-backed IAudioService over the system ffmpeg/ffprobe. The 18.0.0
/// base package ships only the 44-byte-header s16 decoder
/// (SoundFingerprintingAudioService — its FFmpegAudioService moved to the
/// SoundFingerprinting.Emy client package), so the arbitrary-format --dir
/// lane carries this thin service (the R1 §4 canonical insert shape:
/// From(file).UsingServices(FFmpegAudioService).Hash()).
/// </summary>
public sealed class FFmpegAudioService : IAudioService
{
    /// <summary>
    /// Arbitrary formats the ffmpeg CLI decodes for the --dir lane (the
    /// worker's own 44-byte-header files decode directly, before this
    /// service is consulted).
    /// </summary>
    public IReadOnlyCollection<string> SupportedFormats { get; } =
    [
        ".mp3", ".m4a", ".aac", ".ogg", ".oga", ".flac", ".wma",
        ".mp4", ".mov", ".avi", ".mkv",
    ];

    public AudioSamples ReadMonoSamplesFromFile(string pathToSourceFile, int sampleRate, double seconds, double startAt)
    {
        // The base service's contract: seconds < 0.001 = the whole file.
        var seekArgs = startAt > 0.001 ? $"-ss {startAt.ToString("R", CultureInfo.InvariantCulture)} " : "";
        var limitArgs = Math.Abs(seconds) < 0.001 ? "" : $"-t {seconds.ToString("R", CultureInfo.InvariantCulture)} ";
        using var ffmpeg = RunProcess("ffmpeg",
            $"-nostdin -hide_banner {seekArgs}-i \"{pathToSourceFile}\" {limitArgs}-vn -ac 1 -ar {sampleRate} -f f32le -");
        using var pcm = new MemoryStream();
        ffmpeg.StandardOutput.BaseStream.CopyTo(pcm);
        EnsureCleanExit(ffmpeg);
        var bytes = pcm.ToArray();
        var samples = new float[bytes.Length / 4];
        for (var i = 0; i < samples.Length; i++)
            samples[i] = BitConverter.ToSingle(bytes.AsSpan(i * 4, 4));
        return new AudioSamples(samples, pathToSourceFile, sampleRate);
    }

    public AudioSamples ReadMonoSamplesFromFile(string pathToSourceFile, int sampleRate) =>
        ReadMonoSamplesFromFile(pathToSourceFile, sampleRate, 0, 0);

    /// <summary>The file's length in seconds (ffprobe).</summary>
    public float GetLengthInSeconds(string file)
    {
        using var probe = RunProcess("ffprobe",
            $"-v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \"{file}\"");
        var text = probe.StandardOutput.ReadToEnd().Trim();
        EnsureCleanExit(probe);
        return float.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds) ? seconds : 0f;
    }

    private static Process RunProcess(string fileName, string arguments)
    {
        var psi = new ProcessStartInfo(fileName)
        {
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        return Process.Start(psi) ?? throw new IOException($"{fileName} failed to start");
    }

    private static void EnsureCleanExit(Process process)
    {
        if (!process.WaitForExit(30_000))
        {
            process.Kill(true);
            throw new IOException($"{process.ProcessName} did not exit within 30 s");
        }
        if (process.ExitCode != 0)
            throw new IOException($"{process.ProcessName} exited {process.ExitCode}: {process.StandardError.ReadToEnd().Trim()}");
    }
}
