module TerminalPager

using Printf
using REPL

using Crayons
using Parameters

import Base: convert, string

################################################################################
#                             Types and structures
################################################################################

include("./types.jl")

################################################################################
#                                  Constants
################################################################################

const CSI = "\x1b["
const PKG_VERSION = v"0.2.1"
const _keybindings = Dict{Tuple{Union{Symbol, String}, Bool, Bool, Bool}, Symbol}()
const _search_highlighting = Dict{Bool, Decoration}()

# Crayons
const _reset_crayon = string(Crayon(reset = true))
const _ruler_crayon = string(crayon"dark_gray")

################################################################################
#                                   Includes
################################################################################

include("./command_line.jl")
include("./debug.jl")
include("./deprecations.jl")
include("./help.jl")
include("./helpers.jl")
include("./pager.jl")
include("./recipe.jl")
include("./rulers.jl")
include("./search.jl")
include("./screen.jl")
include("./string.jl")
include("./view.jl")

include("./input/keybindings.jl")
include("./input/input.jl")

export pager

function pager(obj::Any; kwargs...)
    str = sprint(show, MIME"text/plain"(), obj, context = :color => true)
    return pager(str; kwargs...)
end

pager(obj::AbstractString; kwargs...) = return _pager(obj; kwargs...)

const less = pager

function __init__()
    # Call `reset_keybindings` to populate the keybindings.
    reset_keybindings()

    # Call `reset_highlighting` to populate the search highlighting.
    reset_highlighting()

    return nothing
end

end # module
