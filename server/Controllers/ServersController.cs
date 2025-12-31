using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZombieSurvivalServer.Models;
using ZombieSurvivalServer.Services;

namespace ZombieSurvivalServer.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ServersController : ControllerBase
{
    private readonly IServerBrowserService _serverBrowser;
    private readonly ILogger<ServersController> _logger;

    public ServersController(IServerBrowserService serverBrowser, ILogger<ServersController> logger)
    {
        _serverBrowser = serverBrowser;
        _logger = logger;
    }

    /// <summary>
    /// Get list of available game servers
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<List<ServerListResponse>>> GetServers(
        [FromQuery] string? region = null,
        [FromQuery] string? gameMode = null,
        [FromQuery] bool hideEmpty = false,
        [FromQuery] bool hideFull = false)
    {
        var servers = await _serverBrowser.GetServersAsync(region, gameMode, hideEmpty, hideFull);
        return Ok(servers);
    }

    /// <summary>
    /// Get specific server details
    /// </summary>
    [HttpGet("{id}")]
    public async Task<ActionResult<ServerListResponse>> GetServer(int id)
    {
        var server = await _serverBrowser.GetServerAsync(id);
        if (server == null)
        {
            return NotFound();
        }

        return Ok(server);
    }

    /// <summary>
    /// Register a new game server
    /// </summary>
    [HttpPost("register")]
    public async Task<ActionResult<object>> RegisterServer([FromBody] ServerRegistrationRequest request)
    {
        var ipAddress = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";

        var result = await _serverBrowser.RegisterServerAsync(request, ipAddress);
        if (!result.HasValue)
        {
            return BadRequest(ApiResponse.Fail("Failed to register server"));
        }

        var (server, token) = result.Value;

        return Ok(new
        {
            ServerId = server.Id,
            Token = token,
            IpAddress = server.IpAddress,
            Port = server.Port
        });
    }

    /// <summary>
    /// Update game server status
    /// </summary>
    [HttpPatch("{id}")]
    public async Task<ActionResult<ApiResponse>> UpdateServer(
        int id,
        [FromHeader(Name = "X-Server-Token")] string token,
        [FromBody] ServerUpdateRequest request)
    {
        if (string.IsNullOrEmpty(token))
        {
            return Unauthorized(ApiResponse.Fail("Server token required"));
        }

        var response = await _serverBrowser.UpdateServerAsync(id, token, request);

        if (!response.Success)
        {
            return BadRequest(response);
        }

        return Ok(response);
    }

    /// <summary>
    /// Send server heartbeat
    /// </summary>
    [HttpPost("{id}/heartbeat")]
    public async Task<ActionResult<ApiResponse>> Heartbeat(
        int id,
        [FromHeader(Name = "X-Server-Token")] string token)
    {
        if (string.IsNullOrEmpty(token))
        {
            return Unauthorized(ApiResponse.Fail("Server token required"));
        }

        var response = await _serverBrowser.HeartbeatAsync(id, token);

        if (!response.Success)
        {
            return BadRequest(response);
        }

        return Ok(response);
    }

    /// <summary>
    /// Deregister a game server
    /// </summary>
    [HttpDelete("{id}")]
    public async Task<ActionResult<ApiResponse>> DeregisterServer(
        int id,
        [FromHeader(Name = "X-Server-Token")] string token)
    {
        if (string.IsNullOrEmpty(token))
        {
            return Unauthorized(ApiResponse.Fail("Server token required"));
        }

        var response = await _serverBrowser.DeregisterServerAsync(id, token);

        if (!response.Success)
        {
            return BadRequest(response);
        }

        return Ok(response);
    }

    /// <summary>
    /// Validate server password
    /// </summary>
    [HttpPost("{id}/validate-password")]
    [Authorize]
    public async Task<ActionResult<ApiResponse>> ValidatePassword(int id, [FromBody] string password)
    {
        var isValid = await _serverBrowser.ValidatePasswordAsync(id, password);

        if (!isValid)
        {
            return BadRequest(ApiResponse.Fail("Invalid password"));
        }

        return Ok(ApiResponse.Ok());
    }
}
