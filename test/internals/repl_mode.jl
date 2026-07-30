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
