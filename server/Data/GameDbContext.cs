using Microsoft.EntityFrameworkCore;
using ZombieSurvivalServer.Models;

namespace ZombieSurvivalServer.Data;

public class GameDbContext : DbContext
{
    public GameDbContext(DbContextOptions<GameDbContext> options) : base(options)
    {
    }

    public DbSet<Player> Players { get; set; }
    public DbSet<PlayerStats> PlayerStats { get; set; }
    public DbSet<PlayerUnlock> PlayerUnlocks { get; set; }
    public DbSet<InventoryItem> InventoryItems { get; set; }
    public DbSet<PlayerAchievement> PlayerAchievements { get; set; }
    public DbSet<MatchHistory> MatchHistories { get; set; }
    public DbSet<FriendRelation> FriendRelations { get; set; }
    public DbSet<GameServer> GameServers { get; set; }
    public DbSet<ServerPlayer> ServerPlayers { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Player
        modelBuilder.Entity<Player>(entity =>
        {
            entity.HasIndex(e => e.Username).IsUnique();
            entity.HasIndex(e => e.Email).IsUnique();

            entity.HasOne(e => e.Stats)
                  .WithOne(e => e.Player)
                  .HasForeignKey<PlayerStats>(e => e.PlayerId)
                  .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany(e => e.Unlocks)
                  .WithOne(e => e.Player)
                  .HasForeignKey(e => e.PlayerId)
                  .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany(e => e.Inventory)
                  .WithOne(e => e.Player)
                  .HasForeignKey(e => e.PlayerId)
                  .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany(e => e.Achievements)
                  .WithOne(e => e.Player)
                  .HasForeignKey(e => e.PlayerId)
                  .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany(e => e.MatchHistory)
                  .WithOne(e => e.Player)
                  .HasForeignKey(e => e.PlayerId)
                  .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany(e => e.Friends)
                  .WithOne(e => e.Player)
                  .HasForeignKey(e => e.PlayerId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        // PlayerUnlock - composite index
        modelBuilder.Entity<PlayerUnlock>(entity =>
        {
            entity.HasIndex(e => new { e.PlayerId, e.UnlockType, e.UnlockId }).IsUnique();
        });

        // InventoryItem
        modelBuilder.Entity<InventoryItem>(entity =>
        {
            entity.HasIndex(e => new { e.PlayerId, e.ItemType, e.ItemId });
        });

        // PlayerAchievement
        modelBuilder.Entity<PlayerAchievement>(entity =>
        {
            entity.HasIndex(e => new { e.PlayerId, e.AchievementId }).IsUnique();
        });

        // MatchHistory
        modelBuilder.Entity<MatchHistory>(entity =>
        {
            entity.HasIndex(e => e.PlayerId);
            entity.HasIndex(e => e.MatchId);
            entity.HasIndex(e => e.PlayedAt);
        });

        // FriendRelation
        modelBuilder.Entity<FriendRelation>(entity =>
        {
            entity.HasIndex(e => new { e.PlayerId, e.FriendId }).IsUnique();
        });

        // GameServer
        modelBuilder.Entity<GameServer>(entity =>
        {
            entity.HasIndex(e => e.ServerToken).IsUnique();
            entity.HasIndex(e => e.Status);
            entity.HasIndex(e => e.Region);
        });

        // ServerPlayer
        modelBuilder.Entity<ServerPlayer>(entity =>
        {
            entity.HasIndex(e => new { e.ServerId, e.PlayerId }).IsUnique();
        });

        // Seed default unlocks that all players should have
        SeedDefaultData(modelBuilder);
    }

    private void SeedDefaultData(ModelBuilder modelBuilder)
    {
        // We don't seed player data, but we could seed achievement definitions, etc.
        // For now, the default unlocks are handled in the PlayerService
    }
}

// Extension methods for common queries
public static class DbContextExtensions
{
    public static async Task<Player?> GetPlayerWithStatsAsync(this GameDbContext context, int playerId)
    {
        return await context.Players
            .Include(p => p.Stats)
            .FirstOrDefaultAsync(p => p.Id == playerId);
    }

    public static async Task<Player?> GetPlayerFullAsync(this GameDbContext context, int playerId)
    {
        return await context.Players
            .Include(p => p.Stats)
            .Include(p => p.Unlocks)
            .Include(p => p.Inventory)
            .Include(p => p.Achievements)
            .FirstOrDefaultAsync(p => p.Id == playerId);
    }

    public static async Task<List<GameServer>> GetActiveServersAsync(this GameDbContext context)
    {
        var cutoff = DateTime.UtcNow.AddSeconds(-60);
        return await context.GameServers
            .Where(s => s.LastHeartbeat > cutoff && s.Status != "ended")
            .OrderByDescending(s => s.CurrentPlayers)
            .ToListAsync();
    }
}
