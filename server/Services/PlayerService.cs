using Microsoft.EntityFrameworkCore;
using ZombieSurvivalServer.Data;
using ZombieSurvivalServer.Models;

namespace ZombieSurvivalServer.Services;

public interface IPlayerService
{
    Task<PlayerProfile?> GetProfileAsync(int playerId);
    Task<PlayerProfile?> GetProfileByUsernameAsync(string username);
    Task<ApiResponse> UpdateProfileAsync(int playerId, UpdateProfileRequest request);
    Task<ApiResponse> UpdateStatsAsync(int playerId, UpdateStatsRequest request);
    Task<ApiResponse> AddExperienceAsync(int playerId, int amount);
    Task<ApiResponse> AddCurrencyAsync(int playerId, int amount, bool isPremium = false);
    Task<ApiResponse<List<MatchHistory>>> GetMatchHistoryAsync(int playerId, int limit = 20);
    Task<ApiResponse> RecordMatchAsync(int playerId, MatchResult result);
    Task<List<FriendInfo>> GetFriendsAsync(int playerId);
    Task<ApiResponse> SendFriendRequestAsync(int playerId, string targetUsername);
    Task<ApiResponse> RespondToFriendRequestAsync(int playerId, int friendId, bool accept);
}

public class PlayerService : IPlayerService
{
    private readonly GameDbContext _context;
    private readonly ILogger<PlayerService> _logger;

