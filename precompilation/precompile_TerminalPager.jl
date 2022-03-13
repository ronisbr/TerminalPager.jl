function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    Base.precompile(Tuple{typeof(_jlgetch),Base.TTY})   # time: 0.051785473
    Base.precompile(Tuple{typeof(reset_keybindings)})   # time: 0.03397135
    Base.precompile(Tuple{typeof(set_keybinding),Char,Symbol})   # time: 0.021033075
    Base.precompile(Tuple{Core.kwftype(typeof(set_keybinding)),NamedTuple{(:shift,), Tuple{Bool}},typeof(set_keybinding),Symbol,Symbol})   # time: 0.011520076
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:term, :buf, :display_size, :start_row, :start_col, :lines, :num_lines), _A} where _A<:Tuple{REPL.Terminals.TTYTerminal, IOContext{IOBuffer}, Any, Int64, Int64, Vector{SubString{String}}, Int64},Type{Pager}})   # time: 0.01032585
    Base.precompile(Tuple{typeof(delete_keybinding),Char})   # time: 0.00689257
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:term, :buf, :display_size, :start_row, :start_col, :lines, :num_lines), Tuple{REPL.Terminals.TTYTerminal, IOContext{IOBuffer}, Tuple{Int64, Int64}, Int64, Int64, Vector{SubString{String}}, Int64}},Type{Pager}})   # time: 0.004967818
    Base.precompile(Tuple{Core.kwftype(typeof(_clear_screen)),NamedTuple{(:newlines,), Tuple{Bool}},typeof(_clear_screen),Base.TTY})   # time: 0.004932083
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value,), Tuple{String}},Type{Keystroke}})   # time: 0.002313915
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value, :shift), Tuple{Symbol, Bool}},Type{Keystroke}})   # time: 0.002108221
    Base.precompile(Tuple{Core.kwftype(typeof(Type)),NamedTuple{(:value, :alt), Tuple{Symbol, Bool}},Type{Keystroke}})   # time: 0.00205253
    Base.precompile(Tuple{Core.kwftype(typeof(delete_keybinding)),NamedTuple{(:shift,), Tuple{Bool}},typeof(delete_keybinding),Symbol})   # time: 0.00174416
end
