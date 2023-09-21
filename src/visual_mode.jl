# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==========================================================================================
#
#   Functions related to the visual mode.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

export reset_visual_mode_backgrounds, set_visual_mode_backgrounds

const _VISUAL_MODE_BACKGROUNDS = Dict{Bool,String}(
    false => "44",
    true => "100"
)

"""
    set_visual_mode_backgrounds(selected_line::String, marked_line::String) -> Nothing

Set the background of the visual mode selected line to `selected_line` and the background of
the visual mode marked lines to `marked_lines`. The inputs must be a valid ANSI escape code
for background decoration.
"""
function set_visual_mode_backgrounds(selected_line::String, marked_line::String)
    _VISUAL_MODE_BACKGROUNDS[false] = marked_line
    _VISUAL_MODE_BACKGROUNDS[true] = selected_line
    return nothing
end

"""
reset_visual_mode_backgrounds() -> Nothing

Reset the visual mode backgrounds to the default values.
"""
function reset_visual_mode_backgrounds()
    _VISUAL_MODE_BACKGROUNDS[false] = "44"
    _VISUAL_MODE_BACKGROUNDS[true] = "100"
    return nothing
end
