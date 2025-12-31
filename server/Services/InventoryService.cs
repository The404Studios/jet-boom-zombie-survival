using Microsoft.EntityFrameworkCore;
using ZombieSurvivalServer.Data;
using ZombieSurvivalServer.Models;

namespace ZombieSurvivalServer.Services;

public interface IInventoryService
{
    Task<List<InventoryItem>> GetInventoryAsync(int playerId);
    Task<ApiResponse> AddItemAsync(int playerId, string itemType, string itemId, int quantity = 1);
    Task<ApiResponse> RemoveItemAsync(int playerId, string itemType, string itemId, int quantity = 1);
    Task<List<ShopItem>> GetShopItemsAsync(int playerId, string? category = null);
    Task<PurchaseResponse> PurchaseItemAsync(int playerId, string itemId);
    Task<bool> HasItemAsync(int playerId, string itemType, string itemId);
}

public class InventoryService : IInventoryService
{
    private readonly GameDbContext _context;
    private readonly ILogger<InventoryService> _logger;

    // Shop catalog (in production, this would be in database or config)
    private static readonly List<ShopItemDefinition> _shopCatalog = new()
    {
        // Weapons
        new ShopItemDefinition("weapon_shotgun", "Shotgun", "Powerful close-range weapon", "weapons", "common", 1000, "currency"),
        new ShopItemDefinition("weapon_smg", "SMG", "Fast-firing automatic weapon", "weapons", "common", 1200, "currency"),
        new ShopItemDefinition("weapon_rifle", "Assault Rifle", "Versatile automatic rifle", "weapons", "uncommon", 2000, "currency"),
        new ShopItemDefinition("weapon_sniper", "Sniper Rifle", "High-damage precision weapon", "weapons", "uncommon", 2500, "currency"),
        new ShopItemDefinition("weapon_lmg", "Light Machine Gun", "High capacity suppressive fire", "weapons", "rare", 4000, "currency"),
        new ShopItemDefinition("weapon_rpg", "Rocket Launcher", "Explosive anti-horde weapon", "weapons", "epic", 8000, "currency"),

        // Skins
        new ShopItemDefinition("skin_camo", "Camo Outfit", "Military camouflage pattern", "skins", "common", 500, "currency"),
        new ShopItemDefinition("skin_tactical", "Tactical Gear", "Black ops tactical outfit", "skins", "uncommon", 1000, "currency"),
        new ShopItemDefinition("skin_hazmat", "Hazmat Suit", "Full hazmat protection", "skins", "rare", 2000, "currency"),
        new ShopItemDefinition("skin_golden", "Golden Outfit", "Premium golden skin", "skins", "legendary", 100, "premium"),

        // Consumables
        new ShopItemDefinition("consumable_medkit", "Medical Kit", "Fully restore health", "consumables", "common", 200, "currency"),
        new ShopItemDefinition("consumable_ammo", "Ammo Pack", "Refill all ammo", "consumables", "common", 150, "currency"),
        new ShopItemDefinition("consumable_boost_xp", "XP Boost", "2x XP for 1 hour", "consumables", "uncommon", 50, "premium"),
        new ShopItemDefinition("consumable_boost_currency", "Currency Boost", "2x currency for 1 hour", "consumables", "uncommon", 50, "premium"),

        // Classes (can also be unlocked via leveling)
        new ShopItemDefinition("class_assault", "Assault Class", "Damage-focused combat specialist", "classes", "uncommon", 3000, "currency"),
        new ShopItemDefinition("class_medic", "Medic Class", "Healing and support specialist", "classes", "uncommon", 3000, "currency"),
        new ShopItemDefinition("class_tank", "Tank Class", "High durability frontline fighter", "classes", "rare", 5000, "currency"),
        new ShopItemDefinition("class_engineer", "Engineer Class", "Barricade and trap expert", "classes", "rare", 5000, "currency"),
        new ShopItemDefinition("class_scout", "Scout Class", "Fast and stealthy reconnaissance", "classes", "rare", 5000, "currency"),
        new ShopItemDefinition("class_demolitionist", "Demolitionist Class", "Explosive ordinance expert", "classes", "epic", 8000, "currency"),
    };

