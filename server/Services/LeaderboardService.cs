using Microsoft.EntityFrameworkCore;
using ZombieSurvivalServer.Data;
using ZombieSurvivalServer.Models;

namespace ZombieSurvivalServer.Services;

public interface ILeaderboardService
{
    Task<LeaderboardResponse> GetLeaderboardAsync(string category, string timeFrame = "all", int limit = 100, int? playerId = null);
    Task<List<LeaderboardEntry>> GetTopPlayersAsync(string category, int limit = 10);
    Task<int?> GetPlayerRankAsync(int playerId, string category);
}

public class LeaderboardService : ILeaderboardService
{
    private readonly GameDbContext _context;

    public LeaderboardService(GameDbContext context)
    {
        _context = context;
    }

    public async Task<LeaderboardResponse> GetLeaderboardAsync(
        string category,
        string timeFrame = "all",
        int limit = 100,
        int? playerId = null)
    {
        var query = BuildLeaderboardQuery(category, timeFrame);

        var entries = await query
            .Take(limit)
            .ToListAsync();

        var response = new LeaderboardResponse
        {
            Category = category,
            TimeFrame = timeFrame,
            Entries = entries.Select((entry, index) => new LeaderboardEntry
            {
                Rank = index + 1,
                PlayerId = entry.PlayerId,
                Username = entry.Username,
                Level = entry.Level,
                AvatarUrl = entry.AvatarUrl,
                Value = entry.Value
            }).ToList()
        };

        // Get player's position if requested
        if (playerId.HasValue)
        {
            var playerRank = await GetPlayerRankAsync(playerId.Value, category);
            if (playerRank.HasValue)
            {
                var player = await _context.Players
                    .Include(p => p.Stats)
                    .FirstOrDefaultAsync(p => p.Id == playerId.Value);

                if (player != null)
                {
                    response.PlayerEntry = new LeaderboardEntry
                    {
                        Rank = playerRank.Value,
                        PlayerId = player.Id,
                        Username = player.Username,
                        Level = player.Level,
                        AvatarUrl = player.AvatarUrl,
                        Value = GetPlayerValue(player, category)
                    };
                }
            }
        }

        return response;
    }

    public async Task<List<LeaderboardEntry>> GetTopPlayersAsync(string category, int limit = 10)
    {
        var query = BuildLeaderboardQuery(category, "all");

        var entries = await query
            .Take(limit)
            .ToListAsync();

        return entries.Select((entry, index) => new LeaderboardEntry
        {
            Rank = index + 1,
            PlayerId = entry.PlayerId,
            Username = entry.Username,
            Level = entry.Level,
            AvatarUrl = entry.AvatarUrl,
            Value = entry.Value
        }).ToList();
    }

    public async Task<int?> GetPlayerRankAsync(int playerId, string category)
    {
        var player = await _context.Players
            .Include(p => p.Stats)
            .FirstOrDefaultAsync(p => p.Id == playerId);

        if (player?.Stats == null)
            return null;

        var playerValue = GetPlayerValue(player, category);

        // Count how many players have a higher value
        var higherCount = await CountPlayersWithHigherValueAsync(category, playerValue);

        return higherCount + 1;
    }

