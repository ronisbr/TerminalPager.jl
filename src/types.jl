# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Definition of types and structures.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

const SearchMatches = Dict{Int, Vector{Tuple{Int, Int}}}

# Structure that holds all the information about the pager.
Base.@kwdef mutable struct Pager
    term::REPL.Terminals.TTYTerminal
    buf::IOContext{IOBuffer}
    display_size::NTuple{2, Int} = (0, 0)
    start_row::Int = 1
    start_column::Int = 1
    lines::Vector{String} = String[]
    num_lines::Int = 0
    cropped_lines::Int = 0
    cropped_columns::Int = 0
    search_matches::SearchMatches = SearchMatches()
    num_matches::Int = 0
    active_search_match_id::Int = 0
    redraw::Bool = true
    mode::Symbol = :view
    event::Union{Nothing, Symbol} = nothing
    features::Vector{Symbol} = Symbol[]
    frozen_columns::Int = 0
    frozen_rows::Int = 0
    title_rows::Int = 0
    show_ruler::Bool = false
end

"""
    struct Keystorke

Structure that defines a keystroke.

# Fields

* `raw`: Raw keystroke code converted to string.
* `value`: String representing the keystroke.
* `alt`: `true` if ALT key was pressed (only valid if `value != :char`).
* `ctrl`: `true` if CTRL key was pressed (only valid if `value != :char`).
* `shift`: `true` if SHIFT key was pressed (only valid if `value != :char`).
"""
Base.@kwdef struct Keystroke
    raw::String   = ""
    value::String = ""
    alt::Bool     = false
    ctrl::Bool    = false
    shift::Bool   = false
end
