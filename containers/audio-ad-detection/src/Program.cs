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
    // The low-priority curator path (retention + auto-promotion) and the
    // capture state machine (exclusive consumer of the producer's
    // per-consumer capture queue) are added as singletons + hosted
    // services the same way the supervisor is, so a second constructor
    // resolution cannot launch a second instance.
    services.AddSingleton<Curator>();
    services.AddHostedService(sp => sp.GetRequiredService<Curator>());
    services.AddHostedService<CaptureMachine>();
    // Hosted services start in registration order: the producer must be up
    // before the query leg consumes its chunk queue.
    services.AddHostedService<AudioPipeline>();
    services.AddHostedService<RealtimeQuery>();
    services.AddHostedService<HealthMetricsServer>();
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
var sigterm = new PosixSignalRegistration();
sigterm.Register(PosixSignal.SIGTERM, context =>
{
    context.Cancel = true;
    return true;
});

await app.RunAsync();
await publisher.DisconnectAsync();
model.Snapshot();
return 0;
