using StructHelpers: @batteries, @battery, StructHelpers, @enumbatteries, @enumbattery
const SH = StructHelpers
using Test
using Aqua
using StaticArrays

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
    @test s == "Skw(a = 1, b = 2)"

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

# 7. Multiple disjoint configs combined with a per-struct override.
const cfg_part_kwshow         = (kwshow=true,)
const cfg_part_kwconstructor  = (kwconstructor=true,)
const cfg_part_typesalt       = (typesalt=0x42,)
struct CfgG; a; b; end
@batteries CfgG cfg_part_kwshow cfg_part_kwconstructor cfg_part_typesalt typesalt=0x99

# Forward-compatibility regression test: a bare symbol that names *both*
# a flag *and* a NamedTuple binding in the calling module must resolve
# to the binding (so future flag additions cannot silently shadow user
# configs sharing the new flag's name). `kwconstructor` is an existing
# flag; the binding below maps it to a NamedTuple that turns on
# `kwshow` instead — proving the binding won and the flag did not.
const kwconstructor = (kwshow = true,)
struct CfgShadow; a; end
@battery CfgShadow kwconstructor
struct CfgExplicit; a; end
@battery CfgExplicit kwconstructor = true

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

    # 7. Multiple disjoint configs + per-struct override. All three
    #    config NamedTuples are spliced in; the explicit `typesalt`
    #    overrides the one set by `cfg_part_typesalt`. Because this is
    #    `@batteries` (not `@battery`), the defaults still apply for
    #    keys none of the configs touched.
    @test CfgG(a=1, b=2) === CfgG(1, 2)
    @test sprint(show, CfgG(1, 2)) == "CfgG(a = 1, b = 2)"
    let h = UInt(0)
        # typesalt from explicit override, not from cfg_part_typesalt.
        @test hash(CfgG(7, 8), h) === hash((7, 8), hash(0x99, h))
        @test hash(CfgG(7, 8), h) !== hash((7, 8), hash(0x42, h))
    end
    # Defaults untouched by any of the three configs are still on:
    @test  has_method(==, (CfgG, CfgG))
    @test  has_method(isequal, (CfgG, CfgG))
    @test  has_method(hash, (CfgG, UInt))
    # And the methods actually defined by the configs are there:
    @test  has_method(show, (IO, CfgG))
    @test  hasmethod(CfgG, Tuple{}, (:a, :b))

    @testset "errors" begin
        if VERSION >= v"1.8"
            # Bare symbol that's neither a flag nor a binding.
            @test_throws "Bad argument" @macroexpand @batteries CfgA undefined_config
            # Bound but not a NamedTuple, and not a flag name either.
            global not_a_namedtuple = 42
            @test_throws "Bad argument" @macroexpand(@batteries CfgA not_a_namedtuple)
            # Inline non-NamedTuple expression.
            @test_throws "Bad argument" @macroexpand @batteries CfgA 1 + 2
        end
    end

    @testset "binding wins over flag name" begin
        # Forward-compatibility guarantee: when a bare symbol names
        # *both* a flag *and* a NamedTuple binding in the calling
        # module, the binding wins. This means StructHelpers can add
        # new flags in the future without silently shadowing a user's
        # const config that happens to share the new flag's name; the
        # user only needs to rename the binding (or spell the flag
        # explicitly as `flag = true`) to opt into the new flag.
        @test :kwconstructor in StructHelpers.BATTERIES_ALLOWED_KW
        # The NamedTuple binding was splatted ⇒ kwshow is on.
        @test sprint(show, CfgShadow(1)) == "CfgShadow(a = 1)"
        # The flag interpretation was *not* taken ⇒ no kw constructor.
        @test_throws MethodError CfgShadow(a = 1)
        # The explicit form still reaches the flag.
        @test CfgExplicit(a = 1).a == 1
    end
end

Base.@kwdef struct SDefaults
    a = 1
    b = 2
    c = 3
end
@batteries SDefaults showrepr=true

Base.@kwdef struct SDefaultsKw
    a = 1
    b = 2
end
@batteries SDefaultsKw showrepr=true

struct SExtraCtor
    a
    b
end
SExtraCtor(a) = SExtraCtor(a, 2)
SExtraCtor() = SExtraCtor(1, 2)
@batteries SExtraCtor showrepr=true

Base.@kwdef struct SMissingDefault
    a = missing
    b = 1
end
@batteries SMissingDefault showrepr=true

struct SNaNCtor
    x::Float64
end
SNaNCtor() = SNaNCtor(NaN)
@batteries SNaNCtor showrepr=true

