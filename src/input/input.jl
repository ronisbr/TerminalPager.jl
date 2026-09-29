## Description #############################################################################
#
# Functions related to input handling. This code was adapted from TextUserInterfaces.jl.
#
############################################################################################

const _MAX_KEYSTROKE_BYTES = 32

"""
    _INCOMPLETE_KEYSTROKE

Sentinel keystroke carried by the result of decoding an incomplete byte prefix.

Returning `nothing` for the key instead made the decoder return a union of tuple types,
which is heap-allocated at the reduced optimization level of this package, costing 80
bytes per keystroke.
"""
const _INCOMPLETE_KEYSTROKE = Keystroke()

# Result returned while the buffered bytes are still incomplete, shared by every return
# site of the decoder.
const _DECODE_INCOMPLETE = (:incomplete, _INCOMPLETE_KEYSTROKE, 0)

# Keystroke synthesized for a lone ESC, which is not followed by the rest of a sequence.
const _ESC_KEYSTROKE = Keystroke(; value = "<esc>")

# Largest parameter of an escape sequence kept by the parser. Every parameter of a key is
# far smaller. Saturating the larger ones keeps a malformed sequence from overflowing into
# the parameters of a valid key.
const _MAX_SEQUENCE_PARAMETER = 1_000

"""
    _decode_keystroke(prefix::Vector{UInt8}) -> Tuple{Symbol, Keystroke, Int}

Decode one package-owned byte prefix without reading from an input stream. The status is
`:complete` or `:incomplete`; the integer is the number of bytes consumed by one key. An
incomplete result carries the sentinel [`_INCOMPLETE_KEYSTROKE`](@ref) and zero consumed
bytes.

# Arguments

- `prefix::Vector{UInt8}`: Buffered bytes beginning with the next keystroke.
"""
function _decode_keystroke(prefix::Vector{UInt8})
    isempty(prefix) && return _DECODE_INCOMPLETE
    length(prefix) >= _MAX_KEYSTROKE_BYTES && return _undefined_key(_MAX_KEYSTROKE_BYTES)

    first_byte = prefix[1]
    first_byte == 0x1b && return _decode_escape(prefix)
    return _decode_scalar(prefix, 1)
end

"""
    _decode_escape(prefix::Vector{UInt8}) -> Tuple{Symbol, Keystroke, Int}

Decode an escape-sequence prefix without performing IO.

The sequences of the special keys are parsed following the xterm conventions instead of
being looked up in a table, so that every combination of modifiers is decoded. An ESC
followed by a character is that character with ALT.

# Arguments

- `prefix::Vector{UInt8}`: Buffered bytes beginning with an escape byte.
"""
function _decode_escape(prefix::Vector{UInt8})
    num_bytes = length(prefix)
    num_bytes == 1 && return _DECODE_INCOMPLETE

    second_byte = prefix[2]
    second_byte == UInt8('[') && return _decode_csi(prefix, 1, false)
    second_byte == UInt8('O') && return _decode_ss3(prefix, 1, false)

    # Some terminals send the ALT-modified special keys as an ESC followed by the sequence
    # of the key.
    if second_byte == 0x1b
        num_bytes == 2 && return _DECODE_INCOMPLETE
        third_byte = prefix[3]
        third_byte == UInt8('[') && return _decode_csi(prefix, 2, true)
        third_byte == UInt8('O') && return _decode_ss3(prefix, 2, true)
    end

    status, scalar, consumed = _decode_scalar(prefix, 2)
    status === :incomplete && return _DECODE_INCOMPLETE
    scalar.value == "<undefined>" && return status, scalar, consumed + 1
    key = Keystroke(;
        value = scalar.value,
        alt = true,
        ctrl = scalar.ctrl,
        shift = scalar.shift,
    )
    return :complete, key, consumed + 1
end

