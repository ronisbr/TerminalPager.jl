using REPL
using Test
using TerminalPager

function _create_pagerd(str::AbstractString)
    lines   = split(str, '\n')
    matches = NTuple{4, Int}[]
    term    = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)
    iobuf   = IOBuffer()
    buf     = IOContext(iobuf, :color => get(stdout, :color, true))

    pagerd = TerminalPager.Pager(
        buf          = buf,
        display_size = displaysize(term.out_stream),
        lines        = lines,
        num_lines    = length(lines),
        start_column = 1,
        start_row    = 1,
        term         = term
    )

    return pagerd
end

include("./internals/key_bindings.jl")
include("./internals/key_processing.jl")
include("./internals/view.jl")
include("./internals/help_key_binding.jl")
