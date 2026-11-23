using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace ApiBff.Functions;

public class OpenApiSpec
{
    private readonly ILogger<OpenApiSpec> _logger;
    public OpenApiSpec(ILogger<OpenApiSpec> logger) => _logger = logger;

    [Function("openapi")]
    public IActionResult Run([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "openapi.json")] HttpRequest req)
    {
        _logger.LogInformation("OpenAPI spec requested");
        var spec = """
        {
          "openapi": "3.0.3",
          "info": { "title": "OOP BFF", "version": "0.1.0" },
          "paths": {
            "/api/health": { "get": { "responses": { "200": { "description": "OK" } } } },
            "/api/ready": { "get": { "responses": { "200": { "description": "OK" } } } }
          }
        }
        """;
        return new ContentResult { Content = spec, ContentType = "application/json" };
    }
}
