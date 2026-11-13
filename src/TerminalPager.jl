module TerminalPager

# The code implementing the inline help triggered by a shortcut accesses the following
# private identifiers in addition to various field accesses. This is not ideal, but
# neither JuliaSyntax nor REPL.LineEdit seem to provide a public API for this. This means
# `TerminalPager.jl` is strongly coupled with `JuliaSyntax.jl` and `REPL.jl`.
using Base.JuliaSyntax
using Base.JuliaSyntax: is_keyword, @KSet_str, sourcetext, span

using REPL
using REPL.LineEdit
using REPL.LineEdit: buffer, input_string

using InteractiveUtils
using Markdown
using Preferences
using StyledStrings
using StyledStrings: Face, SimpleColor, addface!, getface, loadface!, resetfaces!

# Only the string utilities are used. The view is rendered by this package, so the module is
# imported instead of used, and the names are listed, to make sure nothing else is reached.
import StringManipulation
using StringManipulation: Decoration, get_decorations, highlight_search, left_crop,
    parse_decoration, printable_textwidth, remove_decorations, replace_default_background,
    split_string, string_search_per_line, update_decoration

# The performance of TerminalPager.jl does not improve with many compiler optimizations.
# Hence, we disable them to improve compile time.
if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@optlevel"))
    @eval Base.Experimental.@optlevel 1
end

############################################################################################
#                                          Types                                           #
############################################################################################

# The layout is a field of the pager state, so it must be defined before the types.
include("./view/layout.jl")
include("./types.jl")

############################################################################################
#                                        Constants                                         #
############################################################################################

const CSI = "\x1b["

# SGR sequence resetting every text attribute. The other sequences come from the faces.
const _SGR_RESET = "$(CSI)0m"

############################################################################################
#                                         Includes                                         #
############################################################################################

include("./command_line.jl")
include("./debug.jl")
include("./faces.jl")
include("./filter.jl")
include("./help.jl")
include("./helpers.jl")
include("./history.jl")
include("./preferences.jl")
include("./recipes.jl")
include("./repl.jl")
include("./screen.jl")
include("./search.jl")
include("./view.jl")

include("./pager/events.jl")
include("./pager/freeze.jl")
include("./pager/position.jl")
include("./pager/session.jl")
include("./pager/state.jl")
include("./pager/toggles.jl")
include("./pager/visual.jl")
include("./pager/yank.jl")

include("./view/redraw.jl")
include("./view/render.jl")

include("./input/keybindings.jl")
include("./input/input.jl")
include("./input/waiter.jl")

include("./help_keybinding.jl")

export pager

