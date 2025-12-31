using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ZombieSurvivalServer.Models;

public class Player
{
    [Key]
    public int Id { get; set; }

    [Required]
    [MaxLength(50)]
    public string Username { get; set; } = string.Empty;

    [Required]
    [EmailAddress]
    public string Email { get; set; } = string.Empty;

    [Required]
    public string PasswordHash { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime LastLoginAt { get; set; } = DateTime.UtcNow;

    public bool IsBanned { get; set; } = false;
    public string? BanReason { get; set; }
    public DateTime? BanExpiresAt { get; set; }

    // Profile
    public int Level { get; set; } = 1;
    public int Experience { get; set; } = 0;
    public int Currency { get; set; } = 0;
    public int PremiumCurrency { get; set; } = 0;

    [MaxLength(20)]
    public string SelectedClass { get; set; } = "survivor";

    [MaxLength(100)]
    public string? AvatarUrl { get; set; }

    [MaxLength(200)]
    public string? Bio { get; set; }

    // Relationships
    public PlayerStats? Stats { get; set; }
    public ICollection<PlayerUnlock> Unlocks { get; set; } = new List<PlayerUnlock>();
    public ICollection<InventoryItem> Inventory { get; set; } = new List<InventoryItem>();
    public ICollection<PlayerAchievement> Achievements { get; set; } = new List<PlayerAchievement>();
    public ICollection<MatchHistory> MatchHistory { get; set; } = new List<MatchHistory>();
    public ICollection<FriendRelation> Friends { get; set; } = new List<FriendRelation>();
}

public class PlayerStats
{
    [Key]
    public int Id { get; set; }

    public int PlayerId { get; set; }
    public Player? Player { get; set; }

    // Combat Stats
    public int TotalKills { get; set; } = 0;
    public int ZombieKills { get; set; } = 0;
    public int SpecialZombieKills { get; set; } = 0;
    public int BossKills { get; set; } = 0;
    public int Headshots { get; set; } = 0;
    public int Deaths { get; set; } = 0;
    public int Revives { get; set; } = 0;
    public int DamageDealt { get; set; } = 0;
    public int DamageTaken { get; set; } = 0;
    public int HealingDone { get; set; } = 0;

    // Game Stats
    public int GamesPlayed { get; set; } = 0;
    public int GamesWon { get; set; } = 0;
    public int GamesLost { get; set; } = 0;
    public int HighestWave { get; set; } = 0;
    public int TotalWavesSurvived { get; set; } = 0;
    public int TotalPlaytimeMinutes { get; set; } = 0;

    // Economy
    public int TotalPointsEarned { get; set; } = 0;
    public int TotalPointsSpent { get; set; } = 0;
    public int BarricadesBuilt { get; set; } = 0;
    public int BarricadesRepaired { get; set; } = 0;

    // Accuracy
    public int ShotsFired { get; set; } = 0;
    public int ShotsHit { get; set; } = 0;

    [NotMapped]
    public double Accuracy => ShotsFired > 0 ? (double)ShotsHit / ShotsFired * 100 : 0;

    [NotMapped]
    public double KDRatio => Deaths > 0 ? (double)TotalKills / Deaths : TotalKills;

    [NotMapped]
    public double WinRate => GamesPlayed > 0 ? (double)GamesWon / GamesPlayed * 100 : 0;
}

public class PlayerUnlock
{
    [Key]
    public int Id { get; set; }

    public int PlayerId { get; set; }
    public Player? Player { get; set; }

    [Required]
    [MaxLength(50)]
    public string UnlockType { get; set; } = string.Empty; // weapon, skin, class, ability, perk

    [Required]
    [MaxLength(50)]
    public string UnlockId { get; set; } = string.Empty;

    public DateTime UnlockedAt { get; set; } = DateTime.UtcNow;
}

public class InventoryItem
{
    [Key]
    public int Id { get; set; }

    public int PlayerId { get; set; }
    public Player? Player { get; set; }

    [Required]
    [MaxLength(50)]
    public string ItemType { get; set; } = string.Empty; // weapon, consumable, cosmetic

    [Required]
    [MaxLength(50)]
    public string ItemId { get; set; } = string.Empty;

    public int Quantity { get; set; } = 1;

    public string? CustomData { get; set; } // JSON for attachments, etc.
}

public class PlayerAchievement
{
    [Key]
    public int Id { get; set; }

    public int PlayerId { get; set; }
    public Player? Player { get; set; }

    [Required]
    [MaxLength(50)]
    public string AchievementId { get; set; } = string.Empty;

    public int Progress { get; set; } = 0;
    public int Target { get; set; } = 1;
    public bool IsCompleted { get; set; } = false;
    public DateTime? CompletedAt { get; set; }
}

public class MatchHistory
{
    [Key]
    public int Id { get; set; }

    public int PlayerId { get; set; }
    public Player? Player { get; set; }

    [MaxLength(50)]
    public string MatchId { get; set; } = string.Empty;

    [MaxLength(50)]
    public string MapName { get; set; } = string.Empty;

    [MaxLength(20)]
    public string GameMode { get; set; } = string.Empty;

    public DateTime PlayedAt { get; set; } = DateTime.UtcNow;
    public int DurationMinutes { get; set; } = 0;

    public bool Won { get; set; } = false;
    public int WaveReached { get; set; } = 0;

    // Player's performance
    public int Kills { get; set; } = 0;
    public int Deaths { get; set; } = 0;
    public int Score { get; set; } = 0;
    public int Revives { get; set; } = 0;

    [MaxLength(20)]
    public string ClassPlayed { get; set; } = string.Empty;
}

public class FriendRelation
{
    [Key]
    public int Id { get; set; }

    public int PlayerId { get; set; }
    public Player? Player { get; set; }

    public int FriendId { get; set; }

    [MaxLength(20)]
    public string Status { get; set; } = "pending"; // pending, accepted, blocked

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
