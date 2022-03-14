function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    Base.precompile(Tuple{typeof(_jlgetch),Base.TTY})   # time: 0.07453108
    Base.precompile(Tuple{typeof(delete_keybinding),Char})   # time: 0.031410065
    Base.precompile(Tuple{typeof(reset_keybindings)})   # time: 0.024520168
    Base.precompile(Tuple{typeof(set_keybinding),Char,Symbol})   # time: 0.024384301
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:term, :buf, :display_size, :start_row, :start_col, :lines, :num_lines), _A} where _A<:Tuple{REPL.Terminals.TTYTerminal, IOContext{IOBuffer}, Any, Int64, Int64, Vector{SubString{String}}, Int64},Type{Pager}})   # time: 0.013001109
    Base.precompile(Tuple{Core.kwftype(typeof(set_keybinding)),NamedTuple{(:shift,), Tuple{Bool}},typeof(set_keybinding),Symbol,Symbol})   # time: 0.010444512
    Base.precompile(Tuple{Core.kwftype(typeof(_clear_screen)),NamedTuple{(:newlines,), Tuple{Bool}},typeof(_clear_screen),Base.TTY})   # time: 0.005386777
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:term, :buf, :display_size, :start_row, :start_col, :lines, :num_lines), Tuple{REPL.Terminals.TTYTerminal, IOContext{IOBuffer}, Tuple{Int64, Int64}, Int64, Int64, Vector{SubString{String}}, Int64}},Type{Pager}})   # time: 0.00510494
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value,), Tuple{String}},Type{Keystroke}})   # time: 0.002207063
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value, :alt), Tuple{Symbol, Bool}},Type{Keystroke}})   # time: 0.002153135
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value, :shift), Tuple{Symbol, Bool}},Type{Keystroke}})   # time: 0.001964658
    Base.precompile(Tuple{Core.kwftype(typeof(delete_keybinding)),NamedTuple{(:shift,), Tuple{Bool}},typeof(delete_keybinding),Symbol})   # time: 0.00146194
end
