using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace ZombieSurvivalServer.Models;

/// <summary>
/// Stores the body part health state for a player
/// Each body part has individual HP that can be damaged and healed
/// </summary>
public class PlayerBodyPartHealth
{
    [Key]
    public int Id { get; set; }

    public int PlayerId { get; set; }
    public Player? Player { get; set; }

    // Head
    public float HeadCurrentHp { get; set; } = 15.0f;
    public float HeadMaxHp { get; set; } = 15.0f;

    // Chest
    public float ChestCurrentHp { get; set; } = 40.0f;
    public float ChestMaxHp { get; set; } = 40.0f;

    // Thorax
    public float ThoraxCurrentHp { get; set; } = 40.0f;
    public float ThoraxMaxHp { get; set; } = 40.0f;

    // Left Arm
    public float LeftArmCurrentHp { get; set; } = 25.0f;
    public float LeftArmMaxHp { get; set; } = 25.0f;

    // Right Arm
    public float RightArmCurrentHp { get; set; } = 25.0f;
    public float RightArmMaxHp { get; set; } = 25.0f;

    // Left Hand
    public float LeftHandCurrentHp { get; set; } = 25.0f;
    public float LeftHandMaxHp { get; set; } = 25.0f;

    // Right Hand
    public float RightHandCurrentHp { get; set; } = 25.0f;
    public float RightHandMaxHp { get; set; } = 25.0f;

    // Left Leg
    public float LeftLegCurrentHp { get; set; } = 25.0f;
    public float LeftLegMaxHp { get; set; } = 25.0f;

    // Right Leg
    public float RightLegCurrentHp { get; set; } = 25.0f;
    public float RightLegMaxHp { get; set; } = 25.0f;

    // Left Foot
    public float LeftFootCurrentHp { get; set; } = 25.0f;
    public float LeftFootMaxHp { get; set; } = 25.0f;

    // Right Foot
    public float RightFootCurrentHp { get; set; } = 25.0f;
    public float RightFootMaxHp { get; set; } = 25.0f;

    // Active effects stored as JSON
    [MaxLength(1000)]
    public string? ActiveEffects { get; set; } // JSON: [{type, remainingTime, bodyPart}]

    // Healing state
    public bool IsHealing { get; set; } = false;
    public string? HealingBodyPart { get; set; }
    public float HealingProgress { get; set; } = 0.0f;

    public DateTime LastUpdated { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Apply level-based HP bonus (+2 HP per level for each limb)
    /// </summary>
    public void ApplyLevelBonus(int level)
    {
        float bonus = (level - 1) * 2.0f;

        HeadMaxHp = 15.0f + bonus;
        ChestMaxHp = 40.0f + bonus;
        ThoraxMaxHp = 40.0f + bonus;
        LeftArmMaxHp = 25.0f + bonus;
        RightArmMaxHp = 25.0f + bonus;
        LeftHandMaxHp = 25.0f + bonus;
        RightHandMaxHp = 25.0f + bonus;
        LeftLegMaxHp = 25.0f + bonus;
        RightLegMaxHp = 25.0f + bonus;
        LeftFootMaxHp = 25.0f + bonus;
        RightFootMaxHp = 25.0f + bonus;
    }

    /// <summary>
    /// Reset all body parts to full health
    /// </summary>
    public void FullHeal()
    {
        HeadCurrentHp = HeadMaxHp;
        ChestCurrentHp = ChestMaxHp;
        ThoraxCurrentHp = ThoraxMaxHp;
        LeftArmCurrentHp = LeftArmMaxHp;
        RightArmCurrentHp = RightArmMaxHp;
        LeftHandCurrentHp = LeftHandMaxHp;
        RightHandCurrentHp = RightHandMaxHp;
        LeftLegCurrentHp = LeftLegMaxHp;
        RightLegCurrentHp = RightLegMaxHp;
        LeftFootCurrentHp = LeftFootMaxHp;
        RightFootCurrentHp = RightFootMaxHp;
        ActiveEffects = null;
        IsHealing = false;
        HealingBodyPart = null;
        HealingProgress = 0.0f;
    }

    [NotMapped]
    public bool HasBleedingEffect => GetBlackedOutParts().Count > 0;

    /// <summary>
    /// Get list of body parts that are blacked out (0 HP)
    /// </summary>
    public List<string> GetBlackedOutParts()
    {
        var parts = new List<string>();
        if (HeadCurrentHp <= 0) parts.Add("head");
        if (ChestCurrentHp <= 0) parts.Add("chest");
        if (ThoraxCurrentHp <= 0) parts.Add("thorax");
        if (LeftArmCurrentHp <= 0) parts.Add("left_arm");
        if (RightArmCurrentHp <= 0) parts.Add("right_arm");
        if (LeftHandCurrentHp <= 0) parts.Add("left_hand");
        if (RightHandCurrentHp <= 0) parts.Add("right_hand");
        if (LeftLegCurrentHp <= 0) parts.Add("left_leg");
        if (RightLegCurrentHp <= 0) parts.Add("right_leg");
        if (LeftFootCurrentHp <= 0) parts.Add("left_foot");
        if (RightFootCurrentHp <= 0) parts.Add("right_foot");
        return parts;
    }
}

/// <summary>
/// Active status effect on the player
/// </summary>
public class BodyPartEffect
{
    public string Type { get; set; } = string.Empty; // bleeding, healing, poison, etc.
    public string BodyPart { get; set; } = string.Empty;
    public float RemainingTime { get; set; }
    public float TotalDuration { get; set; }
    public float TickDamage { get; set; } // Damage per tick for bleeding
}
