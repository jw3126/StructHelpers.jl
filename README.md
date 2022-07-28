# StructHelpers

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://jw3126.github.io/StructHelpers.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://jw3126.github.io/StructHelpers.jl/dev)
[![Build Status](https://github.com/jw3126/StructHelpers.jl/workflows/CI/badge.svg)](https://github.com/jw3126/StructHelpers.jl/actions)
[![Coverage](https://codecov.io/gh/jw3126/StructHelpers.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/jw3126/StructHelpers.jl)

Sometimes defining a new struct is accompanied by a bit of boilerplate. For instance the default definition of `Base.hash` is by object id. Often a `hash` that is based on the object struture is preferable however. Similar for `==`.
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
```
For all supported options and defaults, consult the docstring:
```julia
julia>?@batteries
```

# Alternatives

* [AutoHashEquals](https://github.com/andrewcooke/AutoHashEquals.jl) requires annotating the struct definition. This can be inconvenient if you want to annotate the definition with another macro as well.
* [StructEquality](https://github.com/jolin-io/StructEquality.jl) is similar to this package.
