# TerminalPager.jl

```@meta
CurrentModule = TerminalPager
DocTestSetup = quote
    using TerminalPager
end
```

This package contains a pager written 100% in Julia. It can be used to scroll through
content that does not fit in the screen. It was developed based on the Linux command `less`.

## Installation

```julia-repl
julia> using Pkg

julia> Pkg.add("TerminalPager")
```

## Automatically Start with Julia

If you want to automatically load **TerminalPager.jl**, add the following line to the file
`.julia/config/startup.jl` after you have installed the package:

```julia
using TerminalPager
```

Another way is to compile the package directly into your Julia system image. For more
information, see the documentation of the package
[PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl).

## Manual outline

```@contents
Pages = [
    "man/usage.md"
]
Depth = 2
```
