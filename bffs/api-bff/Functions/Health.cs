using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace ApiBff.Functions;

public class Health
{
    private readonly ILogger<Health> _logger;
    public Health(ILogger<Health> logger) => _logger = logger;

    [Function("health")]
    public IActionResult Run([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "health")] HttpRequest req)
    {
        _logger.LogInformation("Health check");
        return new OkObjectResult(new { status = "healthy" });
    }
}
