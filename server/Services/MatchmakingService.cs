using System.Collections.Concurrent;
using ZombieSurvivalServer.Models;

namespace ZombieSurvivalServer.Services;

public interface IMatchmakingService
{
    Task<string> JoinQueueAsync(int playerId, MatchmakingRequest request);
    Task<MatchmakingStatus> GetStatusAsync(string ticketId);
    Task CancelAsync(string ticketId);
    Task ProcessMatchmakingAsync();
}

public class MatchmakingService : IMatchmakingService
{
    private readonly IServerBrowserService _serverBrowser;
    private readonly ILogger<MatchmakingService> _logger;

    // In-memory queue (in production, use Redis or similar)
    private static readonly ConcurrentDictionary<string, MatchmakingTicket> _tickets = new();
    private static readonly ConcurrentDictionary<string, List<MatchmakingTicket>> _pools = new();

    public MatchmakingService(IServerBrowserService serverBrowser, ILogger<MatchmakingService> logger)
    {
        _serverBrowser = serverBrowser;
        _logger = logger;
    }

    public Task<string> JoinQueueAsync(int playerId, MatchmakingRequest request)
    {
        var ticketId = Guid.NewGuid().ToString("N");

        var ticket = new MatchmakingTicket
        {
            TicketId = ticketId,
            PlayerId = playerId,
            GameMode = request.GameMode,
            PreferredRegion = request.PreferredRegion,
            PreferredMap = request.PreferredMap,
            MinPlayers = request.MinPlayers,
            MaxPlayers = request.MaxPlayers,
            CreatedAt = DateTime.UtcNow,
            Status = MatchmakingTicketStatus.Searching
        };

        _tickets[ticketId] = ticket;

        // Add to pool
        var poolKey = $"{request.GameMode}:{request.PreferredRegion ?? "any"}";
        _pools.AddOrUpdate(poolKey,
            _ => new List<MatchmakingTicket> { ticket },
            (_, list) => { list.Add(ticket); return list; });

        _logger.LogInformation("Player {PlayerId} joined matchmaking queue for {GameMode}", playerId, request.GameMode);

        return Task.FromResult(ticketId);
    }

    public async Task<MatchmakingStatus> GetStatusAsync(string ticketId)
    {
        if (!_tickets.TryGetValue(ticketId, out var ticket))
        {
            return new MatchmakingStatus
            {
                Status = "error",
                Error = "Ticket not found"
            };
        }

        // Check if we found a server
        if (ticket.Status == MatchmakingTicketStatus.Found && ticket.FoundServer != null)
        {
            return new MatchmakingStatus
            {
                Status = "found",
                FoundServer = ticket.FoundServer
            };
        }

        // Still searching - try to find a server
        var servers = await _serverBrowser.GetServersAsync(
            region: ticket.PreferredRegion,
            gameMode: ticket.GameMode,
            hideEmpty: false,
            hideFull: true
        );

        // Look for available server
        var suitableServer = servers.FirstOrDefault(s =>
            s.CurrentPlayers < s.MaxPlayers &&
            s.Status == "waiting" &&
            (string.IsNullOrEmpty(ticket.PreferredMap) || s.MapName == ticket.PreferredMap));

        if (suitableServer != null)
        {
            ticket.Status = MatchmakingTicketStatus.Found;
            ticket.FoundServer = suitableServer;

            return new MatchmakingStatus
            {
                Status = "found",
                FoundServer = suitableServer
            };
        }

        // Count players in queue
        var poolKey = $"{ticket.GameMode}:{ticket.PreferredRegion ?? "any"}";
        var playersInQueue = _pools.TryGetValue(poolKey, out var pool) ? pool.Count : 1;

        // Estimate wait time
        var waitTime = Math.Max(5, 30 - (playersInQueue * 3));

        return new MatchmakingStatus
        {
            Status = "searching",
            PlayersInQueue = playersInQueue,
            EstimatedWaitSeconds = waitTime
        };
    }

    public Task CancelAsync(string ticketId)
    {
        if (_tickets.TryRemove(ticketId, out var ticket))
        {
            // Remove from pool
            var poolKey = $"{ticket.GameMode}:{ticket.PreferredRegion ?? "any"}";
            if (_pools.TryGetValue(poolKey, out var pool))
            {
                pool.RemoveAll(t => t.TicketId == ticketId);
            }

            _logger.LogInformation("Player {PlayerId} cancelled matchmaking", ticket.PlayerId);
        }

        return Task.CompletedTask;
    }

    public async Task ProcessMatchmakingAsync()
    {
        // This would run periodically to match players and create lobbies
        foreach (var poolKvp in _pools)
        {
            var pool = poolKvp.Value;

            // Remove expired tickets (older than 5 minutes)
            var cutoff = DateTime.UtcNow.AddMinutes(-5);
            pool.RemoveAll(t =>
            {
                if (t.CreatedAt < cutoff)
                {
                    t.Status = MatchmakingTicketStatus.Expired;
                    _tickets.TryRemove(t.TicketId, out _);
                    return true;
                }
                return false;
            });

            // Try to find servers for waiting players
            var searchingTickets = pool.Where(t => t.Status == MatchmakingTicketStatus.Searching).ToList();

            if (!searchingTickets.Any())
                continue;

            // Get the game mode and region from pool key
            var keyParts = poolKvp.Key.Split(':');
            var gameMode = keyParts[0];
            var region = keyParts.Length > 1 && keyParts[1] != "any" ? keyParts[1] : null;

            var servers = await _serverBrowser.GetServersAsync(
                region: region,
                gameMode: gameMode,
                hideFull: true
            );

            foreach (var server in servers.Where(s => s.Status == "waiting"))
            {
                var availableSlots = server.MaxPlayers - server.CurrentPlayers;

                var ticketsToMatch = searchingTickets.Take(availableSlots).ToList();

                foreach (var ticket in ticketsToMatch)
                {
                    ticket.Status = MatchmakingTicketStatus.Found;
                    ticket.FoundServer = server;
                    searchingTickets.Remove(ticket);
                }

                if (!searchingTickets.Any())
                    break;
            }
        }
    }
}

public class MatchmakingTicket
{
    public string TicketId { get; set; } = string.Empty;
    public int PlayerId { get; set; }
    public string GameMode { get; set; } = string.Empty;
    public string? PreferredRegion { get; set; }
    public string? PreferredMap { get; set; }
    public int MinPlayers { get; set; }
    public int MaxPlayers { get; set; }
    public DateTime CreatedAt { get; set; }
    public MatchmakingTicketStatus Status { get; set; }
    public ServerListResponse? FoundServer { get; set; }
}

public enum MatchmakingTicketStatus
{
    Searching,
    Found,
    Expired,
    Cancelled
}
