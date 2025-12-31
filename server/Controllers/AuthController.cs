using Microsoft.AspNetCore.Mvc;
using ZombieSurvivalServer.Models;
using ZombieSurvivalServer.Services;

namespace ZombieSurvivalServer.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly IAuthService _authService;
    private readonly ILogger<AuthController> _logger;

    public AuthController(IAuthService authService, ILogger<AuthController> logger)
    {
        _authService = authService;
        _logger = logger;
    }

    /// <summary>
    /// Register a new player account
    /// </summary>
    [HttpPost("register")]
    public async Task<ActionResult<AuthResponse>> Register([FromBody] RegisterRequest request)
    {
        var response = await _authService.RegisterAsync(request);

        if (!response.Success)
        {
            return BadRequest(response);
        }

        return Ok(response);
    }

    /// <summary>
    /// Login with existing credentials
    /// </summary>
    [HttpPost("login")]
    public async Task<ActionResult<AuthResponse>> Login([FromBody] LoginRequest request)
    {
        var response = await _authService.LoginAsync(request);

        if (!response.Success)
        {
            return Unauthorized(response);
        }

        return Ok(response);
    }

    /// <summary>
    /// Refresh authentication token
    /// </summary>
    [HttpPost("refresh")]
    public async Task<ActionResult<AuthResponse>> Refresh([FromBody] RefreshTokenRequest request)
    {
        var response = await _authService.RefreshTokenAsync(request.RefreshToken);

        if (!response.Success)
        {
            return Unauthorized(response);
        }

        return Ok(response);
    }

    /// <summary>
    /// Validate a token
    /// </summary>
    [HttpPost("validate")]
    public async Task<ActionResult<ApiResponse>> Validate([FromHeader(Name = "Authorization")] string authorization)
    {
        if (string.IsNullOrEmpty(authorization) || !authorization.StartsWith("Bearer "))
        {
            return BadRequest(ApiResponse.Fail("No token provided"));
        }

        var token = authorization.Substring(7);
        var isValid = await _authService.ValidateTokenAsync(token);

        if (!isValid)
        {
            return Unauthorized(ApiResponse.Fail("Invalid token"));
        }

        return Ok(ApiResponse.Ok("Token is valid"));
    }
}
