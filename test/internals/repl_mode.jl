## Description #############################################################################
#
# Tests for the pager REPL mode helpers.
#
############################################################################################

@testset "Non-Interactive REPL Mode Warning" begin
    # `PRINTED_REPL_WARNING` used to be referenced without being defined anywhere, so
    # running a `pager>` command from a script threw an `UndefVarError` instead of warning.
    @test TerminalPager.PRINTED_REPL_WARNING isa Ref{Bool}

    old_state = TerminalPager.PRINTED_REPL_WARNING[]

    try
        TerminalPager.PRINTED_REPL_WARNING[] = false

        # An interactive session must not warn.
        @test_logs TerminalPager._warn_repl_mode_noninteractive!(true)
        @test TerminalPager.PRINTED_REPL_WARNING[] == false

        # A non-interactive session warns exactly once.
        @test_logs (:warn, r"interactive use only") TerminalPager._warn_repl_mode_noninteractive!(
            false
        )
        @test TerminalPager.PRINTED_REPL_WARNING[] == true
        @test_logs TerminalPager._warn_repl_mode_noninteractive!(false)
    finally
        TerminalPager.PRINTED_REPL_WARNING[] = old_state
    end
end

@testset "REPL Hook Initialization" begin
    term = REPL.Terminals.TTYTerminal("", IOBuffer(), IOBuffer(), IOBuffer())
    repl = REPL.LineEditREPL(term, true)
    repl.interface = REPL.setup_interface(repl)
    has_pager_mode() = any(TerminalPager._is_pager_mode, repl.interface.modes)
    old_interactive = isinteractive()

    try
        # The precompilation process is not interactive, so the hook must not touch the REPL.
        Base.is_interactive = false
        TerminalPager._init_repl_integrations(repl)
        yield()
        @test !has_pager_mode()

        Base.is_interactive = true
        TerminalPager._init_repl_integrations(repl)
        @test timedwait(has_pager_mode, 10.0) == :ok
    finally
        Base.is_interactive = old_interactive
    end
end

@testset "REPL Command Assembly" begin
    # The commands were assembled by growing a string, which copied the whole accumulated
    # command once per line and was quadratic for large pasted blocks.
    lines = split("a = 1\nb = [1;\n2]\n", '\n'; keepempty = true)

    @test TerminalPager._assemble_repl_command(lines, 1, 1) == "a = 1\n"
    @test TerminalPager._assemble_repl_command(lines, 2, 3) == "b = [1;\n2]\n"
    @test TerminalPager._assemble_repl_command(lines, 4, 4) == "\n"
end

"""
    _capture_stdout(f::Function) -> String

Run `f` with the standard output redirected to a temporary file and return what it wrote.

# Arguments

- `f::Function`: Function to run.
"""
function _capture_stdout(f::Function)
    path, io = mktemp()

    try
        redirect_stdout(f, io)
        close(io)
        return read(path, String)
    finally
        isopen(io) && close(io)
        rm(path; force = true)
    end
end

@testset "Paged Help Mode" begin
    term = REPL.Terminals.TTYTerminal("", IOBuffer(), IOBuffer(), IOBuffer())
    repl = REPL.LineEditREPL(term, true)
    repl.interface = REPL.setup_interface(repl)

    # The help prompt is found by its prompt string, wrapped once, and restored.
    help_mode = TerminalPager._find_help_mode(repl)
    @test help_mode === repl.interface.modes[3]
    @test REPL.LineEdit.prompt_string(help_mode.prompt) == "help?> "
    original = help_mode.on_done

    @test TerminalPager._replace_help_mode!(repl)
    @test TerminalPager._pages_help(help_mode)
    @test help_mode.on_done.original === original
    @test help_mode.on_done.next === first(repl.interface.modes)
    wrapped = help_mode.on_done
    @test TerminalPager._replace_help_mode!(repl)
    @test help_mode.on_done === wrapped
    @test TerminalPager._restore_help_mode!(repl)
    @test help_mode.on_done === original
    @test !TerminalPager._restore_help_mode!(repl)

    # The pager mode initialization replaces the prompt only when asked.
    TerminalPager._init_pager_repl_mode(repl; replace_help_mode = false)
    @test help_mode.on_done === original
    repl = REPL.LineEditREPL(term, true)
    repl.interface = REPL.setup_interface(repl)
    TerminalPager._init_pager_repl_mode(repl; replace_help_mode = true)
    @test TerminalPager._pages_help(TerminalPager._find_help_mode(repl))

    # A REPL without the help prompt is left alone.
    @test isnothing(TerminalPager._find_help_mode((; interface = (; modes = Any[]))))
    @test !TerminalPager._replace_help_mode!((; interface = (; modes = Any[])))
    @test !TerminalPager._replace_help_mode!("not a REPL")

    # The help is rendered and printed when the pager cannot run.
    output = _capture_stdout(() -> TerminalPager._paged_help_do_cmd(repl, " read ", Main))
    @test occursin("read", output)

    @test_throws ArgumentError TerminalPager.set_preference!("replace_help_mode", "yes")
