# Tests for the `showrepr` battery (heuristic short `Base.show` that
# round-trips through the type's constructor). The struct definitions
# below are mostly minimal fixtures designed to exercise one aspect of
# the algorithm; they are wedged in next to the testset that uses them
# so it stays easy to see what is being probed.
#
# This file is `include`d from `runtests.jl` at the appropriate point;
# it shares `runtests.jl`'s `Main`-level scope (so e.g. `StructHelpers`,
# `SH`, `Test`, and `StaticArrays` must already be in scope).

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
    # On Julia 1.6, `constructorof(SVector{N,T}) === SArray` and
    # `SArray(args...)` throws `DimensionMismatch`. `compact` then falls
    # back to a bracket literal, which the field's `convert` accepts —
    # round-trip works on all versions, but the printed name differs, so
    # the string-shape assertions below are gated on Julia >= 1.7.
    if VERSION >= v"1.7"
        # Uniform → splat into the static constructor.
        @test sprint(show, SStaticVecField(SVector(ntuple(_->0, Val(16))...))) ==
              "SStaticVecField(SVector(fill(0, 16)...))"
        # Mixed leading element + uniform tail.
        @test sprint(show, SStaticVecField(SVector(ntuple(i->i==1 ? 7 : 0, Val(16))...))) ==
              "SStaticVecField(SVector(7, fill(0, 15)...))"
    end
    # Round-trip the compressed forms (works on all versions).
    for v in (SVector(ntuple(_->0, Val(16))...),
              SVector(ntuple(i->i==1 ? 7 : 0, Val(16))...))
        o = SStaticVecField(v)
        @test eval(Meta.parse(sprint(show, o))) == o
    end
    # When the bracket literal is genuinely shorter than the wrapped form
    # (small array, small elements), `compact` rejects the wrapping and
    # falls back to plain `show` — the field's `convert` still accepts a
    # `Vector`, so this round-trips even though no `SVector(...)` appears.
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
