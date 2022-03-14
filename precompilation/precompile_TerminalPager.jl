function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    Base.precompile(Tuple{typeof(_jlgetch),Base.TTY})   # time: 0.056751598
    Base.precompile(Tuple{typeof(delete_keybinding),Char})   # time: 0.032723676
    Base.precompile(Tuple{typeof(reset_keybindings)})   # time: 0.02941807
    Base.precompile(Tuple{typeof(set_keybinding),Char,Symbol})   # time: 0.025140239
    Base.precompile(Tuple{Core.kwftype(typeof(set_keybinding)),NamedTuple{(:shift,), Tuple{Bool}},typeof(set_keybinding),Symbol,Symbol})   # time: 0.010067715
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:buf, :display_size, :lines, :num_lines, :start_column, :start_row, :term), _A} where _A<:Tuple{IOContext{IOBuffer}, Any, Vector{SubString{String}}, Int64, Int64, Int64, REPL.Terminals.TTYTerminal},Type{Pager}})   # time: 0.008918825
    Base.precompile(Tuple{Core.kwftype(typeof(_clear_screen)),NamedTuple{(:newlines,), Tuple{Bool}},typeof(_clear_screen),Base.TTY})   # time: 0.006394438
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:buf, :display_size, :lines, :num_lines, :start_column, :start_row, :term), Tuple{IOContext{IOBuffer}, Tuple{Int64, Int64}, Vector{SubString{String}}, Int64, Int64, Int64, REPL.Terminals.TTYTerminal}},Type{Pager}})   # time: 0.005872454
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value, :shift), Tuple{Symbol, Bool}},Type{Keystroke}})   # time: 0.002973869
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value,), Tuple{String}},Type{Keystroke}})   # time: 0.00243106
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value, :alt), Tuple{Symbol, Bool}},Type{Keystroke}})   # time: 0.001901464
    Base.precompile(Tuple{Core.kwftype(typeof(delete_keybinding)),NamedTuple{(:shift,), Tuple{Bool}},typeof(delete_keybinding),Symbol})   # time: 0.001742677
end
