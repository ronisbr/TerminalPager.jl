using Documenter
using TerminalPager

makedocs(
    modules = [TerminalPager],
    format = Documenter.HTML(
        prettyurls = !("local" in ARGS),
        canonical = "https://ronisbr.github.io/TerminalPager.jl/stable/",
    ),
    sitename = "Terminal Pager",
    authors = "Ronan Arraes Jardim Chagas",
    pages = [
        "Home"               => "index.md",
        "Usage"              => "man/usage.md",
    ]
)

deploydocs(
    repo = "github.com/ronisbr/TerminalPager.jl.git",
    target = "build",
)
