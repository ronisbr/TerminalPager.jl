module TerminalPager

using REPL
using REPL.LineEdit

using Crayons
using InteractiveUtils
using Preferences
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
include("./preferences.jl")
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

!!! info
    Some of the default values shown here can be modified by user-defined preferences.

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
- `use_alternate_screen_buffer::Bool`: If `true`, the pager will use the alternate screen
    buffer, which keeps the current screen when exiting the pager. Notice, however, that we
    use the XTerm escape sequences here. Hence, if your terminal is different, this option
    can lead to rendering problems.

# Preferences

The user can defined custom preferences using the function
[`TerminalPager.set_preference!`](@ref). The available preferences are listed as follows:

- `"active_search_decoration"`: `String` with the ANSI escape sequence to decorate the
    active search element. One can easily obtain this sequence by converting a `Crayon` to
    string. (**Default** = `string(crayon"black bg:yellow")`)
- `"inactive_search_decoration"`: `String` with the ANSI escape sequence to decorate the
    inactive search element. One can easily obtain this sequence by converting a `Crayon` to
    string. (**Default** = `string(crayon"black bg:light_gray")`)
- `"always_use_alternate_screen_buffer_in_repl_mode"`: If `true`, we will always use the
    alternate screen buffer when showing the pager in REPL mode. (**Default** = false)
- `"block_alternate_screen_buffer"`: If `true`, the alternate screen buffer support will be
    globally blocked, regardless of the keyword options. This modification is helpful when
    the terminal is not compatible with XTerm. (**Default** = `false`)
- `"pager_mode"`: If it is "vi", some keywords are modified to match the behavior of Vi.
    Notice that this change only takes effect when a new Julia session is initialized.
    (**Default** = "default")
- `"visual_mode_line_background"`: `String` with the ANSI code of the background for the
    selected lines in the visual mode. (**Default** = "100")
- `"visual_mode_active_line_background"`: `String` with the ANSI code of the background for
    the active line in the visual mode. (**Default** = "44")

For more information, see: [`TerminalPager.set_preference!`](@ref),
[`TerminalPager.drop_preference!`](@ref), and [`TerminalPager.drop_all_preferences!`](@ref).
"""
function pager(obj::Any; kwargs...)
    str = sprint(show, MIME"text/plain"(), obj, context = :color => true)
    return pager(str; kwargs...)
end

pager(obj::AbstractString; kwargs...) = return _pager(obj; kwargs...)

const less = pager

function __init__()
    # Modify the key bindings if the used wants `vi` mode.
    if _get_preference("pager_mode") == "vi"
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