    public PlayerService(GameDbContext context, ILogger<PlayerService> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task<PlayerProfile?> GetProfileAsync(int playerId)
    {
        var player = await _context.Players
            .Include(p => p.Stats)
            .Include(p => p.Unlocks)
            .FirstOrDefaultAsync(p => p.Id == playerId);

        return player != null ? MapToProfile(player) : null;
    }

    public async Task<PlayerProfile?> GetProfileByUsernameAsync(string username)
    {
        var player = await _context.Players
            .Include(p => p.Stats)
            .Include(p => p.Unlocks)
            .FirstOrDefaultAsync(p => p.Username.ToLower() == username.ToLower());

        return player != null ? MapToProfile(player) : null;
    }

    public async Task<ApiResponse> UpdateProfileAsync(int playerId, UpdateProfileRequest request)
    {
        var player = await _context.Players.FindAsync(playerId);
        if (player == null)
            return ApiResponse.Fail("Player not found");

        if (!string.IsNullOrWhiteSpace(request.SelectedClass))
        {
            // Verify player has unlocked this class
            var hasClass = await _context.PlayerUnlocks
                .AnyAsync(u => u.PlayerId == playerId
                            && u.UnlockType == "class"
                            && u.UnlockId == request.SelectedClass);

            if (!hasClass)
                return ApiResponse.Fail("Class not unlocked");

            player.SelectedClass = request.SelectedClass;
        }

        if (request.AvatarUrl != null)
            player.AvatarUrl = request.AvatarUrl;

        if (request.Bio != null)
            player.Bio = request.Bio.Length > 200 ? request.Bio[..200] : request.Bio;

        await _context.SaveChangesAsync();
        return ApiResponse.Ok("Profile updated");
    }

    public async Task<ApiResponse> UpdateStatsAsync(int playerId, UpdateStatsRequest request)
    {
        var stats = await _context.PlayerStats.FirstOrDefaultAsync(s => s.PlayerId == playerId);
        if (stats == null)
        {
            stats = new PlayerStats { PlayerId = playerId };
            _context.PlayerStats.Add(stats);
        }

        // Increment stats
        if (request.ZombieKills.HasValue) stats.ZombieKills += request.ZombieKills.Value;
        if (request.SpecialZombieKills.HasValue) stats.SpecialZombieKills += request.SpecialZombieKills.Value;
        if (request.BossKills.HasValue) stats.BossKills += request.BossKills.Value;
        if (request.Headshots.HasValue) stats.Headshots += request.Headshots.Value;
        if (request.Deaths.HasValue) stats.Deaths += request.Deaths.Value;
        if (request.Revives.HasValue) stats.Revives += request.Revives.Value;
        if (request.DamageDealt.HasValue) stats.DamageDealt += request.DamageDealt.Value;
        if (request.DamageTaken.HasValue) stats.DamageTaken += request.DamageTaken.Value;
        if (request.HealingDone.HasValue) stats.HealingDone += request.HealingDone.Value;
        if (request.WavesSurvived.HasValue) stats.TotalWavesSurvived += request.WavesSurvived.Value;
        if (request.PlaytimeMinutes.HasValue) stats.TotalPlaytimeMinutes += request.PlaytimeMinutes.Value;
        if (request.PointsEarned.HasValue) stats.TotalPointsEarned += request.PointsEarned.Value;
        if (request.PointsSpent.HasValue) stats.TotalPointsSpent += request.PointsSpent.Value;
        if (request.ShotsFired.HasValue) stats.ShotsFired += request.ShotsFired.Value;
        if (request.ShotsHit.HasValue) stats.ShotsHit += request.ShotsHit.Value;
        if (request.BarricadesBuilt.HasValue) stats.BarricadesBuilt += request.BarricadesBuilt.Value;
        if (request.BarricadesRepaired.HasValue) stats.BarricadesRepaired += request.BarricadesRepaired.Value;

        // Update total kills
        stats.TotalKills = stats.ZombieKills + stats.SpecialZombieKills + stats.BossKills;

        await _context.SaveChangesAsync();
        return ApiResponse.Ok("Stats updated");
    }

    public async Task<ApiResponse> AddExperienceAsync(int playerId, int amount)
    {
        var player = await _context.Players.FindAsync(playerId);
        if (player == null)
            return ApiResponse.Fail("Player not found");

        player.Experience += amount;

        // Check for level up
        var expNeeded = CalculateExpToNextLevel(player.Level);
        while (player.Experience >= expNeeded)
        {
            player.Experience -= expNeeded;
            player.Level++;
            expNeeded = CalculateExpToNextLevel(player.Level);

            // Grant level up rewards
            player.Currency += 100 * player.Level;

            _logger.LogInformation("Player {Username} leveled up to {Level}", player.Username, player.Level);

            // Check for class unlocks
            await CheckClassUnlocksAsync(player);
        }

        await _context.SaveChangesAsync();
        return ApiResponse.Ok($"Added {amount} XP. Level: {player.Level}");
    }

    public async Task<ApiResponse> AddCurrencyAsync(int playerId, int amount, bool isPremium = false)
    {
        var player = await _context.Players.FindAsync(playerId);
        if (player == null)
            return ApiResponse.Fail("Player not found");

        if (isPremium)
            player.PremiumCurrency += amount;
        else
            player.Currency += amount;

        await _context.SaveChangesAsync();
        return ApiResponse.Ok();
    }

    public async Task<ApiResponse<List<MatchHistory>>> GetMatchHistoryAsync(int playerId, int limit = 20)
    {
        var history = await _context.MatchHistories
            .Where(m => m.PlayerId == playerId)
            .OrderByDescending(m => m.PlayedAt)
            .Take(limit)
            .ToListAsync();

        return ApiResponse<List<MatchHistory>>.Ok(history);
    }

    public async Task<ApiResponse> RecordMatchAsync(int playerId, MatchResult result)
    {
        var player = await _context.Players.FindAsync(playerId);
        if (player == null)
            return ApiResponse.Fail("Player not found");

        // Find player's result
        var playerResult = result.Players.FirstOrDefault(p => p.PlayerId == playerId);
        if (playerResult == null)
            return ApiResponse.Fail("Player not in match results");

        // Record match history
        var history = new MatchHistory
        {
            PlayerId = playerId,
            MatchId = result.MatchId,
            MapName = result.MapName,
            GameMode = result.GameMode,
            PlayedAt = DateTime.UtcNow,
            DurationMinutes = result.DurationMinutes,
            Won = result.Victory,
            WaveReached = result.WaveReached,
            Kills = playerResult.Kills,
            Deaths = playerResult.Deaths,
            Score = playerResult.Score,
            Revives = playerResult.Revives,
            ClassPlayed = playerResult.ClassPlayed
        };

        _context.MatchHistories.Add(history);

        // Update stats
        var stats = await _context.PlayerStats.FirstOrDefaultAsync(s => s.PlayerId == playerId);
        if (stats != null)
        {
            stats.GamesPlayed++;
            if (result.Victory) stats.GamesWon++;
            else stats.GamesLost++;

            if (result.WaveReached > stats.HighestWave)
                stats.HighestWave = result.WaveReached;
        }

        // Calculate and add experience
        var expGained = CalculateMatchExp(playerResult, result);
        player.Experience += expGained;

        // Check for level up
        await CheckLevelUpAsync(player);

        await _context.SaveChangesAsync();

        _logger.LogInformation("Match recorded for {Username}: Wave {Wave}, Kills {Kills}, XP +{XP}",
            player.Username, result.WaveReached, playerResult.Kills, expGained);

        return ApiResponse.Ok($"Match recorded. XP gained: {expGained}");
    }

    public async Task<List<FriendInfo>> GetFriendsAsync(int playerId)
    {
        var relations = await _context.FriendRelations
            .Where(f => f.PlayerId == playerId || f.FriendId == playerId)
            .ToListAsync();

        var friendIds = relations
            .Select(f => f.PlayerId == playerId ? f.FriendId : f.PlayerId)
            .Distinct()
            .ToList();

        var friends = await _context.Players
            .Where(p => friendIds.Contains(p.Id))
            .ToListAsync();

        return friends.Select(f =>
        {
            var relation = relations.First(r =>
                (r.PlayerId == playerId && r.FriendId == f.Id) ||
                (r.FriendId == playerId && r.PlayerId == f.Id));

            return new FriendInfo
            {
                PlayerId = f.Id,
                Username = f.Username,
                Level = f.Level,
                AvatarUrl = f.AvatarUrl,
                IsOnline = f.LastLoginAt > DateTime.UtcNow.AddMinutes(-5),
                Status = relation.Status
            };
        }).ToList();
    }

    public async Task<ApiResponse> SendFriendRequestAsync(int playerId, string targetUsername)
    {
        var target = await _context.Players.FirstOrDefaultAsync(p =>
            p.Username.ToLower() == targetUsername.ToLower());

        if (target == null)
            return ApiResponse.Fail("Player not found");

        if (target.Id == playerId)
            return ApiResponse.Fail("Cannot add yourself");

        var existing = await _context.FriendRelations.FirstOrDefaultAsync(f =>
            (f.PlayerId == playerId && f.FriendId == target.Id) ||
            (f.PlayerId == target.Id && f.FriendId == playerId));

        if (existing != null)
        {
            if (existing.Status == "accepted")
                return ApiResponse.Fail("Already friends");
            if (existing.Status == "blocked")
                return ApiResponse.Fail("Cannot send request");
            return ApiResponse.Fail("Request already pending");
        }

        _context.FriendRelations.Add(new FriendRelation
        {
            PlayerId = playerId,
            FriendId = target.Id,
            Status = "pending",
            CreatedAt = DateTime.UtcNow
        });

        await _context.SaveChangesAsync();
        return ApiResponse.Ok("Friend request sent");
    }

    public async Task<ApiResponse> RespondToFriendRequestAsync(int playerId, int friendId, bool accept)
    {
        var relation = await _context.FriendRelations.FirstOrDefaultAsync(f =>
            f.PlayerId == friendId && f.FriendId == playerId && f.Status == "pending");

        if (relation == null)
            return ApiResponse.Fail("No pending request found");

        if (accept)
        {
            relation.Status = "accepted";
            await _context.SaveChangesAsync();
            return ApiResponse.Ok("Friend request accepted");
        }
        else
        {
            _context.FriendRelations.Remove(relation);
            await _context.SaveChangesAsync();
            return ApiResponse.Ok("Friend request declined");
        }
    }

    // Helper methods
    private static PlayerProfile MapToProfile(Player player)
    {
        return new PlayerProfile
        {
            Id = player.Id,
            Username = player.Username,
            Level = player.Level,
            Experience = player.Experience,
            ExperienceToNextLevel = CalculateExpToNextLevel(player.Level),
            Currency = player.Currency,
            PremiumCurrency = player.PremiumCurrency,
            SelectedClass = player.SelectedClass,
            AvatarUrl = player.AvatarUrl,
            Bio = player.Bio,
            CreatedAt = player.CreatedAt,
            Stats = player.Stats != null ? new PlayerStatsDto
            {
                TotalKills = player.Stats.TotalKills,
                ZombieKills = player.Stats.ZombieKills,
                SpecialZombieKills = player.Stats.SpecialZombieKills,
                BossKills = player.Stats.BossKills,
                Headshots = player.Stats.Headshots,
                Deaths = player.Stats.Deaths,
                Revives = player.Stats.Revives,
                GamesPlayed = player.Stats.GamesPlayed,
                GamesWon = player.Stats.GamesWon,
                HighestWave = player.Stats.HighestWave,
                TotalPlaytimeMinutes = player.Stats.TotalPlaytimeMinutes,
                Accuracy = player.Stats.Accuracy,
                KDRatio = player.Stats.KDRatio,
                WinRate = player.Stats.WinRate
            } : null,
            Unlocks = player.Unlocks?.Select(u => $"{u.UnlockType}:{u.UnlockId}").ToList() ?? new()
        };
    }

    private static int CalculateExpToNextLevel(int level)
    {
        return (int)(100 * Math.Pow(level, 1.5));
    }

    private static int CalculateMatchExp(MatchPlayerResult player, MatchResult match)
    {
        var baseExp = 50;
        var killExp = player.Kills * 5;
        var waveExp = match.WaveReached * 20;
        var victoryExp = match.Victory ? 200 : 0;
        var reviveExp = player.Revives * 25;

        return baseExp + killExp + waveExp + victoryExp + reviveExp;
    }

    private async Task CheckLevelUpAsync(Player player)
    {
        var expNeeded = CalculateExpToNextLevel(player.Level);
        while (player.Experience >= expNeeded)
        {
            player.Experience -= expNeeded;
            player.Level++;
            player.Currency += 100 * player.Level;
            expNeeded = CalculateExpToNextLevel(player.Level);

            await CheckClassUnlocksAsync(player);
        }
    }

    private async Task CheckClassUnlocksAsync(Player player)
    {
        var classUnlocks = new Dictionary<int, string>
        {
            { 5, "assault" },
            { 10, "medic" },
            { 15, "tank" },
            { 20, "engineer" },
            { 25, "scout" },
            { 30, "demolitionist" }
        };

        if (classUnlocks.TryGetValue(player.Level, out var classId))
        {
            var hasUnlock = await _context.PlayerUnlocks.AnyAsync(u =>
                u.PlayerId == player.Id && u.UnlockType == "class" && u.UnlockId == classId);

            if (!hasUnlock)
            {
                _context.PlayerUnlocks.Add(new PlayerUnlock
                {
                    PlayerId = player.Id,
                    UnlockType = "class",
                    UnlockId = classId,
                    UnlockedAt = DateTime.UtcNow
                });

                _logger.LogInformation("Player {Username} unlocked class: {Class}", player.Username, classId);
            }
        }
    }
}
