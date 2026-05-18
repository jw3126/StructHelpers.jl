# Implementation of the `showrepr` battery: a heuristically short
# `Base.show` that round-trips through the constructor(s) of the type.
# The `showrepr=true` flag of `@batteries` / `@battery` (parsed in
# `StructHelpers.jl`) emits `Base.show(io, ::T) = showrepr(io, o)`,
# which dispatches into the code here.
#
# Everything in this file is `StructHelpers`-internal except for the two
# documented entry points `showrepr` and `constructor_repr`, plus the
# `repr_eq` predicate that is exposed because it is referenced in
# user-facing docstrings.

"""
    showrepr(io::IO, o)

Show `o` using a heuristically short string representation that recreates `o`,
chosen among the constructors of `typeof(o)`. Equality with a candidate
reconstruction is checked via [`repr_eq`](@ref).

Trailing fields whose values match a default — be it from a positional default
(`T(a, b=2) = ...`) or a keyword constructor (e.g. via `Base.@kwdef`) — are
omitted. The result is not guaranteed to be globally shortest; see
[`constructor_repr`](@ref) for the search strategy.
"""
function showrepr(io::IO, o)
    print(io, constructor_repr(o))
end

# Invoke `T(pos...; kws...)` with `@nospecialize`d `T`. Inference resolves
# the call against abstract `::Type` rather than a concrete `Type{X}`, so
# JET (e.g. `report_package` on a downstream package) does not flag
# `Core.kwcall` as missing for types `X` whose constructors take no kwargs
# — those calls are guarded at runtime by the surrounding `try/catch`.
function invoke_ctor(@nospecialize(T::Type), pos_vals::Vector{Any}, kw_pairs)
    T(pos_vals...; kw_pairs...)
end

"""
    constructor_repr(o)::String

Return a short string of the form `T(...)` that, when parsed and evaluated,
recreates `o` (according to [`repr_eq`](@ref)).

All constructors of `T = typeof(o)` are considered — positional, keyword,
and mixed — and trailing fields whose values match a default are omitted.
If no constructor recreates `o`, falls back to a non-executable
`T(field = value, ...)` rendering.

The result is heuristic and not guaranteed to be the globally shortest valid
representation: for each constructor a single greedy pass eliminates kwargs
whose defaults match, then a greedy pass substitutes shorter literal forms
for individual fields (e.g. unsigned hex → decimal, whole-valued floats →
integers, `2//1` → `2`, `2 + 0im` → `2`). The shortest candidate produced
this way is returned.
"""
function constructor_repr(o)
    T = typeof(o)
    fnames = fieldnames(T)
    nf = length(fnames)
    # Compare reconstructions to `o` by fields rather than via `o ==`. That
    # way mutable structs without an explicit `==` (whose default `==` is
    # `===`) still recognize a fresh reconstruction as equivalent. Going
    # through `repr_eq` on the `NamedTuple` retains tolerance for `NaN`
    # leaves and constructors that normalize `-0.0`/`0.0`.
    matches(x) = repr_eq(getproperties(x), getproperties(o))

    candidates = String[]
    seen_strings = Set{String}()

    # Probe every method of `T`. For each `m` we try
    #
    #     T(o.f1, ..., o.fnp; k1 = o.k1, ..., kn = o.kn)
    #
    # where `np` is `m`'s positional arity and `k1..kn` are the kwargs
    # declared by `m` that share a name with a field. Positional defaults
    # (`T(a, b=2)`) show up as separate methods with smaller `np`;
    # `Base.@kwdef` contributes both a positional and a keyword form. We
    # then greedily drop each kwarg whose default already matches `o`.
    for m in methods(T)
        # Vararg constructors (`T(args...)`): unclear how many fields to splat.
        m.isva && continue
        # `m.nargs` includes the `Type{T}` slot.
        np = m.nargs - 1
        np > nf && continue
        # `Base.kwarg_decl` is internal, but the only known way to
        # introspect a method's kwargs.
        kws = Base.kwarg_decl(m)
        # Explicit filter rather than `kws ∩ fnames`: for `Tuple` types
        # `fieldnames(T)` returns integers, which makes `∩` dispatch to a
        # JET-unstable path. The filter has a uniform `Vector{Symbol}`
        # return type.
        relevant_kws = Symbol[k for k in kws if k in fnames]

        # `keep_kws` is only ever rebound, so the alias is safe (no `copy`).
        keep_kws = relevant_kws

        # Mutable so the literal-shortening pass below can write into it.
        pos_vals = Any[getfield(o, i) for i in 1:np]

        # `T(...)` may legitimately throw (custom invariants, type errors,
        # ...); treat any such candidate as a non-match. Routed through
        # `invoke_ctor` so JET stays clean on types without a kwarg ctor.
        recreates(kws) = try
            matches(invoke_ctor(T, pos_vals, (k => getfield(o, k) for k in kws)))
        catch
            false
        end

        recreates(keep_kws) || continue

        # Drop each kwarg whose default already matches. Independent per
        # kwarg, so a single forward pass suffices.
        for k in relevant_kws
            trial = filter(!isequal(k), keep_kws)
            recreates(trial) && (keep_kws = trial)
        end

        # Try to substitute each field with a shorter literal (see `simple`),
        # accepting only when `T(...)` still recreates `o`.
        kw_vals = Dict{Symbol,Any}(k => getfield(o, k) for k in keep_kws)
        trycall() = try
            matches(invoke_ctor(T, pos_vals, (k => kw_vals[k] for k in keep_kws)))
        catch
            false
        end
        for i in 1:np;     simplify!(pos_vals, i, trycall); end
        for k in keep_kws; simplify!(kw_vals,  k, trycall); end

        # Format `T(pos...; kws...)`. For each field try `compactify!` first
        # (e.g. uniform `Vector` → `fill(v, n)`), then fall back to `show`.
        buf = IOBuffer()
        print(buf, T, "(")
        sep = false
        for i in 1:np
            sep && print(buf, ", "); sep = true
            s = compactify!(pos_vals, i, trycall)
            s === nothing ? show(buf, pos_vals[i]) : print(buf, s)
        end
        for k in keep_kws
            sep && print(buf, ", "); sep = true
            print(buf, k, " = ")
            s = compactify!(kw_vals, k, trycall)
            s === nothing ? show(buf, kw_vals[k]) : print(buf, s)
        end
        print(buf, ")")
        # Dedup identical forms from different methods (e.g. `Base.@kwdef`'s
        # positional + keyword constructors on a fully-default object).
        s = String(take!(buf))
        if s ∉ seen_strings
            push!(seen_strings, s)
            push!(candidates, s)
        end
    end

    # No constructor recreated `o` (mutating, context-dependent, or rejects
    # the field values). Fall back to a named-tuple rendering — informative
    # but not directly executable.
    if isempty(candidates)
        buf = IOBuffer()
        print(buf, T)
        show(buf, getproperties(o))
        return String(take!(buf))
    end
    return candidates[argmin(map(length, candidates))]
