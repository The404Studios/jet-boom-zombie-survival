using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using ZombieSurvivalServer.Models;
using ZombieSurvivalServer.Services;

namespace ZombieSurvivalServer.Hubs;

/// <summary>
/// Real-time hub for game server communication
/// </summary>
[Authorize]
public class GameHub : Hub
{
    private readonly IGameServerRegistry _serverRegistry;
    private readonly IServerBrowserService _serverBrowser;
    private readonly ILogger<GameHub> _logger;

    // Connection tracking
    private static readonly Dictionary<string, int> _connectionToPlayer = new();
    private static readonly Dictionary<int, string> _playerToConnection = new();
    private static readonly object _lock = new();

    public GameHub(
        IGameServerRegistry serverRegistry,
        IServerBrowserService serverBrowser,
        ILogger<GameHub> logger)
    {
        _serverRegistry = serverRegistry;
        _serverBrowser = serverBrowser;
        _logger = logger;
    }

    public override async Task OnConnectedAsync()
    {
        var userId = GetUserId();
        if (userId.HasValue)
        {
            lock (_lock)
            {
                _connectionToPlayer[Context.ConnectionId] = userId.Value;
                _playerToConnection[userId.Value] = Context.ConnectionId;
            }

            _logger.LogInformation("Player {PlayerId} connected to GameHub", userId.Value);
        }

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var userId = GetUserId();
        if (userId.HasValue)
        {
            lock (_lock)
            {
                _connectionToPlayer.Remove(Context.ConnectionId);
                _playerToConnection.Remove(userId.Value);
            }

            _logger.LogInformation("Player {PlayerId} disconnected from GameHub", userId.Value);
        }

        await base.OnDisconnectedAsync(exception);
    }

    // ============================================
    // PLAYER METHODS
    // ============================================

