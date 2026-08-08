## Description #############################################################################
#
# Functions for debugging key input.
#
############################################################################################

"""
    debug_keycode() -> Nothing

Read and print decoded keystrokes in raw terminal mode until the user presses `q`.
"""
function debug_keycode()
    # Initialize the terminal.
    term = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)

    # The input state must survive the whole session. Creating one per keystroke dropped
    # the bytes buffered by the lookahead, so exactly the escape sequences this tool exists
    # to diagnose were reported as separate keystrokes.
    input = PagerInput(term.in_stream)

    # Switch the terminal to raw mode, meaning that every keystroke is immediately passed to
    # us instead of waiting for <return>.
    REPL.Terminals.raw!(term, true)

    # Raw mode does not translate the line feed, so the carriage return must be written
    # explicitly. Otherwise, every line starts where the previous one ended.
    write(
        term.out_stream, "Type any key to echo the processed keycode. Hit q to exit.\r\n\r\n"
    )

    try
        while true
            k = _read_keystroke!(input)
            print(term.out_stream, k, "\r\n")
            k.value == "q" && break
        end
    finally
        REPL.Terminals.raw!(term, false)
    end

    return nothing
end
