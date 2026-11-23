namespace Oop.Domain;

public static class Rollup
{
    public static double? Compute(Objective parent)
    {
        if (parent.Children.Count == 0) return null;
        double num = 0, den = 0;
        foreach (var c in parent.Children)
        {
            if (c.Abandoned) continue;
            var pct = c.Percent ?? 0;
            num += pct * c.Weight;
            den += c.Weight;
        }
        if (den == 0) return null;
        return num / den;
    }
}
