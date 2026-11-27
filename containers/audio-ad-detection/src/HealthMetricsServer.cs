using System.Globalization;
using System.Net;
using System.Text;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace AudioAdDetection;

/// <summary>
/// The health + metrics surface: a plain System.Net.HttpListener on
/// 0.0.0.0:HEALTH_PORT (the runtime image has no ASP.NET Core shared
/// framework, so no Kestrel — R3 §1), with a hand-rolled text /metrics
/// exposition (no extra package).
/// </summary>
public sealed class HealthMetricsServer : BackgroundService
{
    private readonly WorkerConfig _config;
    private readonly SnapClientSupervisor _supervisor;
    private readonly IStreamState _state;
    private readonly Curator _curator;
    private readonly ModelService _model;
    private readonly QueryStatus _queryStatus;
    private readonly BrokerPublisher _publisher;
    private readonly ILogger<HealthMetricsServer> _logger;
    private HttpListener? _listener;

    public HealthMetricsServer(
        WorkerConfig config,
        SnapClientSupervisor supervisor,
        IStreamState state,
        Curator curator,
        ModelService model,
        QueryStatus queryStatus,
        BrokerPublisher publisher,
        ILogger<HealthMetricsServer> logger)
    {
        _config = config;
        _supervisor = supervisor;
        // IStreamState.CurrentRmsDb feeds aad_audio_rms_db (LastMatchAt /
        // LastMatchMeta are capture-state-machine inputs, not this surface).
        _state = state;
        _curator = curator;
        // The three /readyz legs beyond the pipe: model loaded (or
        // bootstrapped empty), query leg running, broker session connected.
        _model = model;
        _queryStatus = queryStatus;
        _publisher = publisher;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _listener = new HttpListener();
        _listener.Prefixes.Add($"http://0.0.0.0:{_config.HealthPort}/");
        _listener.Start();
        _logger.LogInformation("health/metrics listening on 0.0.0.0:{Port} (/healthz, /readyz, /metrics)",
            _config.HealthPort);

        while (!stoppingToken.IsCancellationRequested)
        {
            var accept = _listener.GetContextAsync();
            var stopped = Task.Delay(Timeout.Infinite, stoppingToken);
            if (await Task.WhenAny(accept, stopped) != accept)
                break;

            var context = await accept;
            try
            {
                Handle(context);
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "request handling failed");
            }
        }

        _listener.Stop();
        _logger.LogInformation("health/metrics listener stopped");
    }

    private void Handle(HttpListenerContext context)
    {
        var path = context.Request.Url?.AbsolutePath ?? "/";
        switch (path)
        {
            case "/healthz":
                var healthy = _supervisor.ChildAlive;
                Respond(context, healthy ? 200 : 503, "text/plain; charset=utf-8",
                    healthy ? "ok: process alive + snapclient child alive\n" : "degraded: snapclient child not alive\n");
                break;
            case "/readyz":
                var ready = _supervisor.PipeDelivering && _model.Ready && _queryStatus.Running && _publisher.Connected;
                Respond(context, ready ? 200 : 503, "text/plain; charset=utf-8",
                    ready ? "ready (pipe delivering + model loaded + query running + broker connected)\n"
                        : "not ready (pipe / model / query / broker)\n");
                break;
            case "/metrics":
                Respond(context, 200, "text/plain; version=0.0.4; charset=utf-8", MetricsExposition());
                break;
            default:
                Respond(context, 404, "text/plain; charset=utf-8", "not found\n");
                break;
        }
    }

    private string MetricsExposition()
    {
        var sb = new StringBuilder();
        sb.AppendLine("# HELP aad_audio_rms_db Per-chunk RMS of the resampled audio stream (dBFS); NaN while no reading is available yet");
        sb.AppendLine("# TYPE aad_audio_rms_db gauge");
        sb.AppendLine($"aad_audio_rms_db {FormatPrometheus(_state.CurrentRmsDb)}");
        sb.AppendLine("# HELP aad_capture_candidates_total Candidate ad captures produced by the auto-capture state machine");
        sb.AppendLine("# TYPE aad_capture_candidates_total counter");
        sb.AppendLine($"aad_capture_candidates_total {_supervisor.CaptureCandidatesTotal}");
        sb.AppendLine("# HELP aad_snapclient_kills_total snapclient processes killed by the byte-cadence watchdog");
        sb.AppendLine("# TYPE aad_snapclient_kills_total counter");
        sb.AppendLine($"aad_snapclient_kills_total {_supervisor.KillsTotal}");
        sb.AppendLine("# HELP aad_auto_promotions_total Candidates auto-promoted into the live catalogue (recurrence gate passed)");
        sb.AppendLine("# TYPE aad_auto_promotions_total counter");
        sb.AppendLine($"aad_auto_promotions_total {_curator.AutoPromotionsTotal}");
        sb.AppendLine("# HELP aad_auto_promotions_capped_total Auto-promotions skipped on the per-day cap");
        sb.AppendLine("# TYPE aad_auto_promotions_capped_total counter");
        sb.AppendLine($"aad_auto_promotions_capped_total {_curator.AutoPromotionsCappedTotal}");
        return sb.ToString();
    }

    private static string FormatPrometheus(double value) =>
        value is double.NaN ? "NaN" : value.ToString("R", CultureInfo.InvariantCulture);

    private static void Respond(HttpListenerContext context, int status, string contentType, string body)
    {
        context.Response.StatusCode = status;
        context.Response.ContentType = contentType;
        var bytes = Encoding.UTF8.GetBytes(body);
        context.Response.ContentLength64 = bytes.Length;
        context.Response.OutputStream.Write(bytes, 0, bytes.Length);
        context.Response.Close();
    }
}
