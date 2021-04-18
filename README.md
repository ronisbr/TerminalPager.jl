TerminalPager
=============

[![CI](https://github.com/ronisbr/TerminalPager.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/ronisbr/TerminalPager.jl/actions/workflows/ci.yml)

This package contains a pure Julia implementation of the command `less`.

## Usage

The function `TerminalPager.pager` or `TerminalPager.less` call the pager. If
the object is not a string, then it call `show` to obtain the string
representation of it.

```julia
julia> using TerminalPager

julia> TerminalPager.less(rand(10, 100))

julia> rand(10, 100) |> TerminalPager.less
```