struct SHybrid
    a
    b
    c
end
SHybrid(a, b; c=3) = SHybrid(a, b, c)
@batteries SHybrid showrepr=true

@testset "showrepr shortest representation" begin
    # All defaults: empty constructor wins.
    @test sprint(show, SDefaults()) == "SDefaults()"
    # One non-default: only that field is shown.
    @test sprint(show, SDefaults(b=10)) == "SDefaults(b = 10)"
    # Last non-default with defaults preceding it.
    @test sprint(show, SDefaults(c=30)) == "SDefaults(c = 30)"
    # Multiple non-defaults: round-trip plus a sanity length bound. We do
    # not pin the exact rendering — the algorithm may pick the kwarg or
    # positional form depending on tie-breaking — but it must be no
    # longer than the naive all-positional form.
    s = sprint(show, SDefaults(a=10, c=30))
    @test SDefaults(a=10, c=30) == eval(Meta.parse(s))
    @test length(s) <= length("SDefaults(10, 2, 30)")
    # All non-default.
    s = sprint(show, SDefaults(a=10, b=20, c=30))
    @test SDefaults(a=10, b=20, c=30) == eval(Meta.parse(s))

    # `Base.@kwdef` synthesizes a kwconstructor that `showrepr` picks up
    # without `kwconstructor=true` being passed to `@batteries`.
    @test sprint(show, SDefaultsKw()) == "SDefaultsKw()"
    s = sprint(show, SDefaultsKw(b=10))
    @test SDefaultsKw(b=10) == eval(Meta.parse(s))
    @test length(s) <= length("SDefaultsKw(1, 10)")

    # When extra positional constructors exist, the shortest one wins
    # over the keyword form.
    @test sprint(show, SExtraCtor(1, 2)) == "SExtraCtor()"
    @test sprint(show, SExtraCtor(7, 2)) == "SExtraCtor(7)"
    @test sprint(show, SExtraCtor(7, 8)) == "SExtraCtor(7, 8)"

    # `missing` as a default value is handled correctly: a value of
    # `missing` matches the default (via `isequal`), while non-`missing`
    # values do not.
    @test sprint(show, SMissingDefault()) == "SMissingDefault()"
    @test sprint(show, SMissingDefault(a=missing, b=2)) == "SMissingDefault(b = 2)"
    s = sprint(show, SMissingDefault(a=42, b=1))
    @test SMissingDefault(a=42, b=1) == eval(Meta.parse(s)) ||
          isequal(SMissingDefault(a=42, b=1), eval(Meta.parse(s)))

    # `NaN` field values are recognized as recreated even though
    # `NaN == NaN` is `false`.
    @test sprint(show, SNaNCtor(NaN)) == "SNaNCtor()"

    # Hybrid constructor `SHybrid(a, b; c=3)`: when `c == 3`, the kwarg
    # is dropped and the 2-arg form wins. When `c` differs, the 3-arg
    # positional inner constructor happens to be shorter than the kwarg
    # form, so it wins. Either way the rendering recreates the object.
    @test sprint(show, SHybrid(1, 2, 3)) == "SHybrid(1, 2)"
    s = sprint(show, SHybrid(1, 2, 9))
    @test SHybrid(1, 2, 9) == eval(Meta.parse(s))
    @test length(s) <= length("SHybrid(1, 2, c = 9)")
end

# Unsigned fields render shorter as signed decimals when the constructor
# accepts the substitution (here: typed fields convert from `Int`).
struct SUnsigned
    a::UInt8
    b::UInt64
end
@batteries SUnsigned showrepr=true

@testset "showrepr unsigned shortening" begin
    @test sprint(show, SUnsigned(0x07, UInt64(42))) == "SUnsigned(7, 42)"
    s = sprint(show, SUnsigned(0xff, UInt64(99)))
    @test eval(Meta.parse(s)) == SUnsigned(0xff, UInt64(99))
end

# `simple` prefers `Int` over wider signed types whenever the value
# fits, so the substitute matches what a user would normally write. The
# check is value-based, not type-based: `UInt64(42)` becomes `Int(42)`,
# but `typemax(UInt64)` (which does not fit in `Int`) falls back to the
# next-widest signed type.
struct SInt128Field
    x::Int128
    y::UInt64
end
@batteries SInt128Field showrepr=true

