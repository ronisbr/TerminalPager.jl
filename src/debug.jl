## Description #############################################################################
#
# Functions for debugging key input.
#
############################################################################################

"""
    debug_keycode(; kwargs...) -> Nothing

Read and print decoded keystrokes in raw terminal mode until the user presses `q`.

The terminal is set to the modes the pager uses, so that the keystrokes are the ones the
pager receives: the application cursor key mode and, when the preference `"mouse"` is
enabled, the mouse reporting.

# Keywords

- `_terminal_factory::Any`: Callable object that creates the terminal.
    (**Default**: `() -> REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)`)
- `_raw_runner::Any`: Callable object that runs the reading loop in raw mode.
    (**Default**: `_with_raw_mode`)
"""
function debug_keycode(;
    _terminal_factory = () -> REPL.Terminals.TTYTerminal("", stdin, stdout, stderr),
    _raw_runner = _with_raw_mode,
)
    # Initialize the terminal.
    term = _terminal_factory()
    out = term.out_stream

    # The input state must survive the whole session. Creating one per keystroke dropped
    # the bytes buffered by the lookahead, so exactly the escape sequences this tool exists
    # to diagnose were reported as separate keystrokes.
    input = PagerInput(term.in_stream)

    # Switch the terminal to raw mode, meaning that every keystroke is immediately passed to
    # us instead of waiting for <return>.
    _raw_runner(term) do
        # Raw mode does not translate the line feed, so the carriage return must be written
        # explicitly. Otherwise, every line starts where the previous one ended.
        write(out, "Type any key to echo the processed keycode. Hit q to exit.\r\n\r\n")

        # The cursor key mode changes the sequences sent by the arrow, Home, and End keys,
        # and the mouse reporting sends the mouse events. Without them, this tool showed
        # sequences the pager never receives. As in `_pager!`, each flag is set before the
        # write, so that a write that partially reached the terminal is still undone.
        cursor_key_mode_enabled = false
        mouse_enabled = false

        try
            cursor_key_mode_enabled = true
            _turn_on_cursor_key_mode(out)

            if _get_preference("mouse")::Bool
                mouse_enabled = true
                _turn_on_mouse(out)
            end

            while true
                k = _read_keystroke!(input)
                print(out, k, "\r\n")
                k.value == "q" && break
            end
        finally
            _restore_terminal(
                out;
                mouse = mouse_enabled,
                clear_status_row = false,
                show_cursor = false,
                alternate_screen = false,
                cursor_key_mode = cursor_key_mode_enabled,
            )
        end
    end

    return nothing
end
