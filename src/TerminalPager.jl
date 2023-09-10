module TerminalPager

using REPL
using REPL.LineEdit

using Crayons
using StringManipulation

import Base: convert, string

# The performance of TerminalPager.jl does not increase by a lot of
# optimizations that is performed by the compiler. Hence, we disable then to
# improve compile time.
if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@optlevel"))
    @eval Base.Experimental.@optlevel 1
end

############################################################################################
#                                          Types
############################################################################################

include("./types.jl")

############################################################################################
#                                        Constants
############################################################################################

const CSI = "\x1b["
const PKG_VERSION = v"0.3.0"

# Crayons
const _CRAYON_B     = string(crayon"bold")
const _CRAYON_CB    = string(crayon"cyan bold")
const _CRAYON_C     = string(crayon"cyan")
const _CRAYON_G     = string(crayon"dark_gray")
const _CRAYON_R     = string(crayon"red bold")
const _CRAYON_RESET = string(Crayon(reset = true))
const _CRAYON_Y     = string(crayon"yellow bold")

############################################################################################
#                                         Includes
############################################################################################

include("./command_line.jl")
include("./debug.jl")
include("./deprecations.jl")
include("./help.jl")
include("./helpers.jl")
include("./pager.jl")
include("./repl.jl")
include("./search.jl")
include("./screen.jl")
include("./view.jl")

include("./input/keybindings.jl")
include("./input/input.jl")

export pager

"""
    pager(obj; kwargs...)

Call the pager to show the output of the object `obj`.

# Keywords

- `auto::Bool`: If `true`, then the pager is only shown if the output does not fit into the
    display. (**Default** = `false`)
- `change_freeze::Bool`: If `true`, then the user can change the number of frozen rows and
    columns inside the pager. (**Default** = `true`)
- `frozen_columns::Int = 0`: Number of columns to be frozen at startup. (**Default** = 0)
- `frozen_rows::Int = 0`: Number of rows to be frozen at startup. (**Default** = 0)
- `hashelp::Bool = true`: If `true`, then the user can see the pager help.
    (**Default** = `true`)
- `has_visual_mode::Bool = true`: If `true`, the user can use the visual mode.
    (**Default** = `true`)
- `show_ruler::Bool`: If `true`, a vertical ruler is shown at the pager with the line
    numbers. (**Default** = `false`)
"""
function pager(obj::Any; kwargs...)
    str = sprint(show, MIME"text/plain"(), obj, context = :color => true)
    return pager(str; kwargs...)
end

pager(obj::AbstractString; kwargs...) = return _pager(obj; kwargs...)

const less = pager

function __init__()
    # TODO: Fix initialization time with PAGER_MODE=vi
    # The code that adds a key into `_keybindings` takes a lot of time. The startup time
    # is increased by almost 0.1s with `PAGER_MODE=vi`.

    # Modify the key bindings if the used wants `vi` mode.
    if get(ENV, "PAGER_MODE", "default") == "vi"
        _keybindings[("<eot>",     false, false, false)] = :halfpagedown
        _keybindings[("<shiftin>", false, false, false)] = :halfpageup
    end

    if isdefined(Base, :active_repl)
        _init_pager_repl_mode(Base.active_repl)
    else
        atreplinit() do repl
            if isinteractive() && repl isa REPL.LineEditREPL
                if !isdefined(repl, :interface)
                    repl.interface = REPL.setup_interface(repl)
                end

                _init_pager_repl_mode(repl)
            end
        end
    end

    return nothing
end

############################################################################################
#                                      Precompilation
############################################################################################

include("precompilation.jl")

end # module
