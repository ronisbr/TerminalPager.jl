## Description #############################################################################
#
# Manage the preferences in TerminalPager.jl.
#
############################################################################################

############################################################################################
#                                        Constants                                         #
############################################################################################

const _AVAILABLE_PREFERENCES = Dict{String, Any}(
    "active_search_decoration" => string(crayon"black bg:yellow"),
    "inactive_search_decoration" => string(crayon"black bg:light_gray"),
    "always_use_alternate_screen_buffer_in_repl_mode" => false,
    "block_alternate_screen_buffer" => false,
    "copy_stdout_to_clipboard_in_repl_mode" => false,
    "pager_mode" => "default",
    "visual_mode_line_background" => "100",
    "visual_mode_active_line_background" => "44"
)

############################################################################################
#                                     Public Functions                                     #
############################################################################################

"""
    drop_all_preferences!()

Drop all preferences.

# Examples

```julia
julia> TerminalPager.drop_all_preference!()
```
"""
function drop_all_preferences!()
    for pref in keys(_AVAILABLE_PREFERENCES)
        @delete_preferences!(pref)
    end

    return nothing
end

"""
    drop_preference!(pref::String, value) -> Nothing

Drop the preference `pref`.

# Examples

```julia
julia> TerminalPager.drop_preference!("visual_mode_line_background")
```
"""
function drop_preference!(pref::String)
    pref ∉ keys(_AVAILABLE_PREFERENCES) && throw(ArgumentError("$pref is not a valid preference."))
    @delete_preferences!(pref)
    return nothing
end


"""
    set_preference!(pref::String, value) -> Nothing

Set the preference `pref` to the `value`.

# Examples

```julia
julia> TerminalPager.set_preference!("visual_mode_line_background", "44")
```
"""
function set_preference!(pref::String, value)
    pref ∉ keys(_AVAILABLE_PREFERENCES) && throw(ArgumentError("$pref is not a valid preference."))
    @set_preferences!(pref => value)
    return nothing
end

############################################################################################
#                                    Private Functions                                     #
############################################################################################

# Return the value for the preference `pref` falling back to the default one if it is not
# set.
function _get_preference(pref::String)
    return @load_preference(
        pref,
        _AVAILABLE_PREFERENCES[pref]
    )
end
