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
