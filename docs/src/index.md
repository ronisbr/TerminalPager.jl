TerminalPager.jl
================

```@meta
CurrentModule = TerminalPager
DocTestSetup = quote
    using TerminalPager
end
```

This package contains a pager written 100% in Julia. It can be used to scroll
through content that does not fit in the screen. It was developed based on the
Linux command `less`.

## Requirements

Julia >= 1.0
Crayons >= 4.0
Parameters >= 0.12

## Installation

```julia-repl
julia> using Pkg
julia> Pkg.add("TerminalPager")
```

## Manual outline

```@contents
Pages = [
    "man/usage.md"
]
Depth = 2
```
