# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Functions to draw rulers.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function _draw_vertical_ruler!(buf::IO, line::Int, num_lines::Int)
    # Get the required spacing.
    num_spaces = floor(Int, log10(abs(num_lines))) + 1

    # Convert to line and apply the padding.
    line_str = lpad(line, num_spaces)

    # Write to the buffer.
    write(buf, " ", line_str, " │")

    return nothing
end

function _get_vertical_ruler_spacing(num_lines::Int)
    # Get the required spacing for the numbers.
    num_spaces = floor(Int, log10(abs(num_lines))) + 1

    # Return the required spacing to draw the vertical ruller.
    return num_spaces + 3
end

