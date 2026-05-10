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

struct SaltABC; a;b;c end
@batteries SaltABC typesalt = 1

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
    @test SH.has_batteries(SBatteries)
    @test !SH.has_batteries(SVanilla)
    @test !SH.has_batteries(Tuple)

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

    if VERSION >= v"1.8"
        @test_throws "Bad keyword argument value:" @macroexpand @batteries  SErrors kwconstructor="true"
        @test_throws "Unsupported keyword" @macroexpand @batteries SErrors kwconstructor=true nonsense=true
        @test_throws "Expected a keyword argument of the form name = value" @macroexpand @batteries SErrors nonsense
    else
        @test_throws Exception @macroexpand @batteries  SErrors kwconstructor="true"
        @test_throws Exception @macroexpand @batteries SErrors kwconstructor=true nonsense=true
        @test_throws Exception @macroexpand @batteries SErrors nonsense
    end


    @testset "typesalt" begin
        @test hash(Salt1()) === hash(Salt1b())
        @test hash(Salt1()) != hash(NoSalt())
        @test hash(Salt1()) != hash(Salt2())

        # The contract for `typesalt = N` is
        #   hash(o, h) == hash(hash_eq_as(o), hash(N, h))
        # which (by design) excludes the type identity itself. We check
        # this contract directly; pinning literal hash values would be
        # fragile because `hash(::Tuple, ::UInt)` is not stable across
        # Julia versions. We pass an explicit seed `h` so the check does
        # not depend on `hash(x)`'s no-arg default (which changed in
        # Julia 1.11+ to use a randomized initial seed).
        let h = UInt(0)
            @test hash(Salt1(), h) === hash((), hash(1, h))
            @test hash(Salt2(), h) === hash((), hash(2, h))

            @test hash(SaltABC(1  , 2  , 3 ), h) === hash((1,  2,  3 ), hash(1, h))
            @test hash(SaltABC(10 , 2  , 3 ), h) === hash((10, 2,  3 ), hash(1, h))
            @test hash(SaltABC(10 , 20 , 3 ), h) === hash((10, 20, 3 ), hash(1, h))
            @test hash(SaltABC(10 , 20 , 30), h) === hash((10, 20, 30), hash(1, h))
        end
    end

    @test WithSelfCtor(WithSelfCtor(1)) === WithSelfCtor(1)
    @test NoSelfCtor(NoSelfCtor(1)) != NoSelfCtor(1)
    @test NoSelfCtor(NoSelfCtor(1)) isa NoSelfCtor
    @test NoSelfCtor(NoSelfCtor(1)).a === NoSelfCtor(1)
end

@enum EnumNoBatteries UsesGas UsesPlug UsesMuscles

@enum Color Red Blue Green
@enumbatteries Color string_conversion = true symbol_conversion = true selfconstructor = false

@enum Shape Circle = 7 Square = 8
@enumbatteries Shape symbol_conversion = true typesalt = 0x0578044908fb9846

@enum Size Small Medium Large
@enumbatteries Size hash = true

@testset "@enumbatteries" begin
    @test SH.has_batteries(Color)
    @test !SH.has_batteries(EnumNoBatteries)
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

@enum Negative MinusOne=-1 MinusTwo=-2 MinusThree=-3
@enumbatteries Negative typesalt = 0xd11b6121f2b8cd22

@testset "@enumbatteries hash" begin
    # hash with typesalt
    @test hash(Circle) == hash(7, hash(0x0578044908fb9846))
    @test hash(Square) == hash(8, hash(0x0578044908fb9846))

    # hash = true
    @test hash(Small) == hash(0, hash(Size))
    @test hash(Medium) == hash(1, hash(Size))
    @test hash(Large) == hash(2, hash(Size))

    # no hash by default
    @test hash(Red) != hash(0, hash(Color))

    h = 0xed315b93bf264f3e
    typesalt = 0xd11b6121f2b8cd22
    @test hash(MinusOne, h) == hash(-1, hash(typesalt, h))
    @test hash(MinusTwo, h) == hash(-2, hash(typesalt, h))
end

struct Bad end
@testset "Error messages" begin
    @macroexpand @batteries Bad
    @macroexpand @batteries Bad typesalt = 0xb6a4b9eeeb03b58b
    if VERSION >= v"1.7"
        @test_throws "`typesalt` must be literally `nothing` or an unsigned integer." @macroexpand @batteries Bad typesalt = "ouch"
        @test_throws "Unsupported keyword." @macroexpand @batteries Bad does_not_exist = true
        @test_throws "Bad keyword argument value" @macroexpand @batteries Bad hash=:nonsense
        @test_throws "Bad keyword argument value" @macroexpand @batteries Bad StructTypes=:nonsense
    end
end

abstract type AbstractHashEqAs end
function SH.hash_eq_as(x::AbstractHashEqAs)
    return x.hash_eq_as(x.payload)
end

struct HashEqAs <: AbstractHashEqAs
    hash_eq_as
    payload
end
SH.@batteries HashEqAs
struct HashEqAsTS1 <: AbstractHashEqAs
    hash_eq_as
    payload
end
SH.@batteries HashEqAsTS1 typesalt = 1

struct HashEqAsTS1b <: AbstractHashEqAs
    hash_eq_as
    payload
end
SH.@batteries HashEqAsTS1b typesalt = 1

struct HashEqAsTS2 <: AbstractHashEqAs
    hash_eq_as
    payload
end
SH.@batteries HashEqAsTS2 typesalt = 2