"""
    _decode_csi(prefix::Vector{UInt8}, start::Int, alt::Bool) -> Tuple{Symbol, Keystroke, Int}

Decode the CSI sequence `\\e[` that begins at the index `start` of `prefix`, adding ALT to
its modifiers if `alt` is `true`. The consumed bytes are counted from the beginning of
`prefix`.

A key is `\\e[<number>;<modifier><letter>` or `\\e[<number>;<modifier>~`, where both
numbers are optional, and the modifier is one plus the sum of 1 for SHIFT, 2 for ALT, 4 for
CTRL, and 8 for META, which is reported as ALT. The SGR mouse reports begin with `\\e[<`.
Any other sequence, such as a private one or a cursor position report, is an undefined key,
which consumes the sequence up to its final byte.

# Arguments

- `prefix::Vector{UInt8}`: Buffered bytes containing the sequence.
- `start::Int`: Index of the escape byte that begins the sequence.
- `alt::Bool`: Whether the sequence was preceded by an ESC that adds ALT.
"""
function _decode_csi(prefix::Vector{UInt8}, start::Int, alt::Bool)
    num_bytes = length(prefix)
    first_index = start + 2
    num_bytes < first_index && return _DECODE_INCOMPLETE
    prefix[first_index] == UInt8('<') && return _decode_mouse(prefix, start)

    # Parse the parameters, which are decimal numbers separated by semicolons, up to the
    # final byte. A missing parameter is `-1`.
    num_parameters = 1
    first_parameter = -1
    second_parameter = -1
    parameter = -1
    is_key = true
    final_index = 0

    @inbounds for i in first_index:num_bytes
        byte = prefix[i]

        if UInt8('0') <= byte <= UInt8('9')
            digit = Int(byte - UInt8('0'))
            parameter = min(10max(parameter, 0) + digit, _MAX_SEQUENCE_PARAMETER)
        elseif byte == UInt8(';')
            (num_parameters == 1) && (first_parameter = parameter)
            (num_parameters == 2) && (second_parameter = parameter)
            num_parameters += 1
            parameter = -1
        elseif 0x40 <= byte <= 0x7e
            final_index = i
            break
        elseif 0x20 <= byte <= 0x3f
            # The private markers `<=>?`, the `:` of the sub-parameters, and the
            # intermediate bytes belong to sequences that are not keys.
            is_key = false
        else
            # A control byte cannot be part of the sequence, so the sequence is broken. It
            # ends before the byte, which is decoded as the next keystroke.
            return _undefined_key(i - 1)
        end
    end

    final_index == 0 && return _DECODE_INCOMPLETE

    (num_parameters == 1) && (first_parameter = parameter)
    (num_parameters == 2) && (second_parameter = parameter)
    (is_key && (num_parameters <= 2)) || return _undefined_key(final_index)

    final_byte = prefix[final_index]

    value, shift = if final_byte == UInt8('~')
        _csi_tilde_key(first_parameter), false
    elseif first_parameter <= 1
        # The letter keys have no number, or `1` when the modifier follows it. Any other
        # number belongs to another sequence, like the cursor position report `\e[24;80R`.
        _csi_letter_key(final_byte), final_byte == UInt8('Z')
    else
        "", false
    end

    isempty(value) && return _undefined_key(final_index)

    modifier = second_parameter < 0 ? 1 : second_parameter
    (1 <= modifier <= 16) || return _undefined_key(final_index)

    return :complete, _modified_key(value, modifier, alt, shift), final_index
end

"""
    _decode_ss3(prefix::Vector{UInt8}, start::Int, alt::Bool) -> Tuple{Symbol, Keystroke, Int}

Decode the SS3 sequence `\\eO` that begins at the index `start` of `prefix`, adding ALT to
its modifiers if `alt` is `true`. The consumed bytes are counted from the beginning of
`prefix`.

A key is `\\eO<modifier><letter>`, where the modifier is optional and encoded as in
[`_decode_csi`](@ref). A byte that is neither a digit nor a final byte ends the sequence as
an undefined key, and it is decoded as the next keystroke.

# Arguments

- `prefix::Vector{UInt8}`: Buffered bytes containing the sequence.
- `start::Int`: Index of the escape byte that begins the sequence.
- `alt::Bool`: Whether the sequence was preceded by an ESC that adds ALT.
"""
function _decode_ss3(prefix::Vector{UInt8}, start::Int, alt::Bool)
    num_bytes = length(prefix)
    modifier = -1

    @inbounds for i in (start + 2):num_bytes
        byte = prefix[i]

        if UInt8('0') <= byte <= UInt8('9')
            digit = Int(byte - UInt8('0'))
            modifier = min(10max(modifier, 0) + digit, _MAX_SEQUENCE_PARAMETER)
            continue
        end

        (0x40 <= byte <= 0x7e) || return _undefined_key(i - 1)

        value = _ss3_key(byte)
        isempty(value) && return _undefined_key(i)

        modifier = modifier < 0 ? 1 : modifier
        (1 <= modifier <= 16) || return _undefined_key(i)

        return :complete, _modified_key(value, modifier, alt, false), i
    end

    return _DECODE_INCOMPLETE
