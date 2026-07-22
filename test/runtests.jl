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

include("./internals/key_bindings.jl")
include("./internals/key_processing.jl")
include("./internals/view.jl")
include("./internals/help_key_binding.jl")
include("./internals/help.jl")
include("./internals/performance_state.jl")
include("./internals/input_coalescing.jl")
