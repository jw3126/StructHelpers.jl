module StructHelpers

export @batteries
export @enumbatteries

import ConstructionBase: getproperties, constructorof, setproperties

@inline function structural_eq(o1, o2)
    getproperties(o1) == getproperties(o2)
end

start_hash(o, h, typesalt::Nothing) = Base.hash(typeof(o), h)
start_hash(o, h, typesalt) = Base.hash(typesalt, h)
@inline function structural_hash(o, h::UInt, typesalt=nothing)::UInt
    h = start_hash(o, h, typesalt)
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

function def_selfconstructor(T)
    :($T(self::$T) = self)
end

function def_kwconstructor(T, propertynames)
    call = Expr(:call, T, Expr(:parameters, propertynames...))
    ret = :($call = $T($(propertynames...)))
    ret
end

const BATTERIES_DEFAULTS = (
    eq            = true ,
    hash          = true ,
    kwconstructor = false,
    selfconstructor = true,
    kwshow        = false,
    getproperties = true ,
    constructorof = true ,
    typesalt      = nothing,
)

const BATTERIES_DOCSTRINGS = (
    eq            = "Define `Base.(==)` structurally.",
    hash          = "Define `Base.hash` structurally.",
    kwconstructor = "Add a keyword constructor.",
    selfconstructor = "Add a constructor of the for `T(self::T) = self`",
    kwshow        = "Overload `Base.show` such that the names of each field are printed.",
    getproperties = "Overload `ConstructionBase.getproperties`.",
    constructorof = "Overload `ConstructionBase.constructorof`.",
    typesalt      = "Only used if `hash=true`. In this case the `hash` will be purely computed from `typesalt` and `getproperties(T)`. The type `T` will not be used otherwise. This makes the hash more likely to stay constant, when executing on a different machine or julia version",
)

if (keys(BATTERIES_DEFAULTS) != keys(BATTERIES_DOCSTRINGS))
    error("""
          keys(BATTERIES_DEFAULTS) == key(BATTERIES_DOCSTRINGS) must hold.
          Got:
          keys(BATTERIES_DEFAULTS) = $(keys(BATTERIES_DEFAULTS))
          keys(BATTERIES_DOCSTRINGS) = $(keys(BATTERIES_DOCSTRINGS))
    """)
end
@assert keys(BATTERIES_DEFAULTS) == keys(BATTERIES_DOCSTRINGS)

function doc_batteries_options()
    lines = map(propertynames(BATTERIES_DEFAULTS)) do key
        "* **$key** = $(BATTERIES_DEFAULTS[key]):\n $(BATTERIES_DOCSTRINGS[key])"
    end
    join(lines, "\n")
end

const BATTERIES_ALLOWED_KW = keys(BATTERIES_DEFAULTS)

