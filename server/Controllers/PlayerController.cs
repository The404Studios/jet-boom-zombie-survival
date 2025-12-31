using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZombieSurvivalServer.Models;
using ZombieSurvivalServer.Services;

namespace ZombieSurvivalServer.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class PlayerController : ControllerBase
{
    private readonly IPlayerService _playerService;
    private readonly IAuthService _authService;
    private readonly ILogger<PlayerController> _logger;

    public PlayerController(
        IPlayerService playerService,
        IAuthService authService,
        ILogger<PlayerController> logger)
    {
        _playerService = playerService;
        _authService = authService;
        _logger = logger;
    }

    /// <summary>
    /// Get current player's profile
    /// </summary>
    [HttpGet("me")]
    public async Task<ActionResult<PlayerProfile>> GetCurrentPlayer()
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var profile = await _playerService.GetProfileAsync(playerId.Value);
        if (profile == null)
        {
            return NotFound();
        }

        return Ok(profile);
    }

    /// <summary>
    /// Get player profile by ID
    /// </summary>
    [HttpGet("{id}")]
    [AllowAnonymous]
    public async Task<ActionResult<PlayerProfile>> GetPlayer(int id)
    {
        var profile = await _playerService.GetProfileAsync(id);
        if (profile == null)
        {
            return NotFound();
        }

        return Ok(profile);
    }

    /// <summary>
    /// Get player profile by username
    /// </summary>
    [HttpGet("username/{username}")]
    [AllowAnonymous]
    public async Task<ActionResult<PlayerProfile>> GetPlayerByUsername(string username)
    {
        var profile = await _playerService.GetProfileByUsernameAsync(username);
        if (profile == null)
        {
            return NotFound();
        }

        return Ok(profile);
    }

    /// <summary>
    /// Update current player's profile
    /// </summary>
    [HttpPatch("me")]
    public async Task<ActionResult<ApiResponse>> UpdateProfile([FromBody] UpdateProfileRequest request)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var response = await _playerService.UpdateProfileAsync(playerId.Value, request);

        if (!response.Success)
        {
            return BadRequest(response);
        }

        return Ok(response);
    }

    /// <summary>
    /// Update player stats (typically called by game server)
    /// </summary>
    [HttpPost("stats")]
    public async Task<ActionResult<ApiResponse>> UpdateStats([FromBody] UpdateStatsRequest request)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var response = await _playerService.UpdateStatsAsync(playerId.Value, request);

        if (!response.Success)
        {
            return BadRequest(response);
        }

        return Ok(response);
    }

    /// <summary>
    /// Get player's match history
    /// </summary>
    [HttpGet("me/matches")]
    public async Task<ActionResult<List<MatchHistory>>> GetMatchHistory([FromQuery] int limit = 20)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var response = await _playerService.GetMatchHistoryAsync(playerId.Value, limit);
        return Ok(response.Data);
    }

    /// <summary>
    /// Record a completed match
    /// </summary>
    [HttpPost("me/matches")]
    public async Task<ActionResult<ApiResponse>> RecordMatch([FromBody] MatchResult result)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var response = await _playerService.RecordMatchAsync(playerId.Value, result);

        if (!response.Success)
        {
            return BadRequest(response);
        }

        return Ok(response);
    }

    /// <summary>
    /// Get player's friends list
    /// </summary>
    [HttpGet("me/friends")]
    public async Task<ActionResult<List<FriendInfo>>> GetFriends()
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var friends = await _playerService.GetFriendsAsync(playerId.Value);
        return Ok(friends);
    }

    /// <summary>
    /// Send a friend request
    /// </summary>
    [HttpPost("me/friends")]
    public async Task<ActionResult<ApiResponse>> SendFriendRequest([FromBody] FriendRequest request)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var response = await _playerService.SendFriendRequestAsync(playerId.Value, request.Username);

        if (!response.Success)
        {
            return BadRequest(response);
        }

        return Ok(response);
    }

    /// <summary>
    /// Accept or decline a friend request
    /// </summary>
    [HttpPost("me/friends/{friendId}/respond")]
    public async Task<ActionResult<ApiResponse>> RespondToFriendRequest(int friendId, [FromQuery] bool accept = true)
    {
        var playerId = _authService.GetUserIdFromToken(User);
        if (!playerId.HasValue)
        {
            return Unauthorized();
        }

        var response = await _playerService.RespondToFriendRequestAsync(playerId.Value, friendId, accept);

        if (!response.Success)
        {
            return BadRequest(response);
        }

        return Ok(response);
    }
}
