module StructHelpers

export @batteries

import ConstructionBase: getproperties, constructorof, setproperties

@inline function structural_eq(o1, o2)
    getproperties(o1) == getproperties(o2)
end

@inline function structural_hash(o, h::UInt)::UInt
    h = Base.hash(typeof(o), h)
    nt = Tuple(getproperties(o))
    Base.hash(nt, h)
end
function kwshow(io::IO, o)
    print(io, typeof(o))
    show(io, getproperties(o))
end

function def_getproperties(T, propertynames)
    body = Expr(:tuple)
    for pname in propertynames
        ex = :($pname = o.$pname)
        push!(body.args, ex)
    end
    :(StructHelpers.getproperties(o::$T) = $body)
end

function def_kwconstructor(T, propertynames)
    call = Expr(:call, T, Expr(:parameters, propertynames...))
    ret = :($call = $T($(propertynames...)))
    ret
end

const BATTERIES_DEFAULTS = (
    eq=true, hash=true,
    kwconstructor=false, kwshow=false,
    getproperties=true, constructorof=true,
)

const ALLOWED_KW = keys(BATTERIES_DEFAULTS)

"""

    @batteries T [options]

Automatically derive several methods for type `T`.
Supported options are:
$BATTERIES_DEFAULTS

# Example
```julia
struct S
    a
    b
end

@batteries S
@batteries S hash=false # don't overload `Base.hash`
@batteries S kwconstructor=true # add a keyword constructor
```
"""
macro batteries(T, kw...)
    nt = parse_all_macro_kw(kw)
    for (pname, val) in pairs(nt)
        if !(pname in propertynames(BATTERIES_DEFAULTS))
            error("""
                Unsupported keyword.
                Offending Keyword: $pname
                allowed: $ALLOWED_KW
                Got: $nt
            """)
        end
        if !(val isa Bool)
            error("""
                All options must be literally `true` or `false`.
                Got: $nt
                Offending Keyword: $pname
            """)
        end
    end
    nt = merge(BATTERIES_DEFAULTS, nt)
    ret = quote end

    need_StructHelpers = nt.getproperties || nt.constructorof
    if need_StructHelpers
        push!(ret.args, :(import StructHelpers))
    end
    need_fieldnames = nt.kwconstructor || nt.getproperties
    if need_fieldnames
        fieldnames = Base.fieldnames(Base.eval(__module__, T))
    end
    if nt.hash
        def = :(Base.hash(o::$T, h::UInt) = $(structural_hash)(o,h))
        push!(ret.args, def)
    end
    if nt.eq
        def = :(Base.:(==)(o1::$T, o2::$T) = $(structural_eq)(o1, o2))
        push!(ret.args, def)
    end
    if nt.kwshow
        def = :(Base.show(io::IO, o::$T) = $(kwshow)(io, o))
        push!(ret.args, def)
    end
    if nt.getproperties
        def = def_getproperties(T, fieldnames)
        push!(ret.args, def)
    end
    if nt.constructorof
        def = :(StructHelpers.constructorof(::Type{<:$T}) = $T)
        push!(ret.args, def)
    end
    if nt.kwconstructor
        def = def_kwconstructor(T, fieldnames)
        push!(ret.args, def)
    end
    return esc(ret)
end

function error_parse_single_macro_kw(kw; comment=nothing)
    msg = """
    Excepted a keyword argument of the form name = value.
    Got $(kw) instead.
    """
    if comment !== nothing
        msg = msg*comment
    end
    error(msg)
end
function parse_single_macro_kw(kw)
    Meta.isexpr(kw, Symbol("=")) || error_parse_macro_kw(kw)
    length(kw.args) == 2 || error_parse_macro_kw(kw)
    key, val = kw.args
    key isa Symbol || error_parse_macro_kw(kw, comment="key = $key must be a symbol")
    (key => val)
end
function parse_all_macro_kw(kw)
    pairs =  map(parse_single_macro_kw, kw)
    if !(allunique(map(first, pairs)))
        error(
            """
            Keywords must be unique. Got:
            $(kw)
            """
        )
    end
    (;pairs...)
end

end
