## Description #############################################################################
#
# Functions for debugging key input.
#
############################################################################################

"""
    debug_keycode(; kwargs...) -> Nothing

Read and print decoded keystrokes in raw terminal mode until the user presses `q`.

Each line shows the value and the modifiers of the keystroke, which are the arguments of
[`set_keybinding`](@ref), the position of a mouse event, and the bytes the keystroke was
decoded from. The terminal is set to the modes the pager uses, so that the keystrokes are
the ones the pager receives: the application cursor key mode and, when the preference
`"mouse"` is enabled, the mouse reporting.

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

    # The keystrokes do not keep the bytes they were decoded from, so the input records
    # them.
    record = UInt8[]
    input.record = record

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
                _write_debug_keystroke(out, k, record)
                empty!(record)
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

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _write_debug_keystroke(io::IO, k::Keystroke, bytes::Vector{UInt8}) -> Nothing

Write a line to `io` describing the keystroke `k`, decoded from `bytes`, like
`value = "<left>", alt = true, ctrl = false, shift = false, bytes = [27, 27, 91, 68]`.

# Arguments

- `io::IO`: Terminal output stream to update.
- `k::Keystroke`: Decoded keystroke.
- `bytes::Vector{UInt8}`: Bytes the keystroke was decoded from.
"""
function _write_debug_keystroke(io::IO, k::Keystroke, bytes::Vector{UInt8})
    print(io, "value = ", repr(k.value), ", alt = ", k.alt, ", ctrl = ", k.ctrl)
    print(io, ", shift = ", k.shift)

    # The position is only meaningful for the mouse events.
    (k.x > 0) && print(io, ", x = ", k.x, ", y = ", k.y)

    # Raw mode does not translate the line feed, so the carriage return is written too.
    print(io, ", bytes = [", _raw_bytes(bytes), "]\r\n")

    return nothing
end

"""
    _raw_bytes(bytes::Vector{UInt8}) -> String

Format `bytes` as their decimal values separated by commas, like `27, 91, 66`.

# Arguments

- `bytes::Vector{UInt8}`: Bytes to format.
"""
function _raw_bytes(bytes::Vector{UInt8})
    isempty(bytes) && return ""

    io = IOBuffer()

    @inbounds for i in eachindex(bytes)
        i > 1 && write(io, ", ")
        _write_decimal(io, Int(bytes[i]))
    end

    return String(take!(io))
end
