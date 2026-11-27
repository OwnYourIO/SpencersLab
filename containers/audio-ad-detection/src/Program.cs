using System.Runtime.InteropServices;
using AudioAdDetection;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

// The headless ad-detection worker: a Generic Host that supervises the
// snapclient file-player child, serves the health/metrics surface, and
// re-points its snapcast group at SNAP_STREAM_ID on startup. The C02b
// subcommands (promote / list / prune) are one-shot CLI lanes — no host.
var config = WorkerConfig.FromEnvironment();

if (args.Length > 0)
{
    using var loggerFactory = LoggerFactory.Create(b => b.AddConsole().SetMinimumLevel(LogLevel.Information));
    var subArgs = args.Skip(1).ToArray();
    var code = args[0] switch
    {
        "promote" => await PromoteCommand.RunAsync(subArgs, config, loggerFactory),
        "list" => await ListCommand.RunAsync(subArgs, config, loggerFactory),
        "prune" => await PruneCommand.RunAsync(subArgs, config, loggerFactory),
        _ => UnknownSubcommand(args[0]),
    };
    return code;
}

int UnknownSubcommand(string name)
{
    Console.Error.WriteLine($"unknown subcommand '{name}' (expected: promote, list, prune)");
    return 2;
}

var builder = Host.CreateDefaultBuilder(args);
builder.ConfigureLogging(logging =>
{
    logging.SetMinimumLevel(LogLevel.Information);
    logging.AddConsole();
});
builder.ConfigureServices(services =>
{
    services.AddSingleton(config);
    services.AddSingleton<StreamAssigner>();
    // BrokerPublisher and QueryStatus are singletons added as hosted
    // services the same way the supervisor is: AddHostedService<T>
    // registers T as transient, and a second constructor resolution would
    // otherwise open a second broker session / start a second query leg.
    // The publisher is registered BEFORE the supervisor on purpose: the
    // host stops hosted services in reverse registration order, so the
    // graceful MQTT disconnect lands after the child is gone.
    services.AddSingleton<BrokerPublisher>();
    services.AddHostedService(sp => sp.GetRequiredService<BrokerPublisher>());
    services.AddSingleton<QueryStatus>();
    // The supervisor is a singleton added as a hosted service:
    // AddHostedService<T> registers T as transient, and a second
    // constructor resolution (HealthMetricsServer) would otherwise launch a
    // second snapclient child.
    services.AddSingleton<SnapClientSupervisor>();
    services.AddHostedService(sp => sp.GetRequiredService<SnapClientSupervisor>());
    // IStreamState (LastMatchAt / LastMatchMeta / CurrentRmsDb) is the
    // cross-component seam: the pipeline leg writes the per-chunk RMS, the
    // query leg writes the last match, and the metrics surface reads
    // CurrentRmsDb.
    services.AddSingleton<IStreamState, StreamState>();
    services.AddSingleton<IAdEventSink, BrokerAdEventSink>();
    services.AddSingleton<ModelService>();
    // The low-priority curator path (retention + auto-promotion) is added
    // as a singleton + hosted service the same way the supervisor is, so
    // a second constructor resolution cannot launch a second instance.
    services.AddSingleton<Curator>();
    services.AddHostedService(sp => sp.GetRequiredService<Curator>());
    // The remaining hosted services follow the same singleton +
    // existing-instance law: AddHostedService<T> registers T only as a
    // transient IHostedService contribution — T is not resolvable as
    // itself, so a consumer's constructor demand for it throws at host
    // start (the CaptureMachine -> AudioPipeline crash), and a second
    // resolution would launch a second instance (the supervisor bug).
    // AudioPipeline must be the shared singleton: the fan-out design
    // hands the one producer's per-consumer queue to both the query and
    // capture legs — a transient producer would give each leg its own
    // queue. Hosted start order is the registration order and the host
    // stops in reverse: the producer stays before its consumers, and the
    // order keeps the graceful MQTT disconnect after the child is gone.
    services.AddSingleton<CaptureMachine>();
    services.AddHostedService(sp => sp.GetRequiredService<CaptureMachine>());
    services.AddSingleton<AudioPipeline>();
    services.AddHostedService(sp => sp.GetRequiredService<AudioPipeline>());
    services.AddSingleton<RealtimeQuery>();
    services.AddHostedService(sp => sp.GetRequiredService<RealtimeQuery>());
    services.AddSingleton<HealthMetricsServer>();
    services.AddHostedService(sp => sp.GetRequiredService<HealthMetricsServer>());
});
var app = builder.Build();

var publisher = app.Services.GetRequiredService<BrokerPublisher>();
var model = app.Services.GetRequiredService<ModelService>();

// The SIGTERM handler composes the ordered shutdown: context.Cancel starts
// the host stop, which stops the hosted services in reverse registration
// order — query Cancel, reader stop, the snapclient child TERM (5 s grace
// -> Kill), and only then the pipe read end
// Close, then the MQTT Disconnect (the publisher is registered before the
// supervisor, so it stops after the child is gone). RunAsync returns only
// when that stop has finished. The remaining legs are the snapshot-on-exit
// (the restart-load contract) and the idempotent MQTT disconnect safety
// net; everything must land well inside the 30 s K8s grace.
var sigterm = PosixSignalRegistration.Create(PosixSignal.SIGTERM, context =>
{
    context.Cancel = true;
});

await app.RunAsync();
await publisher.DisconnectAsync();
model.Snapshot();
return 0;
