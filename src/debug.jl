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

    # Switch the terminal to raw mode, meaning that every keystroke is immediately passed to
    # us instead of waiting for <return>.
    REPL.Terminals.raw!(term, true)

    write(term.out_stream, "Type any key to echo the processed keycode. Hit q to exit.\n\n")

    try
        while true
            k = _jlgetch(term.in_stream)
            println(k)
            k.value == "q" && break
        end
    finally
        REPL.Terminals.raw!(term, false)
    end

    return nothing
end