end

"""
    _decode_mouse(prefix::Vector{UInt8}, start::Int = 1) -> Tuple{Symbol, Keystroke, Int}

Decode the SGR mouse report that begins at the index `start` of `prefix` without performing
IO. A report is `\\e[<b;x;yM` for a press or a wheel movement and `\\e[<b;x;ym` for a
release, where `b` encodes the button and the modifiers and `x` and `y` are the one-based
column and row. The consumed bytes are counted from the beginning of `prefix`.

The keystroke value is `<wheel_up>`, `<wheel_down>`, `<wheel_left>`, `<wheel_right>`,
`<mouse_press>`, `<mouse_press_middle>`, `<mouse_press_right>`, `<mouse_release>`, or
`<mouse_drag>`. A malformed report is returned as an undefined key.

# Arguments

- `prefix::Vector{UInt8}`: Buffered bytes containing the report after `\\e[<`.
- `start::Int`: Index of the escape byte that begins the report.
    (**Default**: `1`)
"""
function _decode_mouse(prefix::Vector{UInt8}, start::Int = 1)
    num_bytes = length(prefix)
    first_index = start + 3
    final_index = 0

    @inbounds for i in first_index:num_bytes
        byte = prefix[i]

        if (byte == UInt8('M')) || (byte == UInt8('m'))
            final_index = i
            break
        elseif !((byte == UInt8(';')) || (UInt8('0') <= byte <= UInt8('9')))
            return _undefined_key(i)
        end
    end

    final_index == 0 && return _DECODE_INCOMPLETE

    # Parse the button code and the position.
    button = 0
    x = 0
    y = 0
    field = 1
    number = 0

    @inbounds for i in first_index:final_index
        byte = prefix[i]

        if (byte == UInt8(';')) || (i == final_index)
            (field == 1) && (button = number)
            (field == 2) && (x = number)
            (field == 3) && (y = number)
            field += 1
            number = 0
        else
            number = min(10number + Int(byte - UInt8('0')), _MAX_SEQUENCE_PARAMETER)
        end
    end

    field != 4 && return _undefined_key(final_index)

    value = if (button & 0x40) != 0
        ("<wheel_up>", "<wheel_down>", "<wheel_left>", "<wheel_right>")[(button & 0x03) + 1]
    elseif (button & 0x20) != 0
        "<mouse_drag>"
    elseif prefix[final_index] == UInt8('m')
        "<mouse_release>"
    else
        ("<mouse_press>", "<mouse_press_middle>", "<mouse_press_right>", "<undefined>")[
            (button & 0x03) + 1
        ]
    end

    key = Keystroke(;
        value = value,
        alt = (button & 0x08) != 0,
        ctrl = (button & 0x10) != 0,
        shift = (button & 0x04) != 0,
        x = x,
        y = y,
    )

    return :complete, key, final_index
end

"""
    _decode_scalar(prefix::Vector{UInt8}, offset::Int) -> Tuple{Symbol, Keystroke, Int}

Decode one ASCII/control or UTF-8 scalar beginning at `offset`.

# Arguments

- `prefix::Vector{UInt8}`: Buffered bytes containing the scalar.
- `offset::Int`: One-based byte index where decoding starts.
"""
function _decode_scalar(prefix::Vector{UInt8}, offset::Int)
    length(prefix) < offset && return _DECODE_INCOMPLETE
    first_byte = prefix[offset]
    first_byte < 0x80 && return :complete, _ascii_keystroke(first_byte), 1

    num_bytes = if 0xc2 <= first_byte <= 0xdf
        2
    elseif 0xe0 <= first_byte <= 0xef
        3
    elseif 0xf0 <= first_byte <= 0xf4
        4
    else
        return _undefined_key(1)
    end

    length(prefix) - offset + 1 < num_bytes && return _DECODE_INCOMPLETE
    _valid_utf8(prefix, offset, num_bytes) || return _undefined_key(1)

    last_index = offset + num_bytes - 1
    return :complete, Keystroke(; value = String(prefix[offset:last_index])), num_bytes
