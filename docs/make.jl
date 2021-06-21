using StructHelpers
using Documenter

DocMeta.setdocmeta!(StructHelpers, :DocTestSetup, :(using StructHelpers); recursive=true)

makedocs(;
    modules=[StructHelpers],
    authors="Jan Weidner <jw3126@gmail.com> and contributors",
    repo="https://github.com/jw3126/StructHelpers.jl/blob/{commit}{path}#{line}",
    sitename="StructHelpers.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://jw3126.github.io/StructHelpers.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/jw3126/StructHelpers.jl",
)