"""

    @batteries T [options]

Automatically derive several methods for type `T`.

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

Supported options and defaults are:

$(doc_batteries_options())
"""
macro batteries(T, kw...)
    nt = parse_all_macro_kw(kw)
    for (pname, val) in pairs(nt)
        if !(pname in propertynames(BATTERIES_DEFAULTS))
            error("""
                Unsupported keyword.
                Offending Keyword: $pname
                allowed: $BATTERIES_ALLOWED_KW
                Got: $nt
            """)
        end
        if val isa Bool

        elseif pname == :typesalt
            if !(val isa Union{Nothing,Integer})
                error("""`typesalt` must be literally `nothing` or an unsigned integer. Got:
                      typesalt = $(repr(typesalt))::$(typeof(typesalt))
                      """)
            end
        else
            error("""
                Bad keyword argument value:
                Got: $nt
                Offending Keyword: $pname
                Offending value  : $(repr(val))
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
        def = :(Base.hash(o::$T, h::UInt) = $(structural_hash)(o,h, $(nt.typesalt)))
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
    if nt.selfconstructor
        def = def_selfconstructor(T)
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

################################################################################
#### enum
################################################################################
function ifelsechain(
        cond_code_pairs,
        rest
    )
    if length(cond_code_pairs) == 0
        return rest
    elseif length(cond_code_pairs) == 1
        cond, code = only(cond_code_pairs)
        Expr(:if, cond, code, rest)
    else
        cond, code = cond_code_pairs[end]
        ifelsechain(
            cond_code_pairs[begin:end-1],
            Expr(:elseif, cond, code, rest),
        )
    end
end

function enum_from_string(::Type{T}, s::AbstractString)::T where {T}
    _enum_from_string(T,convert(String,s))
end
function enum_from_symbol(::Type{T}, s::Symbol)::T where {T}
    _enum_from_symbol(T,s)
end
function string_from_enum(enum)::String
    string(enum)
end
function symbol_from_enum(enum)::Symbol
    Symbol(string_from_enum(enum))
end
@generated function _enum_from_string(::Type{T}, s::String)::T where {T}
    enum_from_string_or_symbol_body(string_from_enum, T)
end
@generated function _enum_from_symbol(::Type{T}, s::Symbol)::T where {T}
    enum_from_string_or_symbol_body(QuoteNode∘symbol_from_enum, T)
end

function def_enum_from_string(T)::Expr
    body = enum_from_string_or_symbol_body(string_from_enum, T)
    :(
      function StructHelpers.enum_from_string(::Type{$T}, s::String)::$T
          $body
      end
     )
end
function def_enum_from_symbol(T)::Expr
    body = enum_from_string_or_symbol_body(QuoteNode∘symbol_from_enum, T)
    :(
      function StructHelpers.enum_from_symbol(::Type{$T}, s::Symbol)::$T
          $body
      end
     )
end

@noinline function throw_no_matching_instance(f,T,s)
    msg = """
    Cannot instaniate enum `T` from `s`. Got:
    s = $(repr(s))
    T = $(T)
    allowed values for s = $(map(f, instances(T)))
    """
    throw(ArgumentError(msg))
end

function enum_from_string_or_symbol_body(f,T)
    err = :($throw_no_matching_instance($f,$T,s))
    matcharms = [
        :(s === $(f(inst))) => inst for inst in instances(T)
    ]
    ifelsechain(matcharms, err)
end

const ENUM_BATTERIES_DEFAULTS = (
    string_conversion=false,
    symbol_conversion=false,
    selfconstructor=BATTERIES_DEFAULTS.selfconstructor,
)

const ENUM_BATTERIES_DOCSTRINGS = (
    string_conversion="Add `convert(MyEnum, ::String)`, `MyEnum(::String)`, `convert(String, ::MyEnum)` and `String(::MyEnum)`",
    symbol_conversion="Add `convert(MyEnum, ::Symbol)`, `MyEnum(::Symbol)`, `convert(Symbol, ::MyEnum)` and `Symbol(::MyEnum)`",
    selfconstructor=BATTERIES_DOCSTRINGS.selfconstructor,
)

if (keys(ENUM_BATTERIES_DEFAULTS) != keys(ENUM_BATTERIES_DOCSTRINGS))
    error("""
          keys(ENUM_BATTERIES_DEFAULTS) == key(ENUM_BATTERIES_DOCSTRINGS) must hold.
          Got:
          keys(ENUM_BATTERIES_DEFAULTS) = $(keys(ENUM_BATTERIES_DEFAULTS))
          keys(ENUM_BATTERIES_DOCSTRINGS) = $(keys(ENUM_BATTERIES_DOCSTRINGS))
    """)
end
@assert keys(ENUM_BATTERIES_DEFAULTS) == keys(ENUM_BATTERIES_DOCSTRINGS)

function doc_enum_batteries_options()
    lines = map(propertynames(ENUM_BATTERIES_DEFAULTS)) do key
        "* **$key** = $(ENUM_BATTERIES_DEFAULTS[key]):\n $(ENUM_BATTERIES_DOCSTRINGS[key])"
    end
    join(lines, "\n")
end

const ENUM_BATTERIES_ALLOWED_KW = keys(ENUM_BATTERIES_DEFAULTS)

"""

    @enumbatteries T [options]

Automatically derive several methods for Enum type `T`.

# Example
```julia
@enum Color Red Blue Yellow
@enumbatteries Color
@enumbatteries Color hash=false # don't overload `Base.hash`
@enumbatteries Color symbol_conversion=true # allow convert(Color, :Blue), Color(:Blue), convert(Symbol, Blue), Symbol(Blue)
```

Supported options and defaults are:

$(doc_enum_batteries_options())
"""
macro enumbatteries(T, kw...)
    nt = parse_all_macro_kw(kw)
    for (pname, val) in pairs(nt)
        if !(pname in propertynames(ENUM_BATTERIES_DEFAULTS))
            error("""
                Unsupported keyword.
                Offending Keyword: $pname
                allowed: $ENUM_BATTERIES_ALLOWED_KW
                Got: $nt
            """)
        end
        if val isa Bool

        else
            error("""
                Bad keyword argument value:
                Got: $nt
                Offending Keyword: $pname
                Offending value  : $(repr(val))
            """)
        end
    end
    nt = merge(ENUM_BATTERIES_DEFAULTS, nt)
    TT = Base.eval(__module__, T)::Type
    ret = quote end

    push!(ret.args, :(import StructHelpers))
    push!(ret.args, def_enum_from_symbol(TT))
    push!(ret.args, def_enum_from_string(TT))
    if nt.string_conversion
        ex1 = :(Base.convert(::Type{$TT}, s::AbstractString) = StructHelpers.enum_from_string($TT, String(s)))
        ex2 = :($T(s::AbstractString) = StructHelpers.enum_from_string($TT, String(s)))
        ex3 = :(Base.convert(::Type{String}, x::$T) = StructHelpers.string_from_enum(x))
        ex4 = :(Base.String(x::$T) = StructHelpers.string_from_enum(x))
        push!(ret.args, ex1, ex2, ex3, ex4)
    end
    if nt.symbol_conversion
        ex1 = :(Base.convert(::Type{$T}, s::Symbol) = StructHelpers.enum_from_symbol($TT, Symbol(s)))
        ex2 = :($T(s::Symbol) = StructHelpers.enum_from_symbol($TT, Symbol(s)))
        ex3 = :(Base.convert(::Type{Symbol}, x::$T) = StructHelpers.symbol_from_enum(x))
        ex4 = :(Base.Symbol(x::$T) = StructHelpers.symbol_from_enum(x))
        push!(ret.args, ex1, ex2, ex3, ex4)
    end
    if nt.selfconstructor
        def = def_selfconstructor(T)
        push!(ret.args, def)
    end
    return esc(ret)
end

end #module
