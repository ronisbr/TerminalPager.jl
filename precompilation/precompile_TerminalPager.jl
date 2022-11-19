function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    Base.precompile(Tuple{typeof(_jlgetch),Base.TTY})   # time: 0.043986946
    Base.precompile(Tuple{typeof(reset_keybindings)})   # time: 0.025287732
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:buf, :display_size, :lines, :num_lines, :start_column, :start_row, :term), _A} where _A<:Tuple{IOContext{IOBuffer}, Any, Vector{SubString{String}}, Int64, Int64, Int64, REPL.Terminals.TTYTerminal},Type{Pager}})   # time: 0.006974931
    Base.precompile(Tuple{typeof(delete_keybinding),String})   # time: 0.004649532
    Base.precompile(Tuple{Core.kwftype(typeof(_clear_screen)),NamedTuple{(:newlines,), Tuple{Bool}},typeof(_clear_screen),Base.TTY})   # time: 0.004224642
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:buf, :display_size, :lines, :num_lines, :start_column, :start_row, :term), Tuple{IOContext{IOBuffer}, Tuple{Int64, Int64}, Vector{SubString{String}}, Int64, Int64, Int64, REPL.Terminals.TTYTerminal}},Type{Pager}})   # time: 0.003827234
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value, :shift), Tuple{String, Bool}},Type{Keystroke}})   # time: 0.001759829
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value, :alt), Tuple{String, Bool}},Type{Keystroke}})   # time: 0.001759378
    Base.precompile(Tuple{Core.kwftype(typeof(set_keybinding)),NamedTuple{(:shift,), Tuple{Bool}},typeof(set_keybinding),String,Symbol})   # time: 0.001678365
    Base.precompile(Tuple{Core.kwftype(typeof(delete_keybinding)),NamedTuple{(:shift,), Tuple{Bool}},typeof(delete_keybinding),String})   # time: 0.001020973
end