end

struct _RationalDisplay <: AbstractDisplay
    shown::Vector{Any}
end

Base.display(d::_RationalDisplay, x::Rational) = (push!(d.shown, x); nothing)

struct _ThrowingDisplay <: AbstractDisplay end
Base.display(::_ThrowingDisplay, x) = error("boom")

struct _ShowErrorDisplay <: AbstractDisplay end
Base.display(::_ShowErrorDisplay, x) = throw(MethodError(show, (x,)))

@testset "REPL Mode Display Stack" begin
    output = IOBuffer()
    io = IOContext(output, :color => false)
    rational_display = _RationalDisplay(Any[])

    # Without another display, the value is rendered into the buffer.
    @test !TerminalPager._display_value!(io, 42)
    @test String(take!(output)) == "42\n"

    pushdisplay(rational_display)
    try
        # A display accepting the value shows it, and nothing is rendered into the buffer.
        @test TerminalPager._display_value!(io, 1 // 2)
        @test rational_display.shown == [1 // 2]
        @test isempty(take!(output))

        # A display without a method for the value is skipped.
        @test !TerminalPager._display_value!(io, 42)
        @test String(take!(output)) == "42\n"
        @test rational_display.shown == [1 // 2]

        # A display throwing a method error of `show` is skipped too, but other errors are
        # not silenced.
        pushdisplay(_ShowErrorDisplay())
        try
            @test !TerminalPager._display_value!(io, 42)
            @test String(take!(output)) == "42\n"
        finally
            popdisplay()
        end

        pushdisplay(_ThrowingDisplay())
        try
            @test_throws ErrorException TerminalPager._display_value!(io, 42)
        finally
            popdisplay()
        end

        # The REPL display and the text display point at the terminal behind the pager, so
        # they are skipped.
        term = REPL.Terminals.TTYTerminal("", IOBuffer(), IOBuffer(), IOBuffer())
        repl = REPL.LineEditREPL(term, true)
        pushdisplay(REPL.REPLDisplay(repl))
        pushdisplay(TextDisplay(IOBuffer()))
        try
            @test !TerminalPager._display_value!(io, 42)
            @test String(take!(output)) == "42\n"
            @test isempty(take!(term.out_stream))
        finally
            popdisplay()
            popdisplay()
        end

        # The preference keeps every value in the pager.
        try
            TerminalPager.set_preference!("repl_mode_display", "pager")
            @test !TerminalPager._display_value!(io, 1 // 3)
            @test String(take!(output)) == "1//3\n"
            @test rational_display.shown == [1 // 2]
        finally
            TerminalPager.drop_preference!("repl_mode_display")
        end
    finally
        popdisplay(rational_display)
    end

    @test_throws ArgumentError TerminalPager.set_preference!("repl_mode_display", "bogus")
end

@testset "Standard Output To Pager" begin
    # `auto = true` with a text that fits makes the pager print it instead of opening a
    # terminal session, which is what lets us capture it here.
    @test occursin(
        "hello", _capture_stdout(() -> @stdout_to_pager print("hello") auto = true)
    )

    # A keyword value that is not a literal used to be resolved in the scope of the package
    # instead of the caller's, so this threw an `UndefVarError`.
    rows = 0
    @test occursin(
        "scoped",
        _capture_stdout(
            () -> @stdout_to_pager print("scoped") auto = true frozen_rows = rows
        ),
    )

    # The expansion must reference the caller's variable, not one in `TerminalPager`.
    expansion = string(@macroexpand @stdout_to_pager print("x") frozen_rows = rows)
    @test !occursin("TerminalPager.rows", expansion)

    # Additional arguments that are not keyword assignments must be rejected with a useful
    # error. `MethodError` has no single-`String` constructor, so the intended message used to
    # be replaced by a confusing `MethodError` about `MethodError`.
    err = try
        @eval @stdout_to_pager print("x") 1
    catch e
        e
    end
    @test (err isa LoadError ? err.error : err) isa ArgumentError

    # The buffer must be closed even when the pager throws.
    @test_throws ErrorException _capture_stdout(
        () -> @stdout_to_pager error("boom") auto = true
    )
end
