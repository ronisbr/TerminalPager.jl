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
    "visual_mode_active_line_background" => "44",
)

# Reading a preference goes through the TOML-backed `Preferences.jl` storage, which takes
# roughly 50 µs. Opening a pager reads five of them, and every `pager>` command reads two more.
# Since preferences cannot change without going through the functions below, the values are
# cached here.
const _PREFERENCE_CACHE = Dict{String, Any}()

############################################################################################
#                                     Public Functions                                     #
############################################################################################

"""
    drop_all_preferences!() -> Nothing

Drop all preferences.

# Examples

```julia
julia> TerminalPager.drop_all_preferences!()
```
"""
function drop_all_preferences!()
    for pref in keys(_AVAILABLE_PREFERENCES)
        @delete_preferences!(pref)
    end

    _invalidate_preference_cache!()

    return nothing
end

"""
    drop_preference!(pref::String) -> Nothing

Drop the preference `pref`.

# Examples

```julia
julia> TerminalPager.drop_preference!("visual_mode_line_background")
```
"""
function drop_preference!(pref::String)
    pref ∉ keys(_AVAILABLE_PREFERENCES) &&
        throw(ArgumentError("$pref is not a valid preference."))
    @delete_preferences!(pref)
    _invalidate_preference_cache!()
    return nothing
end

"""
    set_preference!(pref::String, value::Any) -> Nothing

Set the preference `pref` to the `value`.

# Arguments

- `pref::String`: Name of a supported preference.
- `value::Any`: Value whose type must match the built-in default.

# Examples

```julia
julia> TerminalPager.set_preference!("visual_mode_line_background", "44")
```
"""
function set_preference!(pref::String, value)
    validated_value = _validate_preference(pref, value)
    @set_preferences!(pref => validated_value)
    _invalidate_preference_cache!()
    return nothing
end

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _get_preference(pref::String) -> Union{Bool, String}

Return the configured value for `pref`, or its built-in default when it is not set.

# Arguments

- `pref::String`: Name of a supported preference.
"""
function _get_preference(pref::String)
    cached = get(_PREFERENCE_CACHE, pref, nothing)
    isnothing(cached) || return cached

    value = _validate_preference(pref, @load_preference(pref, _AVAILABLE_PREFERENCES[pref]))
    _PREFERENCE_CACHE[pref] = value

    return value
end

"""
    _invalidate_preference_cache!() -> Nothing

Drop every cached preference value.
"""
function _invalidate_preference_cache!()
    empty!(_PREFERENCE_CACHE)
    return nothing
end

"""
    _validate_preference(pref::String, value::Any) -> Union{Bool, String}

Validate a known preference against the type of its built-in default.

# Arguments

- `pref::String`: Name of a supported preference.
- `value::Any`: Candidate preference value.
"""
function _validate_preference(pref::String, value)
    haskey(_AVAILABLE_PREFERENCES, pref) ||
        throw(ArgumentError("$pref is not a valid preference."))
    expected_type = typeof(_AVAILABLE_PREFERENCES[pref])
    value isa expected_type || throw(
        ArgumentError(
            "Preference \"$pref\" must be a $expected_type; received $(typeof(value))."
        ),
    )
    return value
end

"""
    _display_config(get_preference::F = _get_preference) -> DisplayConfig where
        {F <: Function}

Capture the display string preferences for a new pager session.

# Arguments

- `get_preference::F`: Callable preference getter used to capture each display value.
    (**Default**: `_get_preference`)
"""
function _display_config(get_preference::F = _get_preference) where {F <: Function}
    return DisplayConfig(
        get_preference("active_search_decoration")::String,
        get_preference("inactive_search_decoration")::String,
        get_preference("visual_mode_active_line_background")::String,
        get_preference("visual_mode_line_background")::String,
    )
end
