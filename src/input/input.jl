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
            return Keystroke(raw = s, value = :esc)
        elseif haskey(keycodes, s)
            aux = keycodes[s]
            return Keystroke(raw = s,
                             value = aux.value,
                             alt = aux.alt,
                             ctrl = aux.ctrl,
                             shift = aux.shift)
        else
            return Keystroke(raw = s, value = :undefined)
        end
    elseif c == nocharval
        return Keystroke(raw = string(c), value = :undefined)
    elseif 192 <= c <= 223 # utf8 based logic starts here
        bs1 = UInt8(c)
        bs2 = read(stream, UInt8)::UInt8
        return Keystroke(raw = string(bs1) * ", " * string(bs2),
                         value = String([bs1, bs2]))
    elseif c < 192 || c > 253
        if c == 4
            return Keystroke(raw = string(c), value = :eot)
        elseif c == 9
            return Keystroke(raw = string(c), value = :tab)
        elseif c == 10
            return Keystroke(raw = string(c), value = :enter)
        elseif c == 13
            return Keystroke(raw = string(c), value = :enter)
        elseif c == 21
            return Keystroke(raw = string(c), value = :shiftin)
        elseif c == 127
            return Keystroke(raw = string(c), value = :backspace)
        elseif c == 410
            return Keystroke(raw = string(c), value = :resize)
        else
            return Keystroke(raw = string(c), value = string(Char(c)))
        end
    elseif  224 <= c <= 239
        bs1 = UInt8(c)
        bs2 = read(stream, UInt8)::UInt8
        bs3 = read(stream, UInt8)::UInt8
        return Keystroke(raw = string(bs1) * ", " *
                               string(bs2) * ", " *
                               string(bs3),
                         value = String([bs1, bs2, bs3]))
    elseif  240 <= c <= 247
        bs1 = UInt8(c)
        bs2 = read(stream, UInt8)::UInt8
        bs3 = read(stream, UInt8)::UInt8
        bs4 = read(stream, UInt8)::UInt8
        return Keystroke(raw = string(bs1) * ", " *
                               string(bs2) * ", " *
                               string(bs3) * ", " *
                               string(bs4),
                         value = String([bs1, bs2, bs3, bs4]))
    elseif  248 <= c <= 251
        bs1 = UInt8(c)
        bs2 = read(stream, UInt8)::UInt8
        bs3 = read(stream, UInt8)::UInt8
        bs4 = read(stream, UInt8)::UInt8
        bs5 = read(stream, UInt8)::UInt8
        return Keystroke(raw = string(bs1) * ", " *
                               string(bs2) * ", " *
                               string(bs3) * ", " *
                               string(bs4) * ", " *
                               string(bs5),
                         value = String([bs1, bs2, bs3, bs4, bs5]))
    elseif  252 <= c <= 253
        bs1 = UInt8(c)
        bs2 = read(stream, UInt8)::UInt8
        bs3 = read(stream, UInt8)::UInt8
        bs4 = read(stream, UInt8)::UInt8
        bs5 = read(stream, UInt8)::UInt8
        bs6 = read(stream, UInt8)::UInt8
        return Keystroke(raw = string(bs1) * ", " *
                               string(bs2) * ", " *
                               string(bs3) * ", " *
                               string(bs4) * ", " *
                               string(bs5) * ", " *
                               string(bs6),
                         value = String([bs1, bs2, bs3, bs4, bs5, bs6]))
    end

    return Keystroke(value = :undefined)
end
