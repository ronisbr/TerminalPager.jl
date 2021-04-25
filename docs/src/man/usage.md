Usage
=====

## Getting started

The pager is called using the function `pager`. If the input object is not a
`AbstractString`, then it will be rendered using `show` with `MIME"text/plain"`.
Thus, you can browse a large matrix, for example, using:

```julia-repl
julia> rand(100,100) |> pager
```

It is also possible to use the `pager` to browse the documentation of a specific
function:

```julia-repl
julia> @doc(write) |> pager
```

