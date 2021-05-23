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

"""
    pager(obj; kwargs...)

Call the pager to show the output of the object `obj`.

# Keywords

- `auto::Bool`: If `true`, then the pager is only shown if the output does not
    fit into the display. (**Default** = `false`)
- `change_freeze::Bool`: If `true`, then the user can change the number of
    frozen rows and columns inside the pager. (**Default** = `true`)
- `draw_ruler::Bool`: If `true`, then a vertical ruler is drawn at the pager
    startup. (**Default** = `false`)
- `freeze_columns::Int = 0`: Number of columns to be frozen at startup.
    (**Default** = 0)
- `freeze_rows::Int = 0`: Number of rows to be frozen at starupt.
    (**Default** = 0)
- `hashelp::Bool = true`: If `true`, then the user can see the pager help.
    (**Default** = `true`)
"""
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
