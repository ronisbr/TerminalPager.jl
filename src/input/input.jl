## Description #############################################################################
#
# Functions related to input handling. This code was adapted from TextUserInterfaces.jl.
#
############################################################################################

include("keycodes.jl")

const _MAX_KEYSTROKE_BYTES = 32

# The escape sequences are matched by packing their bytes into an integer, so that a keypress
# costs a handful of dictionary lookups instead of a linear scan over the whole table. Scanning
# it took roughly 700 array comparisons per arrow key, because the decoder runs again after
# every byte that arrives.
#
# The packing uses one byte per sequence byte plus the length in the highest byte, which makes
# it unambiguous. It only works because every sequence in `keycodes` is short.
const _MIN_KEYCODE_BYTES = minimum(ncodeunits, keys(keycodes))
const _MAX_KEYCODE_BYTES = maximum(ncodeunits, keys(keycodes))

@assert _MAX_KEYCODE_BYTES <= 7 "A keycode does not fit in the packed representation."

"""
    _pack_keycode(bytes, len::Int) -> UInt64

Pack the first `len` bytes of `bytes` and `len` itself into a single integer.

# Arguments

- `bytes`: Byte storage holding an escape sequence.
- `len::Int`: Number of leading bytes to pack, at most `_MAX_KEYCODE_BYTES`.
"""
@inline function _pack_keycode(bytes, len::Int)
    packed = UInt64(len) << 56

    @inbounds for i in 1:len
        packed |= UInt64(bytes[i]) << (8 * (i - 1))
    end

    return packed
end

const _KEYCODE_EXACT = Dict{UInt64, Keystroke}(
    _pack_keycode(codeunits(code), ncodeunits(code)) => key for (code, key) in keycodes
)

# Every proper prefix of every sequence, so that an incomplete sequence is recognized without
# scanning the table either.
const _KEYCODE_PREFIXES = Set{UInt64}(
    _pack_keycode(codeunits(code), len) for code in keys(keycodes) for
    len in 1:(ncodeunits(code) - 1)
)

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
    num_bytes = length(prefix)

    # No sequence in the table is a prefix of another one, hence at most one length can match.
    for len in _MIN_KEYCODE_BYTES:min(num_bytes, _MAX_KEYCODE_BYTES)
        key = get(_KEYCODE_EXACT, _pack_keycode(prefix, len), nothing)
        isnothing(key) || return :complete, key, len
    end

    if num_bytes < _MAX_KEYCODE_BYTES
        _pack_keycode(prefix, num_bytes) ∈ _KEYCODE_PREFIXES &&
            return :incomplete, nothing, 0
    end

    num_bytes == 1 && return :incomplete, nothing, 0

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
_ascii_keystroke(byte::UInt8) = @inbounds _ASCII_KEYSTROKES[byte + 1]

"""
    _build_ascii_keystroke(byte::UInt8) -> Keystroke

Build the keystroke for one ASCII or control byte.

This is only used to fill `_ASCII_KEYSTROKES` when the package is loaded.

# Arguments

- `byte::UInt8`: ASCII or control byte to convert.
"""
function _build_ascii_keystroke(byte::UInt8)
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

# Every ASCII keystroke is precomputed, so that a keypress is a table lookup. Building them on
# demand allocated roughly 100 bytes at every keypress.
const _ASCII_KEYSTROKES = Keystroke[_build_ascii_keystroke(UInt8(i)) for i in 0x00:0x7f]

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
function _raw_bytes(bytes::Vector{UInt8})
    isempty(bytes) && return ""

    io = IOBuffer()

    @inbounds for i in eachindex(bytes)
        i > 1 && write(io, ", ")
        _write_decimal(io, Int(bytes[i]))
    end

    return String(take!(io))
end

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

        # A lone escape byte is ambiguous: it can be the ESC key or the beginning of an escape
        # sequence. Hence, we look ahead without blocking instead of waiting for a byte that
        # may never arrive. Notice that comparing against `UInt8[0x1b]` would allocate a
        # vector at every iteration of this loop.
        if (length(input.prefix) == 1) && (@inbounds input.prefix[1] == 0x1b)
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
