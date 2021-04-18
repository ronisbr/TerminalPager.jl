Less
====

[![CI](https://github.com/ronisbr/Less.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/ronisbr/Less.jl/actions/workflows/ci.yml)

This package contains a pure Julia implementation of the command `less`.

## Usage

The function `Less.viewer` call the viewer. If the object is not a string, then
it call `show` to obtain the string representation of it.

```julia
julia> Less.viewer(rand(10, 100))

julia> rand(10, 100) |> Less.viewer
```
