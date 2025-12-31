using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using ZombieSurvivalServer.Data;
using ZombieSurvivalServer.Models;

namespace ZombieSurvivalServer.Services;

public interface IAuthService
{
    Task<AuthResponse> RegisterAsync(RegisterRequest request);
    Task<AuthResponse> LoginAsync(LoginRequest request);
    Task<AuthResponse> RefreshTokenAsync(string refreshToken);
    Task<bool> ValidateTokenAsync(string token);
    int? GetUserIdFromToken(ClaimsPrincipal user);
}

public class AuthService : IAuthService
{
    private readonly GameDbContext _context;
    private readonly IConfiguration _configuration;
    private readonly ILogger<AuthService> _logger;

    public AuthService(GameDbContext context, IConfiguration configuration, ILogger<AuthService> logger)
    {
        _context = context;
        _configuration = configuration;
        _logger = logger;
    }

    public async Task<AuthResponse> RegisterAsync(RegisterRequest request)
    {
        // Validate input
        if (string.IsNullOrWhiteSpace(request.Username) || request.Username.Length < 3)
        {
            return new AuthResponse { Success = false, Error = "Username must be at least 3 characters" };
        }

        if (string.IsNullOrWhiteSpace(request.Password) || request.Password.Length < 6)
        {
            return new AuthResponse { Success = false, Error = "Password must be at least 6 characters" };
        }

        if (string.IsNullOrWhiteSpace(request.Email) || !request.Email.Contains('@'))
        {
            return new AuthResponse { Success = false, Error = "Invalid email address" };
        }

        // Check if username or email exists
        var existingUser = await _context.Players
            .FirstOrDefaultAsync(p => p.Username.ToLower() == request.Username.ToLower()
                                   || p.Email.ToLower() == request.Email.ToLower());

        if (existingUser != null)
        {
            if (existingUser.Username.ToLower() == request.Username.ToLower())
                return new AuthResponse { Success = false, Error = "Username already exists" };
            return new AuthResponse { Success = false, Error = "Email already registered" };
        }

        // Create player
        var player = new Player
        {
            Username = request.Username,
            Email = request.Email.ToLower(),
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
            CreatedAt = DateTime.UtcNow,
            LastLoginAt = DateTime.UtcNow,
            Level = 1,
            Experience = 0,
            Currency = 500, // Starting currency
            SelectedClass = "survivor"
        };

        _context.Players.Add(player);
        await _context.SaveChangesAsync();

        // Create initial stats
        var stats = new PlayerStats
        {
            PlayerId = player.Id
        };
        _context.PlayerStats.Add(stats);

        // Grant default unlocks
        var defaultUnlocks = GetDefaultUnlocks();
        foreach (var unlock in defaultUnlocks)
        {
            _context.PlayerUnlocks.Add(new PlayerUnlock
            {
                PlayerId = player.Id,
                UnlockType = unlock.Type,
                UnlockId = unlock.Id,
                UnlockedAt = DateTime.UtcNow
            });
        }

        await _context.SaveChangesAsync();

        _logger.LogInformation("New player registered: {Username}", player.Username);

        // Generate tokens
        var (token, refreshToken) = GenerateTokens(player);

        return new AuthResponse
        {
            Success = true,
            Token = token,
            RefreshToken = refreshToken,
            ExpiresAt = DateTime.UtcNow.AddMinutes(GetTokenExpireMinutes()),
            Player = MapToProfile(player, stats)
        };
    }

    public async Task<AuthResponse> LoginAsync(LoginRequest request)
    {
        var player = await _context.Players
            .Include(p => p.Stats)
            .Include(p => p.Unlocks)
            .FirstOrDefaultAsync(p => p.Username.ToLower() == request.Username.ToLower());

        if (player == null)
        {
            return new AuthResponse { Success = false, Error = "Invalid username or password" };
        }

        if (!BCrypt.Net.BCrypt.Verify(request.Password, player.PasswordHash))
        {
            return new AuthResponse { Success = false, Error = "Invalid username or password" };
        }

        if (player.IsBanned)
        {
            if (player.BanExpiresAt == null || player.BanExpiresAt > DateTime.UtcNow)
            {
                var banMessage = player.BanExpiresAt != null
                    ? $"Account banned until {player.BanExpiresAt:g}"
                    : "Account permanently banned";
                return new AuthResponse { Success = false, Error = $"{banMessage}. Reason: {player.BanReason}" };
            }
            // Ban expired, unban
            player.IsBanned = false;
            player.BanReason = null;
            player.BanExpiresAt = null;
        }

        player.LastLoginAt = DateTime.UtcNow;
        await _context.SaveChangesAsync();

        _logger.LogInformation("Player logged in: {Username}", player.Username);

        var (token, refreshToken) = GenerateTokens(player);

        return new AuthResponse
        {
            Success = true,
            Token = token,
            RefreshToken = refreshToken,
            ExpiresAt = DateTime.UtcNow.AddMinutes(GetTokenExpireMinutes()),
            Player = MapToProfile(player, player.Stats)
        };
    }

