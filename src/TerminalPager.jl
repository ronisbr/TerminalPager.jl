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
const PKG_VERSION = v"0.0.1"
const _default_keybindings = Dict{Tuple{Union{Symbol, String}, Bool, Bool, Bool}, Symbol}()
const _default_search_highlighting = Dict{Bool, Decoration}()

################################################################################
#                                   Includes
################################################################################

include("./command_line.jl")
include("./keybindings.jl")
include("./input.jl")
include("./help.jl")
include("./pager.jl")
include("./recipe.jl")
include("./search.jl")
include("./screen.jl")
include("./string.jl")
include("./view.jl")

export pager

function pager(obj::Any; kwargs...)
    str = sprint(show, MIME"text/plain"(), obj, context = :color => true)
    return pager(str; kwargs...)
end

pager(obj::AbstractString; kwargs...) = return _pager(obj; kwargs...)

const less = pager

end # module