end

"""
    repr_eq(a, b)::Bool

Test whether `a` and `b` are equal in a sense suitable for checking that a
candidate constructor call recreates an object faithfully enough for
`show`/`repr` round-tripping.

Returns `true` iff `a == b` (resolving to `true`) **or** `isequal(a, b)`.

Both predicates are used because each one alone would reject legitimate
reconstructions:

* `==` returns `false` for `NaN == NaN`, while `isequal(NaN, NaN)` is `true`.
  Without the `isequal` fallback, a struct containing `NaN` could never be
  recognized as recreated.
* `isequal(0.0, -0.0)` is `false`, but `0.0 == -0.0` is `true`. A constructor
  that normalizes `-0.0` to `0.0`, or a type with a custom `==` (e.g. via
  [`@batteries`](@ref) or [`hash_eq_as`](@ref)), would be rejected if only
  `isequal` were used.

`==` may also return non-`Bool` values (e.g. `missing`, or three-valued
logic from user-defined types). The `=== true` guard rejects those cleanly,
so they fall through to `isequal` instead of throwing in a boolean context.
"""
@inline repr_eq(a, b) = (a == b) === true || isequal(a, b)

# Internal helpers used by `constructor_repr` to shorten the printed form of
# a field while keeping it round-trippable. Two independent axes:
#
#   role               | scalar value | collection rendering
#   -------------------+--------------+----------------------
#   produce candidate  | `simple`     | `compact`
#   apply to slot      | `simplify!`  | `compactify!`
#
# Producers may be liberal — every candidate is verified by a constructor
# probe before being installed. Collection candidates are returned as
# `(string, value)` pairs because the printed form may use a different
# concrete type than the original (e.g. `SVector` → `Vector`).

