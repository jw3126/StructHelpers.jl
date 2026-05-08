using StructHelpers: @batteries, @battery, StructHelpers, @enumbatteries, @enumbattery
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

struct WithDefaults
    a
    b
    c
end
@batteries WithDefaults kwconstructor=true kwshow=true
function SH.default_keywords(::Type{WithDefaults})
    (a = 1, b = 2)
end

struct AllDefaults
    a
    b
end
@batteries AllDefaults kwconstructor=true kwshow=true
function SH.default_keywords(::Type{AllDefaults})
    (a = 1, b = 2)
end

struct NoDefaultsKw
    a
    b
end
@batteries NoDefaultsKw kwconstructor=true kwshow=true

struct WithNaNDefault
    x
end
@batteries WithNaNDefault kwshow=true kwconstructor=true
function SH.default_keywords(::Type{WithNaNDefault})
    (x = NaN,)
end

struct CountedDefaults
    a
    b
    c
end
@batteries CountedDefaults kwconstructor=true
const COUNTED_DEFAULTS_CALLS = Ref(0)
function SH.default_keywords(::Type{CountedDefaults})
    COUNTED_DEFAULTS_CALLS[] += 1
    (a = 1, b = 2)
end

# Bare-flag sugar: `flag` ≡ `flag=true`, mixable with `flag=value`.
struct SBare; a; b; end
@batteries SBare kwconstructor kwshow hash=false

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
        # Bare symbol naming a known flag is sugar for `=true`. A bare
        # symbol that is *not* a known flag falls through to the
        # NamedTuple-config path; if it isn't bound to anything either,
        # we report "Bad argument" with the failed evaluation.
        @test_throws "Bad argument" @macroexpand @batteries SErrors nonsense
    else
        @test_throws Exception @macroexpand @batteries  SErrors kwconstructor="true"
        @test_throws Exception @macroexpand @batteries SErrors kwconstructor=true nonsense=true
        @test_throws Exception @macroexpand @batteries SErrors nonsense
    end

    @testset "bare-flag sugar" begin
        # Bare flag works as a substitute for `=true` and is freely mixable
        # with explicit `=` assignments.
        @test SBare(a=1, b=2) == SBare(1, 2)            # kwconstructor enabled
        @test sprint(show, SBare(1, 2)) == "SBare(a = 1, b = 2)"  # kwshow enabled
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

@testset "default_keywords" begin
    @test SH.default_keywords(SBatteries) === NamedTuple()
    @test SH.default_keywords(WithDefaults) === (a = 1, b = 2)

    # kwconstructor uses defaults from default_keywords
    @test WithDefaults(c = 3) === WithDefaults(1, 2, 3)
    @test WithDefaults(a = 10, c = 3) === WithDefaults(10, 2, 3)
    @test WithDefaults(a = 10, b = 20, c = 30) === WithDefaults(10, 20, 30)
    # fields without a default are still required
    @test_throws UndefKeywordError WithDefaults()
    @test_throws UndefKeywordError WithDefaults(a = 10)

    # all-defaults type can be constructed with no kwargs
    @test AllDefaults() === AllDefaults(1, 2)
    @test AllDefaults(a = 10) === AllDefaults(10, 2)

    # kwconstructor with no default_keywords overload still requires every field
    @test NoDefaultsKw(a = 1, b = 2) === NoDefaultsKw(1, 2)
    @test_throws UndefKeywordError NoDefaultsKw()
    @test_throws UndefKeywordError NoDefaultsKw(a = 1)

    # kwshow omits fields equal to their default
    @test sprint(show, WithDefaults(1, 2, 3)) == "$(WithDefaults)(c = 3)"
    @test sprint(show, WithDefaults(10, 2, 3)) == "$(WithDefaults)(a = 10, c = 3)"
    @test sprint(show, WithDefaults(10, 20, 30)) == "$(WithDefaults)(a = 10, b = 20, c = 30)"
    @test sprint(show, WithDefaults(1, 20, 3)) == "$(WithDefaults)(b = 20, c = 3)"

    # all defaults match → empty argument list
    @test sprint(show, AllDefaults(1, 2)) == "$(AllDefaults)()"
    @test sprint(show, AllDefaults(10, 2)) == "$(AllDefaults)(a = 10)"

    # without default_keywords overload, every field is shown
    @test sprint(show, NoDefaultsKw(1, 2)) == "$(NoDefaultsKw)(a = 1, b = 2)"

    # isequal semantics: isequal(NaN, NaN) is true, so the field is omitted
    @test isequal(WithNaNDefault(), WithNaNDefault(NaN))
    @test sprint(show, WithNaNDefault(NaN)) == "$(WithNaNDefault)()"
    @test sprint(show, WithNaNDefault(1.0)) == "$(WithNaNDefault)(x = 1.0)"

    # default_keywords is called exactly once per kwconstructor invocation,
    # regardless of how many kwargs the caller supplied.
    COUNTED_DEFAULTS_CALLS[] = 0
    CountedDefaults(c = 3)
    @test COUNTED_DEFAULTS_CALLS[] == 1

    COUNTED_DEFAULTS_CALLS[] = 0
    CountedDefaults(a = 10, c = 3)
    @test COUNTED_DEFAULTS_CALLS[] == 1

    COUNTED_DEFAULTS_CALLS[] = 0
    CountedDefaults(a = 10, b = 20, c = 30)
    @test COUNTED_DEFAULTS_CALLS[] == 1