end

"""
    _ascii_keystroke(byte::UInt8) -> Keystroke

Convert one ASCII or control byte into a keystroke.

# Arguments

- `byte::UInt8`: ASCII or control byte to convert.
"""
_ascii_keystroke(byte::UInt8) = @inbounds _ASCII_KEYSTROKES[byte + 1]

"""
    _build_ascii_keystroke(byte::UInt8) -> Keystroke

Build the keystroke for one ASCII or control byte.

This is only used to fill `_ASCII_KEYSTROKES` when the package is loaded.

# Arguments

- `byte::UInt8`: ASCII or control byte to convert.
"""
function _build_ascii_keystroke(byte::UInt8)
    # These control bytes have their own names for historical reasons, and the `vi` key bindings
    # refer to them. Notice that `<shiftin>` is a misnomer: `0x15` is NAK, which is what CTRL-U
    # sends, whereas SHIFT-IN is `0x0f`.
    byte == 0x04 && return Keystroke(; value = "<eot>")
    byte == 0x09 && return Keystroke(; value = "<tab>")
    byte == 0x15 && return Keystroke(; value = "<shiftin>")
    byte == 0x7f && return Keystroke(; value = "<backspace>")
    byte in (0x0a, 0x0d) && return Keystroke(; value = "<enter>")

    # Every other control byte in this range is a CTRL combination with a letter. Reporting it
    # with `ctrl = false` and the raw control character as the value made the documented `ctrl`
    # keyword of `set_keybinding` impossible to match.
    if 0x01 <= byte <= 0x1a
        letter = Char(byte - 0x01 + UInt8('a'))
        return Keystroke(; value = string(letter), ctrl = true)
    end

    return Keystroke(; value = string(Char(byte)))
end

# Every ASCII keystroke is precomputed, so that a keypress is a table lookup. Building them on
# demand allocated roughly 100 bytes at every keypress.
const _ASCII_KEYSTROKES = Keystroke[_build_ascii_keystroke(UInt8(i)) for i in 0x00:0x7f]

"""
    _valid_utf8(bytes::Vector{UInt8}, offset::Int, num_bytes::Int) -> Bool

Return whether the `num_bytes` bytes of `bytes` beginning at `offset` are one valid two- to
four-byte UTF-8 scalar.

# Arguments

- `bytes::Vector{UInt8}`: Buffer containing the candidate encoded scalar.
- `offset::Int`: Index of the first byte of the scalar.
- `num_bytes::Int`: Number of bytes of the scalar, which `bytes` must hold.
"""
function _valid_utf8(bytes::Vector{UInt8}, offset::Int, num_bytes::Int)
    # An indexed loop avoids building a closure over a view on every non-ASCII keypress.
    @inbounds for i in (offset + 1):(offset + num_bytes - 1)
        0x80 <= bytes[i] <= 0xbf || return false
    end

    first_byte = bytes[offset]
    second_byte = bytes[offset + 1]
    first_byte == 0xe0 && second_byte < 0xa0 && return false
    first_byte == 0xed && second_byte > 0x9f && return false
    first_byte == 0xf0 && second_byte < 0x90 && return false
    first_byte == 0xf4 && second_byte > 0x8f && return false
    return true
end

############################################################################################
#                                  Escape Sequence Tables                                  #
############################################################################################

"""
    _csi_letter_key(final_byte::UInt8) -> String

Return the value of the key whose CSI sequence ends with the letter `final_byte`, or an
empty string if there is none.

# Arguments

- `final_byte::UInt8`: Final byte of the sequence.
"""
function _csi_letter_key(final_byte::UInt8)
    final_byte == UInt8('A') && return "<up>"
    final_byte == UInt8('B') && return "<down>"
    final_byte == UInt8('C') && return "<right>"
    final_byte == UInt8('D') && return "<left>"
    final_byte == UInt8('H') && return "<home>"
    final_byte == UInt8('F') && return "<end>"
    final_byte == UInt8('P') && return "<F1>"
    final_byte == UInt8('Q') && return "<F2>"
    final_byte == UInt8('R') && return "<F3>"
    final_byte == UInt8('S') && return "<F4>"

    # The terminals send SHIFT-TAB as `\e[Z`.
    final_byte == UInt8('Z') && return "<tab>"

    return ""
