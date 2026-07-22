## Description #############################################################################
#
# Precompilation.
#
############################################################################################

using PrecompileTools: PrecompileTools

PrecompileTools.@setup_workload begin
    # We will redirect the `stdout` and `stdin` so that we can execute the pager and input
    # some commands without making visible changes to the user.
    old_stdout = Base.stdout
    old_stdin = Base.stdin

    redirect_stdout(devnull)
    stdin_rd, stdin_wr = redirect_stdin()

    PrecompileTools.@compile_workload begin
        # Precompile everything called in __init__.
        __init__()

        # Create a mock REPL to precompile the REPL integration functions.
        mock_repl = REPL.LineEditREPL(
            REPL.Terminals.TTYTerminal("", stdin, stdout, stderr), true
        )
        mock_repl.interface = REPL.setup_interface(mock_repl)
        _init_pager_repl_mode(mock_repl)
        _register_help_shortcuts(mock_repl)

        a = vcat(reshape(fill(0.1986, 100), 1, :), zeros(100, 100))
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
        # Exit the pager directly from search mode. Standalone Escape is exercised below
        # without racing the following quit byte.
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
        TerminalPager._decode_keystroke(collect(codeunits("\e[B")))
        TerminalPager._try_read_keystroke!(PagerInput(IOBuffer("j")))
        TerminalPager._read_keystroke!(PagerInput(IOBuffer("\e")))

        burst_input = IOBuffer("jj")
        burst_term = REPL.Terminals.TTYTerminal("", burst_input, devnull, devnull)
        burst_layout = TextViewLayout(fill("line", 20))
        burst_pager = Pager(;
            term = burst_term,
            buf = IOContext(IOBuffer(), :color => false),
            input = PagerInput(burst_input),
            display_size = displaysize(devnull),
            num_lines = 20,
            cropped_lines = 10,
            text_layout = burst_layout,
        )
        burst_key = TerminalPager._read_keystroke!(burst_pager.input)
        burst_action = TerminalPager._pager_key_process!(burst_pager, burst_key)
        TerminalPager._coalesce_navigation!(burst_pager, burst_action)
        TerminalPager._view!(burst_pager)

        for prepared_lines in (
            ["plain text", "second line"],
            ["Unicode α界", "combining e\u0301"],
            ["\e[31mANSI red\e[0m", "search search"],
        )
            prepared_layout = TextViewLayout(prepared_lines)
            TerminalPager._pager_content_fits(prepared_layout, (10, 40))
            TerminalPager._assemble_yank_text(prepared_layout, [2, 1, 2])
            prepared_layout[1]
            length(prepared_layout)
            prepared_matches = string_search_per_line(prepared_layout, r"search")
            active_location = isempty(prepared_matches) ? (0, 0) : (2, 1)
            textview(
                devnull,
                prepared_layout,
                (1, -1, 1, -1);
                active_match = 0,
                active_match_location = active_location,
                maximum_number_of_columns = 40,
                maximum_number_of_lines = 10,
                search_matches = prepared_matches,
            )
        end
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
