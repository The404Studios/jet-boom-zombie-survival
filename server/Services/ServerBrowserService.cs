using Microsoft.EntityFrameworkCore;
using ZombieSurvivalServer.Data;
using ZombieSurvivalServer.Models;

namespace ZombieSurvivalServer.Services;

public interface IServerBrowserService
{
    Task<List<ServerListResponse>> GetServersAsync(string? region = null, string? gameMode = null, bool hideEmpty = false, bool hideFull = false);
    Task<ServerListResponse?> GetServerAsync(int serverId);
    Task<(GameServer Server, string Token)?> RegisterServerAsync(ServerRegistrationRequest request, string ipAddress);
    Task<ApiResponse> UpdateServerAsync(int serverId, string token, ServerUpdateRequest request);
    Task<ApiResponse> HeartbeatAsync(int serverId, string token);
    Task<ApiResponse> DeregisterServerAsync(int serverId, string token);
    Task<bool> ValidatePasswordAsync(int serverId, string password);
    Task CleanupStaleServersAsync();
}

public class ServerBrowserService : IServerBrowserService
{
    private readonly GameDbContext _context;
    private readonly ILogger<ServerBrowserService> _logger;

    public ServerBrowserService(GameDbContext context, ILogger<ServerBrowserService> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task<List<ServerListResponse>> GetServersAsync(
        string? region = null,
        string? gameMode = null,
        bool hideEmpty = false,
        bool hideFull = false)
    {
        var cutoff = DateTime.UtcNow.AddSeconds(-60);

        var query = _context.GameServers
            .Where(s => s.LastHeartbeat > cutoff && s.Status != "ended");

        if (!string.IsNullOrEmpty(region))
            query = query.Where(s => s.Region == region);

        if (!string.IsNullOrEmpty(gameMode))
            query = query.Where(s => s.GameMode == gameMode);

        if (hideEmpty)
            query = query.Where(s => s.CurrentPlayers > 0);

        if (hideFull)
            query = query.Where(s => s.CurrentPlayers < s.MaxPlayers);

        var servers = await query
            .OrderByDescending(s => s.IsOfficial)
            .ThenByDescending(s => s.CurrentPlayers)
            .ToListAsync();

        // Get player names for each server
        var serverIds = servers.Select(s => s.Id).ToList();
        var serverPlayers = await _context.ServerPlayers
            .Where(sp => serverIds.Contains(sp.ServerId))
            .ToListAsync();

        return servers.Select(s => new ServerListResponse
        {
            Id = s.Id,
            Name = s.Name,
            IpAddress = s.IpAddress,
            Port = s.Port,
            Region = s.Region,
            MapName = s.MapName,
            GameMode = s.GameMode,
            CurrentPlayers = s.CurrentPlayers,
            MaxPlayers = s.MaxPlayers,
            CurrentWave = s.CurrentWave,
            Difficulty = s.Difficulty,
            HasPassword = s.HasPassword,
            IsOfficial = s.IsOfficial,
            Status = s.Status,
            PlayerNames = serverPlayers
                .Where(sp => sp.ServerId == s.Id)
                .Select(sp => sp.PlayerName)
                .ToList()
        }).ToList();
    }

    public async Task<ServerListResponse?> GetServerAsync(int serverId)
    {
        var server = await _context.GameServers.FindAsync(serverId);
        if (server == null)
            return null;

        var players = await _context.ServerPlayers
            .Where(sp => sp.ServerId == serverId)
            .ToListAsync();

        return new ServerListResponse
        {
            Id = server.Id,
            Name = server.Name,
            IpAddress = server.IpAddress,
            Port = server.Port,
            Region = server.Region,
            MapName = server.MapName,
            GameMode = server.GameMode,
            CurrentPlayers = server.CurrentPlayers,
            MaxPlayers = server.MaxPlayers,
            CurrentWave = server.CurrentWave,
            Difficulty = server.Difficulty,
            HasPassword = server.HasPassword,
            IsOfficial = server.IsOfficial,
            Status = server.Status,
            PlayerNames = players.Select(p => p.PlayerName).ToList()
        };
    }

    public async Task<(GameServer Server, string Token)?> RegisterServerAsync(ServerRegistrationRequest request, string ipAddress)
    {
        // Generate server token
        var token = Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");

        var server = new GameServer
        {
            Name = request.Name,
            IpAddress = ipAddress,
            Port = request.Port,
            Region = request.Region,
            MapName = request.MapName,
            GameMode = request.GameMode,
            MaxPlayers = request.MaxPlayers,
            Difficulty = request.Difficulty,
            HasPassword = !string.IsNullOrEmpty(request.Password),
            PasswordHash = !string.IsNullOrEmpty(request.Password)
                ? BCrypt.Net.BCrypt.HashPassword(request.Password)
                : null,
            ServerToken = token,
            Status = "waiting",
            CreatedAt = DateTime.UtcNow,
            LastHeartbeat = DateTime.UtcNow
        };

        _context.GameServers.Add(server);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Server registered: {Name} at {IP}:{Port}", server.Name, ipAddress, request.Port);

        return (server, token);
    }

    public async Task<ApiResponse> UpdateServerAsync(int serverId, string token, ServerUpdateRequest request)
    {
        var server = await _context.GameServers.FindAsync(serverId);
        if (server == null)
            return ApiResponse.Fail("Server not found");

        if (server.ServerToken != token)
            return ApiResponse.Fail("Invalid server token");

        if (request.MapName != null)
            server.MapName = request.MapName;

        if (request.GameMode != null)
            server.GameMode = request.GameMode;

        if (request.CurrentPlayers.HasValue)
            server.CurrentPlayers = request.CurrentPlayers.Value;

        if (request.CurrentWave.HasValue)
            server.CurrentWave = request.CurrentWave.Value;

        if (request.Status != null)
            server.Status = request.Status;

        server.LastHeartbeat = DateTime.UtcNow;

        // Update player list
        if (request.Players != null)
        {
            // Remove old players
            var oldPlayers = await _context.ServerPlayers
                .Where(sp => sp.ServerId == serverId)
                .ToListAsync();
            _context.ServerPlayers.RemoveRange(oldPlayers);

            // Add new players
            foreach (var player in request.Players)
            {
                _context.ServerPlayers.Add(new ServerPlayer
                {
                    ServerId = serverId,
                    PlayerId = player.PlayerId,
                    PlayerName = player.PlayerName,
                    PlayerClass = player.PlayerClass,
                    Score = player.Score,
                    Kills = player.Kills,
                    Deaths = player.Deaths,
                    IsAlive = player.IsAlive
                });
            }

            server.CurrentPlayers = request.Players.Count;
        }

        await _context.SaveChangesAsync();
        return ApiResponse.Ok();
    }

    public async Task<ApiResponse> HeartbeatAsync(int serverId, string token)
    {
        var server = await _context.GameServers.FindAsync(serverId);
        if (server == null)
            return ApiResponse.Fail("Server not found");

        if (server.ServerToken != token)
            return ApiResponse.Fail("Invalid server token");

        server.LastHeartbeat = DateTime.UtcNow;
        await _context.SaveChangesAsync();

        return ApiResponse.Ok();
    }

    public async Task<ApiResponse> DeregisterServerAsync(int serverId, string token)
    {
        var server = await _context.GameServers.FindAsync(serverId);
        if (server == null)
            return ApiResponse.Fail("Server not found");

        if (server.ServerToken != token)
            return ApiResponse.Fail("Invalid server token");

        // Remove players
        var players = await _context.ServerPlayers
            .Where(sp => sp.ServerId == serverId)
            .ToListAsync();
        _context.ServerPlayers.RemoveRange(players);

        // Remove server
        _context.GameServers.Remove(server);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Server deregistered: {Name}", server.Name);

        return ApiResponse.Ok();
    }

    public async Task<bool> ValidatePasswordAsync(int serverId, string password)
    {
        var server = await _context.GameServers.FindAsync(serverId);
        if (server == null || !server.HasPassword || string.IsNullOrEmpty(server.PasswordHash))
            return false;

        return BCrypt.Net.BCrypt.Verify(password, server.PasswordHash);
    }

    public async Task CleanupStaleServersAsync()
    {
        var cutoff = DateTime.UtcNow.AddSeconds(-90);

        var staleServers = await _context.GameServers
            .Where(s => s.LastHeartbeat < cutoff)
            .ToListAsync();

        if (staleServers.Any())
        {
            var serverIds = staleServers.Select(s => s.Id).ToList();

            // Remove players
            var stalePlayers = await _context.ServerPlayers
                .Where(sp => serverIds.Contains(sp.ServerId))
                .ToListAsync();
            _context.ServerPlayers.RemoveRange(stalePlayers);

            // Remove servers
            _context.GameServers.RemoveRange(staleServers);
            await _context.SaveChangesAsync();

            _logger.LogInformation("Cleaned up {Count} stale servers", staleServers.Count);
        }
    }
}

// In-memory server registry for quick lookups
public interface IGameServerRegistry
{
    void RegisterServer(int serverId, string connectionId);
    void UnregisterServer(int serverId);
    string? GetConnectionId(int serverId);
    int? GetServerId(string connectionId);
    IEnumerable<int> GetAllServerIds();
}

public class GameServerRegistry : IGameServerRegistry
{
    private readonly Dictionary<int, string> _serverToConnection = new();
    private readonly Dictionary<string, int> _connectionToServer = new();
    private readonly object _lock = new();

    public void RegisterServer(int serverId, string connectionId)
    {
        lock (_lock)
        {
            _serverToConnection[serverId] = connectionId;
            _connectionToServer[connectionId] = serverId;
        }
    }

    public void UnregisterServer(int serverId)
    {
        lock (_lock)
        {
            if (_serverToConnection.TryGetValue(serverId, out var connectionId))
            {
                _serverToConnection.Remove(serverId);
                _connectionToServer.Remove(connectionId);
            }
        }
    }

    public string? GetConnectionId(int serverId)
    {
        lock (_lock)
        {
            return _serverToConnection.TryGetValue(serverId, out var connectionId) ? connectionId : null;
        }
    }

    public int? GetServerId(string connectionId)
    {
        lock (_lock)
        {
            return _connectionToServer.TryGetValue(connectionId, out var serverId) ? serverId : null;
        }
    }

    public IEnumerable<int> GetAllServerIds()
    {
        lock (_lock)
        {
            return _serverToConnection.Keys.ToList();
        }
    }
}
