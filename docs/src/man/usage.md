Usage
=====

The pager is called using the function `pager`. If the input object is not a
`AbstractString`, then it will be rendered using `show` with `MIME"text/plain"`.

Browsing through a large matrix:

```julia
julia> rand(100,100) |> pager
```

