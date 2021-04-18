# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Miscellaneous functions.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _print_cmd_line(io::IO, display_size::NTuple{2, Int}, pos::Float64)

Print the command line to the screen.

"""
function _print_cmd_line(io::IO, display_size::NTuple{2, Int}, pos::Float64)
    if get(io, :color, true)
        _d = string(Crayon(reset = true))
        _g = string(crayon"dark_gray")
    else
        _d = ""
        _g = ""
    end

    # Compute the scroll position.
    pos = @sprintf("%3d", 100pos)

    cmd_help = "(q:quit, ?:help) $(pos)%"
    lcmd_help = length(cmd_help)

    if display_size[2] > (lcmd_help + 4)
        cmd_aligned = " "^(display_size[2] - lcmd_help - 1) * _g * cmd_help * _d
    else
        cmd_aligned = ""
    end

    # Move the cursor to the last line and print the command line.
    _move_cursor(io, display_size[1], 0)
    write(io, ":")
    _save_cursor(io)
    write(io, cmd_aligned)
    _restore_cursor(io)

    return nothing
end

"""
    _print_help(io::IO)

Print help screen to the IO `io`.

"""
function _print_help(io::IO)
    if get(io, :color, true)
        _b = string(crayon"bold")
        _d = string(Crayon(reset = true))
        _c = string(crayon"cyan bold")
        _g = string(crayon"dark_gray")
    else
        _b = ""
        _d = ""
        _c = ""
        _g = ""
    end

    help_str =
    """
        $(_c)TerminalPager.jl $(PKG_VERSION)$(_d)

        $(_b)Usage:$(_d)

              ←   : Move the display one column to the left.
        SHIFT ←   : Move the display 10 columns to the left.
              →   : Move the display one column to the right.
        SHIFT →   : Move the display 10 columns to the right.
              ↑   : Move the display one line up.
        SHIFT ↑   : Move the display 5 lines up.
              ↓   : Move the display one line down.
        SHIFT ↓   : Move the display 5 lines down.
        PAGE UP   : Move the display one page up.
        PAGE DOWN : Move the display one page down.
        HOME      : Go to the first column.
        END       : Display the last column.
        ?         : This help screen.
        q         : Quit.

        $(_g)Press any key to exit...$(_d)
    """


    write(io, help_str)
    return nothing
end
