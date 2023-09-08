TerminalPager.jl
================

[![CI](https://github.com/ronisbr/TerminalPager.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/ronisbr/TerminalPager.jl/actions/workflows/ci.yml)
[![](https://img.shields.io/badge/docs-stable-blue.svg)][docs-stable-url]
[![](https://img.shields.io/badge/docs-dev-blue.svg)][docs-dev-url]
[![Code Style: Blue](https://img.shields.io/badge/code%20style-blue-4495d1.svg)](https://github.com/invenia/BlueStyle)

This package contains a pager written 100% in Julia. It can be used to scroll through
content that does not fit in the screen. It was developed based on the Linux command `less`.

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
