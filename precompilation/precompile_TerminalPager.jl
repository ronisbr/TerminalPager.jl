function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    Base.precompile(Tuple{typeof(reset_keybindings)})   # time: 0.06360835
    Base.precompile(Tuple{typeof(_jlgetch),Base.TTY})   # time: 0.052643724
    Base.precompile(Tuple{typeof(set_keybinding),String,Symbol})   # time: 0.019764958
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:buf, :display_size, :lines, :num_lines, :start_column, :start_row, :term), _A} where _A<:Tuple{IOContext{IOBuffer}, Any, Vector{SubString{String}}, Int64, Int64, Int64, REPL.Terminals.TTYTerminal},Type{Pager}})   # time: 0.007895087
    Base.precompile(Tuple{typeof(delete_keybinding),String})   # time: 0.005830658
    Base.precompile(Tuple{Core.kwftype(typeof(_clear_screen)),NamedTuple{(:newlines,), Tuple{Bool}},typeof(_clear_screen),Base.TTY})   # time: 0.00488455
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:buf, :display_size, :lines, :num_lines, :start_column, :start_row, :term), Tuple{IOContext{IOBuffer}, Tuple{Int64, Int64}, Vector{SubString{String}}, Int64, Int64, Int64, REPL.Terminals.TTYTerminal}},Type{Pager}})   # time: 0.004574806
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value, :shift), Tuple{String, Bool}},Type{Keystroke}})   # time: 0.002437687
    Base.precompile(Tuple{Core.kwftype(typeof(set_keybinding)),NamedTuple{(:shift,), Tuple{Bool}},typeof(set_keybinding),String,Symbol})   # time: 0.001966285
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value, :alt), Tuple{String, Bool}},Type{Keystroke}})   # time: 0.001893504
    Base.precompile(Tuple{Core.kwftype(typeof(delete_keybinding)),NamedTuple{(:shift,), Tuple{Bool}},typeof(delete_keybinding),String})   # time: 0.001182894
end
