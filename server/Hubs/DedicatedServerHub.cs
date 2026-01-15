using Microsoft.AspNetCore.SignalR;
using ZombieSurvivalServer.Models;
using ZombieSurvivalServer.Services;
using System.Collections.Concurrent;

namespace ZombieSurvivalServer.Hubs;

/// <summary>
/// Hub for dedicated game server communication
/// Handles all real-time game state synchronization between dedicated servers and clients
/// </summary>
public class DedicatedServerHub : Hub
{
    private readonly IGameServerRegistry _serverRegistry;
    private readonly IServerBrowserService _serverBrowser;
    private readonly ILogger<DedicatedServerHub> _logger;

    // Active game sessions
    private static readonly ConcurrentDictionary<int, GameSession> _gameSessions = new();

    // Connection tracking
    private static readonly ConcurrentDictionary<string, int> _connectionToServer = new();
    private static readonly ConcurrentDictionary<string, PlayerSession> _connectionToPlayer = new();

    public DedicatedServerHub(
        IGameServerRegistry serverRegistry,
        IServerBrowserService serverBrowser,
        ILogger<DedicatedServerHub> logger)
    {
        _serverRegistry = serverRegistry;
        _serverBrowser = serverBrowser;
        _logger = logger;
    }

    public override async Task OnConnectedAsync()
    {
        _logger.LogInformation("New connection to DedicatedServerHub: {ConnectionId}", Context.ConnectionId);
        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var connectionId = Context.ConnectionId;

        // Check if this was a game server
        if (_connectionToServer.TryRemove(connectionId, out var serverId))
        {
            _serverRegistry.UnregisterServer(serverId);
            if (_gameSessions.TryRemove(serverId, out var session))
            {
                // Notify all players the server is shutting down
                await Clients.Group($"game_{serverId}").SendAsync("ServerShutdown", new { Reason = "Server disconnected" });
            }
            _logger.LogInformation("Game server {ServerId} disconnected", serverId);
        }

        // Check if this was a player
        if (_connectionToPlayer.TryRemove(connectionId, out var playerSession))
        {
            // Notify server about player disconnect
            var serverConnectionId = _serverRegistry.GetConnectionId(playerSession.ServerId);
            if (serverConnectionId != null)
            {
                await Clients.Client(serverConnectionId).SendAsync("PlayerDisconnected", new
                {
                    PlayerId = playerSession.PlayerId,
                    PeerId = playerSession.PeerId,
                    Username = playerSession.Username
                });
            }

            // Remove from game group
            await Groups.RemoveFromGroupAsync(connectionId, $"game_{playerSession.ServerId}");

            _logger.LogInformation("Player {Username} disconnected from server {ServerId}",
                playerSession.Username, playerSession.ServerId);
        }

        await base.OnDisconnectedAsync(exception);
    }

    // ============================================
    // GAME SERVER REGISTRATION
    // ============================================

