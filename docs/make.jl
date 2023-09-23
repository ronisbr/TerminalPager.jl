using Documenter
using TerminalPager

makedocs(
    modules = [TerminalPager],
    format = Documenter.HTML(
        prettyurls = !("local" in ARGS),
        canonical = "https://ronisbr.github.io/TerminalPager.jl/stable/",
        edit_link = "main"
    ),
    sitename = "Terminal Pager",
    authors = "Ronan Arraes Jardim Chagas",
    pages = [
        "Introduction"  => "index.md",
        "Usage"         => "man/usage.md",
        "Customization" => "man/customization.md",
        "Library"       => "lib/library.md"
    ],
)

deploydocs(
    repo = "github.com/ronisbr/TerminalPager.jl.git",
    devbranch = "main",
    target = "build",
)
