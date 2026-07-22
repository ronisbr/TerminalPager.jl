## Description #############################################################################
#
# Functions related to input handling. This code was adapted from TextUserInterfaces.jl.
#
############################################################################################

include("keycodes.jl")

const _MAX_KEYSTROKE_BYTES = 32
const _KEYCODE_BYTES = [(collect(codeunits(code)), key) for (code, key) in keycodes]

"""
    _decode_keystroke(prefix::Vector{UInt8}) ->
        Tuple{Symbol, Union{Nothing, Keystroke}, Int}

Decode one package-owned byte prefix without reading from an input stream. The status is
`:complete` or `:incomplete`; the integer is the number of bytes consumed by one key.

# Arguments

- `prefix::Vector{UInt8}`: Buffered bytes beginning with the next keystroke.
"""
function _decode_keystroke(prefix::Vector{UInt8})
    isempty(prefix) && return :incomplete, nothing, 0
    if length(prefix) >= _MAX_KEYSTROKE_BYTES
        return (
            :complete,
            Keystroke(; raw = _raw_bytes(prefix), value = "<undefined>"),
            _MAX_KEYSTROKE_BYTES,
        )
    end

    first_byte = prefix[1]
    first_byte == 0x1b && return _decode_escape(prefix)
    return _decode_scalar(prefix, 1)
end

"""
    _decode_escape(prefix::Vector{UInt8}) ->
        Tuple{Symbol, Union{Nothing, Keystroke}, Int}

Decode an escape-sequence prefix without performing IO.

# Arguments

- `prefix::Vector{UInt8}`: Buffered bytes beginning with an escape byte.
"""
function _decode_escape(prefix::Vector{UInt8})
    for (code, key) in _KEYCODE_BYTES
        length(prefix) >= length(code) || continue
        if @views prefix[1:length(code)] == code
            return :complete, key, length(code)
        end
    end

    for (code, _) in _KEYCODE_BYTES
        length(prefix) < length(code) || continue
        if @views prefix == code[1:length(prefix)]
            return :incomplete, nothing, 0
        end
    end

    length(prefix) == 1 && return :incomplete, nothing, 0

    offset = length(prefix) >= 2 && prefix[2] == 0x1b ? 2 : 1
    if length(prefix) >= offset + 2 && prefix[offset + 1] in (0x5b, 0x4f)
        final_index = findfirst(
            byte -> 0x40 <= byte <= 0x7e, @view(prefix[(offset + 2):end])
        )
        isnothing(final_index) && return :incomplete, nothing, 0
        consumed = offset + 1 + final_index
        bytes = prefix[1:consumed]
        return (
            :complete, Keystroke(; raw = _raw_bytes(bytes), value = "<undefined>"), consumed
        )
    end

    status, scalar, consumed = _decode_scalar(prefix, 2)
    status === :incomplete && return status, nothing, 0
    scalar.value == "<undefined>" && return status, scalar, consumed + 1
    key = Keystroke(;
        raw = "\e" * scalar.raw,
        value = scalar.value,
        alt = true,
        ctrl = scalar.ctrl,
        shift = scalar.shift,
    )
    return :complete, key, consumed + 1
end

"""
    _decode_scalar(prefix::Vector{UInt8}, offset::Int) ->
        Tuple{Symbol, Union{Nothing, Keystroke}, Int}

Decode one ASCII/control or UTF-8 scalar beginning at `offset`.

# Arguments

- `prefix::Vector{UInt8}`: Buffered bytes containing the scalar.
- `offset::Int`: One-based byte index where decoding starts.
"""
function _decode_scalar(prefix::Vector{UInt8}, offset::Int)
    length(prefix) < offset && return :incomplete, nothing, 0
    first_byte = prefix[offset]
    first_byte < 0x80 && return :complete, _ascii_keystroke(first_byte), 1

    num_bytes = if 0xc2 <= first_byte <= 0xdf
        2
    elseif 0xe0 <= first_byte <= 0xef
        3
    elseif 0xf0 <= first_byte <= 0xf4
        4
    else
        key = Keystroke(; raw = string(first_byte), value = "<undefined>")
        return :complete, key, 1
    end

    length(prefix) - offset + 1 < num_bytes && return :incomplete, nothing, 0
    bytes = prefix[offset:(offset + num_bytes - 1)]
    if !_valid_utf8(bytes)
        key = Keystroke(; raw = _raw_bytes(bytes), value = "<undefined>")
        return :complete, key, 1
    end
    key = Keystroke(; raw = _raw_bytes(bytes), value = String(copy(bytes)))
    return :complete, key, num_bytes