    /// <summary>
    /// Register as a dedicated game server
    /// </summary>
    public async Task<ServerRegistrationResult> RegisterDedicatedServer(DedicatedServerInfo info)
    {
        try
        {
            // Register with the backend
            var request = new ServerRegistrationRequest
            {
                Name = info.ServerName,
                Port = info.Port,
                Region = info.Region,
                MapName = info.MapName,
                GameMode = info.GameMode,
                MaxPlayers = info.MaxPlayers,
                Difficulty = info.Difficulty
            };

            var ipAddress = Context.GetHttpContext()?.Connection.RemoteIpAddress?.ToString() ?? "127.0.0.1";
            var result = await _serverBrowser.RegisterServerAsync(request, ipAddress);

            if (result == null)
            {
                return new ServerRegistrationResult { Success = false, Error = "Failed to register server" };
            }

            var (server, token) = result.Value;

            // Register in memory
            _serverRegistry.RegisterServer(server.Id, Context.ConnectionId);
            _connectionToServer[Context.ConnectionId] = server.Id;

            // Create game session
            var session = new GameSession
            {
                ServerId = server.Id,
                ServerToken = token,
                MapName = info.MapName,
                GameMode = info.GameMode,
                MaxPlayers = info.MaxPlayers,
                Status = GameSessionStatus.WaitingForPlayers
            };
            _gameSessions[server.Id] = session;

            // Join server group
            await Groups.AddToGroupAsync(Context.ConnectionId, "dedicated_servers");
            await Groups.AddToGroupAsync(Context.ConnectionId, $"game_{server.Id}");

            _logger.LogInformation("Dedicated server registered: {ServerName} (ID: {ServerId})",
                info.ServerName, server.Id);

            return new ServerRegistrationResult
            {
                Success = true,
                ServerId = server.Id,
                ServerToken = token
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to register dedicated server");
            return new ServerRegistrationResult { Success = false, Error = ex.Message };
        }
    }

    /// <summary>
    /// Update server status and send heartbeat
    /// </summary>
    public async Task<bool> UpdateServerStatus(int serverId, string token, ServerStatusUpdate status)
    {
        if (!_gameSessions.TryGetValue(serverId, out var session))
            return false;

        if (session.ServerToken != token)
            return false;

        // Update session
        session.CurrentPlayers = status.CurrentPlayers;
        session.CurrentWave = status.CurrentWave;
        session.Status = status.Status;

        // Update database via service
        var updateRequest = new ServerUpdateRequest
        {
            CurrentPlayers = status.CurrentPlayers,
            CurrentWave = status.CurrentWave,
            Status = status.Status.ToString().ToLower()
        };

        await _serverBrowser.UpdateServerAsync(serverId, token, updateRequest);

        return true;
    }

    /// <summary>
    /// Deregister server
    /// </summary>
    public async Task<bool> DeregisterServer(int serverId, string token)
    {
        if (!_gameSessions.TryGetValue(serverId, out var session))
            return false;

        if (session.ServerToken != token)
            return false;

        // Notify players
        await Clients.Group($"game_{serverId}").SendAsync("ServerShutdown", new { Reason = "Server closing" });

        // Cleanup
        _gameSessions.TryRemove(serverId, out _);
        _serverRegistry.UnregisterServer(serverId);
        await _serverBrowser.DeregisterServerAsync(serverId, token);

        _logger.LogInformation("Server {ServerId} deregistered", serverId);
        return true;
    }

    // ============================================
    // PLAYER CONNECTION
    // ============================================

    /// <summary>
    /// Player requests to join a game server
    /// </summary>
    public async Task<JoinServerResult> JoinServer(int serverId, PlayerJoinInfo playerInfo)
    {
        if (!_gameSessions.TryGetValue(serverId, out var session))
        {
            return new JoinServerResult { Success = false, Error = "Server not found" };
        }

        if (session.CurrentPlayers >= session.MaxPlayers)
        {
            return new JoinServerResult { Success = false, Error = "Server is full" };
        }

        // Generate peer ID
        var peerId = session.NextPeerId++;

        // Create player session
        var playerSession = new PlayerSession
        {
            ConnectionId = Context.ConnectionId,
            ServerId = serverId,
            PlayerId = playerInfo.PlayerId,
            PeerId = peerId,
            Username = playerInfo.Username,
            SteamId = playerInfo.SteamId
        };

        _connectionToPlayer[Context.ConnectionId] = playerSession;
        session.Players[peerId] = playerSession;

        // Join game group
        await Groups.AddToGroupAsync(Context.ConnectionId, $"game_{serverId}");

        // Notify the game server
        var serverConnectionId = _serverRegistry.GetConnectionId(serverId);
        if (serverConnectionId != null)
        {
            await Clients.Client(serverConnectionId).SendAsync("PlayerJoined", new
            {
                PeerId = peerId,
                PlayerId = playerInfo.PlayerId,
                Username = playerInfo.Username,
                SteamId = playerInfo.SteamId,
                Level = playerInfo.Level,
                CharacterClass = playerInfo.CharacterClass
            });
        }

        _logger.LogInformation("Player {Username} joined server {ServerId} as peer {PeerId}",
            playerInfo.Username, serverId, peerId);

        return new JoinServerResult
        {
            Success = true,
            PeerId = peerId,
            ServerInfo = new GameServerInfo
            {
                ServerId = session.ServerId,
                MapName = session.MapName,
                GameMode = session.GameMode,
                CurrentWave = session.CurrentWave,
                Status = session.Status
            }
        };
    }

    /// <summary>
    /// Player leaves server
    /// </summary>
    public async Task LeaveServer()
    {
        if (_connectionToPlayer.TryRemove(Context.ConnectionId, out var playerSession))
        {
            if (_gameSessions.TryGetValue(playerSession.ServerId, out var session))
            {
                session.Players.TryRemove(playerSession.PeerId, out _);
            }

            // Notify server
            var serverConnectionId = _serverRegistry.GetConnectionId(playerSession.ServerId);
            if (serverConnectionId != null)
            {
                await Clients.Client(serverConnectionId).SendAsync("PlayerLeft", new
                {
                    PeerId = playerSession.PeerId,
                    PlayerId = playerSession.PlayerId,
                    Username = playerSession.Username
                });
            }

            await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"game_{playerSession.ServerId}");
        }
    }