end

# `@battery T ...`: opt-in variant where every default is `false`. Only
# the listed batteries are derived; nothing else.
struct BatOnlyKwconstructor; a; b; end
@battery BatOnlyKwconstructor kwconstructor

struct BatOnlyEqIsequal; a; end
@battery BatOnlyEqIsequal eq isequal

struct BatOnlyHash; a; end
@battery BatOnlyHash hash typesalt=0xabcdef0123456789

struct BatNothing; a; end
@battery BatNothing  # legal: derives only `has_batteries`

@testset "@battery" begin
    # `kwconstructor` enabled, but no `==`, `isequal`, `hash`,
    # `getproperties`, `constructorof`, `selfconstructor`.
    @test BatOnlyKwconstructor(a=1, b=2).a == 1
    # No structural ==: two structurally equal objects compare false (===),
    # but the default Julia `==` on structs (egal-by-fields for immutables)
    # may still return true. We assert the *macro* didn't define one by
    # checking that `Base.:(==)(::T,::T)` is the generic fallback method,
    # i.e. that no method was added with both args ::BatOnlyKwconstructor.
    @test !any(methods(==, (BatOnlyKwconstructor, BatOnlyKwconstructor))) do m
        m.sig === Tuple{typeof(==), BatOnlyKwconstructor, BatOnlyKwconstructor}
    end
    # No selfconstructor: outer-of-outer wraps rather than passes through.
    @test BatOnlyKwconstructor(BatOnlyKwconstructor(1, 2), 3).a isa BatOnlyKwconstructor

    # `eq` and `isequal` enabled; `hash` is NOT — verify by checking that
    # no specialized `Base.hash(::T, ::UInt)` method exists.
    @test BatOnlyEqIsequal(1) == BatOnlyEqIsequal(1)
    @test isequal(BatOnlyEqIsequal(1), BatOnlyEqIsequal(1))
    @test !any(methods(hash, (BatOnlyEqIsequal, UInt))) do m
        m.sig === Tuple{typeof(hash), BatOnlyEqIsequal, UInt}
    end

    # `hash` + `typesalt` works in subset mode without auto-enabling
    # anything else.
    h = 0x123456789abcdef0
    @test hash(BatOnlyHash(7), h) == hash((7,), hash(0xabcdef0123456789, h))

    # `@battery T` with no flags is legal (only `has_batteries` is set).
    @test StructHelpers.has_batteries(BatNothing)

    # `@battery` rejects unknown keywords just like `@batteries`.
    if VERSION >= v"1.8"
        # Bare symbol that is neither a flag nor bound to a NamedTuple
        # triggers the config-eval path and reports a "Bad argument"
        # error with the underlying UndefVarError.
        @test_throws "Bad argument" @macroexpand @battery BatNothing nonsense
        @test_throws "Bad keyword argument value" @macroexpand @battery BatNothing kwshow="true"
    end
end

# `NamedTuple`-config splatting: any macro argument that is neither a
# flag nor `name=value` is evaluated in the calling module and its
# `pairs(...)` are spliced in. Later args override earlier ones.
const config_kwshow_kwconst    = (kwshow=true, kwconstructor=true)
const config_with_typesalt     = (kwshow=true, kwconstructor=true, typesalt=0x42)
const config_no_kwconstructor  = (kwconstructor=false,)

# 1. Single config splat into `@batteries`. The defaults still apply for
#    keys not in the config; the config wins for keys it sets.
struct CfgA; a; b; end
@batteries CfgA config_kwshow_kwconst

# 2. Config + per-struct override: explicit `typesalt=...` wins over
#    whatever the config says (and over the default).
struct CfgB; a; b; end
@batteries CfgB config_with_typesalt typesalt=0x99

# 3. Two configs combined; later overrides earlier.
struct CfgC; a; b; end
@batteries CfgC config_kwshow_kwconst config_no_kwconstructor

# 4. Inline NamedTuple literal (no const required).
struct CfgD; a; b; end
@batteries CfgD (kwshow=true, kwconstructor=true)

# 5. `@battery` (opt-in form) plus a config: only the config's batteries
#    are derived, nothing else.
struct CfgE; a; b; end
@battery CfgE config_kwshow_kwconst

# 6. `@battery` plus a config plus a bare-flag override.
struct CfgF; a; end
@battery CfgF config_kwshow_kwconst eq

