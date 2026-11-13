## Description #############################################################################
#
# Manage the preferences in TerminalPager.jl.
#
############################################################################################

############################################################################################
#                                        Constants                                         #
############################################################################################

# The value type must stay a small concrete union. With `Any`, every preference read
# inferred as `Any`, which made the session options in `_pager!` and in the REPL mode
# dynamically dispatched. Every read asserts the type of its preference anyway.
const _AVAILABLE_PREFERENCES = Dict{String, Union{Bool, Int, String}}(
    "always_use_alternate_screen_buffer_in_repl_mode" => false,
    "block_alternate_screen_buffer" => false,
    "copy_stdout_to_clipboard_in_repl_mode" => false,
    "history_max_bytes" => 50_000_000,
    "history_size" => 5,
    "mouse" => true,
    "pager_mode" => "default",
    "repl_mode_display" => "stack",
    "replace_help_mode" => false,
    "show_column_ruler" => false,
    "show_scrollbar" => false,
    "status_position" => "percent",
    "use_scroll_regions" => true,
)

# Preferences replaced by faces, mapped to the face that replaced them. Setting or dropping
# one of them throws an error pointing to the face, so that an old configuration does not
# fail silently.
const _REPLACED_PREFERENCES = Dict{String, String}(
    "active_search_decoration" => "search_active_match",
    "inactive_search_decoration" => "search_match",
    "visual_mode_active_line_background" => "visual_active_line",
    "visual_mode_line_background" => "visual_line",
)

# Reading a preference goes through the TOML-backed `Preferences.jl` storage, which takes
# roughly 50 µs. Opening a pager reads five of them, and every `pager>` command reads two more.
# Since preferences cannot change without going through the functions below, the values are
# cached here.
const _PREFERENCE_CACHE = Dict{String, Union{Bool, Int, String}}()

############################################################################################
#                                     Public Functions                                     #
############################################################################################

"""
    drop_all_preferences!() -> Nothing

Drop all preferences, including the faces customized with [`set_face!`](@ref), which are
reset to their built-in defaults, and the key bindings persisted with
[`set_keybinding`](@ref).

# Examples

```julia
julia> TerminalPager.drop_all_preferences!()
```
"""
function drop_all_preferences!()
    for pref in keys(_AVAILABLE_PREFERENCES)
        @delete_preferences!(pref)
    end

    # The replaced preferences are deleted too, so that an old configuration is cleaned up.
    for pref in keys(_REPLACED_PREFERENCES)
        @delete_preferences!(pref)
    end

    @delete_preferences!(_FACES_PREFERENCE)

    for (name, _) in _FACES
        resetfaces!(Symbol(_FACE_PREFIX, name))
    end

    # The persisted key bindings are dropped and the session bindings are rebuilt without
    # them.
    @delete_preferences!(_KEYBINDINGS_PREFERENCE)
    reset_keybindings()

    _invalidate_preference_cache!()

    return nothing
end

"""
    drop_preference!(pref::String) -> Nothing

Drop the preference `pref`.

# Arguments

- `pref::String`: Name of a supported preference.

# Examples

```julia
julia> TerminalPager.drop_preference!("show_scrollbar")
```
"""
function drop_preference!(pref::String)
    _check_preference_name(pref)
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
julia> TerminalPager.set_preference!("show_scrollbar", true)
```
"""
function set_preference!(pref::String, value)
    validated_value = _validate_preference(pref, value)

    # The alternate screen buffer is now used by default, so this preference has no effect.
    # It is still accepted so that existing configurations keep loading.
    if pref == "always_use_alternate_screen_buffer_in_repl_mode"
        @warn(
            "The preference \"always_use_alternate_screen_buffer_in_repl_mode\" is " *
                "deprecated and ignored: the alternate screen buffer is now used by " *
                "default. Use \"block_alternate_screen_buffer\" to disable it."
        )
    end

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
    _validate_preference(pref::String, value::Any) -> Union{Bool, Int, String}

Validate a known preference against the type of its built-in default. An integer preference
accepts any integer but a `Bool`, which is converted to `Int`, and must be positive.

# Arguments

- `pref::String`: Name of a supported preference.
- `value::Any`: Candidate preference value.
"""
function _validate_preference(pref::String, value)::Union{Bool, Int, String}
    _check_preference_name(pref)
    expected_type = typeof(_AVAILABLE_PREFERENCES[pref])

    if expected_type === Int
        # The preferences are stored as TOML integers, which load as `Int64`. A `Bool` is an
        # `Integer` in Julia, but it is not a count.
        ((value isa Integer) && !(value isa Bool)) || throw(
            ArgumentError(
                "Preference \"$pref\" must be an Int; received $(typeof(value))."
            ),
        )

        value = Int(value)
        (value >= 1) || throw(
            ArgumentError("Preference \"$pref\" must be at least 1; received $value."),
        )

        return value
    end

    value isa expected_type || throw(
        ArgumentError(
            "Preference \"$pref\" must be a $expected_type; received $(typeof(value))."
        ),
    )

    # The pager mode only supports two values. Anything else used to be accepted,
    # persisted, and then silently treated as the default mode.
    if (pref == "pager_mode") && (value ∉ ("default", "vi"))
        throw(
            ArgumentError(
                "Preference \"pager_mode\" must be \"default\" or \"vi\"; " *
                    "received \"$value\".",
            ),
        )
    end

    # The values of the `pager>` mode go through the display stack or to the pager only.
    if (pref == "repl_mode_display") && (value ∉ ("stack", "pager"))
        throw(
            ArgumentError(
                "Preference \"repl_mode_display\" must be \"stack\" or \"pager\"; " *
                    "received \"$value\".",
            ),
        )
    end

    # The position of the status line has three styles.
    if (pref == "status_position") && (value ∉ ("percent", "line", "both"))
        throw(
            ArgumentError(
                "Preference \"status_position\" must be \"percent\", \"line\", or " *
                    "\"both\"; received \"$value\".",
            ),
        )
    end

    return value
end

"""
    _check_preference_name(pref::String) -> Nothing

Throw an `ArgumentError` if `pref` is not a supported preference. The error of a preference
replaced by a face names the face and [`set_face!`](@ref).

# Arguments

- `pref::String`: Name of the preference to check.
"""
function _check_preference_name(pref::String)
    haskey(_AVAILABLE_PREFERENCES, pref) && return nothing

    if haskey(_REPLACED_PREFERENCES, pref)
        throw(
            ArgumentError(
                "The preference \"$pref\" was replaced by the face " *
                    "\"$(_REPLACED_PREFERENCES[pref])\". Use `TerminalPager.set_face!` " *
                    "to customize it.",
            ),
        )
    end

    throw(ArgumentError("$pref is not a valid preference."))
end
