## Description #############################################################################
#
# Precompilation.
#
############################################################################################

import PrecompileTools

PrecompileTools.@setup_workload begin
    # We will redirect the `stdout` and `stdin` so that we can execute the pager and input
    # some commands without making visible changes to the user.
    old_stdout = Base.stdout
    old_stdin  = Base.stdin

    redirect_stdout(devnull)
    stdin_rd, stdin_wr = redirect_stdin()

    PrecompileTools.@compile_workload begin
        # Precompile everything called in __init__.
        __init__()

        # Precompile REPL integration functions - create a mock REPL for precompilation
        mock_repl = REPL.LineEditREPL(REPL.Terminals.TTYTerminal("", stdin, stdout, stderr), true)
        mock_repl.interface = REPL.setup_interface(mock_repl)
        _init_pager_repl_mode(mock_repl)
        _register_help_shortcuts(mock_repl)

        a = vcat(fill(0.1986, 100)', rand(100, 100))
        t = @async pager(a)

        # Ruler.
        write(stdin_wr, "r")
        # Freeze rows and columns.
        write(stdin_wr, "f10\n10\n")
        # Title rows.
        write(stdin_wr, "t1\n")
        # Down.
        write(stdin_wr, "\eOB")
        # Up.
        write(stdin_wr, "\eOA")
        # Right.
        write(stdin_wr, "\eOC")
        # Left.
        write(stdin_wr, "\eOD")
        # Page down.
        write(stdin_wr, "\e[6~")
        # Page up.
        write(stdin_wr, "\e[5~")
        # End.
        write(stdin_wr, "\e[F")
        # Home.
        write(stdin_wr, "\e[H")
        # Visual mode.
        write(stdin_wr, "v")
        # Mark lines.
        write(stdin_wr, "mjmjmjmjmjm")
        # Unmark lines.
        write(stdin_wr, "mkmk")
        # Exit visual mode.
        write(stdin_wr, "v")
        # Help.
        write(stdin_wr, "?")
        # Exit help mode.
        write(stdin_wr, "q")
        # Search.
        write(stdin_wr, "/0.1986\n")
        # Next search.
        write(stdin_wr, "nnn")
        # Exit search (ESC).
        write(stdin_wr, Char(27))
        # Exit pager.
        write(stdin_wr, "q")

        wait(t)

        # Pager with the alternate screen buffer.
        t = @async pager(a; use_alternate_screen_buffer = true)
        write(stdin_wr, "q")
        wait(t)

        # Pager with auto mode, which exercises the `printable_textwidth` code path. This
        # is important because the REPL mode always uses `auto = true`.
        t = @async pager(a; auto = true)
        write(stdin_wr, "q")
        wait(t)

        # == Internal Functions ============================================================

        TerminalPager._get_help("read")
        f = "read read read"
        TerminalPager._get_help(@view f[1:4])
        TerminalPager._extract_identifier("while true break end", 10)
    end

    close(stdin_wr)
    close(stdin_rd)

    redirect_stdout(old_stdout)

    if isopen(old_stdin)
        redirect_stdin(old_stdin)
    else
        redirect_stdin(devnull)
    end
end
