using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace ApiBff.Functions;

public class Ready
{
    private readonly ILogger<Ready> _logger;
    public Ready(ILogger<Ready> logger) => _logger = logger;

    [Function("ready")]
    public IActionResult Run([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "ready")] HttpRequest req)
    {
        _logger.LogInformation("Readiness check");
        return new OkObjectResult(new { status = "ready" });
    }
}
