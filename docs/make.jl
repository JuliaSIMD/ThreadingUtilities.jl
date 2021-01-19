using ThreadingUtilities
using Documenter

makedocs(;
    modules=[ThreadingUtilities],
    authors="Chris Elrod <elrodc@gmail.com> and contributors",
    repo="https://github.com/chriselrod/ThreadingUtilities.jl/blob/{commit}{path}#L{line}",
    sitename="ThreadingUtilities.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://chriselrod.github.io/ThreadingUtilities.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Public API" => "public-api.md",
        "Internal (Private)" => "internals.md",
    ],
    strict=true,
)

deploydocs(;
    repo="github.com/chriselrod/ThreadingUtilities.jl",
)
