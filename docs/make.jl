using Documenter
using TerminalPager

makedocs(;
    modules = [TerminalPager],
    format = Documenter.HTML(;
        prettyurls = !("local" in ARGS),
        canonical = "https://ronisbr.github.io/TerminalPager.jl/stable/",
        edit_link = "main",
        # The library page documents every function, including the private ones, which
        # exceeds the default thresholds.
        size_threshold = 400 * 2^10,
        size_threshold_warn = 300 * 2^10,
    ),
    sitename = "Terminal Pager",
    authors = "Ronan Arraes Jardim Chagas",
    pages = [
        "Introduction"  => "index.md",
        "Usage"         => "man/usage.md",
        "Customization" => "man/customization.md",
        "Library"       => "lib/library.md",
    ],
)

deploydocs(;
    repo = "github.com/ronisbr/TerminalPager.jl.git", devbranch = "main", target = "build"
)
