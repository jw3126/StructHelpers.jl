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
    
    @test_throws "Bad keyword argument value:" @macroexpand @batteries  SErrors kwconstructor="true"
    @test_throws "Unsupported keyword" @macroexpand @batteries SErrors kwconstructor=true nonsense=true
    @test_throws "Expected a keyword argument of the form name = value" @macroexpand @batteries SErrors nonsense
    

    @testset "typesalt" begin
        @test hash(Salt1()) === hash(Salt1b())
        @test hash(Salt1()) != hash(NoSalt())
        @test hash(Salt1()) != hash(Salt2())

        # persistence
        @test hash(Salt1())  === 0xd39a1e58a7b0c35e
        @test hash(Salt1b()) === 0xd39a1e58a7b0c35e
        @test hash(Salt2())  === 0x2f64a52e5f45d104

        @test hash(SaltABC(1  , 2  , 3 )) === 0x92290cfd972fe54d
        @test hash(SaltABC(10 , 2  , 3 )) === 0xcc48b9e98b6f3ef4
        @test hash(SaltABC(10 , 20 , 3 )) === 0x6f8c614051f68ec7
        @test hash(SaltABC(10 , 20 , 30)) === 0x90cb2b9a94741e53
    end

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
    @test hash(HashEqAsTS1(identity, 1)) === 0x486b072c90d60e64
    @test hash(HashEqAsTS2(x->5x, 1)) === 0xa4360acf486c15a4
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
