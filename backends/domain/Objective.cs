namespace Oop.Domain;

public sealed record Objective(
    string Id,
    string Title,
    double? Percent,
    double Weight,
    string Status,
    bool Abandoned,
    IReadOnlyList<Objective> Children);
