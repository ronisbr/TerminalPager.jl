# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   This file contains functions reltated to input handling. This code was
#   adapted from the on in TextUserInterfaces.jl.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    struct Keystorke

Structure that defines a keystroke.

# Fields
#
* `value`: String representing the keystroke.
* `ktype`: Type of the key (`:char`, `:F1`, `:up`, etc.).
* `alt`: `true` if ALT key was pressed (only valid if `ktype != :char`).
* `ctrl`: `true` if CTRL key was pressed (only valid if `ktype != :char`).
* `shift`: `true` if SHIFT key was pressed (only valid if `ktype != :char`).

"""
Base.@kwdef struct Keystroke
    raw::Int32 = 0
    value::String
    ktype::Symbol
    alt::Bool   = false
    ctrl::Bool  = false
    shift::Bool = false
end

################################################################################
#                                  Constants
################################################################################

include("keycodes.jl")

################################################################################
#                                  Functions
################################################################################

"""
    jlgetch(win::Union{Ptr{WINDOW},Nothing} = nothing)

Wait for an keystroke in the window `win` and return it (see `Keystroke`).  If
`win` is `nothing`, then `getch()` will be used instead of `wgetch(win)` to
listen for the keystroke.

"""
function _jlgetch(stream::IO)
    c_raw = read(stream, UInt8)
    c_raw < 0 && return Keystroke(raw = c_raw, value = "ERR", ktype = :undefined)

    c::UInt32 = UInt32(c_raw)
    nc::Int32 = 0

    if c == 27

        s = string(Char(c))

        # Read the entire sequence limited to 10 characters.
        for i = 1:10
            stream.buffer.size == 0 && break
            nc = read(stream, Char)
            s *= string(Char(nc))
            haskey(keycodes, s) && break
        end

        if length(s) == 1
            return Keystroke(raw = c, value = s, ktype = :esc)
        elseif haskey( keycodes, s )
            aux = keycodes[s]
            return Keystroke(value = aux.value,
                             ktype = aux.ktype,
                             alt = aux.alt,
                             ctrl = aux.ctrl,
                             shift = aux.shift,
                             raw = c)
        else
            # In this case, ALT was pressed.
            return Keystroke(raw = c, value = s, alt = true, ktype = :undefined)
        end
    elseif c == nocharval
        return Keystroke(raw = c, value = c, ktype = :undefined)
    elseif c < 192 || c > 253
        if c == 9
            return Keystroke(raw = c, value = string(Char(c)), ktype = :tab)
        elseif c == 10
            return Keystroke(raw = c, value = "\n", ktype = :enter)
        elseif c == 127
            return Keystroke(raw = c, value = string(Char(c)), ktype = :backspace)
        elseif c == 410
            return Keystroke(raw = c, value = string(Char(c)), ktype = :resize)
        else
            return Keystroke(raw = c, value = string(Char(c)), ktype = :char)
        end
    end

    return Keystroke(raw = 0, value = string(c), ktype = :undefined)
end
