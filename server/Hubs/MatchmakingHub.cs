using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using ZombieSurvivalServer.Services;

namespace ZombieSurvivalServer.Hubs;

/// <summary>
/// Real-time hub for matchmaking updates
/// </summary>
[Authorize]
public class MatchmakingHub : Hub
{
    private readonly IMatchmakingService _matchmakingService;
    private readonly ILogger<MatchmakingHub> _logger;

    // Track active matchmaking connections
    private static readonly Dictionary<string, MatchmakingConnection> _connections = new();
    private static readonly object _lock = new();

    public MatchmakingHub(IMatchmakingService matchmakingService, ILogger<MatchmakingHub> logger)
    {
        _matchmakingService = matchmakingService;
        _logger = logger;
    }

    public override async Task OnConnectedAsync()
    {
        var userId = GetUserId();
        if (userId.HasValue)
        {
            lock (_lock)
            {
                _connections[Context.ConnectionId] = new MatchmakingConnection
                {
                    PlayerId = userId.Value,
                    ConnectionId = Context.ConnectionId
                };
            }

            _logger.LogInformation("Player {PlayerId} connected to MatchmakingHub", userId.Value);
        }

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        lock (_lock)
        {
            if (_connections.TryGetValue(Context.ConnectionId, out var connection))
            {
                // Cancel any active matchmaking
                if (!string.IsNullOrEmpty(connection.TicketId))
                {
                    _ = _matchmakingService.CancelAsync(connection.TicketId);
                }

                _connections.Remove(Context.ConnectionId);
                _logger.LogInformation("Player {PlayerId} disconnected from MatchmakingHub", connection.PlayerId);
            }
        }

        await base.OnDisconnectedAsync(exception);
    }

    /// <summary>
    /// Start searching for a match
    /// </summary>
    public async Task StartMatchmaking(string gameMode, string? preferredRegion = null, string? preferredMap = null)
    {
        var userId = GetUserId();
        if (!userId.HasValue)
        {
            await Clients.Caller.SendAsync("MatchmakingError", "Not authenticated");
            return;
        }

        var request = new Models.MatchmakingRequest
        {
            GameMode = gameMode,
            PreferredRegion = preferredRegion,
            PreferredMap = preferredMap
        };

        var ticketId = await _matchmakingService.JoinQueueAsync(userId.Value, request);

        lock (_lock)
        {
            if (_connections.TryGetValue(Context.ConnectionId, out var connection))
            {
                connection.TicketId = ticketId;
            }
        }

        await Clients.Caller.SendAsync("MatchmakingStarted", new { TicketId = ticketId });

        // Start polling for updates
        _ = PollMatchmakingStatus(Context.ConnectionId, ticketId);

        _logger.LogInformation("Player {PlayerId} started matchmaking for {GameMode}", userId.Value, gameMode);
    }

    /// <summary>
    /// Cancel matchmaking
    /// </summary>
    public async Task CancelMatchmaking()
    {
        lock (_lock)
        {
            if (_connections.TryGetValue(Context.ConnectionId, out var connection))
            {
                if (!string.IsNullOrEmpty(connection.TicketId))
                {
                    _ = _matchmakingService.CancelAsync(connection.TicketId);
                    connection.TicketId = null;
                }
            }
        }

        await Clients.Caller.SendAsync("MatchmakingCancelled");
    }

    /// <summary>
    /// Join a party for group matchmaking
    /// </summary>
    public async Task JoinParty(string partyCode)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"party_{partyCode}");
        await Clients.Group($"party_{partyCode}").SendAsync("PartyMemberJoined", new
        {
            PlayerId = GetUserId()
        });
    }

    /// <summary>
    /// Leave current party
    /// </summary>
    public async Task LeaveParty(string partyCode)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"party_{partyCode}");
        await Clients.Group($"party_{partyCode}").SendAsync("PartyMemberLeft", new
        {
            PlayerId = GetUserId()
        });
    }

    // ============================================
    // PRIVATE METHODS
    // ============================================

    private async Task PollMatchmakingStatus(string connectionId, string ticketId)
    {
        var maxAttempts = 120; // 2 minutes at 1 second intervals
        var attempt = 0;

        while (attempt < maxAttempts)
        {
            await Task.Delay(1000);

            // Check if connection still exists
            MatchmakingConnection? connection;
            lock (_lock)
            {
                if (!_connections.TryGetValue(connectionId, out connection) ||
                    connection.TicketId != ticketId)
                {
                    return; // Connection closed or matchmaking cancelled
                }
            }

            var status = await _matchmakingService.GetStatusAsync(ticketId);

            // Send update to client
            try
            {
                await Clients.Client(connectionId).SendAsync("MatchmakingUpdate", status);
            }
            catch
            {
                return; // Client disconnected
            }

            if (status.Status == "found")
            {
                _logger.LogInformation("Match found for ticket {TicketId}", ticketId);

                // Clear ticket
                lock (_lock)
                {
                    if (_connections.TryGetValue(connectionId, out connection))
                    {
                        connection.TicketId = null;
                    }
                }

                return;
            }

            if (status.Status == "error" || status.Status == "cancelled")
            {
                return;
            }

            attempt++;
        }

        // Timeout - cancel matchmaking
        await _matchmakingService.CancelAsync(ticketId);
        try
        {
            await Clients.Client(connectionId).SendAsync("MatchmakingTimeout");
        }
        catch { /* Client may be disconnected */ }
    }

    private int? GetUserId()
    {
        var idClaim = Context.User?.FindFirst("id")?.Value;
        return int.TryParse(idClaim, out var id) ? id : null;
    }

    private class MatchmakingConnection
    {
        public int PlayerId { get; set; }
        public string ConnectionId { get; set; } = string.Empty;
        public string? TicketId { get; set; }
    }
}