    public InventoryService(GameDbContext context, ILogger<InventoryService> logger)
    {
        _context = context;
        _logger = logger;
    }

    public async Task<List<InventoryItem>> GetInventoryAsync(int playerId)
    {
        return await _context.InventoryItems
            .Where(i => i.PlayerId == playerId)
            .ToListAsync();
    }

    public async Task<ApiResponse> AddItemAsync(int playerId, string itemType, string itemId, int quantity = 1)
    {
        var existingItem = await _context.InventoryItems
            .FirstOrDefaultAsync(i => i.PlayerId == playerId
                                   && i.ItemType == itemType
                                   && i.ItemId == itemId);

        if (existingItem != null)
        {
            existingItem.Quantity += quantity;
        }
        else
        {
            _context.InventoryItems.Add(new InventoryItem
            {
                PlayerId = playerId,
                ItemType = itemType,
                ItemId = itemId,
                Quantity = quantity
            });
        }

        await _context.SaveChangesAsync();
        _logger.LogInformation("Added {Quantity}x {ItemType}:{ItemId} to player {PlayerId}",
            quantity, itemType, itemId, playerId);

        return ApiResponse.Ok();
    }

    public async Task<ApiResponse> RemoveItemAsync(int playerId, string itemType, string itemId, int quantity = 1)
    {
        var item = await _context.InventoryItems
            .FirstOrDefaultAsync(i => i.PlayerId == playerId
                                   && i.ItemType == itemType
                                   && i.ItemId == itemId);

        if (item == null || item.Quantity < quantity)
        {
            return ApiResponse.Fail("Insufficient items");
        }

        item.Quantity -= quantity;

        if (item.Quantity <= 0)
        {
            _context.InventoryItems.Remove(item);
        }

        await _context.SaveChangesAsync();
        return ApiResponse.Ok();
    }

    public async Task<List<ShopItem>> GetShopItemsAsync(int playerId, string? category = null)
    {
        var playerUnlocks = await _context.PlayerUnlocks
            .Where(u => u.PlayerId == playerId)
            .Select(u => $"{u.UnlockType}:{u.UnlockId}")
            .ToListAsync();

        var playerInventory = await _context.InventoryItems
            .Where(i => i.PlayerId == playerId)
            .Select(i => $"{i.ItemType}:{i.ItemId}")
            .ToListAsync();

        var player = await _context.Players.FindAsync(playerId);
        var selectedClass = player?.SelectedClass ?? "";

        var items = _shopCatalog
            .Where(item => string.IsNullOrEmpty(category) || item.Category == category)
            .Select(item =>
            {
                var unlockKey = GetUnlockKey(item);
                var inventoryKey = $"{item.ItemType}:{item.ItemId}";

                return new ShopItem
                {
                    ItemId = item.ItemId,
                    Name = item.Name,
                    Description = item.Description,
                    Category = item.Category,
                    Rarity = item.Rarity,
                    Price = item.Price,
                    CurrencyType = item.CurrencyType,
                    IsOwned = playerUnlocks.Contains(unlockKey) || playerInventory.Contains(inventoryKey),
                    IsEquipped = IsItemEquipped(item, selectedClass)
                };
            })
            .ToList();

        return items;
    }

