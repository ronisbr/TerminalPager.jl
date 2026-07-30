# TerminalPager.jl

[![CI](https://img.shields.io/github/actions/workflow/status/ronisbr/TerminalPager.jl/ci.yml?style=flat-square&logo=githubactions&logoColor=white&labelColor=475569&label=CI)](https://github.com/ronisbr/TerminalPager.jl/actions/workflows/ci.yml)
[![docs-stable](https://img.shields.io/badge/docs-stable-16A34A?style=flat-square&logo=gitbook&logoColor=white&labelColor=475569)][docs-stable-url]
[![docs-dev](https://img.shields.io/badge/docs-dev-D97706?style=flat-square&logo=gitbook&logoColor=white&labelColor=475569)][docs-dev-url]
[![Code Style: Blue](https://img.shields.io/badge/code%20style-blue-4495D1?style=flat-square&logo=julia&logoColor=white&labelColor=475569)](https://github.com/invenia/BlueStyle)
[![License](https://img.shields.io/github/license/ronisbr/TerminalPager.jl?style=flat-square&logo=readme&logoColor=white&labelColor=475569&color=0284C7)](https://github.com/ronisbr/TerminalPager.jl/blob/main/LICENSE.txt)
[![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.8368511-DB2777?style=flat-square&logo=doi&logoColor=white&labelColor=475569)](https://zenodo.org/doi/10.5281/zenodo.8368511)

This package contains a pager written 100% in Julia. It can be used to scroll through
content that does not fit on the screen. It was developed based on the Linux command `less`.

## Quick installation

```julia
julia> using Pkg

julia> Pkg.add("TerminalPager")
```

## Quick start

You can call the pager using the function `pager` with any object. If it is not a string,
then it will be rendered to one using `show` with `MIME"text/plain"`.

```julia
julia> rand(100, 100) |> pager

julia> pager(rand(100, 100))
```

For more details, see the [documentation][docs-dev-url].

[docs-dev-url]: https://ronisbr.github.io/TerminalPager.jl/dev
[docs-stable-url]: https://ronisbr.github.io/TerminalPager.jl/stable
