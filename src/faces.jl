## Description #############################################################################
#
# Faces that style the pager. They are registered with StyledStrings.jl, so that the user
# can customize them in `faces.toml`, and persisted with Preferences.jl through `set_face!`.
#
############################################################################################

############################################################################################
#                                        Constants                                         #
############################################################################################

# Every face is registered with this prefix, as StyledStrings.jl recommends for packages. In
# `faces.toml`, the faces are customized under the tables `[terminalpager.<name>]`.
const _FACE_PREFIX = "terminalpager_"

# Default faces, in the order they are documented. The public functions refer to them by the
# name without the prefix.
const _FACES = Pair{Symbol, Face}[
    :status_bar => Face(; inverse = true),
    :badge_normal => Face(;
        weight = :bold,
        foreground = :bright_white,
        background = :blue,
    ),
    :badge_search => Face(;
        weight = :bold,
        foreground = :black,
        background = :yellow,
    ),
    :badge_visual => Face(;
        weight = :bold,
        foreground = :bright_white,
        background = :magenta,
    ),
    :message_info => Face(;
        weight = :bold,
        foreground = :bright_white,
        background = :green,
    ),
    :message_error => Face(;
        weight = :bold,
        foreground = :bright_white,
        background = :red,
    ),
    :search_match => Face(; foreground = :black, background = :white),
    :search_active_match => Face(; foreground = :black, background = :yellow),
    :visual_line => Face(; background = :bright_black),
    :visual_active_line => Face(; background = :blue),
    :ruler => Face(; foreground = :bright_black),
    :scrollbar_track => Face(; foreground = :bright_black),
    :scrollbar_thumb => Face(),
    :command_status => Face(; foreground = :bright_black),
    :help_title => Face(; weight = :bold, foreground = :cyan),
    :help_section => Face(; weight = :bold),
    :help_description => Face(; foreground = :bright_black),
    :help_key => Face(; foreground = :cyan),
    :help_action => Face(; weight = :bold, foreground = :yellow),
]

const _DEFAULT_FACES = Dict{Symbol, Face}(_FACES)

# Name of the preference that stores the customized faces.
const _FACES_PREFERENCE = "faces"

############################################################################################
#                                     Public Functions                                     #
############################################################################################

"""
    set_face!(name::AbstractString, face::Face) -> Nothing
    set_face!(name::AbstractString; kwargs...) -> Nothing

Customize the pager face `name` with the attributes set in `face`, or with the keywords
accepted by `StyledStrings.Face`. The attributes and the available faces are listed in the
extended help.

The attributes are merged into the current face, so that the ones left unset keep their
values, and they are persisted with **Preferences.jl** in the same format as `faces.toml`.
The change applies to the next pager session, without restarting Julia. An unknown face or
attribute is rejected with an error.

See also: [`drop_face!`](@ref).

# Arguments

- `name::AbstractString`: Name of a pager face, without the prefix `terminalpager_`.
- `face::Face`: Attributes to merge into the face.

# Keywords

- `kwargs...`: Attributes to merge into the face, as accepted by `StyledStrings.Face`.

# Extended help

## Attributes

- `foreground` and `background`: Color, which can be the name of one of the 16 terminal
    colors (`:black`, `:red`, `:green`, `:yellow`, `:blue`, `:magenta`, `:cyan`, `:white`,
    and their `:bright_` variants, with `:grey` and `:gray` as aliases of
    `:bright_black`), `:default` for the color of the terminal, a 24-bit color written as a
    `"#rrggbb"` string or a `UInt32` like `0x005f87`, or the name of another face, whose
    foreground is used. The 24-bit colors are approximated on terminals without true color
    support.
- `weight`: `:thin`, `:extralight`, `:light`, `:semilight`, `:normal`, `:medium`,
    `:semibold`, `:bold`, `:extrabold`, or `:black`. The weights above `:normal` are shown
    in bold, and the ones below it are shown faint.
- `slant`: `:normal`, `:italic`, or `:oblique`. The last two are shown in italics.
- `underline`: `true` or `false`. A color or a style, like `(:red, :curly)`, is accepted and
    persisted, but the pager only underlines the text.
- `strikethrough`: `true` or `false`.
- `inverse`: `true` or `false` to swap the foreground and the background. Notice that the
    terminal swaps the colors after applying them. Hence, a face with `inverse = true`
    shows its background as the foreground and vice versa.
- `inherit`: Name of a face, or a vector of names, whose attributes fill the ones left
    unset, like `:bold` or `:terminalpager_help_key`.
- `font` and `height`: Accepted and persisted, but they have no effect in the terminal.

## Faces

- `"status_bar"`: Status bar. It is drawn in reverse video by default, so that it matches
    light and dark themes. Custom colors must come with `inverse = false`.
    (**Default**: reverse video)
- `"badge_normal"`: Mode badge in the normal mode.
    (**Default**: bold, bright white on blue)
- `"badge_search"`: Mode badge in the search mode.
    (**Default**: bold, black on yellow)
- `"badge_visual"`: Mode badge in the visual mode.
    (**Default**: bold, bright white on magenta)
- `"message_info"`: Informative message on the status bar.
    (**Default**: bold, bright white on green)
- `"message_error"`: Error message on the status bar.
    (**Default**: bold, bright white on red)
- `"search_match"`: Inactive search match.
    (**Default**: black on white)
- `"search_active_match"`: Active search match.
    (**Default**: black on yellow)
- `"visual_line"`: Lines marked in the visual mode. Only its background is used.
    (**Default**: bright black background)
- `"visual_active_line"`: Visual line. Only its background is used.
    (**Default**: blue background)
- `"ruler"`: Line number ruler.
    (**Default**: bright black)
- `"scrollbar_track"`: Track of the scrollbar.
    (**Default**: bright black)
- `"scrollbar_thumb"`: Thumb of the scrollbar.
    (**Default**: no attributes)
- `"command_status"`: Status shown at the right of the command line, like the number of
    matches while searching.
    (**Default**: bright black)
- `"help_title"`: Title of the help screen.
    (**Default**: bold cyan)
- `"help_section"`: Section titles of the help screen.
    (**Default**: bold)
- `"help_description"`: Section descriptions and feature tags of the help screen.
    (**Default**: bright black)
- `"help_key"`: Keys of the help screen.
    (**Default**: cyan)
- `"help_action"`: Action names of the help screen.
    (**Default**: bold yellow)

## Throws

- `ArgumentError`: If `name` is not a pager face, or if a keyword is not a face attribute.

## Examples

```julia
julia> TerminalPager.set_face!("search_active_match"; background = :red)

julia> TerminalPager.set_face!("badge_normal"; foreground = "#ffffff", background = 0x005f87)

julia> TerminalPager.set_face!("status_bar"; foreground = :white, background = :blue, inverse = false)

julia> TerminalPager.set_face!("help_key", StyledStrings.Face(; weight = :bold, inherit = :terminalpager_help_title))
```
"""
function set_face!(name::AbstractString, face::Face)
    face_name = _face_name(name)

    faces = _face_preferences()
    spec = Dict{String, Any}(get(faces, name, Dict{String, Any}()))
    merge!(spec, _face_spec(face))
    faces[String(name)] = spec
    @set_preferences!(_FACES_PREFERENCE => faces)

    loadface!(face_name => face)

    return nothing
