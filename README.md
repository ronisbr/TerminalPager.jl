TerminalPager
=============

[![CI](https://github.com/ronisbr/TerminalPager.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/ronisbr/TerminalPager.jl/actions/workflows/ci.yml)

This package contains a pure Julia implementation of the command `less`.

## Usage

The function `pager` calls the pager. If the object is not a string, then it
calls `show` to obtain the string representation of it.

```julia
julia> using TerminalPager

julia> pager(rand(10, 100))

julia> rand(10, 100) |> pager
```
