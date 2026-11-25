using Microsoft.Extensions.Logging;
using SoundFingerprinting.InMemory;

namespace AudioAdDetection;

/// <summary>
/// The worker's model service: an InMemoryModelService that loads from
/// MODEL_DIR at startup (restart = file load, not re-fingerprint — R1 §3)
/// and snapshots back to MODEL_DIR on shutdown. The snapshot is the
/// directory form: <c>audio</c> + <c>video</c> files under the directory,
/// followed by the completion marker — a crash mid-Snapshot leaves the
/// marker missing, and the next boot starts empty instead of loading a
/// partial store (the catalogue re-bootstraps via auto-capture).
/// </summary>
public sealed class ModelService
{
    private const string SnapshotMarkerFile = "snapshot.complete";

    private readonly InMemoryModelService _inner;
    private readonly WorkerConfig _config;
    private bool _ready;

    public ModelService(WorkerConfig config, ILoggerFactory loggerFactory, ILogger<ModelService> logger)
    {
        _config = config;

        // An empty or missing model dir is the normal first-boot state
        // (auto-capture bootstrap: the catalogue starts empty) — load only
        // when the snapshot store AND its completion marker are actually
        // present, never fatal.
        var hasStore = Directory.Exists(config.ModelDir) && File.Exists(Path.Combine(config.ModelDir, "audio"));
        var hasMarker = File.Exists(Path.Combine(config.ModelDir, SnapshotMarkerFile));

        if (hasStore && hasMarker)
        {
            _inner = new InMemoryModelService(config.ModelDir, loggerFactory);
        }
        else if (hasStore)
        {
            // A crash between the snapshot write and the marker: the store
            // on disk is partial — start empty rather than load it (the
            // next shutdown snapshot rewrites the store + marker).
            logger.LogWarning(
                "partial model snapshot in {ModelDir} (the completion marker is missing) — starting with an empty catalogue",
                config.ModelDir);
            _inner = new InMemoryModelService(loggerFactory);
        }
        else
        {
            logger.LogInformation(
                "no model snapshot in {ModelDir} — starting with an empty catalogue (auto-capture bootstrap)",
                config.ModelDir);
            _inner = new InMemoryModelService(loggerFactory);
        }

        _ready = true;
    }

    /// <summary>True once the startup load attempt has completed (loaded, or bootstrapped empty) — the /readyz model leg.</summary>
    public bool Ready => _ready;

    public IModelService Inner => _inner;

    /// <summary>
    /// Snapshot to MODEL_DIR (creates the directory when missing; idempotent).
    /// The marker is written only after the store files are complete: a
    /// crash mid-snapshot leaves it missing, and the load path treats a
    /// store-without-marker as partial (empty start, never a partial load).
    /// </summary>
    public void Snapshot()
    {
        _inner.Snapshot(_config.ModelDir);
        File.WriteAllText(Path.Combine(_config.ModelDir, SnapshotMarkerFile), DateTime.UtcNow.ToString("O"));
    }
}
