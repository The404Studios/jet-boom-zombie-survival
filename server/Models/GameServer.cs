using System.ComponentModel.DataAnnotations;

namespace ZombieSurvivalServer.Models;

public class GameServer
{
    [Key]
    public int Id { get; set; }

    [Required]
    [MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    [Required]
    [MaxLength(50)]
    public string IpAddress { get; set; } = string.Empty;

    public int Port { get; set; } = 27015;

    [MaxLength(50)]
    public string Region { get; set; } = "unknown";

    [MaxLength(50)]
    public string MapName { get; set; } = string.Empty;

    [MaxLength(30)]
    public string GameMode { get; set; } = "survival";

    public int CurrentPlayers { get; set; } = 0;
    public int MaxPlayers { get; set; } = 8;

    public int CurrentWave { get; set; } = 0;

    [MaxLength(20)]
    public string Difficulty { get; set; } = "Normal";

    public bool HasPassword { get; set; } = false;

    [MaxLength(100)]
    public string? PasswordHash { get; set; }

    public bool IsOfficial { get; set; } = false;

    [MaxLength(20)]
    public string Status { get; set; } = "waiting"; // waiting, in_progress, ended

    public DateTime LastHeartbeat { get; set; } = DateTime.UtcNow;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // Server token for authentication
    [MaxLength(100)]
    public string ServerToken { get; set; } = string.Empty;

    // Additional info stored as JSON
    public string? CustomData { get; set; }
}

public class ServerPlayer
{
    [Key]
    public int Id { get; set; }

    public int ServerId { get; set; }
    public int PlayerId { get; set; }

    [MaxLength(50)]
    public string PlayerName { get; set; } = string.Empty;

    [MaxLength(20)]
    public string PlayerClass { get; set; } = string.Empty;

    public int Score { get; set; } = 0;
    public int Kills { get; set; } = 0;
    public int Deaths { get; set; } = 0;

    public bool IsAlive { get; set; } = true;
    public bool IsReady { get; set; } = false;

    public DateTime JoinedAt { get; set; } = DateTime.UtcNow;
}

// DTOs for API responses
public class ServerListResponse
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string IpAddress { get; set; } = string.Empty;
    public int Port { get; set; }
    public string Region { get; set; } = string.Empty;
    public string MapName { get; set; } = string.Empty;
    public string GameMode { get; set; } = string.Empty;
    public int CurrentPlayers { get; set; }
    public int MaxPlayers { get; set; }
    public int CurrentWave { get; set; }
    public string Difficulty { get; set; } = string.Empty;
    public bool HasPassword { get; set; }
    public bool IsOfficial { get; set; }
    public string Status { get; set; } = string.Empty;
    public int Ping { get; set; } // Calculated client-side
    public List<string> PlayerNames { get; set; } = new();
}

public class ServerRegistrationRequest
{
    public string Name { get; set; } = string.Empty;
    public int Port { get; set; }
    public string Region { get; set; } = string.Empty;
    public string MapName { get; set; } = string.Empty;
    public string GameMode { get; set; } = string.Empty;
    public int MaxPlayers { get; set; }
    public string Difficulty { get; set; } = string.Empty;
    public string? Password { get; set; }
}

public class ServerUpdateRequest
{
    public string? MapName { get; set; }
    public string? GameMode { get; set; }
    public int? CurrentPlayers { get; set; }
    public int? CurrentWave { get; set; }
    public string? Status { get; set; }
    public List<ServerPlayerUpdate>? Players { get; set; }
}

public class ServerPlayerUpdate
{
    public int PlayerId { get; set; }
    public string PlayerName { get; set; } = string.Empty;
    public string PlayerClass { get; set; } = string.Empty;
    public int Score { get; set; }
    public int Kills { get; set; }
    public int Deaths { get; set; }
    public bool IsAlive { get; set; }
}