end

"""
    _csi_tilde_key(number::Int) -> String

Return the value of the key whose CSI sequence is `\\e[<number>~`, or an empty string if
there is none.

# Arguments

- `number::Int`: First parameter of the sequence, or `-1` if it is missing.
"""
function _csi_tilde_key(number::Int)
    # The Linux console, tmux, and rxvt send their own sequences for Home and End.
    number in (1, 7) && return "<home>"
    number in (4, 8) && return "<end>"
    number == 3 && return "<delete>"
    number == 5 && return "<pageup>"
    number == 6 && return "<pagedown>"
    number == 15 && return "<F5>"
    number == 17 && return "<F6>"
    number == 18 && return "<F7>"
    number == 19 && return "<F8>"
    number == 20 && return "<F9>"
    number == 21 && return "<F10>"
    number == 23 && return "<F11>"
    number == 24 && return "<F12>"
    return ""
end

"""
    _ss3_key(final_byte::UInt8) -> String

Return the value of the key whose SS3 sequence ends with `final_byte`, or an empty string if
there is none.

# Arguments

- `final_byte::UInt8`: Final byte of the sequence.
"""
function _ss3_key(final_byte::UInt8)
    # The pager enables the application cursor key mode, in which xterm-compatible terminals
    # send SS3 sequences for the arrows, Home, and End.
    final_byte == UInt8('A') && return "<up>"
    final_byte == UInt8('B') && return "<down>"
    final_byte == UInt8('C') && return "<right>"
    final_byte == UInt8('D') && return "<left>"
    final_byte == UInt8('H') && return "<home>"
    final_byte == UInt8('F') && return "<end>"
    final_byte == UInt8('P') && return "<F1>"
    final_byte == UInt8('Q') && return "<F2>"
    final_byte == UInt8('R') && return "<F3>"
    final_byte == UInt8('S') && return "<F4>"

    # Keys of the keypad in the application keypad mode.
    final_byte == UInt8('M') && return "<keypad_enter>"
    final_byte == UInt8('X') && return "<keypad_equal>"
    final_byte == UInt8('j') && return "<keypad_asterisk>"
    final_byte == UInt8('k') && return "<keypad_plus>"
    final_byte == UInt8('m') && return "<keypad_minus>"
    final_byte == UInt8('n') && return "<keypad_dot>"
    final_byte == UInt8('o') && return "<keypad_slash>"

    if UInt8('p') <= final_byte <= UInt8('y')
        return ("<keypad_0>", "<keypad_1>", "<keypad_2>", "<keypad_3>", "<keypad_4>",
            "<keypad_5>", "<keypad_6>", "<keypad_7>", "<keypad_8>", "<keypad_9>")[
            final_byte - UInt8('p') + 1
        ]
    end

    return ""
end

"""
    _modified_key(value::String, modifier::Int, alt::Bool, shift::Bool) -> Keystroke

Return the keystroke `value` with the modifiers encoded in the xterm `modifier`, adding ALT
if `alt` is `true` and SHIFT if `shift` is `true`.

# Arguments

- `value::String`: Value of the keystroke.
- `modifier::Int`: xterm modifier, which is one plus the sum of 1 for SHIFT, 2 for ALT, 4
    for CTRL, and 8 for META, reported as ALT.
- `alt::Bool`: Whether to add ALT.
- `shift::Bool`: Whether to add SHIFT.
"""
function _modified_key(value::String, modifier::Int, alt::Bool, shift::Bool)
    bits = modifier - 1

    return Keystroke(;
        value = value,
        alt = alt || ((bits & 0x02) != 0) || ((bits & 0x08) != 0),
        ctrl = (bits & 0x04) != 0,
        shift = shift || ((bits & 0x01) != 0),
    )
end

"""
    _undefined_key(consumed::Int) -> Tuple{Symbol, Keystroke, Int}

Return the decoding result of an undefined key that consumes `consumed` bytes.

# Arguments

- `consumed::Int`: Number of bytes consumed by the key.
"""
_undefined_key(consumed::Int) = (:complete, Keystroke(; value = "<undefined>"), consumed)