end

function set_face!(name::AbstractString; kwargs...)
    for key in keys(kwargs)
        hasfield(Face, key) || throw(
            ArgumentError(
                "\"$key\" is not a face attribute. The valid attributes are: " *
                    join(("`$f`" for f in fieldnames(Face)), ", ") * ".",
            ),
        )
    end

    return set_face!(name, Face(; kwargs...))
end

"""
    drop_face!(name::AbstractString) -> Nothing

Drop the customization of the pager face `name`, restoring its built-in default.

The persisted preference is removed and the face is reset for the current session, which
also discards any customization loaded from `faces.toml` until Julia is restarted.

All the faces can be restored at once with [`drop_all_preferences!`](@ref), which also drops
the other preferences of the package. To reset only the faces, remove the tables
`[TerminalPager.faces.<name>]` from the `LocalPreferences.toml` of the active environment
and restart Julia.

See also: [`set_face!`](@ref) and [`drop_all_preferences!`](@ref).

# Arguments

- `name::AbstractString`: Name of a pager face, without the prefix `terminalpager_`.

# Examples

```julia
julia> TerminalPager.drop_face!("search_active_match")

julia> TerminalPager.drop_all_preferences!()
```
"""
function drop_face!(name::AbstractString)
    face_name = _face_name(name)

    faces = _face_preferences()
    delete!(faces, String(name))

    if isempty(faces)
        @delete_preferences!(_FACES_PREFERENCE)
    else
        @set_preferences!(_FACES_PREFERENCE => faces)
    end

    resetfaces!(face_name)

    return nothing
end

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _register_faces!() -> Nothing

Register the default pager faces with StyledStrings.jl, keeping any customization the user
made in `faces.toml`.

The user faces are loaded lazily by StyledStrings.jl on Julia 1.11 and later. They are
loaded here explicitly, so that the precedence is always the same: the built-in defaults,
then `faces.toml`, and then the pager preferences.
"""
function _register_faces!()
    isdefined(StyledStrings, :load_customisations!) && StyledStrings.load_customisations!()

    for (name, face) in _FACES
        addface!(Symbol(_FACE_PREFIX, name) => face)
    end

    return nothing
end

"""
    _load_face_preferences!() -> Nothing

Apply the faces persisted with [`set_face!`](@ref) to the registered faces.

Entries that are not pager faces, or whose specification is not a table, are ignored with a
warning instead of breaking the package initialization.
"""
function _load_face_preferences!()
    faces = @load_preference(_FACES_PREFERENCE, nothing)
    isnothing(faces) && return nothing

    if !(faces isa AbstractDict)
        @warn "The preference \"$_FACES_PREFERENCE\" must be a table. It was ignored."
        return nothing
    end

    for (name, spec) in faces
        if !_is_face(name) || !(spec isa AbstractDict)
            @warn(
                "The entry \"$name\" of the preference \"$_FACES_PREFERENCE\" is not a " *
                    "valid pager face. It was ignored."
            )
            continue
        end

        loadface!(Symbol(_FACE_PREFIX, name) => convert(Face, Dict{String, Any}(spec)))
    end

    return nothing
end

"""
    _is_face(name::AbstractString) -> Bool