    public async Task<AuthResponse> RefreshTokenAsync(string refreshToken)
    {
        // In production, store refresh tokens in database
        // For simplicity, we validate the refresh token format
        try
        {
            var handler = new JwtSecurityTokenHandler();
            var key = Encoding.UTF8.GetBytes(_configuration["Jwt:Key"]!);

            handler.ValidateToken(refreshToken, new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new SymmetricSecurityKey(key),
                ValidateIssuer = true,
                ValidIssuer = _configuration["Jwt:Issuer"],
                ValidateAudience = true,
                ValidAudience = _configuration["Jwt:Issuer"],
                ValidateLifetime = true,
                ClockSkew = TimeSpan.Zero
            }, out var validatedToken);

            var jwtToken = (JwtSecurityToken)validatedToken;
            var userId = int.Parse(jwtToken.Claims.First(x => x.Type == "id").Value);

            var player = await _context.Players
                .Include(p => p.Stats)
                .FirstOrDefaultAsync(p => p.Id == userId);

            if (player == null)
            {
                return new AuthResponse { Success = false, Error = "Invalid token" };
            }

            var (token, newRefreshToken) = GenerateTokens(player);

            return new AuthResponse
            {
                Success = true,
                Token = token,
                RefreshToken = newRefreshToken,
                ExpiresAt = DateTime.UtcNow.AddMinutes(GetTokenExpireMinutes())
            };
        }
        catch
        {
            return new AuthResponse { Success = false, Error = "Invalid or expired refresh token" };
        }
    }

    public Task<bool> ValidateTokenAsync(string token)
    {
        try
        {
            var handler = new JwtSecurityTokenHandler();
            var key = Encoding.UTF8.GetBytes(_configuration["Jwt:Key"]!);

            handler.ValidateToken(token, new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new SymmetricSecurityKey(key),
                ValidateIssuer = true,
                ValidIssuer = _configuration["Jwt:Issuer"],
                ValidateAudience = true,
                ValidAudience = _configuration["Jwt:Issuer"],
                ValidateLifetime = true,
                ClockSkew = TimeSpan.Zero
            }, out _);

            return Task.FromResult(true);
        }
        catch
        {
            return Task.FromResult(false);
        }
    }

    public int? GetUserIdFromToken(ClaimsPrincipal user)
    {
        var idClaim = user.FindFirst("id")?.Value;
        return int.TryParse(idClaim, out var id) ? id : null;
    }

    private (string Token, string RefreshToken) GenerateTokens(Player player)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_configuration["Jwt:Key"]!));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var issuer = _configuration["Jwt:Issuer"];

        var claims = new[]
        {
            new Claim("id", player.Id.ToString()),
            new Claim(ClaimTypes.Name, player.Username),
            new Claim(ClaimTypes.Email, player.Email),
            new Claim("level", player.Level.ToString())
        };

        var token = new JwtSecurityToken(
            issuer: issuer,
            audience: issuer,
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(GetTokenExpireMinutes()),
            signingCredentials: credentials
        );

        var refreshToken = new JwtSecurityToken(
            issuer: issuer,
            audience: issuer,
            claims: new[] { new Claim("id", player.Id.ToString()) },
            expires: DateTime.UtcNow.AddDays(7),
            signingCredentials: credentials
        );

        var handler = new JwtSecurityTokenHandler();
        return (handler.WriteToken(token), handler.WriteToken(refreshToken));
    }

    private int GetTokenExpireMinutes()
    {
        return int.TryParse(_configuration["Jwt:ExpireMinutes"], out var minutes) ? minutes : 1440;
    }

    private static PlayerProfile MapToProfile(Player player, PlayerStats? stats)
    {
        return new PlayerProfile
        {
            Id = player.Id,
            Username = player.Username,
            Level = player.Level,
            Experience = player.Experience,
            ExperienceToNextLevel = CalculateExpToNextLevel(player.Level),
            Currency = player.Currency,
            PremiumCurrency = player.PremiumCurrency,
            SelectedClass = player.SelectedClass,
            AvatarUrl = player.AvatarUrl,
            Bio = player.Bio,
            CreatedAt = player.CreatedAt,
            Stats = stats != null ? MapToStatsDto(stats) : null,
            Unlocks = player.Unlocks?.Select(u => $"{u.UnlockType}:{u.UnlockId}").ToList() ?? new()
        };
    }

    private static PlayerStatsDto MapToStatsDto(PlayerStats stats)
    {
        return new PlayerStatsDto
        {
            TotalKills = stats.TotalKills,
            ZombieKills = stats.ZombieKills,
            SpecialZombieKills = stats.SpecialZombieKills,
            BossKills = stats.BossKills,
            Headshots = stats.Headshots,
            Deaths = stats.Deaths,
            Revives = stats.Revives,
            GamesPlayed = stats.GamesPlayed,
            GamesWon = stats.GamesWon,
            HighestWave = stats.HighestWave,
            TotalPlaytimeMinutes = stats.TotalPlaytimeMinutes,
            Accuracy = stats.Accuracy,
            KDRatio = stats.KDRatio,
            WinRate = stats.WinRate
        };
    }

    private static int CalculateExpToNextLevel(int level)
    {
        // Exponential curve: 100 * level^1.5
        return (int)(100 * Math.Pow(level, 1.5));
    }

    private static List<(string Type, string Id)> GetDefaultUnlocks()
    {
        return new List<(string Type, string Id)>
        {
            // Default classes
            ("class", "survivor"),

            // Default weapons
            ("weapon", "pistol"),
            ("weapon", "knife"),

            // Default skins
            ("skin", "default_survivor")
        };
    }
}