end

"""
    _ascii_keystroke(byte::UInt8) -> Keystroke

Convert one ASCII or control byte into a keystroke.

# Arguments

- `byte::UInt8`: ASCII or control byte to convert.
"""
function _ascii_keystroke(byte::UInt8)
    value = if byte == 0x04
        "<eot>"
    elseif byte == 0x09
        "<tab>"
    elseif byte in (0x0a, 0x0d)
        "<enter>"
    elseif byte == 0x15
        "<shiftin>"
    elseif byte == 0x7f
        "<backspace>"
    else
        string(Char(byte))
    end
    return Keystroke(; raw = string(UInt32(byte)), value = value)
end

"""
    _valid_utf8(bytes::Vector{UInt8}) -> Bool

Return whether `bytes` is one valid two- to four-byte UTF-8 scalar.

# Arguments

- `bytes::Vector{UInt8}`: Candidate encoded scalar.
"""
function _valid_utf8(bytes::Vector{UInt8})
    all(byte -> 0x80 <= byte <= 0xbf, @view(bytes[2:end])) || return false
    first_byte = bytes[1]
    second_byte = bytes[2]
    first_byte == 0xe0 && second_byte < 0xa0 && return false
    first_byte == 0xed && second_byte > 0x9f && return false
    first_byte == 0xf0 && second_byte < 0x90 && return false
    first_byte == 0xf4 && second_byte > 0x8f && return false
    return true
end

"""
    _raw_bytes(bytes::Vector{UInt8}) -> String

Format bytes using the legacy raw-keystroke representation.

# Arguments

- `bytes::Vector{UInt8}`: Bytes to format.
"""
_raw_bytes(bytes::Vector{UInt8}) = join(string.(bytes), ", ")

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
    _take_decoded!(input::PagerInput, key::Keystroke, consumed::Int) -> Keystroke

Clear the consumed prefix and return `key`.

# Arguments

- `input::PagerInput`: Input state whose prefix is updated.
- `key::Keystroke`: Decoded keystroke to return.
- `consumed::Int`: Number of leading prefix bytes to remove.
"""
function _take_decoded!(input::PagerInput, key::Keystroke, consumed::Int)
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
    if !isnothing(input.pending)
        key = input.pending
        input.pending = nothing
        return key
    end

    while true
        status, key, consumed = _decode_keystroke(input.prefix)
        status === :complete && return _take_decoded!(input, key, consumed)

        if input.prefix == UInt8[0x1b]
            _try_append_available!(input) ||
                return _take_decoded!(input, Keystroke(; raw = "\e", value = "<esc>"), 1)
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
    if !isnothing(input.pending)
        key = input.pending
        input.pending = nothing
        return key
    end

    while true
        status, key, consumed = _decode_keystroke(input.prefix)
        status === :complete && return _take_decoded!(input, key, consumed)
        _try_append_available!(input) || return nothing
    end
end

"""
    _jlgetch(stream::IO) -> Keystroke

Compatibility wrapper that waits for one keystroke from `stream`.

# Arguments

- `stream::IO`: Input stream from which to read the keystroke.
"""
_jlgetch(@nospecialize(stream::IO)) = _read_keystroke!(PagerInput(stream))
