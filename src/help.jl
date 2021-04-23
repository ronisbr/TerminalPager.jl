# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions related to help screen.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

"""
    _help!(pargerd::Pager)

Open a new pager with the help.

"""
function _help!(pagerd::Pager)
    # Unpack values.
    @unpack term, buf = pagerd

    if get(term.out_stream, :color, true)
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
          ALT ←   : Go to the first column.
              →   : Move the display one column to the right.
        SHIFT →   : Move the display 10 columns to the right.
          ALT →   : Go to the last column.
              ↑   : Move the display one line up.
        SHIFT ↑   : Move the display 5 lines up.
              ↓   : Move the display one line down.
        SHIFT ↓   : Move the display 5 lines down.
        PAGE UP   : Move the display one page up.
        PAGE DOWN : Move the display one page down.
        HOME      : Go to the beginning.
        END       : Go to the end.
        ?         : This help screen.
        q         : Quit.

        $(_g)Press any key to exit...$(_d)
    """

    _pager!(pagerd.term, help_str; hashelp = false)

    return nothing
end
