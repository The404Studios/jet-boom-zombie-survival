using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZombieSurvivalServer.Models;
using ZombieSurvivalServer.Services;

namespace ZombieSurvivalServer.Controllers;

[ApiController]
[Route("api/[controller]")]
public class LeaderboardController : ControllerBase
{
    private readonly ILeaderboardService _leaderboardService;
    private readonly IAuthService _authService;

    public LeaderboardController(ILeaderboardService leaderboardService, IAuthService authService)
    {
        _leaderboardService = leaderboardService;
        _authService = authService;
    }

    /// <summary>
    /// Get leaderboard for a category
    /// </summary>
    /// <param name="category">kills, zombiekills, bosskills, headshots, revives, wins, highestwave, playtime, level</param>
    /// <param name="timeFrame">all, daily, weekly, monthly</param>
    /// <param name="limit">Max entries to return (default 100)</param>
    [HttpGet("{category}")]
    public async Task<ActionResult<LeaderboardResponse>> GetLeaderboard(
        string category,
        [FromQuery] string timeFrame = "all",
        [FromQuery] int limit = 100)
    {
        int? playerId = null;

        // Try to get player ID if authenticated
        if (User.Identity?.IsAuthenticated == true)
        {
            playerId = _authService.GetUserIdFromToken(User);
        }

        var response = await _leaderboardService.GetLeaderboardAsync(category, timeFrame, limit, playerId);
        return Ok(response);
    }

    /// <summary>
    /// Get top players for a category
    /// </summary>
    [HttpGet("{category}/top")]
    public async Task<ActionResult<List<LeaderboardEntry>>> GetTopPlayers(
        string category,
        [FromQuery] int limit = 10)
    {
        var entries = await _leaderboardService.GetTopPlayersAsync(category, limit);
        return Ok(entries);
    }

    /// <summary>
    /// Get current player's rank in a category
    /// </summary>
    [HttpGet("{category}/me")]
    [Authorize]
    public async Task<ActionResult<object>> GetMyRank(string category)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var rank = await _leaderboardService.GetPlayerRankAsync(playerId.Value, category);

        if (!rank.HasValue)
        {
            return NotFound(new { Error = "Player not ranked" });
        }

        return Ok(new { Rank = rank.Value, Category = category });
    }
}