Return whether `name` is the name of a pager face, without the prefix.
"""
_is_face(name::AbstractString) = haskey(_DEFAULT_FACES, Symbol(name))

"""
    _face_name(name::AbstractString) -> Symbol

Return the name of the pager face `name` in the StyledStrings.jl registry, throwing an
`ArgumentError` if `name` is not a pager face.
"""
function _face_name(name::AbstractString)
    _is_face(name) || throw(
        ArgumentError(
            "\"$name\" is not a pager face. The available faces are: " *
                join(("\"$(first(f))\"" for f in _FACES), ", ") * ".",
        ),
    )

    return Symbol(_FACE_PREFIX, name)
end

"""
    _face_preferences() -> Dict{String, Any}

Return a copy of the faces persisted with [`set_face!`](@ref), keyed by the face name
without the prefix.
"""
function _face_preferences()
    faces = @load_preference(_FACES_PREFERENCE, nothing)
    faces isa AbstractDict || return Dict{String, Any}()
    return Dict{String, Any}(String(k) => v for (k, v) in faces)
end

"""
    _current_face(name::Symbol) -> Face

Return the pager face `name`, without the prefix, as it is currently registered, merged
with the faces it inherits from.
"""
_current_face(name::Symbol) = getface(Symbol(_FACE_PREFIX, name))

"""
    _default_face(name::Symbol) -> Face

Return the built-in default of the pager face `name`, without the prefix.
"""
_default_face(name::Symbol) = _DEFAULT_FACES[name]

"""
    _display_config(face_of::F = _current_face) -> DisplayConfig where {F <: Function}

Render every pager face into the escape sequences used by a pager session.

The faces are converted by **StringManipulation.jl**, so that each sequence resets the
terminal attributes and then selects the ones set in the face. The visual faces keep only
the SGR parameters of their background, like `"44"`, as `textview` expects for the visual
line backgrounds.

# Arguments

- `face_of::F`: Callable object returning the `Face` of a pager face name without the
    prefix.
    (**Default**: `_current_face`)
"""
function _display_config(face_of::F = _current_face) where {F <: Function}
    sgr(name::Symbol) = String(Decoration(face_of(name)))
    background(name::Symbol) = Decoration(face_of(name)).background

    return DisplayConfig(
        sgr(:status_bar),
        sgr(:badge_normal),
        sgr(:badge_search),
        sgr(:badge_visual),
        sgr(:message_info),
        sgr(:message_error),
        sgr(:search_match),
        sgr(:search_active_match),
        background(:visual_line),
        background(:visual_active_line),
        sgr(:ruler),
        sgr(:scrollbar_track),
        sgr(:scrollbar_thumb),
        sgr(:command_status),
        sgr(:help_title),
        sgr(:help_section),
        sgr(:help_description),
        sgr(:help_key),
        sgr(:help_action),
    )
end

"""
    DisplayConfig() -> DisplayConfig

Construct a display configuration from the built-in default faces.
"""
DisplayConfig() = _display_config(_default_face)

"""
    _face_spec(face::Face) -> Dict{String, Any}

Convert `face` into the table format of `faces.toml`, which is how the faces are persisted
with **Preferences.jl**. The attributes left unset in `face` are omitted.

# Arguments

- `face::Face`: Face to convert.
"""
function _face_spec(face::Face)
    spec = Dict{String, Any}()

    isnothing(face.font) || (spec["font"] = face.font)
    isnothing(face.height) || (spec["height"] = face.height)
    isnothing(face.weight) || (spec["weight"] = string(face.weight))
    isnothing(face.slant) || (spec["slant"] = string(face.slant))
    isnothing(face.foreground) || (spec["foreground"] = _color_spec(face.foreground))
    isnothing(face.background) || (spec["background"] = _color_spec(face.background))
    isnothing(face.strikethrough) || (spec["strikethrough"] = face.strikethrough)
    isnothing(face.inverse) || (spec["inverse"] = face.inverse)
    isempty(face.inherit) || (spec["inherit"] = string.(face.inherit))

    underline = face.underline

    if underline isa Bool
        spec["underline"] = underline
    elseif underline isa SimpleColor
        spec["underline"] = _color_spec(underline)
    elseif underline isa Tuple
        color, style = underline
        spec["underline"] = [isnothing(color) ? "" : _color_spec(color), string(style)]
    end

    return spec
end

"""
    _color_spec(color::SimpleColor) -> String

Convert `color` into the string format of `faces.toml`: the name of a named color, or
`"#rrggbb"` for a 24-bit color.

# Arguments

- `color::SimpleColor`: Color to convert.
"""
function _color_spec(color::SimpleColor)
    value = color.value
    value isa Symbol && return string(value)
    return string(
        '#',
        string(value.r; base = 16, pad = 2),
        string(value.g; base = 16, pad = 2),
        string(value.b; base = 16, pad = 2),
    )
end