@testset "NamedTuple config splat" begin
    # The behavior of every individual flag (kwshow, kwconstructor, ==,
    # isequal, hash, typesalt, ...) is already exercised exhaustively
    # by the @batteries / @battery testsets above. The job of *this*
    # testset is to verify that the splatting machinery sets exactly
    # the flags the user asked for and nothing else, regardless of
    # whether they came from a const config, an inline NamedTuple
    # literal, multiple configs, or a config + override.
    has_method(f, sig) = any(m -> m.sig === Tuple{typeof(f), sig...}, methods(f, sig))

    # 1. `@batteries` + config: config-set flags ON, untouched flags
    #    keep their (mostly-on) defaults.
    @test  has_method(==,      (CfgA, CfgA))   # default
    @test  has_method(isequal, (CfgA, CfgA))   # default
    @test  has_method(hash,    (CfgA, UInt))   # default

    # 2. Per-struct override wins over the config it follows. typesalt
    #    is the only flag whose value can be observed without method
    #    introspection, hence the explicit hash check.
    h = UInt(0)
    @test hash(CfgB(7, 8), h) === hash((7, 8), hash(0x99, h))
    @test hash(CfgB(7, 8), h) !== hash((7, 8), hash(0x42, h))

    # 3. Two-config last-write-wins: the second config's
    #    `kwconstructor=false` undoes the first config's `=true`.
    @test_throws MethodError CfgC(a=1, b=2)

    # 4. Inline NamedTuple literal: same effect as a const config.
    @test has_method(==, (CfgD, CfgD))
    @test CfgD(a=1, b=2) === CfgD(1, 2)        # kwconstructor reached us

    # 5. `@battery` + config: only the config's flags are set; defaults
    #    are NOT pulled in (this is what distinguishes the two macros).
    @test !has_method(==,      (CfgE, CfgE))
    @test !has_method(isequal, (CfgE, CfgE))
    @test !has_method(hash,    (CfgE, UInt))

    # 6. `@battery` + config + bare-flag override: bare `eq` adds `==`
    #    on top of the config; isequal/hash still absent.
    @test  has_method(==,      (CfgF, CfgF))
    @test !has_method(isequal, (CfgF, CfgF))
    @test !has_method(hash,    (CfgF, UInt))

    @testset "errors" begin
        if VERSION >= v"1.8"
            # Bare symbol that's neither a flag nor a binding.
            @test_throws "Bad argument" @macroexpand @batteries CfgA undefined_config
            # Bound but not a NamedTuple.
            global not_a_namedtuple = 42
            @test_throws "Bad argument" @macroexpand(@batteries CfgA not_a_namedtuple)
            # Inline non-NamedTuple expression.
            @test_throws "Bad argument" @macroexpand @batteries CfgA 1 + 2
        end
    end
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

# `@enumbattery T ...`: opt-in variant of `@enumbatteries`.
@enum ECol1 ECol1A ECol1B
@enumbattery ECol1 symbol_conversion

@enum ECol2 ECol2A=4 ECol2B=5
@enumbattery ECol2 hash typesalt=0xfedcba9876543210

@enum ECol3 ECol3A ECol3B
@enumbattery ECol3  # legal: only the always-on enum_from_*/from_enum methods + has_batteries

@testset "@enumbattery" begin
    # symbol_conversion enabled, string_conversion not.
    @test ECol1(:ECol1A) === ECol1A
    @test Symbol(ECol1A) === :ECol1A
    @test_throws Exception ECol1("ECol1A")          # string_conversion off
    # selfconstructor off too: ECol1(::ECol1) is not defined.
    @test_throws Exception ECol1(ECol1A)

    # hash + typesalt works without auto-enabling anything else.
    h = 0x55aa55aa55aa55aa
    @test hash(ECol2A, h) == hash(4, hash(0xfedcba9876543210, h))

    # Empty `@enumbattery` is legal; the always-on methods are there.
    @test StructHelpers.has_batteries(ECol3)
    @test StructHelpers.string_from_enum(ECol3A) == "ECol3A"
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

    # Shadow every Core / Base name `@batteries` / `@enumbatteries`
    # reach for. Most of these are bogus String constants — what
    # matters is that the symbol is *not* its Core / Base meaning at
    # macro-expansion time. `Base` and `Core` themselves are shadowed
    # by user-defined empty structs, which is the most aggressive case
    # (any `Base.foo` / `Core.foo` reference in a quoted AST that
    # `esc`s into this module would now hit our struct, not the
    # standard library module).
    struct Base end
    struct Core end
    const Type = "shadowed-Type"
    const Any  = "shadowed-Any"
    const Bool = "shadowed-Bool"
    const UInt = "shadowed-UInt"
    const String          = "shadowed-String"
    const Symbol          = "shadowed-Symbol"
    const AbstractString  = "shadowed-AbstractString"
    const Integer         = "shadowed-Integer"
    const IO              = "shadowed-IO"

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

        # Enum decorations all worked. Note: `Base` is itself
        # shadowed inside this module, so we call generic functions by
        # the unqualified names (which Julia's implicit `using Base`
        # has imported into scope independently of the `Base` binding
        # we redefined). The shadowing test is exactly that those
        # bare names don't go through `Base.X` lookup at the call
        # site of the macro-emitted methods.
        @test StructHelpers.has_batteries(Color)
        @test convert(Color, "RED") === RED
        @test Color(:GREEN) === GREEN
        @test convert(Main.Base.String, BLUE) == "BLUE"
        @test Main.Base.Symbol(RED) === :RED
    end
end
