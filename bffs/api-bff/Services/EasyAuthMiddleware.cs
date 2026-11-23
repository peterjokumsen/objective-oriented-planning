using Microsoft.AspNetCore.Http;

namespace ApiBff.Services;

// Stub middleware: Easy Auth JWT validation lands in Phase 3.
public class EasyAuthMiddleware : IMiddleware
{
    public Task InvokeAsync(HttpContext context, RequestDelegate next) => next(context);
}