    public async Task<PurchaseResponse> PurchaseItemAsync(int playerId, string itemId)
    {
        var item = _shopCatalog.FirstOrDefault(i => i.ItemId == itemId);
        if (item == null)
        {
            return new PurchaseResponse
            {
                Success = false,
                Error = "Item not found"
            };
        }

        var player = await _context.Players.FindAsync(playerId);
        if (player == null)
        {
            return new PurchaseResponse
            {
                Success = false,
                Error = "Player not found"
            };
        }

        // Check if already owned
        var unlockKey = GetUnlockKey(item);
        var hasUnlock = await _context.PlayerUnlocks
            .AnyAsync(u => u.PlayerId == playerId
                        && $"{u.UnlockType}:{u.UnlockId}" == unlockKey);

        if (hasUnlock && !item.Category.StartsWith("consumable"))
        {
            return new PurchaseResponse
            {
                Success = false,
                Error = "Already owned",
                RemainingCurrency = player.Currency,
                RemainingPremiumCurrency = player.PremiumCurrency
            };
        }

        // Check currency
        var hasEnough = item.CurrencyType == "premium"
            ? player.PremiumCurrency >= item.Price
            : player.Currency >= item.Price;

        if (!hasEnough)
        {
            return new PurchaseResponse
            {
                Success = false,
                Error = "Insufficient funds",
                RemainingCurrency = player.Currency,
                RemainingPremiumCurrency = player.PremiumCurrency
            };
        }

        // Deduct currency
        if (item.CurrencyType == "premium")
            player.PremiumCurrency -= item.Price;
        else
            player.Currency -= item.Price;

        // Grant item
        if (item.Category.StartsWith("consumable"))
        {
            // Consumables go to inventory
            await AddItemAsync(playerId, "consumable", item.ItemId, 1);
        }
        else
        {
            // Permanent unlocks
            var unlockType = item.Category switch
            {
                "weapons" => "weapon",
                "skins" => "skin",
                "classes" => "class",
                _ => item.Category.TrimEnd('s')
            };

            _context.PlayerUnlocks.Add(new PlayerUnlock
            {
                PlayerId = playerId,
                UnlockType = unlockType,
                UnlockId = item.ItemId.Replace($"{unlockType}_", ""),
                UnlockedAt = DateTime.UtcNow
            });
        }

        await _context.SaveChangesAsync();

        _logger.LogInformation("Player {PlayerId} purchased {ItemId} for {Price} {Currency}",
            playerId, itemId, item.Price, item.CurrencyType);

        return new PurchaseResponse
        {
            Success = true,
            RemainingCurrency = player.Currency,
            RemainingPremiumCurrency = player.PremiumCurrency
        };
    }

    public async Task<bool> HasItemAsync(int playerId, string itemType, string itemId)
    {
        // Check unlocks
        var hasUnlock = await _context.PlayerUnlocks
            .AnyAsync(u => u.PlayerId == playerId
                        && u.UnlockType == itemType
                        && u.UnlockId == itemId);

        if (hasUnlock)
            return true;

        // Check inventory
        return await _context.InventoryItems
            .AnyAsync(i => i.PlayerId == playerId
                        && i.ItemType == itemType
                        && i.ItemId == itemId
                        && i.Quantity > 0);
    }

    private static string GetUnlockKey(ShopItemDefinition item)
    {
        var unlockType = item.Category switch
        {
            "weapons" => "weapon",
            "skins" => "skin",
            "classes" => "class",
            _ => item.Category.TrimEnd('s')
        };

        var unlockId = item.ItemId.Replace($"{unlockType}_", "");
        return $"{unlockType}:{unlockId}";
    }

    private static bool IsItemEquipped(ShopItemDefinition item, string selectedClass)
    {
        if (item.Category == "classes")
        {
            var classId = item.ItemId.Replace("class_", "");
            return classId == selectedClass;
        }
        return false;
    }

    private class ShopItemDefinition
    {
        public string ItemId { get; }
        public string Name { get; }
        public string Description { get; }
        public string Category { get; }
        public string Rarity { get; }
        public int Price { get; }
        public string CurrencyType { get; }

        public string ItemType => Category switch
        {
            "weapons" => "weapon",
            "skins" => "skin",
            "classes" => "class",
            "consumables" => "consumable",
            _ => Category.TrimEnd('s')
        };

        public ShopItemDefinition(string itemId, string name, string description, string category, string rarity, int price, string currencyType)
        {
            ItemId = itemId;
            Name = name;
            Description = description;
            Category = category;
            Rarity = rarity;
            Price = price;
            CurrencyType = currencyType;
        }
    }
}
