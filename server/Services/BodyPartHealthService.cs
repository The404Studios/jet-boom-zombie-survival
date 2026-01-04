using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using ZombieSurvivalServer.Data;
using ZombieSurvivalServer.Models;

namespace ZombieSurvivalServer.Services;

public interface IBodyPartHealthService
{
    Task<BodyPartHealthDto?> GetHealthAsync(int playerId);
    Task<ApiResponse<BodyPartHealthDto>> InitializeHealthAsync(int playerId);
    Task<ApiResponse<BodyPartHealthDto>> DamageBodyPartAsync(int playerId, string bodyPart, float amount);
    Task<ApiResponse<BodyPartHealthDto>> HealBodyPartAsync(int playerId, string bodyPart, float amount);
    Task<ApiResponse<BodyPartHealthDto>> StartHealingAsync(int playerId, string bodyPart);
    Task<ApiResponse> CancelHealingAsync(int playerId);
    Task<ApiResponse<BodyPartHealthDto>> UpdateHealingProgressAsync(int playerId, float progress);
    Task<ApiResponse<BodyPartHealthDto>> FullHealAsync(int playerId);
    Task<ApiResponse<BodyPartHealthDto>> SyncHealthAsync(int playerId, UpdateBodyPartHealthRequest request);
    Task<ApiResponse> ApplyLevelBonusAsync(int playerId, int level);
}

public class BodyPartHealthService : IBodyPartHealthService
{
    private readonly GameDbContext _context;
    private readonly ILogger<BodyPartHealthService> _logger;

    private static readonly Dictionary<string, (string currentField, string maxField)> BodyPartFields = new()
    {
        { "head", ("HeadCurrentHp", "HeadMaxHp") },
        { "chest", ("ChestCurrentHp", "ChestMaxHp") },
        { "thorax", ("ThoraxCurrentHp", "ThoraxMaxHp") },
        { "left_arm", ("LeftArmCurrentHp", "LeftArmMaxHp") },
        { "right_arm", ("RightArmCurrentHp", "RightArmMaxHp") },
        { "left_hand", ("LeftHandCurrentHp", "LeftHandMaxHp") },
        { "right_hand", ("RightHandCurrentHp", "RightHandMaxHp") },
        { "left_leg", ("LeftLegCurrentHp", "LeftLegMaxHp") },
        { "right_leg", ("RightLegCurrentHp", "RightLegMaxHp") },
        { "left_foot", ("LeftFootCurrentHp", "LeftFootMaxHp") },
        { "right_foot", ("RightFootCurrentHp", "RightFootMaxHp") }
    };

