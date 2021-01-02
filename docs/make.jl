using ThreadingUtilities
using Documenter

makedocs(;
    modules=[ThreadingUtilities],
    authors="Chris Elrod <elrodc@gmail.com> and contributors",
    repo="https://github.com/"Chris Elrod"/ThreadingUtilities.jl/blob/{commit}{path}#L{line}",
    sitename="ThreadingUtilities.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://"Chris Elrod".github.io/ThreadingUtilities.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/"Chris Elrod"/ThreadingUtilities.jl",
)
