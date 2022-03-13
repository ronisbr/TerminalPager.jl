function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    Base.precompile(Tuple{typeof(reset_keybindings)})   # time: 0.025076335
    Base.precompile(Tuple{typeof(set_keybinding),Char,Symbol})   # time: 0.021336425
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:term, :buf, :display_size, :start_row, :start_col, :lines, :num_lines), _A} where _A<:Tuple{REPL.Terminals.TTYTerminal, IOContext{IOBuffer}, Any, Int64, Int64, Vector{SubString{String}}, Int64},Type{Pager}})   # time: 0.012502053
    Base.precompile(Tuple{Core.kwftype(typeof(set_keybinding)),NamedTuple{(:shift,), Tuple{Bool}},typeof(set_keybinding),Symbol,Symbol})   # time: 0.008475663
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:term, :buf, :display_size, :start_row, :start_col, :lines, :num_lines), Tuple{REPL.Terminals.TTYTerminal, IOContext{IOBuffer}, Tuple{Int64, Int64}, Int64, Int64, Vector{SubString{String}}, Int64}},Type{Pager}})   # time: 0.006221953
    Base.precompile(Tuple{typeof(delete_keybinding),Char})   # time: 0.005644871
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value, :shift), Tuple{Symbol, Bool}},Type{Keystroke}})   # time: 0.002552443
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value,), Tuple{String}},Type{Keystroke}})   # time: 0.002379567
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value, :alt), Tuple{Symbol, Bool}},Type{Keystroke}})   # time: 0.001930076
    Base.precompile(Tuple{Core.kwftype(typeof(delete_keybinding)),NamedTuple{(:shift,), Tuple{Bool}},typeof(delete_keybinding),Symbol})   # time: 0.001510105
end
