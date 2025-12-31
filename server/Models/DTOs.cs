namespace ZombieSurvivalServer.Models;

// ============================================
// Authentication DTOs
// ============================================

public class RegisterRequest
{
    public string Username { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}

public class LoginRequest
{
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}

public class AuthResponse
{
    public bool Success { get; set; }
    public string? Token { get; set; }
    public string? RefreshToken { get; set; }
    public DateTime? ExpiresAt { get; set; }
    public PlayerProfile? Player { get; set; }
    public string? Error { get; set; }
}

public class RefreshTokenRequest
{
    public string RefreshToken { get; set; } = string.Empty;
}

// ============================================
// Player DTOs
// ============================================

public class PlayerProfile
{
    public int Id { get; set; }
    public string Username { get; set; } = string.Empty;
    public int Level { get; set; }
    public int Experience { get; set; }
    public int ExperienceToNextLevel { get; set; }
    public int Currency { get; set; }
    public int PremiumCurrency { get; set; }
    public string SelectedClass { get; set; } = string.Empty;
    public string? AvatarUrl { get; set; }
    public string? Bio { get; set; }
    public DateTime CreatedAt { get; set; }
    public PlayerStatsDto? Stats { get; set; }
    public List<string> Unlocks { get; set; } = new();
}

public class PlayerStatsDto
{
    public int TotalKills { get; set; }
    public int ZombieKills { get; set; }
    public int SpecialZombieKills { get; set; }
    public int BossKills { get; set; }
    public int Headshots { get; set; }
    public int Deaths { get; set; }
    public int Revives { get; set; }
    public int GamesPlayed { get; set; }
    public int GamesWon { get; set; }
    public int HighestWave { get; set; }
    public int TotalPlaytimeMinutes { get; set; }
    public double Accuracy { get; set; }
    public double KDRatio { get; set; }
    public double WinRate { get; set; }
}

public class UpdateProfileRequest
{
    public string? SelectedClass { get; set; }
    public string? AvatarUrl { get; set; }
    public string? Bio { get; set; }
}

public class UpdateStatsRequest
{
    public int? ZombieKills { get; set; }
    public int? SpecialZombieKills { get; set; }
    public int? BossKills { get; set; }
    public int? Headshots { get; set; }
    public int? Deaths { get; set; }
    public int? Revives { get; set; }
    public int? DamageDealt { get; set; }
    public int? DamageTaken { get; set; }
    public int? HealingDone { get; set; }
    public int? WavesSurvived { get; set; }
    public int? PlaytimeMinutes { get; set; }
    public int? PointsEarned { get; set; }
    public int? PointsSpent { get; set; }
    public int? ShotsFired { get; set; }
    public int? ShotsHit { get; set; }
    public int? BarricadesBuilt { get; set; }
    public int? BarricadesRepaired { get; set; }
}

// ============================================
// Leaderboard DTOs
// ============================================

public class LeaderboardEntry
{
    public int Rank { get; set; }
    public int PlayerId { get; set; }
    public string Username { get; set; } = string.Empty;
    public int Level { get; set; }
    public string? AvatarUrl { get; set; }
    public int Value { get; set; } // The leaderboard value (kills, score, etc.)
}

public class LeaderboardResponse
{
    public string Category { get; set; } = string.Empty;
    public string TimeFrame { get; set; } = string.Empty;
    public List<LeaderboardEntry> Entries { get; set; } = new();
    public LeaderboardEntry? PlayerEntry { get; set; } // Current player's position
}

// ============================================
// Matchmaking DTOs
// ============================================

public class MatchmakingRequest
{
    public string GameMode { get; set; } = "survival";
    public string? PreferredRegion { get; set; }
    public string? PreferredMap { get; set; }
    public int MinPlayers { get; set; } = 1;
    public int MaxPlayers { get; set; } = 8;
}

public class MatchmakingStatus
{
    public string Status { get; set; } = "searching"; // searching, found, cancelled, error
    public int PlayersInQueue { get; set; }
    public int EstimatedWaitSeconds { get; set; }
    public ServerListResponse? FoundServer { get; set; }
    public string? Error { get; set; }
}

public class MatchResult
{
    public string MatchId { get; set; } = string.Empty;
    public string MapName { get; set; } = string.Empty;
    public string GameMode { get; set; } = string.Empty;
    public int DurationMinutes { get; set; }
    public bool Victory { get; set; }
    public int WaveReached { get; set; }
    public List<MatchPlayerResult> Players { get; set; } = new();
}

public class MatchPlayerResult
{
    public int PlayerId { get; set; }
    public string Username { get; set; } = string.Empty;
    public string ClassPlayed { get; set; } = string.Empty;
    public int Kills { get; set; }
    public int Deaths { get; set; }
    public int Score { get; set; }
    public int Revives { get; set; }
    public int DamageDealt { get; set; }
}

// ============================================
// Shop DTOs
// ============================================

public class ShopItem
{
    public string ItemId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Rarity { get; set; } = "common";
    public int Price { get; set; }
    public string CurrencyType { get; set; } = "currency"; // currency or premium
    public bool IsOwned { get; set; }
    public bool IsEquipped { get; set; }
    public string? ImageUrl { get; set; }
}

public class PurchaseRequest
{
    public string ItemId { get; set; } = string.Empty;
}

public class PurchaseResponse
{
    public bool Success { get; set; }
    public string? Error { get; set; }
    public int RemainingCurrency { get; set; }
    public int RemainingPremiumCurrency { get; set; }
}

// ============================================
// Social DTOs
// ============================================

public class FriendInfo
{
    public int PlayerId { get; set; }
    public string Username { get; set; } = string.Empty;
    public int Level { get; set; }
    public string? AvatarUrl { get; set; }
    public bool IsOnline { get; set; }
    public string? CurrentServer { get; set; }
    public string Status { get; set; } = string.Empty; // pending, accepted
}

public class FriendRequest
{
    public string Username { get; set; } = string.Empty;
}

// ============================================
// General Response
// ============================================

public class ApiResponse<T>
{
    public bool Success { get; set; }
    public T? Data { get; set; }
    public string? Error { get; set; }

    public static ApiResponse<T> Ok(T data) => new() { Success = true, Data = data };
    public static ApiResponse<T> Fail(string error) => new() { Success = false, Error = error };
}

public class ApiResponse
{
    public bool Success { get; set; }
    public string? Message { get; set; }
    public string? Error { get; set; }

    public static ApiResponse Ok(string? message = null) => new() { Success = true, Message = message };
    public static ApiResponse Fail(string error) => new() { Success = false, Error = error };
}
