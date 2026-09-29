using REPL
using Test
using TerminalPager

"""
    _create_pagerd(str::AbstractString) -> TerminalPager.Pager

Construct a pager for internal tests.

# Arguments

- `str::AbstractString`: Provide the pager text.
"""
function _create_pagerd(str::AbstractString)
    text_layout = TerminalPager.TextViewLayout(split(str, '\n'))
    matches = NTuple{4, Int}[]
    term = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)
    iobuf = IOBuffer()
    buf = IOContext(iobuf, :color => get(stdout, :color, true))

    pagerd = TerminalPager.Pager(;
        buf = buf,
        display_config = TerminalPager._display_config(),
        display_size = displaysize(term.out_stream),
        num_lines = length(text_layout),
        start_column = 1,
        start_row = 1,
        term = term,
        text_layout = text_layout,
    )

    return pagerd
end

"""
    TypedInput

Represent an input stream whose keystrokes arrive one at a time, as typed keys do: only the
bytes of the keystroke being read are available without blocking.

# Fields

- `chunks::Vector{Vector{UInt8}}`: Bytes of each arrival, in order.
- `chunk::Int`: Index of the arrival being read.
- `position::Int`: Index of the next byte of the arrival being read.
"""
mutable struct TypedInput <: IO
    chunks::Vector{Vector{UInt8}}
    chunk::Int
    position::Int
end

"""
    TypedInput(chunks::AbstractVector{<:AbstractString}) -> TypedInput
    TypedInput(text::AbstractString) -> TypedInput

Create an input stream that delivers each entry of `chunks` at once, like a pasted text, or
each keystroke of `text` on its own, like typed keys.

# Arguments

- `chunks::AbstractVector{<:AbstractString}`: Text of each arrival.
- `text::AbstractString`: Keystrokes to split with the decoder of the pager.
"""
function TypedInput(chunks::AbstractVector{<:AbstractString})
    return TypedInput([collect(codeunits(chunk)) for chunk in chunks], 1, 1)
end

function TypedInput(text::AbstractString)
    bytes = collect(codeunits(text))
    chunks = String[]

    while !isempty(bytes)
        status, _, consumed = TerminalPager._decode_keystroke(bytes)
        num_bytes = status === :complete ? consumed : length(bytes)
        push!(chunks, String(bytes[1:num_bytes]))
        bytes = bytes[(num_bytes + 1):end]
    end

    return TypedInput(chunks)
end

"""
    Base.bytesavailable(io::TypedInput) -> Int

Return the number of unread bytes of the arrival being read.

# Arguments

- `io::TypedInput`: Input stream to inspect.
"""
function Base.bytesavailable(io::TypedInput)
    io.chunk > length(io.chunks) && return 0
    return length(io.chunks[io.chunk]) - io.position + 1
end

"""
    Base.read(io::TypedInput, ::Type{UInt8}) -> UInt8

Read the next byte of `io`, waiting for the next arrival when the current one was read.

# Arguments

- `io::TypedInput`: Input stream to read.
"""
function Base.read(io::TypedInput, ::Type{UInt8})
    while (io.chunk <= length(io.chunks)) && (io.position > length(io.chunks[io.chunk]))
        io.chunk += 1
        io.position = 1
    end

    io.chunk > length(io.chunks) && throw(EOFError())

    byte = io.chunks[io.chunk][io.position]
    io.position += 1

    return byte
end

include("./internals/screen.jl")
include("./internals/redraw.jl")
include("./internals/key_bindings.jl")
include("./internals/key_processing.jl")
include("./internals/view.jl")
include("./internals/help_key_binding.jl")
include("./internals/help.jl")
include("./internals/performance_state.jl")
include("./internals/repl_mode.jl")
include("./internals/search.jl")
include("./internals/empty_text.jl")
include("./internals/caches.jl")
include("./internals/command_line.jl")
include("./internals/ruler.jl")
include("./internals/visual_mode.jl")
include("./internals/input_coalescing.jl")
include("./internals/input_tables.jl")
include("./internals/rendering.jl")
include("./internals/status_bar.jl")
include("./internals/faces.jl")
include("./internals/debug.jl")
