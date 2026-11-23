using Oop.Domain;
using Xunit;

public class RollupTests
{
    [Fact]
    public void Childless_Parent_Null()
    {
        var p = new Objective("p","p",null,1,"",false,new List<Objective>());
        Assert.Null(Rollup.Compute(p));
    }

    [Fact]
    public void Unassigned_Child_Drags()
    {
        var c1 = new Objective("a","a",50,2,"",false,new List<Objective>());
        var c2 = new Objective("b","b",null,3,"",false,new List<Objective>());
        var p = new Objective("p","p",null,1,"",false,new List<Objective>{c1,c2});
        Assert.Equal(20.0, Rollup.Compute(p)!.Value, 3);
    }

    [Fact]
    public void Abandoned_Excluded()
    {
        var c1 = new Objective("a","a",100,2,"",false,new List<Objective>());
        var c2 = new Objective("b","b",0,3,"",true,new List<Objective>());
        var p = new Objective("p","p",null,1,"",false,new List<Objective>{c1,c2});
        Assert.Equal(100.0, Rollup.Compute(p)!.Value, 3);
    }
}