############################################################################################
#                                     Input Handling                                       #
############################################################################################

"""
    _try_append_available!(input::PagerInput) -> Bool

Append exactly one advertised byte without blocking. Unsupported lookahead is disabled.

# Arguments

- `input::PagerInput`: Input state to update.
"""
function _try_append_available!(input::PagerInput)
    input.can_lookahead || return false
    available = try
        bytesavailable(input.stream)
    catch
        input.can_lookahead = false
        return false
    end
    available > 0 || return false

    byte = read(input.stream, UInt8)
    push!(input.prefix, byte)
    return true
end

"""
    _has_buffered_input(input::PagerInput) -> Bool

Return whether `input` holds a keystroke that can be read without waiting for the user: a
pending keystroke, the bytes of a partially decoded one, or bytes available in its stream.

# Arguments

- `input::PagerInput`: Input state to inspect.
"""
function _has_buffered_input(input::PagerInput)
    isnothing(input.pending) || return true
    isempty(input.prefix) || return true
    input.can_lookahead || return false

    # As in `_try_append_available!`, a stream without lookahead support disables it.
    return try
        bytesavailable(input.stream) > 0
    catch
        input.can_lookahead = false
        false
    end
end

"""
    _take_decoded!(input::PagerInput, key::Keystroke, consumed::Int) -> Keystroke

Clear the consumed prefix and return `key`. If `input` records the consumed bytes, they are
appended to its record.

# Arguments

- `input::PagerInput`: Input state whose prefix is updated.
- `key::Keystroke`: Decoded keystroke to return.
- `consumed::Int`: Number of leading prefix bytes to remove.
"""
function _take_decoded!(input::PagerInput, key::Keystroke, consumed::Int)
    # The field is loaded once, so that its type is known below. Otherwise, the compiler
    # cannot refine the type of a mutable field across two loads.
    record = input.record
    isnothing(record) || append!(record, @view(input.prefix[1:consumed]))

    deleteat!(input.prefix, 1:consumed)
    return key
end

"""
    _read_keystroke!(input::PagerInput) -> Keystroke

Read one keystroke, blocking one byte at a time and honoring pending boundary input.

# Arguments

- `input::PagerInput`: Input state to consume.
"""
function _read_keystroke!(input::PagerInput)
    # The pending field must be loaded exactly once. The compiler cannot refine the type of
    # a mutable field across two loads, so testing and reading it separately made this
    # function return a union, turning the key processing of the main loop into a dynamic
    # dispatch at every keystroke.
    pending = input.pending

    if !isnothing(pending)
        input.pending = nothing
        return pending
    end

    while true
        status, key, consumed = _decode_keystroke(input.prefix)
        status === :complete && return _take_decoded!(input, key, consumed)

        # An all-escape prefix is ambiguous: it can be one or two ESC keys or the beginning
        # of an escape sequence, since `"\e\e"` starts the ALT-modified arrow sequences.
        # Hence, we look ahead without blocking instead of waiting for a byte that may
        # never arrive. Waiting used to freeze the pager after two consecutive ESC keys.
        # Notice that comparing against `UInt8[0x1b]` would allocate a vector at every
        # iteration of this loop.
        prefix_length = length(input.prefix)

        if (1 <= prefix_length <= 2) && all(==(0x1b), input.prefix)
            _try_append_available!(input) ||
                return _take_decoded!(input, _ESC_KEYSTROKE, 1)
        else
            push!(input.prefix, read(input.stream, UInt8))
        end
    end
end

"""
    _try_read_keystroke!(input::PagerInput) -> Union{Nothing, Keystroke}

Read one already-buffered keystroke without blocking, retaining incomplete prefixes.

# Arguments

- `input::PagerInput`: Input state to inspect and consume.
"""
function _try_read_keystroke!(input::PagerInput)
    # See `_read_keystroke!` for why the pending field must be loaded exactly once.
    pending = input.pending

    if !isnothing(pending)
        input.pending = nothing
        return pending
    end

    while true
        status, key, consumed = _decode_keystroke(input.prefix)
        status === :complete && return _take_decoded!(input, key, consumed)
        _try_append_available!(input) || return nothing
    end
end