@testset "hash_eq_as" begin
    @test HashEqAs(identity, 1) != HashEqAs(identity, -1)
    @test HashEqAs(abs, 1) == HashEqAs(abs, -1)
    @test isequal(HashEqAs(identity, 1), HashEqAs(x->x, 1))

    @test hash(HashEqAs(identity, 1)) != hash(HashEqAs(identity, -1))
    @test hash(HashEqAs(abs, 1)) === hash(HashEqAs(abs, -1))
    @test hash(HashEqAs(identity, 1)) === hash(HashEqAs(x->x, 1))

    @test hash(HashEqAsTS1(identity, 1)) != hash(HashEqAsTS1(identity, -1))
    @test hash(HashEqAsTS1(abs, 1)) == hash(HashEqAsTS1(abs, -1))
    @test hash(HashEqAsTS1b(abs, 1)) == hash(HashEqAsTS1(abs, -1))
    @test hash(HashEqAsTS2(abs, 1)) != hash(HashEqAsTS1(abs, -1))

    @test hash(HashEqAsTS1(x->2x::Int, 1)) === hash(HashEqAsTS1(identity, 2))
    @test hash(HashEqAsTS2(x->2x::Int, 1)) != hash(HashEqAsTS1(identity, 2))
    # The contract for `typesalt = N` is
    #   hash(o, h) == hash(hash_eq_as(o), hash(N, h))
    # which (by design) excludes the type identity itself. We check
    # this contract directly; pinning literal hash values would be
    # fragile because `hash(::Int, ::UInt)` is not stable across Julia
    # versions. We pass an explicit seed `h` so the check does not
    # depend on `hash(x)`'s no-arg default (which changed in Julia
    # 1.11+ to use a randomized initial seed).
    let h = UInt(0)
        @test hash(HashEqAsTS1(identity, 1), h) === hash(1, hash(1, h))
        @test hash(HashEqAsTS2(x->5x, 1), h)    === hash(5, hash(2, h))
    end
end

mutable struct HashEqErr
    a
    b
end
Base.hash(::HashEqErr, h::UInt) = error()
Base.isequal(::HashEqErr, ::HashEqErr) = error()
Base.:(==)(::HashEqErr, ::HashEqErr) = error()

@testset "structural hash eq" begin
    S = HashEqErr
    @test SH.structural_eq(S(1,3), S(1,3))
    @test !SH.structural_eq(S(1,NaN), S(1,NaN))
    @test SH.structural_isequal(S(1,NaN), S(1,NaN))
    @test !SH.structural_isequal(S(2,NaN), S(1,NaN))
    @test SH.structural_hash(S(2,NaN), UInt(0)) != SH.structural_hash(S(1,NaN), UInt(0))
    @test SH.structural_hash(S(2,NaN), UInt(0)) == SH.structural_hash(S(2,NaN), UInt(0))
    @test SH.structural_hash(S(2,NaN), UInt(0)) != SH.structural_hash(S(2,NaN), UInt(1))
end

struct WithStructTypes
    x
    y
end
SH.@batteries WithStructTypes StructTypes=true

import StructTypes as ST
@testset "StructTypes" begin
    with = WithStructTypes(1,2)
    @test ST.StructType(typeof(with)) == ST.Struct()
end

# Regression test: every Core / Base name the macro touches in its
# quoted ASTs (Type, Any, Bool, UInt, String, Symbol, AbstractString)
# is captured by interpolation at the macro's *definition site*, so a
# user module that has redefined those bindings to bogus values must
# not derail macro expansion. Use a fresh module so the redefinitions
# only live in this scope.
module ShadowedCore
    using StructHelpers
    using Test

    # Shadow every Core / Base name @batteries / @enumbatteries reach for.
    # Each one is the bogus binding (anything will do — what matters is
    # that the symbol is *not* its Core / Base meaning at macro-expansion
    # time).
    const Type = "shadowed-Type"
    const Any  = "shadowed-Any"
    const Bool = "shadowed-Bool"
    const UInt = "shadowed-UInt"
    const String          = "shadowed-String"
    const Symbol          = "shadowed-Symbol"
    const AbstractString  = "shadowed-AbstractString"
    const Integer         = "shadowed-Integer"

    # Struct decorated with the most demanding option set (all the
    # quoted ASTs reachable: hash, eq, isequal, kwshow, getproperties,
    # constructorof, kwconstructor, selfconstructor, StructTypes).
    struct Strenuous
        a::Int
        b::Int
    end
    @batteries Strenuous eq=true hash=true isequal=true kwshow=true getproperties=true constructorof=true kwconstructor=true selfconstructor=true StructTypes=true typesalt=0xdeadbeef

    # Enum decorated with both string + symbol conversion paths so the
    # convert(::Type{...}, ::AbstractString) / Symbol forms also expand.
    @enum Color RED=0 GREEN=1 BLUE=2
    @enumbatteries Color string_conversion=true symbol_conversion=true hash=true typesalt=0xc0ffee

    @testset "macro is immune to user-side Core/Base shadowing" begin
        # Struct decorations all worked.
        s = Strenuous(1, 2)
        @test StructHelpers.has_batteries(Strenuous)
        @test s == Strenuous(1, 2)
        @test isequal(s, Strenuous(1, 2))
        @test hash(s) == hash(Strenuous(1, 2))
        @test (Strenuous(; a=3, b=4)).a == 3
        @test StructHelpers.constructorof(Strenuous) === Strenuous

        # Enum decorations all worked.
        @test StructHelpers.has_batteries(Color)
        @test Base.convert(Color, "RED") === RED
        @test Color(:GREEN) === GREEN
        @test Base.convert(Base.String, BLUE) == "BLUE"
        @test Base.Symbol(RED) === :RED
    end
end
