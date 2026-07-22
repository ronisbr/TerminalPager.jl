# Usage

## Getting started

The pager is called using the function `pager`. If the input object is not a
`AbstractString`, then it will be rendered using `show` with `MIME"text/plain"`.  Thus, you
can browse a large matrix, for example, using:

```julia-repl
julia> rand(100,100) |> pager
```

It is also possible to use the `pager` to browse the documentation of a specific function:

```julia-repl
julia> @doc(write) |> pager
```

All the functionalities can be seen in the built-in help system, accessible by typing `?`
inside the `pager`.

## Helpers

The following macros are available to help calling the pager.

### `@help`

This macro calls the help of any function, macro, or other object and redirects it to the
`pager`:

```julia-repl
julia> @help write
```

![](../assets/dpr_01.png)

You can hit `<Alt> + h` (alternatively `<F1>`) on any REPL input to get help about the
identifier the cursor currently is above. After you ended the `pager`, you are back
with the REPL input you have already written. If you are in a new argument of a
method call, the pager will print help about the function instead to help you complete
the method's argument list.

You can hit `<Alt> + <Shift> + h` to perform the same action but showing the extended help
instead.

### `@stdout_to_pager`

This macro redirects all the `stdout` to the pager after the command is completed:

```julia-repl
julia> @stdout_to_pager show(stdout, MIME"text/plain"(), rand(100,100))
```

![](../assets/stdout_to_pager_01.png)

This macro also works with blocks such as `for` loops:

```julia-repl
julia> @stdout_to_pager for i = 1:100
       println("$(mod(i,9))"^i)
       end
```

![](../assets/stdout_to_pager_02.png)

!!! note
    This macro can also be called using the shorter name `@out2pr`.

## REPL Modes

**TerminalPager.jl** comes with a REPL mode that automatically renders the command output to
a pager if it does not fit the screen. To access this mode, just type `|` at the beginning
of the REPL command line. If the mode is loaded correctly, the prompt `julia>` is changed to
`pager>`.

In pager mode, you can also type `?` at the beginning of the command line to access the pager
help mode. In this case, the prompt is changed to `pager?>`. Any docstring accessed in this
mode is rendered inside a pager. By default, we use the alternate screen buffer,
allowing to keep the screen content after exiting the pager.
