namespace Oop.Domain;

public static class BlockScoring
{
    public static string Score(int logged, int target, DateTime endDate, DateTime today)
    {
        if (today < endDate.Date) return "pending";
        if (logged >= target) return "successful";
        var ratio = target == 0 ? 0 : (double)logged / target;
        if (ratio >= 0.5) return "partial";
        return "missed";
    }
}
