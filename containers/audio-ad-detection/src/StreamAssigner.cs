using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Logging;

namespace AudioAdDetection;

/// <summary>
/// The one-shot startup stream assignment: re-point the group containing the
/// pinned hostID at SNAP_STREAM_ID over the JSON-RPC endpoint. Runs once per
/// child start, never in a hot loop — a fresh CodecHeader is a #1563
/// exposure event (R2 §5). Best-effort: a failure is logged, not fatal, and
/// readiness does not depend on the assignment (config-order is a working
/// state on the deployed 0.28.0 server).
/// </summary>
public sealed class StreamAssigner
{
    private static readonly HttpClient Rpc = new() { Timeout = TimeSpan.FromSeconds(10) };

    private readonly WorkerConfig _config;
    private readonly ILogger<StreamAssigner> _logger;

    public StreamAssigner(WorkerConfig config, ILogger<StreamAssigner> logger)
    {
        _config = config;
        _logger = logger;
    }

    /// <summary>
    /// True when SNAP_STREAM_ID holds a real value — the documented
    /// placeholder (TBD-owner) and the empty value are "unassigned".
    /// </summary>
    public static bool HasRealStreamId(string streamId) =>
        !string.IsNullOrWhiteSpace(streamId) && streamId != "TBD-owner";

    /// <summary>
    /// The tapped group's reference (its name, or the id when unnamed),
    /// learned from the Server.GetStatus answer — the capture naming leg;
    /// null until the first successful lookup (the naming falls back to the
    /// pinned hostID).
    /// </summary>
    public string? GroupRef
    {
        get { return _groupRef; }
        private set => _groupRef = value;
    }

    private string? _groupRef;

    public async Task AssignOnceAsync(CancellationToken ct)
    {
        if (!HasRealStreamId(_config.SnapStreamId))
        {
            _logger.LogInformation(
                "SNAP_STREAM_ID unassigned (empty or 'TBD-owner') — the group stays in config-order; no Group.SetStream RPC sent (readiness is not blocked)");
            return;
        }

        try
        {
            var status = await PostAsync("Server.GetStatus", new JsonObject(), ct);
            var groupId = FindGroupIdForHost(status, _config.SnapHostId);
            if (groupId is null)
            {
                _logger.LogWarning(
                    "no group for hostID {HostId} in the Server.GetStatus answer yet — config-order applies until the next attempt",
                    _config.SnapHostId);
                return;
            }

            var setParams = new JsonObject
            {
                ["id"] = groupId.DeepClone(),
                ["stream_id"] = _config.SnapStreamId,
            };
            await PostAsync("Group.SetStream", setParams, ct);
            _groupRef = FindGroupRefForHost(status, _config.SnapHostId);
            _logger.LogInformation("stream assigned: group {GroupId} -> stream {StreamId}",
                groupId, _config.SnapStreamId);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            _logger.LogDebug("stream assignment cancelled at shutdown");
        }
        catch (Exception ex)
        {
            // Best-effort boundary: a failed re-point is not fatal —
            // config-order still works and the next child start retries.
            _logger.LogWarning(ex, "stream assignment failed (best-effort) — config-order applies");
        }
    }

    private static JsonNode? FindGroupIdForHost(JsonDocument status, string hostId)
    {
        foreach (var group in status.RootElement.EnumerateObject()
            .Single(p => p.Name == "groups").Value.EnumerateArray())
        {
            var id = group.EnumerateObject().First(p => p.Name == "id").Value;
            var clients = group.EnumerateObject().First(p => p.Name == "clients").Value;
            foreach (var client in clients.EnumerateArray())
            {
                var clientId = client.EnumerateObject().First(p => p.Name == "id").Value;
                if (clientId.ValueKind == JsonValueKind.String && clientId.GetString() == hostId)
                    return JsonNode.Parse(id.GetRawText());
                if (clientId.ValueKind == JsonValueKind.Number && clientId.GetRawText() == hostId)
                    return JsonNode.Parse(id.GetRawText());
            }
        }
        return null;
    }

    /// <summary>
    /// The group reference for the capture naming leg: the group's name
    /// when it carries one, else its id — the same hostID lookup the
    /// assignment keys on.
    /// </summary>
    private static string? FindGroupRefForHost(JsonDocument status, string hostId)
    {
        foreach (var group in status.RootElement.EnumerateObject()
            .Single(p => p.Name == "groups").Value.EnumerateArray())
        {
            var clients = group.EnumerateObject().First(p => p.Name == "clients").Value;
            var matched = false;
            foreach (var client in clients.EnumerateArray())
            {
                var clientId = client.EnumerateObject().First(p => p.Name == "id").Value;
                if (clientId.ValueKind == JsonValueKind.String && clientId.GetString() == hostId)
                    matched = true;
                if (clientId.ValueKind == JsonValueKind.Number && clientId.GetRawText() == hostId)
                    matched = true;
            }
            if (!matched)
                continue;

            string? name = null;
            foreach (var property in group.EnumerateObject())
            {
                if (property.Name == "name" && property.Value.ValueKind == JsonValueKind.String)
                    name = property.Value.GetString();
            }
            if (!string.IsNullOrWhiteSpace(name))
                return name;

            var id = group.EnumerateObject().First(p => p.Name == "id").Value;
            return id.ValueKind == JsonValueKind.String ? id.GetString() : id.GetRawText();
        }
        return null;
    }

    private async Task<JsonDocument> PostAsync(string method, JsonObject @params, CancellationToken ct)
    {
        var request = new JsonObject
        {
            ["jsonrpc"] = "2.0",
            ["id"] = 1,
            ["method"] = method,
            ["params"] = @params,
        };
        using var message = new HttpRequestMessage(HttpMethod.Post, _config.SnapRpcUrl)
        {
            Content = new StringContent(request.ToJsonString(), Encoding.UTF8),
        };
        message.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
        using var response = await Rpc.SendAsync(message, ct);
        var body = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException($"JSON-RPC {method} -> HTTP {(int)response.StatusCode}");
        return JsonDocument.Parse(body);
    }
}
