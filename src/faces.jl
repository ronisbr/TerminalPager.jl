## Description #############################################################################
#
# Faces that style the pager. They are registered with StyledStrings.jl, so that the user
# can customize them in `faces.toml`.
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

############################################################################################
#                                    Private Functions                                     #
############################################################################################

"""
    _register_faces!() -> Nothing

Register the default pager faces with StyledStrings.jl, keeping any customization the user
made in `faces.toml`.

The user faces are loaded lazily by StyledStrings.jl on Julia 1.11 and later. They are
loaded here explicitly, so that the precedence is always the same: the built-in defaults,
and then `faces.toml`.
"""
function _register_faces!()
    isdefined(StyledStrings, :load_customisations!) && StyledStrings.load_customisations!()

    for (name, face) in _FACES
        addface!(Symbol(_FACE_PREFIX, name) => face)
    end

    return nothing
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

# Arguments

- `face_of::F`: Callable object returning the `Face` of a pager face name without the
    prefix.
    (**Default**: `_current_face`)
"""
function _display_config(face_of::F = _current_face) where {F <: Function}
    return DisplayConfig(
        _face_sgr(face_of(:status_bar)),
        _face_sgr(face_of(:badge_normal)),
        _face_sgr(face_of(:badge_search)),
        _face_sgr(face_of(:badge_visual)),
        _face_sgr(face_of(:message_info)),
        _face_sgr(face_of(:message_error)),
        _face_sgr(face_of(:search_match)),
        _face_sgr(face_of(:search_active_match)),
        _face_background_sgr(face_of(:visual_line)),
        _face_background_sgr(face_of(:visual_active_line)),
        _face_sgr(face_of(:ruler)),
        _face_sgr(face_of(:scrollbar_track)),
        _face_sgr(face_of(:scrollbar_thumb)),
        _face_sgr(face_of(:command_status)),
        _face_sgr(face_of(:help_title)),
        _face_sgr(face_of(:help_section)),
        _face_sgr(face_of(:help_description)),
        _face_sgr(face_of(:help_key)),
        _face_sgr(face_of(:help_action)),
    )
end

"""
    DisplayConfig() -> DisplayConfig

Construct a display configuration from the built-in default faces.
"""
DisplayConfig() = _display_config(_default_face)

# NOTE: The rendering below relies on `StyledStrings.termcolor`, which is not part of the
# public API of StyledStrings.jl. The public `termstyle` cannot be used because it consults
# the terminfo database and silently drops the reverse video, on which the status bar
# depends, when `TERM` is `dumb` or unset. `termcolor` has kept the same signature since the
# first release of StyledStrings.jl, and it handles named colors, 24-bit colors with an
# 8-bit fallback, and colors that name another face.

"""
    _face_sgr(face::Face) -> String

Render `face` into an SGR escape sequence that resets the terminal attributes and then
selects the ones set in `face`. The attributes left unset, or set to their defaults, are
not written.

# Arguments

- `face::Face`: Face to render.
"""
function _face_sgr(face::Face)
    buf = IOBuffer()

    write(buf, CSI, '0')

    weight = face.weight
    (weight ∈ (:medium, :semibold, :bold, :extrabold, :black)) && write(buf, ";1")
    (weight ∈ (:semilight, :light, :extralight, :thin)) && write(buf, ";2")
    (face.slant ∈ (:italic, :oblique)) && write(buf, ";3")
    (face.underline ∉ (nothing, false)) && write(buf, ";4")
    (face.strikethrough === true) && write(buf, ";9")
    (face.inverse === true) && write(buf, ";7")

    write(buf, 'm')

    _write_color(buf, face.foreground, '3')
    _write_color(buf, face.background, '4')

    return String(take!(buf))
end

"""
    _face_background_sgr(face::Face) -> String

Render the background of `face` into the parameters of an SGR escape sequence, like `"44"`
or `"48;2;0;95;135"`, as `textview` expects for the visual line backgrounds. Return an empty
string when the background is unset or the default one.

# Arguments

- `face::Face`: Face whose background is rendered.
"""
function _face_background_sgr(face::Face)
    buf = IOBuffer()
    _write_color(buf, face.background, '4')
    sequence = String(take!(buf))
    isempty(sequence) && return sequence

    # `termcolor` writes `\\e[<parameters>m`. Only the parameters are returned.
    return sequence[(ncodeunits(CSI) + 1):(end - 1)]
end

"""
    _write_color(
        buf::IOBuffer,
        color::Union{Nothing, SimpleColor},
        category::Char,
    ) -> Nothing

Write the SGR escape sequence selecting `color` for `category` to `buf`, where the category
is `'3'` for the foreground and `'4'` for the background. Nothing is written when `color` is
unset or the default one, which the reset written before already selects.

# Arguments

- `buf::IOBuffer`: Buffer receiving the sequence.
- `color::Union{Nothing, SimpleColor}`: Color to select.
- `category::Char`: SGR category of the color.
"""
function _write_color(buf::IOBuffer, color::Union{Nothing, SimpleColor}, category::Char)
    isnothing(color) && return nothing
    (color == SimpleColor(:default)) && return nothing
    StyledStrings.termcolor(buf, color, category)
    return nothing
end