"""
    pager(obj::Any; kwargs...) -> Union{Nothing, PagerResult}

Call the pager to show the output of the object `obj`. Return `nothing`, or the
[`PagerResult`](@ref) of the session when the keyword `return_selection` is `true`.

The default keywords of `obj` come from its recipe, [`pager_options`](@ref), which packages
and users define for their types. For example, an array keeps its summary line on top. The
keywords passed explicitly win over the recipe.

# Arguments

- `obj::Any`: Object to render and display.

# Keywords

!!! info
    Some of the default values shown here can be modified by user-defined preferences.

- `auto::Bool`: Show the pager only when the output does not fit in the display.
    (**Default**: `false`)
- `return_selection::Bool`: Return the [`PagerResult`](@ref) of the session, with the lines
    copied by the last yank, the viewport, and the search pattern, instead of `nothing`.
    (**Default**: `false`)
- `change_freeze::Bool`: If `true`, then the user can change the number of frozen rows and
    columns inside the pager.
    (**Default**: `true`)
- `frozen_columns::Int`: Number of columns to freeze at startup.
    (**Default**: `0`)
- `frozen_rows::Int`: Number of rows to freeze at startup.
    (**Default**: `0`)
- `title_rows::Int`: Number of frozen rows treated as horizontally fixed titles.
    (**Default**: `0`)
- `has_help::Bool`: Allow the user to open pager help.
    (**Default**: `true`)
- `has_visual_mode::Bool`: Allow the user to use visual mode.
    (**Default**: `true`)
- `show_ruler::Bool`: If `true`, a vertical ruler is shown in the pager with the line
    numbers.
    (**Default**: `false`)
- `show_column_ruler::Bool`: If `true`, a two-row ruler with the column numbers is shown
    on top of the view.
    (**Default**: the value of the preference `"show_column_ruler"`)
- `show_scrollbar::Bool`: If `true`, a scrollbar is shown at the right edge of the view.
    (**Default**: the value of the preference `"show_scrollbar"`)
- `use_alternate_screen_buffer::Bool`: If `true`, the pager will use the alternate screen
    buffer, which restores the current screen when exiting the pager and lets the mouse
    wheel scroll the pager in most terminals. Notice, however, that we use the XTerm escape
    sequences here. Hence, if your terminal is different, this option can lead to rendering
    problems, in which case it can be disabled globally with the preference
    `"block_alternate_screen_buffer"`.
    (**Default**: `true`)

# Preferences

The user can define custom preferences using the function
[`TerminalPager.set_preference!`](@ref). The available preferences are listed as follows:

- `"always_use_alternate_screen_buffer_in_repl_mode"`: Deprecated and ignored, because the
    alternate screen buffer is now used by default. Use `"block_alternate_screen_buffer"` to
    disable it.
    (**Default**: `false`)
- `"block_alternate_screen_buffer"`: If `true`, the alternate screen buffer support will be
    globally blocked, regardless of the keyword options. This modification is helpful when
    the terminal is not compatible with XTerm.
    (**Default**: `false`)
- `"copy_stdout_to_clipboard_in_repl_mode"`: If `true`, the output of every command of the
    `pager>` REPL mode that does not throw is also copied to the system clipboard, without
    any decoration, even when it fits the display and no pager is opened.
    (**Default**: `false`)
- `"history_size"`: Number of texts shown by the pager that are kept in the history, which
    `TerminalPager.last` reopens.
    (**Default**: `5`)
- `"history_max_bytes"`: Number of bytes of the texts kept in the history. The oldest texts
    are dropped beyond it, but the most recent one is always kept.
    (**Default**: `50_000_000`)
- `"mouse"`: If `true`, the pager reports the mouse events: the wheel scrolls the text, SHIFT
    and the wheel scroll it horizontally, and clicking a line in the visual mode moves the
    visual line to it or marks it. Notice that, while the mouse is reported, selecting text
    with the terminal requires holding SHIFT, or OPTION on some terminals.
    (**Default**: `true`)
- `"pager_mode"`: If it is `"vi"`, some keybindings are modified to match the behavior of Vi.
    Notice that this change only takes effect when a new Julia session is initialized.
    (**Default**: `"default"`)
- `"repl_mode_display"`: If it is `"stack"`, the value of a `pager>` command goes through
    the display stack like in the regular REPL, so that a display pushed by a package, such
    as a plot window, shows it; the pager renders it only when no display accepts it. If it
    is `"pager"`, the value is always rendered into the pager.
    (**Default**: `"stack"`)
- `"replace_help_mode"`: If `true`, the answers of the regular `help?>` prompt are shown
    in the pager when they do not fit the display, like the ones of the `pager?>` prompt.
    Notice that this change only takes effect when a new Julia session is initialized, and
    that it replaces the callback of the prompt, so other packages hooking it are bypassed.
    (**Default**: `false`)
- `"show_scrollbar"`: If `true`, the pager shows a scrollbar at the right edge of the view
    unless the keyword `show_scrollbar` says otherwise.
    (**Default**: `false`)
- `"status_position"`: Style of the position at the right of the status line: `"percent"`
    shows `All`, `Top`, `Bot`, or the percentage of the text above the bottom of the view,
    `"line"` shows the top row over the number of lines, like `L120/3456`, and `"both"`
    shows the two.
    (**Default**: `"percent"`)
- `"use_scroll_regions"`: If `true`, scrolling asks the terminal to shift the rows it
    already shows and repaints only the new ones, which makes scrolling much cheaper on
    large windows and slow connections. Disable it if your terminal does not support the
    XTerm scroll region sequences.
    (**Default**: `true`)

For more information, see: [`TerminalPager.set_preference!`](@ref),
[`TerminalPager.drop_preference!`](@ref), and [`TerminalPager.drop_all_preferences!`](@ref).

# Faces

The colors and the text attributes of the pager are faces registered with
**StyledStrings.jl** under the prefix `terminalpager_`. They can be customized with
[`TerminalPager.set_face!`](@ref), which persists the change as a preference, or in the
file `config/faces.toml` of the Julia depot under the tables `[terminalpager.<name>]`. The
available faces are listed as follows:

- `"status_bar"`: Base of the status line, which is the last row of the display. It holds
    the prompt of the normal mode, the position, and the search and visual mode
    details, and every other element of the row returns to it. Set `inverse = true` to draw
    the row as a bar.
    (**Default**: no attributes)
- `"status_hint"`: Key hints, feature tags, and the hints that the text continues beyond
    the edges of the view.
    (**Default**: bright black)
- `"mode_search"`: Name of the search mode on the status line.
    (**Default**: bold yellow)
- `"mode_visual"`: Name of the visual mode on the status line.
    (**Default**: bold magenta)
- `"mode_freeze"`: Name of the freeze selection mode on the status line.
    (**Default**: bold cyan)
- `"mode_filter"`: Name of the filter state on the status line.
    (**Default**: bold green)
- `"message_info"`: Informative message on the status line.
    (**Default**: green)
- `"message_error"`: Error message on the status line.
    (**Default**: red)
- `"search_match"`: Inactive search match.
    (**Default**: black on white)
- `"search_active_match"`: Active search match.
    (**Default**: black on yellow)
- `"visual_line"`: Lines marked in the visual mode. Only its background is used.
    (**Default**: bright black background)
- `"visual_active_line"`: Visual line. Only its background is used.
    (**Default**: blue background)
- `"freeze_guide"`: Guide lines of the freeze selection mode.
    (**Default**: bold cyan)
- `"ruler"`: Line number ruler.
    (**Default**: bright black)
- `"bookmark"`: Mark of a bookmarked line in the line number ruler.
    (**Default**: yellow)
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

For more information, see: [`TerminalPager.set_face!`](@ref) and
[`TerminalPager.drop_face!`](@ref).
"""
function pager(@nospecialize(obj::Any); kwargs...)
    # NOTE: This function and the ones that render the object do not specialize on its
    # type. Otherwise, all of them are compiled again for each type of object shown in a
    # session, which takes much longer than rendering the object itself.
    rendered, options = _object_pager_call(obj, kwargs)
    return pager(rendered; options...)
