using REPL
using Test
using TerminalPager

function _create_pagerd(str::AbstractString)
    lines = split(str, '\n')
    matches = NTuple{4, Int}[]
    term = REPL.Terminals.TTYTerminal("", stdin, stdout, stderr)
    iobuf = IOBuffer()
    buf = IOContext(iobuf, :color => get(stdout, :color, true))
    pagerd = TerminalPager.Pager(term = term,
                                 buf = buf,
                                 display_size = displaysize(term.out_stream),
                                 start_row = 1,
                                 start_col = 1,
                                 lines = lines,
                                 num_lines = length(lines))

    return pagerd
end

include("./internals/key_bindings.jl")
include("./internals/key_processing.jl")
include("./internals/view.jl")
