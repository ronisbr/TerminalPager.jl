## Description #############################################################################
#
# Helpers.
#
############################################################################################

export @help, @stdout_to_pager, @out2pr

"""
    @help(f)

Open the documentation of the function, macro or other object `f` in pager.

# Examples

```julia-repl
julia> @help write
```
"""
macro help(f)
    # When calling @help for a macro, the argument `f` will get prefixed with a block comment.
    # We remove that comment and just keep the macro name.
    local f_str = chopprefix(string(f), r"#= .+ =# ")
    ex_out = quote
        # We do not need to verify if we are in a interactive environment because this mode is
        # only accessible through pager mode, which already checks it.
        try
            pager(TerminalPager._get_help($f_str); use_alternate_screen_buffer = true)
        catch err
            Base.display_error(stderr, err, Base.catch_backtrace())
        end
    end

    return esc(ex_out)
end

"""
    @stdout_to_pager(ex_in)

Capture the `stdout` generated by `ex_in` and show inside a pager.

!!! note
    The command **must** write to `stdout` explicitly. For example, `@stdout_to_pager 1`
    shows a blank screen since `1` does not write to `stdout`, but returns `1`.
    `@stdout_to_pager show(1)`, on the other hand, shows the number `1` inside the pager.

!!! note
    This macro can also be called using the shorter name `@out2pr`.
"""
macro stdout_to_pager(ex_in)
    ex_out = quote
        hascolor   = get(stdout, :color, true)
        old_stdout = stdout
        buf        = IOBuffer()
        io         = IOContext(buf, :color => hascolor, :limit => false)

        try
            Base.eval(:(stdout = $io))
            $(esc(ex_in))
            Base.eval(:(stdout = $old_stdout))
            String(take!(buf)) |> pager
            close(io)
        finally
            Base.eval(:(stdout = $old_stdout))
        end

    end

    return ex_out
end

macro out2pr(ex)
    return :(@stdout_to_pager $(esc(ex)))
end

############################################################################################
#                                    Private Functions                                     #
############################################################################################

# Return the rendered help string of the function `f`.
function _get_help(f)
    # Create a buffer that will replace `stdout`.
    buf = IOBuffer()
    io = IOContext(
        IOContext(buf, stdout),
        :displaysize => displaysize(stdout),
        :limit => false,
    )

    # Get the AST that generates the help.
    ast = Base.invokelatest(TerminalPager.REPL.helpmode, io, f)

    # Evaluate the AST, which returns a Markdown object.
    response = Core.eval(Main, ast)

    # Render the output.
    show(io, MIME("text/plain"), response)
    write(io, '\n')

    str = String(take!(buf))

    close(io)

    return str
end