end

"""
    pager(obj::AbstractString; kwargs...) -> Union{Nothing, PagerResult}

Show the text in `obj` using the terminal pager.

If the standard input or output is not a terminal, for example in a script whose output is
redirected or in a notebook, the text is printed instead.

# Arguments

- `obj::AbstractString`: Text to display without applying plain-text object rendering.

# Keywords

- `return_selection::Bool`: Return the [`PagerResult`](@ref) of the session instead of
    `nothing`. The result of a printed text is empty.
    (**Default**: `false`)
- `kwargs...`: Pager options documented by [`pager(::Any; kwargs...)`](@ref).
"""
function pager(obj::AbstractString; @nospecialize(kwargs...))
    # NOTE: This function does not specialize on the keywords, which are read with built-in
    # functions and collected into the options of the session. Otherwise, every function
    # that starts the session is compiled again for each combination of keywords.
    keywords = getfield(kwargs, :data)

    return_selection = if isdefined(keywords, :return_selection)
        getfield(keywords, :return_selection)::Bool
    else
        false
    end

    # If we have a context key called `bypass_pager` with the value `true`, we must not call
    # the pager because we are in the pager> REPL mode. Otherwise, the pager locks the
    # screen until the user types CTRL-D. For more information, see:
    #
    #   https://github.com/ronisbr/TerminalPager.jl/issues/40
    #
    # In addition, without a terminal on both ends, the pager can neither read keystrokes
    # nor paint the screen. Like `less`, print the text instead. It used to paint escape
    # sequences into the redirected output and then throw when the input reached its end.
    if get(stdout, :bypass_pager, false) || !(_is_terminal(stdin) && _is_terminal(stdout))
        print(obj)
        return return_selection ? _empty_result() : nothing
    end

    # `_pager` requires a `String`. The conversion is a no-op for a `String`, whereas any
    # other subtype, such as a `SubString`, must be copied.
    str = String(obj)
    options = _session_options(keywords)

    # The text is recorded before the session, so that a session interrupted with CTRL-C is
    # in the history too. Its result restores the viewport when the text is reopened.
    entry = _push_pager_history!(str, keywords)
    result = _pager(str, options)
    (result isa PagerResult) && (entry.result = result)

    return return_selection ? result : nothing
