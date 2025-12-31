using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZombieSurvivalServer.Models;
using ZombieSurvivalServer.Services;

namespace ZombieSurvivalServer.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ShopController : ControllerBase
{
    private readonly IInventoryService _inventoryService;
    private readonly IAuthService _authService;
    private readonly ILogger<ShopController> _logger;

    public ShopController(
        IInventoryService inventoryService,
        IAuthService authService,
        ILogger<ShopController> logger)
    {
        _inventoryService = inventoryService;
        _authService = authService;
        _logger = logger;
    }

    /// <summary>
    /// Get shop catalog
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<List<ShopItem>>> GetShopItems([FromQuery] string? category = null)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var items = await _inventoryService.GetShopItemsAsync(playerId.Value, category);
        return Ok(items);
    }

    /// <summary>
    /// Purchase an item
    /// </summary>
    [HttpPost("purchase")]
    public async Task<ActionResult<PurchaseResponse>> PurchaseItem([FromBody] PurchaseRequest request)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var response = await _inventoryService.PurchaseItemAsync(playerId.Value, request.ItemId);

        if (!response.Success)
        {
            return BadRequest(response);
        }

        return Ok(response);
    }

    /// <summary>
    /// Get player's inventory
    /// </summary>
    [HttpGet("inventory")]
    public async Task<ActionResult<List<InventoryItem>>> GetInventory()
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var inventory = await _inventoryService.GetInventoryAsync(playerId.Value);
        return Ok(inventory);
    }

    /// <summary>
    /// Use a consumable item
    /// </summary>
    [HttpPost("use/{itemId}")]
    public async Task<ActionResult<ApiResponse>> UseItem(string itemId)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        // Check if player has the item
        var hasItem = await _inventoryService.HasItemAsync(playerId.Value, "consumable", itemId);
        if (!hasItem)
        {
            return BadRequest(ApiResponse.Fail("Item not in inventory"));
        }

        // Remove item from inventory
        var response = await _inventoryService.RemoveItemAsync(playerId.Value, "consumable", itemId, 1);

        if (!response.Success)
        {
            return BadRequest(response);
        }

        _logger.LogInformation("Player {PlayerId} used consumable {ItemId}", playerId.Value, itemId);

        return Ok(ApiResponse.Ok($"Used {itemId}"));
    }
}