    /// <summary>
    /// Join a game server's channel for real-time updates
    /// </summary>
    public async Task JoinServer(int serverId)
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, $"server_{serverId}");
        _logger.LogInformation("Player joined server group: {ServerId}", serverId);
    }

    /// <summary>
    /// Leave a game server's channel
    /// </summary>
    public async Task LeaveServer(int serverId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"server_{serverId}");
    }

    /// <summary>
    /// Send chat message to server
    /// </summary>
    public async Task SendChatMessage(int serverId, string message)
    {
        var userId = GetUserId();
        if (!userId.HasValue)
            return;

        var username = Context.User?.Identity?.Name ?? "Unknown";

        await Clients.Group($"server_{serverId}").SendAsync("ChatMessage", new
        {
            PlayerId = userId.Value,
            Username = username,
            Message = message,
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Send voice activity indicator
    /// </summary>
    public async Task VoiceActivity(int serverId, bool isSpeaking)
    {
        var userId = GetUserId();
        if (!userId.HasValue)
            return;

        await Clients.Group($"server_{serverId}").SendAsync("VoiceActivity", new
        {
            PlayerId = userId.Value,
            IsSpeaking = isSpeaking
        });
    }

    // ============================================
    // GAME SERVER METHODS
    // ============================================

    /// <summary>
    /// Register as a game server (called by dedicated servers)
    /// </summary>
    public async Task RegisterGameServer(int serverId, string serverToken)
    {
        // Validate token (in production, verify against database)
        _serverRegistry.RegisterServer(serverId, Context.ConnectionId);
        await Groups.AddToGroupAsync(Context.ConnectionId, "game_servers");

        _logger.LogInformation("Game server {ServerId} registered via SignalR", serverId);
    }

    /// <summary>
    /// Broadcast game state to all players in server
    /// </summary>
    public async Task BroadcastGameState(int serverId, object gameState)
    {
        await Clients.Group($"server_{serverId}").SendAsync("GameState", gameState);
    }

    /// <summary>
    /// Broadcast wave start
    /// </summary>
    public async Task BroadcastWaveStart(int serverId, int waveNumber, int zombieCount)
    {
        await Clients.Group($"server_{serverId}").SendAsync("WaveStart", new
        {
            WaveNumber = waveNumber,
            ZombieCount = zombieCount
        });
    }

    /// <summary>
    /// Broadcast player death
    /// </summary>
    public async Task BroadcastPlayerDeath(int serverId, int playerId, string killerName, string weapon)
    {
        await Clients.Group($"server_{serverId}").SendAsync("PlayerDeath", new
        {
            PlayerId = playerId,
            KillerName = killerName,
            Weapon = weapon
        });
    }

    /// <summary>
    /// Broadcast player revival
    /// </summary>
    public async Task BroadcastPlayerRevive(int serverId, int revivedPlayerId, int reviverPlayerId)
    {
        await Clients.Group($"server_{serverId}").SendAsync("PlayerRevive", new
        {
            RevivedPlayerId = revivedPlayerId,
            ReviverPlayerId = reviverPlayerId
        });
    }

    /// <summary>
    /// Broadcast game end
    /// </summary>
    public async Task BroadcastGameEnd(int serverId, bool victory, int waveReached, object stats)
    {
        await Clients.Group($"server_{serverId}").SendAsync("GameEnd", new
        {
            Victory = victory,
            WaveReached = waveReached,
            Stats = stats
        });
    }

    // ============================================
    // BODY PART HEALTH METHODS
    // ============================================

    /// <summary>
    /// Broadcast body part health update to all players in the same server
    /// </summary>
    public async Task BroadcastBodyPartHealth(int serverId, BodyPartHealthDto health)
    {
        var userId = GetUserId();
        if (!userId.HasValue)
            return;

        await Clients.Group($"server_{serverId}").SendAsync("BodyPartHealthUpdated", new BodyPartHealthSyncMessage
        {
            PlayerId = userId.Value,
            Health = health,
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Broadcast damage taken to a body part
    /// </summary>
    public async Task BroadcastBodyPartDamage(int serverId, string bodyPart, float damage, float currentHp, float maxHp)
    {
        var userId = GetUserId();
        if (!userId.HasValue)
            return;

        await Clients.Group($"server_{serverId}").SendAsync("BodyPartDamaged", new
        {
            PlayerId = userId.Value,
            BodyPart = bodyPart,
            Damage = damage,
            CurrentHp = currentHp,
            MaxHp = maxHp,
            IsBlackedOut = currentHp <= 0,
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Broadcast healing started on a body part
    /// </summary>
    public async Task BroadcastHealingStarted(int serverId, string bodyPart)
    {
        var userId = GetUserId();
        if (!userId.HasValue)
            return;

        await Clients.Group($"server_{serverId}").SendAsync("HealingStarted", new
        {
            PlayerId = userId.Value,
            BodyPart = bodyPart,
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Broadcast healing progress update
    /// </summary>
    public async Task BroadcastHealingProgress(int serverId, string bodyPart, float progress)
    {
        var userId = GetUserId();
        if (!userId.HasValue)
            return;

        await Clients.Group($"server_{serverId}").SendAsync("HealingProgress", new
        {
            PlayerId = userId.Value,
            BodyPart = bodyPart,
            Progress = progress,
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Broadcast healing completed
    /// </summary>
    public async Task BroadcastHealingCompleted(int serverId, string bodyPart, float newHp, float maxHp)
    {
        var userId = GetUserId();
        if (!userId.HasValue)
            return;

        await Clients.Group($"server_{serverId}").SendAsync("HealingCompleted", new
        {
            PlayerId = userId.Value,
            BodyPart = bodyPart,
            NewHp = newHp,
            MaxHp = maxHp,
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Broadcast bleeding effect started (when body part is blacked out)
    /// </summary>
    public async Task BroadcastBleedingStarted(int serverId, string bodyPart)
    {
        var userId = GetUserId();
        if (!userId.HasValue)
            return;

        await Clients.Group($"server_{serverId}").SendAsync("BleedingStarted", new
        {
            PlayerId = userId.Value,
            BodyPart = bodyPart,
            Timestamp = DateTime.UtcNow
        });

        _logger.LogInformation("Player {PlayerId} started bleeding from {BodyPart}", userId.Value, bodyPart);
    }

    /// <summary>
    /// Broadcast bleeding effect stopped
    /// </summary>
    public async Task BroadcastBleedingStopped(int serverId, string bodyPart)
    {
        var userId = GetUserId();
        if (!userId.HasValue)
            return;

        await Clients.Group($"server_{serverId}").SendAsync("BleedingStopped", new
        {
            PlayerId = userId.Value,
            BodyPart = bodyPart,
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Send body part health update to a specific player
    /// </summary>
    public static async Task SendBodyPartHealthToPlayer(IHubContext<GameHub> hubContext, int playerId, BodyPartHealthDto health)
    {
        string? connectionId;
        lock (_lock)
        {
            _playerToConnection.TryGetValue(playerId, out connectionId);
        }

        if (connectionId != null)
        {
            await hubContext.Clients.Client(connectionId).SendAsync("BodyPartHealthUpdated", new BodyPartHealthSyncMessage
            {
                PlayerId = playerId,
                Health = health,
                Timestamp = DateTime.UtcNow
            });
        }
    }

    // ============================================
    // NOTIFICATION METHODS
    // ============================================

    /// <summary>
    /// Send notification to specific player
    /// </summary>
    public static async Task SendNotificationToPlayer(IHubContext<GameHub> hubContext, int playerId, string type, string message)
    {
        string? connectionId;
        lock (_lock)
        {
            _playerToConnection.TryGetValue(playerId, out connectionId);
        }

        if (connectionId != null)
        {
            await hubContext.Clients.Client(connectionId).SendAsync("Notification", new
            {
                Type = type,
                Message = message,
                Timestamp = DateTime.UtcNow
            });
        }
    }

    /// <summary>
    /// Send friend request notification
    /// </summary>
    public static async Task SendFriendRequestNotification(IHubContext<GameHub> hubContext, int targetPlayerId, int fromPlayerId, string fromUsername)
    {
        await SendNotificationToPlayer(hubContext, targetPlayerId, "friend_request", $"{fromUsername} sent you a friend request");
    }

    // ============================================
    // HELPERS
    // ============================================

    private int? GetUserId()
    {
        var idClaim = Context.User?.FindFirst("id")?.Value;
        return int.TryParse(idClaim, out var id) ? id : null;
    }
}