@testset "showrepr prefers Int over wider integer types" begin
    @test StructHelpers.simple(UInt8(7)) === Int(7)
    @test StructHelpers.simple(UInt16(42)) === Int(42)
    @test StructHelpers.simple(UInt32(0)) === Int(0)
    @test StructHelpers.simple(UInt64(99)) === Int(99)
    @test StructHelpers.simple(Int128(42)) === Int(42)
    @test StructHelpers.simple(big(42)) === Int(42)
    # Out-of-`Int`-range unsigned: still falls back to a widened signed type.
    @test StructHelpers.simple(typemax(UInt64)) isa Int128
    # Numeric forms collapse via the universal `Int(v)` path.
    @test StructHelpers.simple(2 + 0im) === Int(2)
    @test StructHelpers.simple(2//1) === Int(2)
    @test StructHelpers.simple(2.0) === Int(2)
    # `Rational`/`Complex` wrappers around an out-of-`Int`-range value still
    # drop the wrapper by recursing through `simple` on the inner numerator
    # / real part (which itself collapses to a widened signed type).
    @test StructHelpers.simple(Complex(typemax(UInt64))) isa Int128
    @test StructHelpers.simple(typemax(UInt64) // 1) isa Int128
    # `-0.0` must preserve its sign bit (would silently become `0` under `Int`).
    @test StructHelpers.simple(-0.0) === nothing
    # Non-numeric values still return `nothing`.
    @test StructHelpers.simple("foo") === nothing
    # `Number` subtypes that don't define an `Int` conversion (the call
    # throws `MethodError` rather than `InexactError`) are tolerated and
    # fall through to `nothing` rather than propagating the error. This
    # is what allows `simple` to be safely called on user-defined
    # numeric wrappers like `Unitful.Quantity`.
    struct UnConvertibleNum <: Number end
    @test StructHelpers.simple(UnConvertibleNum()) === nothing
end

# Whole-valued floats render as integer literals when the constructor
# accepts them; non-integer, non-finite, and `-0.0` values are left alone.
struct SFloatFields
    x::Float64
    y::Float64
end
@batteries SFloatFields showrepr=true

@testset "showrepr float shortening" begin
    @test sprint(show, SFloatFields(2.0, 3.0)) == "SFloatFields(2, 3)"
    @test sprint(show, SFloatFields(2.5, 3.0)) == "SFloatFields(2.5, 3)"
    @test sprint(show, SFloatFields(Inf, 1.0)) == "SFloatFields(Inf, 1)"
    # `NaN` is non-finite and must not be shortened to an integer.
    s = sprint(show, SFloatFields(NaN, 2.0))
    @test occursin("NaN", s)
    @test isequal(eval(Meta.parse(s)), SFloatFields(NaN, 2.0))
    # -0.0 must round-trip exactly under isequal (the user may rely on the sign bit).
    s = sprint(show, SFloatFields(-0.0, 1.0))
    @test occursin("-0.0", s)
    @test isequal(eval(Meta.parse(s)), SFloatFields(-0.0, 1.0))
end

# Rationals with denominator 1 render as bare integers when the constructor
# accepts them; non-unit denominators are left alone.
struct SRatFields
    a::Rational{Int}
    b::Rational{Int}
end
@batteries SRatFields showrepr=true

@testset "showrepr rational shortening" begin
    @test sprint(show, SRatFields(2//1, 3//4)) == "SRatFields(2, 3//4)"
    @test sprint(show, SRatFields(0//1, 5//1)) == "SRatFields(0, 5)"
    s = sprint(show, SRatFields(7//1, -2//3))
    @test eval(Meta.parse(s)) == SRatFields(7//1, -2//3)
end

# Complex numbers with zero imaginary part render as bare reals when the
# constructor accepts them; non-zero imaginary parts are left alone.
struct SCplxFields
    a::Complex{Int}
    b::Complex{Int}
end
@batteries SCplxFields showrepr=true

@testset "showrepr complex shortening" begin
    @test sprint(show, SCplxFields(2 + 0im, 3 + 4im)) == "SCplxFields(2, 3 + 4im)"
    @test sprint(show, SCplxFields(0 + 0im, 1 + 0im)) == "SCplxFields(0, 1)"
    s = sprint(show, SCplxFields(7 + 0im, -2 + 5im))
    @test eval(Meta.parse(s)) == SCplxFields(7 + 0im, -2 + 5im)
end

# Uniform `AbstractVector` fields render as `fill(v, n)` (for `isbits`
# elements) or `[v for _ = 1:n]` (for non-`isbits`, to avoid aliasing)
# when shorter than the literal AND when the constructor accepts the
# substitute. The substitute is a `Vector{eltype(v)}`, so strictly-typed
# fields (e.g. an `NTuple`-only constructor) fall back to the default
# `repr`.
struct SVecField
    a::Vector{Int}
    b::Vector{Float64}
end
@batteries SVecField showrepr=true

Base.@kwdef struct SVecFieldKwDefaults
    a::Vector{Int} = [0, 0, 0, 0, 0]
    b::Vector{Int} = [1, 2, 3]
end
@batteries SVecFieldKwDefaults showrepr=true

# A struct whose constructor strictly types the field. The `fill`
# substitute is a `Vector`, which the `NTuple`-only constructor rejects,
# so the literal rendering is preserved.
struct STupleField
    a::NTuple{3,Int}
end
@batteries STupleField showrepr=true

@testset "showrepr vector fill compression" begin
    # Long uniform vector → `fill(...)` is shorter than the literal.
    @test sprint(show, SVecField([1,1,1,1,1], [2.0,3.0])) ==
          "SVecField(fill(1, 5), [2.0, 3.0])"
    # Both fields uniform.
    @test sprint(show, SVecField([7,7,7,7], [0.0,0.0,0.0,0.0])) ==
          "SVecField(fill(7, 4), fill(0.0, 4))"
    # Short uniform vector ([1,1,1] vs fill(1,3)) → literal already
    # shorter, no compression.
    @test sprint(show, SVecField([1,1,1], [1.0])) ==
          "SVecField([1, 1, 1], [1.0])"
    # Non-uniform → no compression.
    @test sprint(show, SVecField([1,2,3,4,5], [0.0,0.0,0.0,0.0])) ==
          "SVecField([1, 2, 3, 4, 5], fill(0.0, 4))"
    # Empty / single element → no compression.
    @test sprint(show, SVecField(Int[], [3.0])) ==
          "SVecField(Int64[], [3.0])"
    # Round-trip every case: parsing the rendering must produce a value
    # equal to the original under `repr_eq`.
    for (a, b) in ((Int[1,1,1,1,1], Float64[2.0,3.0]),
                   (Int[7,7,7,7], Float64[0.0,0.0,0.0,0.0]),
                   (Int[1,1,1], Float64[1.0]),
                   (Int[1,2,3,4,5], Float64[0.0,0.0,0.0,0.0]))
        o = SVecField(a, b)
        s = sprint(show, o)
        @test eval(Meta.parse(s)) == o
    end

    # Default-omission still works when the kwarg's default also gets
    # compressed: `SVecFieldKwDefaults()` has both defaults so renders
    # without arguments.
    @test sprint(show, SVecFieldKwDefaults()) == "SVecFieldKwDefaults()"
    # Overriding `a` with another long uniform vector still uses `fill`.
    @test sprint(show, SVecFieldKwDefaults(a=[9,9,9,9,9,9])) ==
          "SVecFieldKwDefaults(a = fill(9, 6))"

    # Strictly-typed field (NTuple) won't accept a `Vector` substitute,
    # so the default rendering is preserved.
    @test sprint(show, STupleField((5,5,5))) == "STupleField((5, 5, 5))"

    # Run-length compression with a heterogeneous vector: the long zero
    # run is splatted while distinct elements stay literal.
    @test sprint(show, SVecField([1,17,0,0,0,0,0,0,0,0], [1.0])) ==
          "SVecField([1, 17, fill(0, 8)...], [1.0])"
    let o = SVecField([1,17,0,0,0,0,0,0,0,0], [1.0])
        @test eval(Meta.parse(sprint(show, o))) == o
    end
    # Multiple long runs are each splatted.
    @test sprint(show, SVecField([1,1,1,1,1,1,2,2,2,2,2,2], [1.0])) ==
          "SVecField([fill(1, 6)..., fill(2, 6)...], [1.0])"
    # Short runs aren't worth splatting → falls back to plain literal.
    @test sprint(show, SVecField([1,17,0,0,0], [1.0])) ==
          "SVecField([1, 17, 0, 0, 0], [1.0])"
end

# Fields whose concrete type's `constructorof` accepts positional varargs
# (e.g. `SVector`, `MVector`) render as `Tc(elems...)` so the printed form
# round-trips back to that concrete type. Note: `constructorof(SVector{N,T})`
# is `SVector` (without the size parameter), so the printed form drops the
# static size — round-trip recovers it via type inference from the arg count.
struct SStaticVecField
    v::SVector{16, Int}
end
@batteries SStaticVecField showrepr=true

@testset "showrepr static-vector fill compression" begin
    # Uniform → splat into the static constructor.
    @test sprint(show, SStaticVecField(SVector(ntuple(_->0, Val(16))...))) ==
          "SStaticVecField(SVector(fill(0, 16)...))"
    # Mixed leading element + uniform tail.
    @test sprint(show, SStaticVecField(SVector(ntuple(i->i==1 ? 7 : 0, Val(16))...))) ==
          "SStaticVecField(SVector(7, fill(0, 15)...))"
    # Round-trip the compressed forms.
    for v in (SVector(ntuple(_->0, Val(16))...),
              SVector(ntuple(i->i==1 ? 7 : 0, Val(16))...))
        o = SStaticVecField(v)
        @test eval(Meta.parse(sprint(show, o))) == o
    end
    # When the bracket literal is genuinely shorter than the wrapped form
    # (small array, small elements), `compact` rejects the wrapping and
    # falls back to plain `show` — the field type still coerces, so this
    # round-trips even though no `SVector(...)` appears.
    @test sprint(show, SStaticVecField(SVector(1, 2, 3, 4, 5, 6, 7, 8,
                                                9,10,11,12,13,14,15,16))) ==
          "SStaticVecField([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])"
end

# Mutable element types: re-evaluating the comprehension must produce
# distinct instances (no aliasing). This is the reason `compact`
# uses a comprehension rather than `fill`.
mutable struct MutCell
    x::Int
end
Base.:(==)(a::MutCell, b::MutCell) = a.x == b.x
Base.show(io::IO, c::MutCell) = print(io, "MutCell(", c.x, ")")

struct SMutVec
    cells::Vector{MutCell}
end
@batteries SMutVec showrepr=true

@testset "showrepr vector comprehension preserves distinct instances" begin
    o = SMutVec([MutCell(7), MutCell(7), MutCell(7), MutCell(7), MutCell(7)])
    s = sprint(show, o)
    @test s == "SMutVec([MutCell(7) for _ = 1:5])"
    o2 = eval(Meta.parse(s))
    @test o2.cells[1] !== o2.cells[2]   # distinct instances, no aliasing
    @test o2.cells == o.cells
end

# `kwshow` and `showrepr` both target `Base.show` and are mutually exclusive.
struct SBothShow; a; end
@testset "showrepr/kwshow mutual exclusion" begin
    if VERSION >= v"1.8"
        @test_throws "mutually exclusive" @macroexpand @batteries SBothShow kwshow=true showrepr=true
    else
        @test_throws Exception @macroexpand @batteries SBothShow kwshow=true showrepr=true
    end
end

# When no constructor recreates the object, `showrepr` falls back to a
# named-tuple-style rendering. We trigger this with a struct whose only
# user-defined constructor unconditionally errors and which has a single
# typed field so that the auto-generated inner constructor also fails on
# the held value (we install one via `Core.setfield!` on a mutable proxy).
mutable struct SFallback
    a::Int
    SFallback() = error("rejected")
end
let s = ccall(:jl_new_struct_uninit, Any, (Any,), SFallback)::SFallback
    s.a = 7
    global _sfallback_inst = s
end
@batteries SFallback showrepr=true selfconstructor=false eq=false isequal=false hash=false

@testset "showrepr fallback when no constructor recreates" begin
    s = sprint(show, _sfallback_inst)
    @test occursin("SFallback", s)
    @test occursin("a", s) && occursin("7", s)
end

# `mutable struct` whose `==` defaults to `===`: a fresh reconstruction is
# never `==` to the original, so without field-level comparison every
# constructor candidate (and every default-elision attempt) would be
# rejected. Verify defaults still get elided here.
Base.@kwdef mutable struct SMutNoEq
    a::Int = 0
    b::Int = 0
end
@batteries SMutNoEq showrepr=true eq=false isequal=false hash=false

@testset "showrepr handles mutable structs without ==" begin
    @test sprint(show, SMutNoEq())             == "SMutNoEq()"
    @test sprint(show, SMutNoEq(b = 7))        == "SMutNoEq(0, 7)"
    @test sprint(show, SMutNoEq(a = 1, b = 2)) == "SMutNoEq(1, 2)"
end

# Vararg constructors must be skipped (we don't know how many fields to splat).
struct SVararg
    a
    b
end
SVararg(args...) = SVararg(args[1], args[2])
@batteries SVararg showrepr=true

@testset "showrepr skips vararg constructors" begin
    s = sprint(show, SVararg(1, 2))
    @test SVararg(1, 2) == eval(Meta.parse(s))
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

@testset "Aqua" begin
    Aqua.test_all(StructHelpers)
end

@testset "JET" begin
    using JET
    result = JET.report_package(StructHelpers)
    @test isempty(JET.get_reports(result))
end
