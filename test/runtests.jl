using StructHelpers: @batteries, StructHelpers
const SH = StructHelpers
using Test

struct SVanilla
    a
    b
end
struct SBatteries
    a
    b
end
@batteries SBatteries
struct SNoHash
    a
    b
end
@batteries SNoHash hash=false
struct Skw
    a
    b
end
@batteries Skw kwconstructor=true kwshow=true

struct Empty1 end
struct Empty2 end
@batteries Empty1
@batteries Empty2

struct Salt1 end
struct Salt1b end
struct Salt2 end
@batteries Salt1 typesalt = 1
@batteries Salt1b typesalt = 1
@batteries Salt2 typesalt = 2
struct NoSalt end
@batteries NoSalt

struct SErrors;a;b;c;end

@testset "@batteries" begin
    @test SBatteries(1,2) == SBatteries(1,2)
    @test SBatteries(1,[]) == SBatteries(1,[])
    @test Skw(1,[]) == Skw(1,[])
    @test SNoHash(1,[]) == SNoHash(1,[])
    @test SVanilla(1,[]) != SVanilla(1,[])

    @test SBatteries(2,1) != SBatteries(1,2)
    @test Skw(2,1) != Skw(1,2)
    @test SNoHash(2,1) != SNoHash(1,2)

    @test hash(SBatteries(1,[])) == hash(SBatteries(1,[]))
    @test hash(SVanilla(1,[])) != hash(SVanilla(1,[]))
    @test hash(SNoHash(1,[])) != hash(SNoHash(1,[]))

    @test hash(SBatteries(2,[])) != hash(SBatteries(1,[]))
    @test hash(SNoHash(2,[])) != hash(SNoHash(1,[]))
    @test hash(Skw(2,[])) != hash(Skw(1,[]))

    @test SH.getproperties(SBatteries(1,2)) === (a=1, b=2)
    @test SH.setproperties(SBatteries(1,2), (a=10, b=20)) === SBatteries(10, 20)

    @test Skw(a=1, b=2) === Skw(1,2)
    @test_throws MethodError SBatteries(a=1, b=2)

    s = sprint(show, Skw(a=1, b=2))
    @test occursin("=", s)

    s = sprint(show, SBatteries(1,2))
    @test !occursin("=", s)

    @test Empty1() !== Empty2()
    @test Empty1() != Empty2()
    @test hash(Empty1()) != hash(Empty2())

    @test_throws Exception @macroexpand @batteries SErrors kwconstructor="true"
    @test_throws Exception @macroexpand @batteries SErrors nonsense=true
    @macroexpand @batteries SErrors kwconstructor=true

    @test hash(Salt1()) === hash(Salt1b())
    @test hash(Salt1()) != hash(NoSalt())
    @test hash(Salt1()) != hash(Salt2())
end