    public BodyPartHealthService(GameDbContext context, ILogger<BodyPartHealthService> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task<BodyPartHealthDto?> GetHealthAsync(int playerId)
    {
        var health = await _context.Set<PlayerBodyPartHealth>()
            .FirstOrDefaultAsync(h => h.PlayerId == playerId);

        return health != null ? MapToDto(health) : null;
    }

    public async Task<ApiResponse<BodyPartHealthDto>> InitializeHealthAsync(int playerId)
    {
        var existing = await _context.Set<PlayerBodyPartHealth>()
            .FirstOrDefaultAsync(h => h.PlayerId == playerId);

        if (existing != null)
        {
            return ApiResponse<BodyPartHealthDto>.Ok(MapToDto(existing));
        }

        // Get player level for HP bonus
        var player = await _context.Players.FindAsync(playerId);
        if (player == null)
        {
            return ApiResponse<BodyPartHealthDto>.Fail("Player not found");
        }

        var health = new PlayerBodyPartHealth
        {
            PlayerId = playerId
        };

        // Apply level bonus
        health.ApplyLevelBonus(player.Level);
        health.FullHeal();

        _context.Set<PlayerBodyPartHealth>().Add(health);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Initialized body part health for player {PlayerId}", playerId);

        return ApiResponse<BodyPartHealthDto>.Ok(MapToDto(health));
    }

    public async Task<ApiResponse<BodyPartHealthDto>> DamageBodyPartAsync(int playerId, string bodyPart, float amount)
    {
        var health = await GetOrCreateHealthAsync(playerId);
        if (health == null)
        {
            return ApiResponse<BodyPartHealthDto>.Fail("Could not get player health");
        }

        bodyPart = bodyPart.ToLower();
        if (!BodyPartFields.ContainsKey(bodyPart))
        {
            return ApiResponse<BodyPartHealthDto>.Fail($"Invalid body part: {bodyPart}");
        }

        // Apply damage to the specific body part
        var currentHp = GetCurrentHp(health, bodyPart);
        var newHp = Math.Max(0, currentHp - amount);
        SetCurrentHp(health, bodyPart, newHp);

        // Check if body part became blacked out (apply bleeding effect)
        if (currentHp > 0 && newHp <= 0)
        {
            AddBleedingEffect(health, bodyPart);
            _logger.LogInformation("Player {PlayerId} body part {BodyPart} blacked out - bleeding applied",
                playerId, bodyPart);
        }

        health.LastUpdated = DateTime.UtcNow;
        await _context.SaveChangesAsync();

        return ApiResponse<BodyPartHealthDto>.Ok(MapToDto(health));
    }

    public async Task<ApiResponse<BodyPartHealthDto>> HealBodyPartAsync(int playerId, string bodyPart, float amount)
    {
        var health = await GetOrCreateHealthAsync(playerId);
        if (health == null)
        {
            return ApiResponse<BodyPartHealthDto>.Fail("Could not get player health");
        }

        bodyPart = bodyPart.ToLower();
        if (!BodyPartFields.ContainsKey(bodyPart))
        {
            return ApiResponse<BodyPartHealthDto>.Fail($"Invalid body part: {bodyPart}");
        }

        var currentHp = GetCurrentHp(health, bodyPart);
        var maxHp = GetMaxHp(health, bodyPart);
        var wasBlackedOut = currentHp <= 0;

        var newHp = Math.Min(maxHp, currentHp + amount);
        SetCurrentHp(health, bodyPart, newHp);

        // Remove bleeding effect if body part is no longer blacked out
        if (wasBlackedOut && newHp > 0)
        {
            RemoveBleedingEffect(health, bodyPart);
            _logger.LogInformation("Player {PlayerId} body part {BodyPart} healed from blacked out state",
                playerId, bodyPart);
        }

        // Reset healing state
        health.IsHealing = false;
        health.HealingBodyPart = null;
        health.HealingProgress = 0;
        health.LastUpdated = DateTime.UtcNow;

        await _context.SaveChangesAsync();

        return ApiResponse<BodyPartHealthDto>.Ok(MapToDto(health));
    }

    public async Task<ApiResponse<BodyPartHealthDto>> StartHealingAsync(int playerId, string bodyPart)
    {
        var health = await GetOrCreateHealthAsync(playerId);
        if (health == null)
        {
            return ApiResponse<BodyPartHealthDto>.Fail("Could not get player health");
        }

        bodyPart = bodyPart.ToLower();
        if (!BodyPartFields.ContainsKey(bodyPart))
        {
            return ApiResponse<BodyPartHealthDto>.Fail($"Invalid body part: {bodyPart}");
        }

        // Check if the body part actually needs healing
        var currentHp = GetCurrentHp(health, bodyPart);
        var maxHp = GetMaxHp(health, bodyPart);

        if (currentHp >= maxHp)
        {
            return ApiResponse<BodyPartHealthDto>.Fail("Body part is already at full health");
        }

        health.IsHealing = true;
        health.HealingBodyPart = bodyPart;
        health.HealingProgress = 0;
        health.LastUpdated = DateTime.UtcNow;

        await _context.SaveChangesAsync();

        _logger.LogInformation("Player {PlayerId} started healing {BodyPart}", playerId, bodyPart);

        return ApiResponse<BodyPartHealthDto>.Ok(MapToDto(health));
    }

    public async Task<ApiResponse> CancelHealingAsync(int playerId)
    {
        var health = await _context.Set<PlayerBodyPartHealth>()
            .FirstOrDefaultAsync(h => h.PlayerId == playerId);

        if (health == null)
        {
            return ApiResponse.Fail("Player health not found");
        }

        health.IsHealing = false;
        health.HealingBodyPart = null;
        health.HealingProgress = 0;
        health.LastUpdated = DateTime.UtcNow;

        await _context.SaveChangesAsync();

        return ApiResponse.Ok("Healing cancelled");
    }

    public async Task<ApiResponse<BodyPartHealthDto>> UpdateHealingProgressAsync(int playerId, float progress)
    {
        var health = await _context.Set<PlayerBodyPartHealth>()
            .FirstOrDefaultAsync(h => h.PlayerId == playerId);

        if (health == null)
        {
            return ApiResponse<BodyPartHealthDto>.Fail("Player health not found");
        }

        if (!health.IsHealing || string.IsNullOrEmpty(health.HealingBodyPart))
        {
            return ApiResponse<BodyPartHealthDto>.Fail("Not currently healing");
        }

        health.HealingProgress = Math.Clamp(progress, 0, 100);
        health.LastUpdated = DateTime.UtcNow;

        await _context.SaveChangesAsync();

        return ApiResponse<BodyPartHealthDto>.Ok(MapToDto(health));
    }

    public async Task<ApiResponse<BodyPartHealthDto>> FullHealAsync(int playerId)
    {
        var health = await GetOrCreateHealthAsync(playerId);
        if (health == null)
        {
            return ApiResponse<BodyPartHealthDto>.Fail("Could not get player health");
        }

        health.FullHeal();
        health.LastUpdated = DateTime.UtcNow;

        await _context.SaveChangesAsync();

        _logger.LogInformation("Player {PlayerId} fully healed", playerId);

        return ApiResponse<BodyPartHealthDto>.Ok(MapToDto(health));
    }

    public async Task<ApiResponse<BodyPartHealthDto>> SyncHealthAsync(int playerId, UpdateBodyPartHealthRequest request)
    {
        var health = await GetOrCreateHealthAsync(playerId);
        if (health == null)
        {
            return ApiResponse<BodyPartHealthDto>.Fail("Could not get player health");
        }

        // Update HP values from client
        foreach (var kvp in request.CurrentHpValues)
        {
            var bodyPart = kvp.Key.ToLower();
            if (BodyPartFields.ContainsKey(bodyPart))
            {
                var maxHp = GetMaxHp(health, bodyPart);
                SetCurrentHp(health, bodyPart, Math.Clamp(kvp.Value, 0, maxHp));
            }
        }

        // Update effects if provided
        if (request.ActiveEffects != null)
        {
            health.ActiveEffects = JsonSerializer.Serialize(request.ActiveEffects);
        }

        // Update healing state if provided
        if (request.HealingState != null)
        {
            health.IsHealing = request.HealingState.IsHealing;
            health.HealingBodyPart = request.HealingState.BodyPart;
            health.HealingProgress = request.HealingState.Progress;
        }

        health.LastUpdated = DateTime.UtcNow;
        await _context.SaveChangesAsync();

        return ApiResponse<BodyPartHealthDto>.Ok(MapToDto(health));
    }

    public async Task<ApiResponse> ApplyLevelBonusAsync(int playerId, int level)
    {
        var health = await GetOrCreateHealthAsync(playerId);
        if (health == null)
        {
            return ApiResponse.Fail("Could not get player health");
        }

        health.ApplyLevelBonus(level);
        health.LastUpdated = DateTime.UtcNow;

        await _context.SaveChangesAsync();

        _logger.LogInformation("Applied level {Level} bonus to player {PlayerId}", level, playerId);

        return ApiResponse.Ok($"Level {level} bonus applied");
    }

    // ============================================
    // HELPER METHODS
    // ============================================

    private async Task<PlayerBodyPartHealth?> GetOrCreateHealthAsync(int playerId)
    {
        var health = await _context.Set<PlayerBodyPartHealth>()
            .FirstOrDefaultAsync(h => h.PlayerId == playerId);

        if (health == null)
        {
            var result = await InitializeHealthAsync(playerId);
            if (!result.Success) return null;

            health = await _context.Set<PlayerBodyPartHealth>()
                .FirstOrDefaultAsync(h => h.PlayerId == playerId);
        }

        return health;
    }

    private static float GetCurrentHp(PlayerBodyPartHealth health, string bodyPart) => bodyPart switch
    {
        "head" => health.HeadCurrentHp,
        "chest" => health.ChestCurrentHp,
        "thorax" => health.ThoraxCurrentHp,
        "left_arm" => health.LeftArmCurrentHp,
        "right_arm" => health.RightArmCurrentHp,
        "left_hand" => health.LeftHandCurrentHp,
        "right_hand" => health.RightHandCurrentHp,
        "left_leg" => health.LeftLegCurrentHp,
        "right_leg" => health.RightLegCurrentHp,
        "left_foot" => health.LeftFootCurrentHp,
        "right_foot" => health.RightFootCurrentHp,
        _ => 0
    };

    private static float GetMaxHp(PlayerBodyPartHealth health, string bodyPart) => bodyPart switch
    {
        "head" => health.HeadMaxHp,
        "chest" => health.ChestMaxHp,
        "thorax" => health.ThoraxMaxHp,
        "left_arm" => health.LeftArmMaxHp,
        "right_arm" => health.RightArmMaxHp,
        "left_hand" => health.LeftHandMaxHp,
        "right_hand" => health.RightHandMaxHp,
        "left_leg" => health.LeftLegMaxHp,
        "right_leg" => health.RightLegMaxHp,
        "left_foot" => health.LeftFootMaxHp,
        "right_foot" => health.RightFootMaxHp,
        _ => 0
    };

    private static void SetCurrentHp(PlayerBodyPartHealth health, string bodyPart, float value)
    {
        switch (bodyPart)
        {
            case "head": health.HeadCurrentHp = value; break;
            case "chest": health.ChestCurrentHp = value; break;
            case "thorax": health.ThoraxCurrentHp = value; break;
            case "left_arm": health.LeftArmCurrentHp = value; break;
            case "right_arm": health.RightArmCurrentHp = value; break;
            case "left_hand": health.LeftHandCurrentHp = value; break;
            case "right_hand": health.RightHandCurrentHp = value; break;
            case "left_leg": health.LeftLegCurrentHp = value; break;
            case "right_leg": health.RightLegCurrentHp = value; break;
            case "left_foot": health.LeftFootCurrentHp = value; break;
            case "right_foot": health.RightFootCurrentHp = value; break;
        }
    }

    private static void AddBleedingEffect(PlayerBodyPartHealth health, string bodyPart)
    {
        var effects = ParseEffects(health.ActiveEffects);
        effects.Add(new BodyPartEffect
        {
            Type = "bleeding",
            BodyPart = bodyPart,
            RemainingTime = 9999, // Indefinite until healed
            TotalDuration = 9999,
            TickDamage = 1.0f
        });
        health.ActiveEffects = JsonSerializer.Serialize(effects);
    }

    private static void RemoveBleedingEffect(PlayerBodyPartHealth health, string bodyPart)
    {
        var effects = ParseEffects(health.ActiveEffects);
        effects.RemoveAll(e => e.Type == "bleeding" && e.BodyPart == bodyPart);
        health.ActiveEffects = effects.Count > 0 ? JsonSerializer.Serialize(effects) : null;
    }

    private static List<BodyPartEffect> ParseEffects(string? json)
    {
        if (string.IsNullOrEmpty(json)) return new List<BodyPartEffect>();
        try
        {
            return JsonSerializer.Deserialize<List<BodyPartEffect>>(json) ?? new List<BodyPartEffect>();
        }
        catch
        {
            return new List<BodyPartEffect>();
        }
    }

    private static BodyPartHealthDto MapToDto(PlayerBodyPartHealth health)
    {
        var effects = ParseEffects(health.ActiveEffects);

        return new BodyPartHealthDto
        {
            Head = new BodyPartDto { CurrentHp = health.HeadCurrentHp, MaxHp = health.HeadMaxHp },
            Chest = new BodyPartDto { CurrentHp = health.ChestCurrentHp, MaxHp = health.ChestMaxHp },
            Thorax = new BodyPartDto { CurrentHp = health.ThoraxCurrentHp, MaxHp = health.ThoraxMaxHp },
            LeftArm = new BodyPartDto { CurrentHp = health.LeftArmCurrentHp, MaxHp = health.LeftArmMaxHp },
            RightArm = new BodyPartDto { CurrentHp = health.RightArmCurrentHp, MaxHp = health.RightArmMaxHp },
            LeftHand = new BodyPartDto { CurrentHp = health.LeftHandCurrentHp, MaxHp = health.LeftHandMaxHp },
            RightHand = new BodyPartDto { CurrentHp = health.RightHandCurrentHp, MaxHp = health.RightHandMaxHp },
            LeftLeg = new BodyPartDto { CurrentHp = health.LeftLegCurrentHp, MaxHp = health.LeftLegMaxHp },
            RightLeg = new BodyPartDto { CurrentHp = health.RightLegCurrentHp, MaxHp = health.RightLegMaxHp },
            LeftFoot = new BodyPartDto { CurrentHp = health.LeftFootCurrentHp, MaxHp = health.LeftFootMaxHp },
            RightFoot = new BodyPartDto { CurrentHp = health.RightFootCurrentHp, MaxHp = health.RightFootMaxHp },
            ActiveEffects = effects.Select(e => new BodyPartEffectDto
            {
                Type = e.Type,
                BodyPart = e.BodyPart,
                RemainingTime = e.RemainingTime,
                TotalDuration = e.TotalDuration
            }).ToList(),
            HealingState = health.IsHealing ? new HealingStateDto
            {
                IsHealing = health.IsHealing,
                BodyPart = health.HealingBodyPart,
                Progress = health.HealingProgress
            } : null,
            BlackedOutParts = health.GetBlackedOutParts(),
            HasBleedingDebuff = health.HasBleedingEffect
        };
    }
}
