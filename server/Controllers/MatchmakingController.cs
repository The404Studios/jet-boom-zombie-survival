using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZombieSurvivalServer.Models;
using ZombieSurvivalServer.Services;

namespace ZombieSurvivalServer.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class MatchmakingController : ControllerBase
{
    private readonly IMatchmakingService _matchmakingService;
    private readonly IAuthService _authService;
    private readonly ILogger<MatchmakingController> _logger;

    public MatchmakingController(
        IMatchmakingService matchmakingService,
        IAuthService authService,
        ILogger<MatchmakingController> logger)
    {
        _matchmakingService = matchmakingService;
        _authService = authService;
        _logger = logger;
    }

    /// <summary>
    /// Join matchmaking queue
    /// </summary>
    [HttpPost("join")]
    public async Task<ActionResult<object>> JoinQueue([FromBody] MatchmakingRequest request)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var ticketId = await _matchmakingService.JoinQueueAsync(playerId.Value, request);

        return Ok(new { TicketId = ticketId });
    }

    /// <summary>
    /// Get matchmaking status
    /// </summary>
    [HttpGet("status/{ticketId}")]
    public async Task<ActionResult<MatchmakingStatus>> GetStatus(string ticketId)
    {
        var status = await _matchmakingService.GetStatusAsync(ticketId);
        return Ok(status);
    }

    /// <summary>
    /// Cancel matchmaking
    /// </summary>
    [HttpDelete("{ticketId}")]
    public async Task<ActionResult<ApiResponse>> CancelMatchmaking(string ticketId)
    {
        await _matchmakingService.CancelAsync(ticketId);
        return Ok(ApiResponse.Ok("Matchmaking cancelled"));
    }
}
