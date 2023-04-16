using StructHelpers: @batteries, StructHelpers, @enumbatteries
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

struct NoSelfCtor; a; end
struct WithSelfCtor; a; end
@batteries NoSelfCtor selfconstructor=false
@batteries WithSelfCtor selfconstructor=true

struct SNoIsEqual; a; end
@batteries SNoIsEqual isequal=false

@testset "@batteries" begin
    @test SBatteries(1,2) == SBatteries(1,2)
    @test SBatteries(1,[]) == SBatteries(1,[])
    @test Skw(1,[]) == Skw(1,[])
    @test SNoHash(1,[]) == SNoHash(1,[])
    @test SVanilla(1,[]) != SVanilla(1,[])

    @test isequal(SBatteries(NaN, 1), SBatteries(NaN, 1))
    @test !isequal(SBatteries(1, 1), SBatteries(NaN, 1))
    @test !isequal(SBatteries(NaN, 1), SBatteries(NaN, 2))
    @test SBatteries(NaN, 1) != SBatteries(NaN, 1)
    @test !isequal(SNoIsEqual(NaN), SNoIsEqual(NaN))
    @test isequal(SNoIsEqual(1), SNoIsEqual(1))
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

    @test WithSelfCtor(WithSelfCtor(1)) === WithSelfCtor(1)
    @test NoSelfCtor(NoSelfCtor(1)) != NoSelfCtor(1)
    @test NoSelfCtor(NoSelfCtor(1)) isa NoSelfCtor
    @test NoSelfCtor(NoSelfCtor(1)).a === NoSelfCtor(1)
end

@enum Color Red Blue Green

@enumbatteries Color string_conversion = true symbol_conversion = true selfconstructor = false

@enum Shape Circle Square 
@enumbatteries Shape symbol_conversion =true

@testset "@enumbatteries" begin
    @test Red === @inferred Color("Red")
    @test Red === @inferred convert(Color, "Red")
    @test "Red" === @inferred String(Red)
    @test "Red" === @inferred convert(String, Red)
    @test_throws ArgumentError Color("Nonsense")
    @test_throws MethodError Color(Red)

    @test :Red === @inferred Symbol(Red)
    @test :Red === @inferred convert(Symbol, Red)
    @test Red === @inferred Color(:Red)
    @test Red === @inferred convert(Color, :Red)
    @test_throws ArgumentError Color(:Nonsense)
    res = @test_throws ArgumentError convert(Color, :nonsense)
    @test occursin(":nonsense", res.value.msg)
    @test occursin(":Red", res.value.msg)
    @test occursin(":Blue", res.value.msg)
    @test occursin(":Green", res.value.msg)

    @test :Circle === @inferred Symbol(Circle)
    @test :Circle === @inferred convert(Symbol, Circle)
    @test Circle === @inferred Shape(:Circle)
    @test Circle === @inferred convert(Shape, :Circle)
    @test Circle === @inferred Shape(Circle)
    @test_throws ArgumentError Shape(:Nonsense)
    res = @test_throws ArgumentError convert(Shape, :nonsense)
    @test occursin(":Circle", res.value.msg)
    @test occursin(":Square", res.value.msg)

    @test_throws Exception String(Circle)
    @test_throws Exception convert(String, Circle)
    @test_throws Exception Shape("Circle")
    @test_throws Exception convert(Shape, "Circle")
end

struct Bad end
@testset "Error messages" begin
    @macroexpand @batteries Bad
    @macroexpand @batteries Bad typesalt = 0xb6a4b9eeeb03b58b
    @test_throws "`typesalt` must be literally `nothing` or an unsigned integer." @macroexpand @batteries Bad typesalt = "ouch"
    @test_throws "Unsupported keyword." @macroexpand @batteries Bad does_not_exist = true   
    @test_throws "Bad keyword argument value" @macroexpand @batteries Bad hash=:nonsense
end
