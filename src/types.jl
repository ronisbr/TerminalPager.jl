# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Definition of types and structures.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

const SearchMatch = NTuple{3, Int}
const SearchMatches = Vector{SearchMatch}

# Structure that holds all the information about the pager.
@with_kw mutable struct Pager
    term::REPL.Terminals.TTYTerminal
    buf::IOContext{IOBuffer}
    display_size::NTuple{2, Int} = (0, 0)
    start_row::Int = 1
    start_col::Int = 1
    lines::Vector{String} = String[]
    num_lines::Int = 0
    lines_cropped::Int = 0
    columns_cropped::Int = 0
    search_matches::SearchMatches = SearchMatch[]
    active_search_match_id::Int = 0
    redraw::Bool = true
    mode::Symbol = :view
    event::Union{Nothing, Symbol} = nothing
end

# This struct describe the decoration of a string.
@with_kw struct Decoration
    foreground::String = ""
    background::String = ""
    bold::Bool         = false
    underline::Bool    = false
    reset::Bool        = false
    reversed::Bool     = false

    # This variable is used to force a formatting. This is necessary because we
    # do not add escape sequences if the decoration is the default, avoiding
    # unnecessary writing. However, we need to differentiate the decoration
    # that is forcing to go back to the default.
    force::Bool = false
end

"""
    struct Keystorke

Structure that defines a keystroke.

# Fields

* `value`: String representing the keystroke.
* `ktype`: Type of the key (`:char`, `:F1`, `:up`, etc.).
* `alt`: `true` if ALT key was pressed (only valid if `ktype != :char`).
* `ctrl`: `true` if CTRL key was pressed (only valid if `ktype != :char`).
* `shift`: `true` if SHIFT key was pressed (only valid if `ktype != :char`).

"""
@with_kw struct Keystroke
    value::Union{Symbol, String}
    alt::Bool   = false
    ctrl::Bool  = false
    shift::Bool = false
end