# For any `Number`, the first attempt is `Int(v)`: an `Int` literal is the
# shortest possible repr and is accepted by the widest range of constructors
# via `convert(::Type{T}, ::Int)`. The check is value-based, so `UInt64(42)`,
# `Float64(2.0)`, `2//1`, `2 + 0im` all collapse to `42`/`2`. `Int(v)` is
# wrapped in a bare `catch` because user-defined `Number` subtypes (e.g.
# `Unitful.Quantity`) may throw `MethodError` rather than `InexactError`.
# `-0.0` is guarded explicitly: `Int(-0.0)` silently succeeds and would lose
# the sign bit.
simple(v) = nothing
function simple(v::Number)
    v isa AbstractFloat && iszero(v) && signbit(v) && return nothing
    try
        return Int(v)
    catch
    end
    v isa Unsigned && return signed(widen(v))
    v isa Rational && return isone(denominator(v)) ? something(simple(numerator(v)), numerator(v)) : nothing
    v isa Complex  && return iszero(imag(v)) ? something(simple(real(v)), real(v)) : nothing
    return nothing
end

# Apply `simple` to `coll[key]`, accepting only if the substitute is strictly
# shorter and `trycall()` still passes. Works on any container supporting
# `getindex`/`setindex!`.
function simplify!(coll, key, trycall)
    old = coll[key]
    alt = simple(old)
    alt === nothing && return
    length(repr(alt)) < length(repr(old)) || return
    coll[key] = alt
    trycall() || (coll[key] = old)
    return
end

# For `AbstractVector`, group consecutive `repr_eq` elements into runs and
# render each run as either a literal sequence or a splat — `fill(v, k)...`
# for `isbits` values, `[v for _ = 1:k]...` otherwise so mutable elements
# aren't aliased on re-eval — picking whichever is shorter per run.
#
# `compact_pieces` returns the un-wrapped run rendering and a tag:
#   * `:uniform` — single repeated element, e.g. `"fill(0, 4)"`. Already
#     stands alone (a function call, not an argument list).
#   * `:multi`   — comma-separated argument list, e.g. `"1, fill(0, 3)..."`.
#     A wrapper has to bracket it (`[...]`) or splat it into a constructor.
#
# `compact(::AbstractVector)` then picks the wrapper based on whether the
# concrete type's `constructorof` accepts positional varargs of element
# values: `Vector` doesn't (so we bracket), `SVector`/`MVector`/`Tuple`
# do (so we emit `Tc(elems...)` and the static size shows up in the repr).
function compact_pieces(v::AbstractVector)
    n = length(v)
    n == 0 && return nothing

    runs = Tuple{Any,Int}[]
    cur = first(v)
    cnt = 1
    for i in 2:n
        x = v[i]
        if repr_eq(x, cur)
            cnt += 1
        else
            push!(runs, (cur, cnt))
            cur = x
            cnt = 1
        end
    end
    push!(runs, (cur, cnt))

    splat_form(val, k) = isbits(val) ? "fill($(repr(val)), $k)..." :
                                       "[$(repr(val)) for _ = 1:$k]..."

    if length(runs) == 1
        first_v = first(v)
        elem_repr = repr(first_v)
        str = isbits(first_v) ? "fill($elem_repr, $n)" :
                                "[$elem_repr for _ = 1:$n]"
        return (str, :uniform)
    end

    pieces = String[]
    for (val, k) in runs
        literal = join(fill(repr(val), k), ", ")
        splat = splat_form(val, k)
        push!(pieces, length(splat) < length(literal) ? splat : literal)
    end
    return (join(pieces, ", "), :multi)
end

compact(v) = nothing
function compact(v::AbstractVector)
    cp = compact_pieces(v)
    cp === nothing && return nothing
    pieces, kind = cp
    Tc = constructorof(typeof(v))
    # Prefer `Tc(elems...)` so the printed form preserves the concrete type
    # (notably `SVector`'s static size). Fall back to a bracket literal when
    # the wrapped form doesn't round-trip — `Vector` rejects the signature,
    # and on Julia 1.6 `constructorof(SVector{N,T}) === SArray` throws
    # `DimensionMismatch` since size can't be inferred from positional args.
    fallback, wrapped = kind === :uniform ?
        (pieces,     "$Tc($pieces...)") :
        ("[$pieces]", "$Tc($pieces)")
    str = try
        repr_eq(Tc(v...), v) ? wrapped : fallback
    catch
        fallback
    end
    length(str) < length(repr(v)) || return nothing
    return (str, collect(v))
end

# Apply `compact` to `coll[key]`, accepting only if `trycall()` still passes.
# On success returns the rendered string and leaves `coll[key]` bound to the
# substitute value (`repr_eq` to the original); on failure restores the
# original and returns `nothing`.
function compactify!(coll, key, trycall)
    orig = coll[key]
    cr = compact(orig)
    cr === nothing && return nothing
    str, alt = cr
    coll[key] = alt
    trycall() && return str
    coll[key] = orig
    return nothing
end