end

const less = pager

"""
    _is_terminal(io::IO) -> Bool

Return whether `io` is a terminal, looking through an `IOContext`.

# Arguments

- `io::IO`: Stream to inspect.
"""
_is_terminal(io::IO) = (io isa IOContext ? io.io : io) isa Base.TTY

"""
    _render_object(obj::Any) -> String

Render `obj` with `show` and `MIME"text/plain"` for the color support and display size of
`stdout`, without any limit on the output size.

# Arguments

- `obj::Any`: Object to render.
"""
function _render_object(@nospecialize(obj))
    # The rendering must honor the color support and the size of the current output.
    # Rendering with color unconditionally showed raw ANSI escapes on terminals without
    # color support, and rendering without the display size wrapped Markdown, and any other
    # object that consults it, at the default 80 columns regardless of the terminal width.
    # The limit is disabled explicitly because the pager exists to show the whole object.
    #
    # A terminal always reports its color support. A stream without the property, such as a
    # redirected output, must not receive escape sequences, like `show` does.
    hascolor = get(stdout, :color, false)::Bool
    buf = IOBuffer()
    io = IOContext(
        buf, :color => hascolor, :displaysize => displaysize(stdout), :limit => false
    )

    # Notice that `sprint` is not used because it would be compiled for each type of object.
    show(io, MIME"text/plain"(), obj)

    return String(take!(buf))
end

"""
    __init__() -> Nothing

Apply mode-dependent keybindings and initialize REPL integrations.
"""
function __init__()
    # The preference cache is populated while the package is precompiled, and the cached
    # values are serialized into the compiled image. Drop it here so that a session never
    # starts with values captured at precompile time.
    _invalidate_preference_cache!()

    # The precompile workload confirms a search, and the history it leaves is serialized
    # into the compiled image as well. Hence, the history is emptied so that every session
    # starts without the patterns of another one.
    empty!(_SEARCH_HISTORY)
    empty!(_SAVE_HISTORY)
    empty!(_FILTER_HISTORY)
    empty!(_LAST_YANK)
    empty!(_PAGER_HISTORY)

    # The functions replaced by the precompilation workload are also serialized.
    _CLIPBOARD[] = InteractiveUtils.clipboard

    # The faces live in the registry of StyledStrings.jl, which is not serialized with this
    # package. Hence, they must be registered at every session start, and only then can the
    # customized ones be applied.
    _register_faces!()
    _load_face_preferences!()

    # Modify the key bindings if the user wants `vi` mode, and then apply the persisted ones,
    # which take precedence over the mode bindings.
    _apply_mode_keybindings!()
    _load_keybindings!()

    # The integrations with the REPL are initialized now if it is already running, or when
    # it starts otherwise.
    if isdefined(Base, :active_repl)
        _init_repl_integrations(Base.active_repl)
    else
        atreplinit(_init_repl_integrations)
    end

    return nothing
end

"""
    _init_repl_integrations(repl::Any) -> Nothing

Initialize the pager REPL mode and the shortcuts in `repl`, if the session is interactive
and `repl` is a line-edit REPL.

Non-line-edit REPLs, such as the basic REPL used on a dumb terminal, have no keymap
interface. Initializing the pager mode there broke package loading, and the shortcut
registration leaked a task that never terminates.

# Arguments

- `repl::Any`: Active REPL, or the one passed to the `atreplinit` hooks.
"""
function _init_repl_integrations(repl)
    (isinteractive() && repl isa REPL.LineEditREPL) || return nothing

    # The interface of the REPL is not set up yet when the package is loaded from an
    # `atreplinit` hook. We must not call `REPL.setup_interface` here: it is called later
    # by `run_frontend`, which respects user options such as `auto_insert_closing_bracket`,
    # and calling it early would bypass any options set by other `atreplinit` hooks.
    if isdefined(repl, :interface)
        _init_pager_repl_mode(repl)
    else
        _init_pager_repl_mode_when_ready(repl)
    end

    _register_help_shortcuts(repl)
    _register_history_shortcuts(repl)
    _register_pipe_shortcuts(repl)

    return nothing
end

############################################################################################
#                                      Precompilation                                      #
############################################################################################

include("precompilation.jl")

end # module
