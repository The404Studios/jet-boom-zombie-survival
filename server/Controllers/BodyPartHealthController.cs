using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using ZombieSurvivalServer.Hubs;
using ZombieSurvivalServer.Models;
using ZombieSurvivalServer.Services;

namespace ZombieSurvivalServer.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class BodyPartHealthController : ControllerBase
{
    private readonly IBodyPartHealthService _healthService;
    private readonly IAuthService _authService;
    private readonly IHubContext<GameHub> _gameHub;
    private readonly ILogger<BodyPartHealthController> _logger;

    public BodyPartHealthController(
        IBodyPartHealthService healthService,
        IAuthService authService,
        IHubContext<GameHub> gameHub,
        ILogger<BodyPartHealthController> logger)
    {
        _healthService = healthService;
        _authService = authService;
        _gameHub = gameHub;
        _logger = logger;
    }

    /// <summary>
    /// Get current player's body part health
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<BodyPartHealthDto>> GetHealth()
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var health = await _healthService.GetHealthAsync(playerId.Value);
        if (health == null)
        {
            // Initialize if doesn't exist
            var result = await _healthService.InitializeHealthAsync(playerId.Value);
            if (!result.Success)
            {
                return BadRequest(result);
            }
            return Ok(result.Data);
        }

        return Ok(health);
    }

    /// <summary>
    /// Initialize body part health for current player
    /// </summary>
    [HttpPost("initialize")]
    public async Task<ActionResult<ApiResponse<BodyPartHealthDto>>> InitializeHealth()
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var result = await _healthService.InitializeHealthAsync(playerId.Value);
        if (!result.Success)
        {
            return BadRequest(result);
        }

        return Ok(result);
    }

    /// <summary>
    /// Apply damage to a specific body part
    /// </summary>
    [HttpPost("damage")]
    public async Task<ActionResult<ApiResponse<BodyPartHealthDto>>> DamageBodyPart([FromBody] DamageBodyPartRequest request)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var result = await _healthService.DamageBodyPartAsync(playerId.Value, request.BodyPart, request.Amount);
        if (!result.Success)
        {
            return BadRequest(result);
        }

        // Broadcast update to other players in same server
        await BroadcastHealthUpdate(playerId.Value, result.Data!);

        return Ok(result);
    }

    /// <summary>
    /// Heal a specific body part
    /// </summary>
    [HttpPost("heal")]
    public async Task<ActionResult<ApiResponse<BodyPartHealthDto>>> HealBodyPart([FromBody] HealBodyPartRequest request)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var result = await _healthService.HealBodyPartAsync(playerId.Value, request.BodyPart, request.Amount);
        if (!result.Success)
        {
            return BadRequest(result);
        }

        // Broadcast update to other players in same server
        await BroadcastHealthUpdate(playerId.Value, result.Data!);

        return Ok(result);
    }

    /// <summary>
    /// Start healing a body part (for the healing timer)
    /// </summary>
    [HttpPost("start-healing")]
    public async Task<ActionResult<ApiResponse<BodyPartHealthDto>>> StartHealing([FromBody] StartHealingRequest request)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var result = await _healthService.StartHealingAsync(playerId.Value, request.BodyPart);
        if (!result.Success)
        {
            return BadRequest(result);
        }

        return Ok(result);
    }

    /// <summary>
    /// Cancel current healing action
    /// </summary>
    [HttpPost("cancel-healing")]
    public async Task<ActionResult<ApiResponse>> CancelHealing()
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var result = await _healthService.CancelHealingAsync(playerId.Value);
        if (!result.Success)
        {
            return BadRequest(result);
        }

        return Ok(result);
    }

    /// <summary>
    /// Update healing progress (called periodically by client)
    /// </summary>
    [HttpPost("healing-progress")]
    public async Task<ActionResult<ApiResponse<BodyPartHealthDto>>> UpdateHealingProgress([FromQuery] float progress)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var result = await _healthService.UpdateHealingProgressAsync(playerId.Value, progress);
        if (!result.Success)
        {
            return BadRequest(result);
        }

        return Ok(result);
    }

    /// <summary>
    /// Fully heal all body parts
    /// </summary>
    [HttpPost("full-heal")]
    public async Task<ActionResult<ApiResponse<BodyPartHealthDto>>> FullHeal()
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var result = await _healthService.FullHealAsync(playerId.Value);
        if (!result.Success)
        {
            return BadRequest(result);
        }

        // Broadcast update to other players in same server
        await BroadcastHealthUpdate(playerId.Value, result.Data!);

        return Ok(result);
    }

    /// <summary>
    /// Sync body part health from client to server
    /// </summary>
    [HttpPost("sync")]
    public async Task<ActionResult<ApiResponse<BodyPartHealthDto>>> SyncHealth([FromBody] UpdateBodyPartHealthRequest request)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var result = await _healthService.SyncHealthAsync(playerId.Value, request);
        if (!result.Success)
        {
            return BadRequest(result);
        }

        // Broadcast update to other players in same server
        await BroadcastHealthUpdate(playerId.Value, result.Data!);

        return Ok(result);
    }

    /// <summary>
    /// Apply level bonus to body part max HP
    /// </summary>
    [HttpPost("apply-level-bonus/{level}")]
    public async Task<ActionResult<ApiResponse>> ApplyLevelBonus(int level)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var result = await _healthService.ApplyLevelBonusAsync(playerId.Value, level);
        if (!result.Success)
        {
            return BadRequest(result);
        }

        return Ok(result);
    }

    /// <summary>
    /// Get body part health for a specific player (for viewing teammates)
    /// </summary>
    [HttpGet("player/{playerId}")]
    [AllowAnonymous]
    public async Task<ActionResult<BodyPartHealthDto>> GetPlayerHealth(int playerId)
    {
        var health = await _healthService.GetHealthAsync(playerId);
        if (health == null)
        {
            return NotFound();
        }

        return Ok(health);
    }

    // ============================================
    // HELPER METHODS
    // ============================================

    private async Task BroadcastHealthUpdate(int playerId, BodyPartHealthDto health)
    {
        try
        {
            var syncMessage = new BodyPartHealthSyncMessage
            {
                PlayerId = playerId,
                Health = health,
                Timestamp = DateTime.UtcNow
            };

            // Broadcast to all connected clients
            await _gameHub.Clients.All.SendAsync("BodyPartHealthUpdated", syncMessage);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to broadcast health update for player {PlayerId}", playerId);
        }
    }
}