    // ============================================
    // GAME STATE SYNCHRONIZATION
    // ============================================

    /// <summary>
    /// Server broadcasts game state to all players
    /// </summary>
    public async Task BroadcastGameState(int serverId, object gameState)
    {
        if (!ValidateServerConnection(serverId))
            return;

        await Clients.Group($"game_{serverId}").SendAsync("GameStateUpdate", gameState);
    }

    /// <summary>
    /// Server broadcasts entity states (players, zombies, etc.)
    /// </summary>
    public async Task BroadcastEntityStates(int serverId, List<EntityStateData> states)
    {
        if (!ValidateServerConnection(serverId))
            return;

        await Clients.OthersInGroup($"game_{serverId}").SendAsync("EntityStates", states);
    }

    /// <summary>
    /// Server broadcasts a specific event to all players
    /// </summary>
    public async Task BroadcastGameEvent(int serverId, string eventName, object eventData)
    {
        if (!ValidateServerConnection(serverId))
            return;

        await Clients.Group($"game_{serverId}").SendAsync("GameEvent", new
        {
            Event = eventName,
            Data = eventData,
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Server sends data to a specific player
    /// </summary>
    public async Task SendToPlayer(int serverId, int peerId, string eventName, object data)
    {
        if (!ValidateServerConnection(serverId))
            return;

        if (_gameSessions.TryGetValue(serverId, out var session) &&
            session.Players.TryGetValue(peerId, out var player))
        {
            await Clients.Client(player.ConnectionId).SendAsync(eventName, data);
        }
    }

    /// <summary>
    /// Player sends input to server
    /// </summary>
    public async Task SendPlayerInput(PlayerInputData input)
    {
        if (!_connectionToPlayer.TryGetValue(Context.ConnectionId, out var playerSession))
            return;

        var serverConnectionId = _serverRegistry.GetConnectionId(playerSession.ServerId);
        if (serverConnectionId != null)
        {
            input.PeerId = playerSession.PeerId;
            await Clients.Client(serverConnectionId).SendAsync("PlayerInput", input);
        }
    }

    /// <summary>
    /// Player sends state update to server (for client-side prediction validation)
    /// </summary>
    public async Task SendPlayerState(PlayerStateData state)
    {
        if (!_connectionToPlayer.TryGetValue(Context.ConnectionId, out var playerSession))
            return;

        var serverConnectionId = _serverRegistry.GetConnectionId(playerSession.ServerId);
        if (serverConnectionId != null)
        {
            state.PeerId = playerSession.PeerId;
            await Clients.Client(serverConnectionId).SendAsync("PlayerState", state);
        }
    }

    /// <summary>
    /// Player sends action to server (shoot, reload, use item, etc.)
    /// </summary>
    public async Task SendPlayerAction(string actionType, object actionData)
    {
        if (!_connectionToPlayer.TryGetValue(Context.ConnectionId, out var playerSession))
            return;

        var serverConnectionId = _serverRegistry.GetConnectionId(playerSession.ServerId);
        if (serverConnectionId != null)
        {
            await Clients.Client(serverConnectionId).SendAsync("PlayerAction", new
            {
                PeerId = playerSession.PeerId,
                ActionType = actionType,
                Data = actionData,
                Timestamp = DateTime.UtcNow
            });
        }
    }

    // ============================================
    // WAVE MANAGEMENT
    // ============================================

    /// <summary>
    /// Server broadcasts wave start
    /// </summary>
    public async Task BroadcastWaveStart(int serverId, int waveNumber, int totalZombies)
    {
        if (!ValidateServerConnection(serverId))
            return;

        await Clients.Group($"game_{serverId}").SendAsync("WaveStart", new
        {
            WaveNumber = waveNumber,
            TotalZombies = totalZombies,
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Server broadcasts wave complete
    /// </summary>
    public async Task BroadcastWaveComplete(int serverId, int waveNumber, object rewards)
    {
        if (!ValidateServerConnection(serverId))
            return;

        await Clients.Group($"game_{serverId}").SendAsync("WaveComplete", new
        {
            WaveNumber = waveNumber,
            Rewards = rewards,
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Server spawns a zombie and notifies clients
    /// </summary>
    public async Task SpawnZombie(int serverId, ZombieSpawnData zombieData)
    {
        if (!ValidateServerConnection(serverId))
            return;

        await Clients.OthersInGroup($"game_{serverId}").SendAsync("ZombieSpawned", zombieData);
    }

    /// <summary>
    /// Server notifies zombie death
    /// </summary>
    public async Task ZombieDied(int serverId, int zombieId, int killerPeerId, object dropData)
    {
        if (!ValidateServerConnection(serverId))
            return;

        await Clients.Group($"game_{serverId}").SendAsync("ZombieDied", new
        {
            ZombieId = zombieId,
            KillerPeerId = killerPeerId,
            Drop = dropData,
            Timestamp = DateTime.UtcNow
        });
    }

    // ============================================
    // PLAYER EVENTS
    // ============================================

    /// <summary>
    /// Server broadcasts player damage
    /// </summary>
    public async Task BroadcastPlayerDamage(int serverId, int peerId, float damage, string bodyPart, float newHealth)
    {
        if (!ValidateServerConnection(serverId))
            return;

        await Clients.Group($"game_{serverId}").SendAsync("PlayerDamaged", new
        {
            PeerId = peerId,
            Damage = damage,
            BodyPart = bodyPart,
            NewHealth = newHealth,
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Server broadcasts player death
    /// </summary>
    public async Task BroadcastPlayerDeath(int serverId, int peerId, string killerName)
    {
        if (!ValidateServerConnection(serverId))
            return;

        await Clients.Group($"game_{serverId}").SendAsync("PlayerDied", new
        {
            PeerId = peerId,
            KillerName = killerName,
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Server broadcasts player respawn
    /// </summary>
    public async Task BroadcastPlayerRespawn(int serverId, int peerId, float[] position)
    {
        if (!ValidateServerConnection(serverId))
            return;

        await Clients.Group($"game_{serverId}").SendAsync("PlayerRespawned", new
        {
            PeerId = peerId,
            Position = position,
            Timestamp = DateTime.UtcNow
        });
    }

    // ============================================
    // CHAT
    // ============================================

    /// <summary>
    /// Player sends chat message
    /// </summary>
    public async Task SendChatMessage(string message)
    {
        if (!_connectionToPlayer.TryGetValue(Context.ConnectionId, out var playerSession))
            return;

        await Clients.Group($"game_{playerSession.ServerId}").SendAsync("ChatMessage", new
        {
            PeerId = playerSession.PeerId,
            Username = playerSession.Username,
            Message = message,
            Timestamp = DateTime.UtcNow
        });
    }

    // ============================================
    // HELPERS
    // ============================================

    private bool ValidateServerConnection(int serverId)
    {
        if (!_connectionToServer.TryGetValue(Context.ConnectionId, out var connectedServerId))
            return false;

        return connectedServerId == serverId;
    }
}

// ============================================
// DATA CLASSES
// ============================================

public class DedicatedServerInfo
{
    public string ServerName { get; set; } = string.Empty;
    public int Port { get; set; } = 7777;
    public string Region { get; set; } = "us-east";
    public string MapName { get; set; } = "arena_01";
    public string GameMode { get; set; } = "survival";
    public int MaxPlayers { get; set; } = 8;
    public string Difficulty { get; set; } = "Normal";
}

public class ServerRegistrationResult
{
    public bool Success { get; set; }
    public int ServerId { get; set; }
    public string ServerToken { get; set; } = string.Empty;
    public string? Error { get; set; }
}

public class ServerStatusUpdate
{
    public int CurrentPlayers { get; set; }
    public int CurrentWave { get; set; }
    public GameSessionStatus Status { get; set; }
}

public class PlayerJoinInfo
{
    public int PlayerId { get; set; }
    public string Username { get; set; } = string.Empty;
    public long SteamId { get; set; }
    public int Level { get; set; } = 1;
    public string CharacterClass { get; set; } = string.Empty;
}

public class JoinServerResult
{
    public bool Success { get; set; }
    public int PeerId { get; set; }
    public GameServerInfo? ServerInfo { get; set; }
    public string? Error { get; set; }
}

public class GameServerInfo
{
    public int ServerId { get; set; }
    public string MapName { get; set; } = string.Empty;
    public string GameMode { get; set; } = string.Empty;
    public int CurrentWave { get; set; }
    public GameSessionStatus Status { get; set; }
}

public class PlayerInputData
{
    public int PeerId { get; set; }
    public float[] MovementInput { get; set; } = Array.Empty<float>();
    public float[] LookRotation { get; set; } = Array.Empty<float>();
    public bool Jump { get; set; }
    public bool Sprint { get; set; }
    public bool Crouch { get; set; }
    public int Tick { get; set; }
}

public class PlayerStateData
{
    public int PeerId { get; set; }
    public float[] Position { get; set; } = Array.Empty<float>();
    public float[] Rotation { get; set; } = Array.Empty<float>();
    public float[] Velocity { get; set; } = Array.Empty<float>();
    public float Health { get; set; }
    public int WeaponId { get; set; }
    public int AmmoInClip { get; set; }
    public int Tick { get; set; }
}

public class EntityStateData
{
    public int EntityId { get; set; }
    public string EntityType { get; set; } = string.Empty;
    public float[] Position { get; set; } = Array.Empty<float>();
    public float[] Rotation { get; set; } = Array.Empty<float>();
    public float[] Velocity { get; set; } = Array.Empty<float>();
    public Dictionary<string, object>? CustomData { get; set; }
    public int Tick { get; set; }
}

public class ZombieSpawnData
{
    public int ZombieId { get; set; }
    public string ZombieType { get; set; } = "shambler";
    public float[] Position { get; set; } = Array.Empty<float>();
    public float Health { get; set; }
}

public class GameSession
{
    public int ServerId { get; set; }
    public string ServerToken { get; set; } = string.Empty;
    public string MapName { get; set; } = string.Empty;
    public string GameMode { get; set; } = string.Empty;
    public int MaxPlayers { get; set; } = 8;
    public int CurrentPlayers => Players.Count;
    public int CurrentWave { get; set; }
    public GameSessionStatus Status { get; set; }
    public int NextPeerId { get; set; } = 2; // 1 is reserved for server
    public ConcurrentDictionary<int, PlayerSession> Players { get; set; } = new();
}

public class PlayerSession
{
    public string ConnectionId { get; set; } = string.Empty;
    public int ServerId { get; set; }
    public int PlayerId { get; set; }
    public int PeerId { get; set; }
    public string Username { get; set; } = string.Empty;
    public long SteamId { get; set; }
    public bool IsReady { get; set; }
}

public enum GameSessionStatus
{
    WaitingForPlayers,
    Starting,
    InProgress,
    Intermission,
    GameOver
}
