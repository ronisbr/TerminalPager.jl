# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   This file contains functions reltated to input handling. This code was
#   adapted from the on in TextUserInterfaces.jl.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

################################################################################
#                                  Constants
################################################################################

include("keycodes.jl")

################################################################################
#                                  Functions
################################################################################

"""
    _jlgetch(stream::IO)

Wait for an keystroke in the stream `stream` and return it (see
[`Keystroke`](@ref)).

"""
function _jlgetch((@nospecialize stream::IO))
    c_raw = read(stream, UInt8)::UInt8
    c_raw < 0 && return Keystroke(raw = c_raw, value = "ERR", ktype = :undefined)

    c::UInt32 = UInt32(c_raw)
    nc::Int32 = 0

    if c == 27

        s = string(Char(c))

        # Read the entire sequence limited to 10 characters.
        for i = 1:10
            stream.buffer.size == i && break
            nc = read(stream, Char)::Char
            s *= string(Char(nc))
            haskey(keycodes, s) && break
        end

        if length(s) == 1
            return Keystroke(value = :esc)
        elseif haskey(keycodes, s)
            aux = keycodes[s]
            return Keystroke(value = aux.value,
                             alt = aux.alt,
                             ctrl = aux.ctrl,
                             shift = aux.shift)
        else
            # In this case, ALT was pressed.
            return Keystroke(value = :undefined, alt = true)
        end
    elseif c == nocharval
        return Keystroke(value = c, ktype = :undefined)
    elseif 192 <= c <= 223 # utf8 based logic starts here
        bs1 = UInt8(c)
        bs2 = read(stream, UInt8)::UInt8
        return Keystroke(value = String([bs1,bs2]))
    elseif c < 192 || c > 253
        if c == 4
            return Keystroke(value = :eot)
        elseif c == 9
            return Keystroke(value = :tab)
        elseif c == 10
            return Keystroke(value = :enter)
        elseif c == 13
            return Keystroke(value = :enter)
        elseif c == 21
            return Keystroke(value = :shiftin)
        elseif c == 127
            return Keystroke(value = :backspace)
        elseif c == 410
            return Keystroke(value = :resize)
        else
            return Keystroke(value = string(Char(c)))
        end
    elseif  224 <= c <= 239
        bs1 = UInt8(c)
        bs2 = read(stream, UInt8)::UInt8
        bs3 = read(stream, UInt8)::UInt8
        return Keystroke(value = String([bs1,bs2,bs3]))
    elseif  240 <= c <= 247
        bs1 = UInt8(c)
        bs2 = read(stream, UInt8)::UInt8
        bs3 = read(stream, UInt8)::UInt8
        bs4 = read(stream, UInt8)::UInt8
        return Keystroke(value = String([bs1,bs2,bs3,bs4]))
    elseif  248 <= c <= 251
        bs1 = UInt8(c)
        bs2 = read(stream, UInt8)::UInt8
        bs3 = read(stream, UInt8)::UInt8
        bs4 = read(stream, UInt8)::UInt8
        bs5 = read(stream, UInt8)::UInt8
        return Keystroke(value = String([bs1,bs2,bs3,bs4,bs5]))
    elseif  252 <= c <= 253
        bs1 = UInt8(c)
        bs2 = read(stream, UInt8)::UInt8
        bs3 = read(stream, UInt8)::UInt8
        bs4 = read(stream, UInt8)::UInt8
        bs5 = read(stream, UInt8)::UInt8
        bs6 = read(stream, UInt8)::UInt8
        return Keystroke(value = String([bs1,bs2,bs3,bs4,bs5,bs6]))
    end

    return Keystroke(value = :undefined)
end