    private IQueryable<LeaderboardQueryResult> BuildLeaderboardQuery(string category, string timeFrame)
    {
        var baseQuery = _context.Players
            .Include(p => p.Stats)
            .Where(p => p.Stats != null && !p.IsBanned);

        // Apply time frame filter for time-based categories
        if (timeFrame != "all")
        {
            var cutoff = timeFrame switch
            {
                "daily" => DateTime.UtcNow.AddDays(-1),
                "weekly" => DateTime.UtcNow.AddDays(-7),
                "monthly" => DateTime.UtcNow.AddDays(-30),
                _ => DateTime.MinValue
            };

            // For time-based leaderboards, we'd need to track stats per period
            // For now, we use lifetime stats
        }

        // Build query based on category
        return category.ToLower() switch
        {
            "kills" => baseQuery
                .OrderByDescending(p => p.Stats!.TotalKills)
                .Select(p => new LeaderboardQueryResult
                {
                    PlayerId = p.Id,
                    Username = p.Username,
                    Level = p.Level,
                    AvatarUrl = p.AvatarUrl,
                    Value = p.Stats!.TotalKills
                }),

            "zombiekills" => baseQuery
                .OrderByDescending(p => p.Stats!.ZombieKills)
                .Select(p => new LeaderboardQueryResult
                {
                    PlayerId = p.Id,
                    Username = p.Username,
                    Level = p.Level,
                    AvatarUrl = p.AvatarUrl,
                    Value = p.Stats!.ZombieKills
                }),

            "bosskills" => baseQuery
                .OrderByDescending(p => p.Stats!.BossKills)
                .Select(p => new LeaderboardQueryResult
                {
                    PlayerId = p.Id,
                    Username = p.Username,
                    Level = p.Level,
                    AvatarUrl = p.AvatarUrl,
                    Value = p.Stats!.BossKills
                }),

            "headshots" => baseQuery
                .OrderByDescending(p => p.Stats!.Headshots)
                .Select(p => new LeaderboardQueryResult
                {
                    PlayerId = p.Id,
                    Username = p.Username,
                    Level = p.Level,
                    AvatarUrl = p.AvatarUrl,
                    Value = p.Stats!.Headshots
                }),

            "revives" => baseQuery
                .OrderByDescending(p => p.Stats!.Revives)
                .Select(p => new LeaderboardQueryResult
                {
                    PlayerId = p.Id,
                    Username = p.Username,
                    Level = p.Level,
                    AvatarUrl = p.AvatarUrl,
                    Value = p.Stats!.Revives
                }),

            "wins" => baseQuery
                .OrderByDescending(p => p.Stats!.GamesWon)
                .Select(p => new LeaderboardQueryResult
                {
                    PlayerId = p.Id,
                    Username = p.Username,
                    Level = p.Level,
                    AvatarUrl = p.AvatarUrl,
                    Value = p.Stats!.GamesWon
                }),

            "highestwave" => baseQuery
                .OrderByDescending(p => p.Stats!.HighestWave)
                .Select(p => new LeaderboardQueryResult
                {
                    PlayerId = p.Id,
                    Username = p.Username,
                    Level = p.Level,
                    AvatarUrl = p.AvatarUrl,
                    Value = p.Stats!.HighestWave
                }),

            "playtime" => baseQuery
                .OrderByDescending(p => p.Stats!.TotalPlaytimeMinutes)
                .Select(p => new LeaderboardQueryResult
                {
                    PlayerId = p.Id,
                    Username = p.Username,
                    Level = p.Level,
                    AvatarUrl = p.AvatarUrl,
                    Value = p.Stats!.TotalPlaytimeMinutes
                }),

            "level" => baseQuery
                .OrderByDescending(p => p.Level)
                .ThenByDescending(p => p.Experience)
                .Select(p => new LeaderboardQueryResult
                {
                    PlayerId = p.Id,
                    Username = p.Username,
                    Level = p.Level,
                    AvatarUrl = p.AvatarUrl,
                    Value = p.Level
                }),

            _ => baseQuery
                .OrderByDescending(p => p.Stats!.TotalKills)
                .Select(p => new LeaderboardQueryResult
                {
                    PlayerId = p.Id,
                    Username = p.Username,
                    Level = p.Level,
                    AvatarUrl = p.AvatarUrl,
                    Value = p.Stats!.TotalKills
                })
        };
    }

    private async Task<int> CountPlayersWithHigherValueAsync(string category, int value)
    {
        return category.ToLower() switch
        {
            "kills" => await _context.PlayerStats.CountAsync(s => s.TotalKills > value),
            "zombiekills" => await _context.PlayerStats.CountAsync(s => s.ZombieKills > value),
            "bosskills" => await _context.PlayerStats.CountAsync(s => s.BossKills > value),
            "headshots" => await _context.PlayerStats.CountAsync(s => s.Headshots > value),
            "revives" => await _context.PlayerStats.CountAsync(s => s.Revives > value),
            "wins" => await _context.PlayerStats.CountAsync(s => s.GamesWon > value),
            "highestwave" => await _context.PlayerStats.CountAsync(s => s.HighestWave > value),
            "playtime" => await _context.PlayerStats.CountAsync(s => s.TotalPlaytimeMinutes > value),
            "level" => await _context.Players.CountAsync(p => p.Level > value),
            _ => await _context.PlayerStats.CountAsync(s => s.TotalKills > value)
        };
    }

    private static int GetPlayerValue(Player player, string category)
    {
        if (player.Stats == null)
            return 0;

        return category.ToLower() switch
        {
            "kills" => player.Stats.TotalKills,
            "zombiekills" => player.Stats.ZombieKills,
            "bosskills" => player.Stats.BossKills,
            "headshots" => player.Stats.Headshots,
            "revives" => player.Stats.Revives,
            "wins" => player.Stats.GamesWon,
            "highestwave" => player.Stats.HighestWave,
            "playtime" => player.Stats.TotalPlaytimeMinutes,
            "level" => player.Level,
            _ => player.Stats.TotalKills
        };
    }
}

internal class LeaderboardQueryResult
{
    public int PlayerId { get; set; }
    public string Username { get; set; } = string.Empty;
    public int Level { get; set; }
    public string? AvatarUrl { get; set; }
    public int Value { get; set; }
}
