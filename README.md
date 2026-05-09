# StructHelpers

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://jw3126.github.io/StructHelpers.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://jw3126.github.io/StructHelpers.jl/dev)
[![Build Status](https://github.com/jw3126/StructHelpers.jl/workflows/CI/badge.svg)](https://github.com/jw3126/StructHelpers.jl/actions)
[![Coverage](https://codecov.io/gh/jw3126/StructHelpers.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/jw3126/StructHelpers.jl)

Sometimes defining a new struct is accompanied by a bit of boilerplate. For instance the default definition of `Base.hash` is by object id. Often a `hash` that is based on the object structure is preferable however. Similar for `==`.
StructHelpers aims to simplify the boilerplate required for such common tweaks.

# Usage

```julia
struct S
    a
    b
end

@batteries S
@batteries S hash=false # don't overload `Base.hash`
@batteries S kwconstructor=true # add a keyword constructor
@batteries S kwconstructor      # bare-symbol shorthand for `kwconstructor=true`
```

If you want only a hand-picked subset of batteries (no defaults), use
`@battery`:

```julia
@battery S kwconstructor       # only the keyword constructor
@battery S eq isequal hash     # only structural ==, isequal, hash
```

To share a configuration across many structs, pass a `NamedTuple`:

```julia
const config = (kwshow=true, kwconstructor=true, eq=false)

@batteries S1 config
@batteries S2 config typesalt=0xdeadbeef   # config + per-struct override
@battery   S3 config                       # opt-in form, same config
```

A config only *overrides* the keys it mentions. With `@batteries`, every
key the config doesn't set keeps its default value (e.g. `S1` above
still gets the default structural `isequal`, `hash`, `selfconstructor`
etc.). With `@battery` the same config picks exactly the listed
batteries and nothing else, since `@battery`'s baseline has every flag
turned off.

Useful configs could look like this:

```julia
# Value-like records: nice display + keyword construction, structural
# `==` / `isequal` / `hash` from the defaults.
const value_like  = (kwshow=true, kwconstructor=true)

# Plain data you also want to (de)serialize via StructTypes.jl / JSON3.
const serializable = (kwshow=true, kwconstructor=true, StructTypes=true)

# Identity semantics: keep ergonomic show/construction, but opt out of
# structural equality and hashing (e.g. for mutable handles or types
# whose fields aren't meaningfully comparable).
const identity_like = (kwshow=true, kwconstructor=true,
                       eq=false, isequal=false, hash=false)

# Reproducible cross-machine hashes: combine with a per-struct typesalt.
const stable_hash = (kwshow=true, kwconstructor=true)

@batteries Point value_like
@batteries Config serializable
@batteries FileHandle identity_like
@batteries CacheKey stable_hash typesalt=0xdeadbeefcafebabe
```

For all supported options and defaults, consult the docstring:
```julia
julia>?@batteries
```

## `kwshow` vs `showrepr`

Two options overload `Base.show`; pick at most one (passing both is an
error):

* `kwshow=true` always renders `T(f1 = v1, f2 = v2, …)` — every field,
  named, in declaration order. The output shape is fixed and stable
  across versions, which makes it well-suited to diagnostics and
  golden-file tests. It round-trips through `eval` only when the type
  has a keyword constructor (e.g. via `kwconstructor=true` or
  `Base.@kwdef`).

* `showrepr=true` prints a heuristically short constructor call that
  recreates the object. It probes every constructor of the type
  (positional, keyword, hybrid), omits trailing fields that already
  match a default, and substitutes shorter literals where the
  constructor still accepts them (e.g. `0x2a` → `42`, `2//1` → `2`,
  uniform vectors → `fill(v, n)`). Because the result depends on the
  field values and on the package's heuristics, the exact output is
  *not* guaranteed to be stable across minor releases — don't pin
  golden files against it. If no constructor recreates the object,
  `showrepr` falls back to a non-executable `T(field = value, …)`
  rendering.

Rule of thumb: pick `kwshow` if you want a predictable, name-every-field
diagnostic; pick `showrepr` if you want `Base.show` to produce an
idiomatic, recreatable, as-short-as-reasonable form for end users.

# Alternatives

* [AutoHashEquals](https://github.com/andrewcooke/AutoHashEquals.jl) requires annotating the struct definition. This can be inconvenient if you want to annotate the definition with another macro as well.
* [StructEquality](https://github.com/jolin-io/StructEquality.jl) is similar to this package.
