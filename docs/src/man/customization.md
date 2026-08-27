# Customization

The user can customize some preferences in **TerminalPager.jl**. We handle those
preferences using [Preferences.jl](https://github.com/JuliaPackaging/Preferences.jl).
Thus, they persist between Julia sessions.

To add a new `value` to a `preference`, use the function:

```julia
TerminalPager.set_preference!(preference, value)
```

To drop the customized value for the `preference`, use:

```julia
TerminalPager.drop_preference!(preference)
```

To drop all the customized values, use:

```julia
TerminalPager.drop_all_preferences!()
```

The available preferences are:

- `"always_use_alternate_screen_buffer_in_repl_mode"`: Deprecated and ignored, because the
    alternate screen buffer is now used by default. Use `"block_alternate_screen_buffer"` to
    disable it. (**Default** = `false`)
- `"block_alternate_screen_buffer"`: If `true`, the alternate screen buffer support will be
    globally blocked, regardless of the keyword options. This modification is helpful when
    the terminal is not compatible with XTerm. (**Default** = `false`)
- `"copy_stdout_to_clipboard_in_repl_mode"`: If `true`, when the pager is exited in REPL
    mode, the output will be copied to the clipboard. Notice that the decorations (ANSI
    sequences) will be removed. (**Default** = `false`)
- `"mouse"`: If `true`, the pager reports the mouse events: the wheel scrolls the text,
    SHIFT and the wheel scroll it horizontally, and clicking a line in the visual mode moves
    the visual line to it or marks it. Notice that, while the mouse is reported, selecting
    text with the terminal requires holding SHIFT, or OPTION on some terminals.
    (**Default** = `true`)
- `"pager_mode"`: If it is `"vi"`, some keybindings are modified to match the behavior of
    Vi. Notice that this change only takes effect when a new Julia session is initialized.
    (**Default** = `"default"`)
- `"show_scrollbar"`: If `true`, the pager shows a scrollbar at the right edge of the view
    unless the keyword `show_scrollbar` says otherwise. (**Default** = `false`)
- `"use_scroll_regions"`: If `true`, scrolling asks the terminal to shift the rows it
    already shows and repaints only the new ones, which makes scrolling much cheaper on
    large windows and slow connections. Disable it if your terminal does not support the
    XTerm scroll region sequences. (**Default** = `true`)

For example, if the user wants to show the scrollbar in every pager, they should do:

```julia
julia> TerminalPager.set_preference!("show_scrollbar", true)
```

The default value can be restored by:

```julia
julia> TerminalPager.drop_preference!("show_scrollbar")
```

## Faces

The colors and the text attributes of the pager are defined by faces of
[StyledStrings.jl](https://github.com/JuliaLang/StyledStrings.jl), registered under the
prefix `terminalpager_`. The available faces are:

| Face                  | Description                                            | Default                            |
|:----------------------|:-------------------------------------------------------|:-----------------------------------|
| `status_bar`          | Status bar.                                            | Reverse video.                     |
| `badge_normal`        | Mode badge in the normal mode.                         | Bold, bright white on blue.        |
| `badge_search`        | Mode badge in the search mode.                         | Bold, black on yellow.             |
| `badge_visual`        | Mode badge in the visual mode.                         | Bold, bright white on magenta.     |
| `message_info`        | Informative message on the status bar.                 | Bold, bright white on green.       |
| `message_error`       | Error message on the status bar.                       | Bold, bright white on red.         |
| `search_match`        | Inactive search match.                                 | Black on white.                    |
| `search_active_match` | Active search match.                                   | Black on yellow.                   |
| `visual_line`         | Lines marked in the visual mode (background only).     | Bright black background.           |
| `visual_active_line`  | Visual line (background only).                         | Blue background.                   |
| `ruler`               | Line number ruler.                                     | Bright black.                      |
| `scrollbar_track`     | Track of the scrollbar.                                | Bright black.                      |
| `scrollbar_thumb`     | Thumb of the scrollbar.                                | No attributes.                     |
| `command_status`      | Status at the right of the command line.               | Bright black.                      |
| `help_title`          | Title of the help screen.                              | Bold cyan.                         |
| `help_section`        | Section titles of the help screen.                     | Bold.                              |
| `help_description`    | Section descriptions and feature tags of the help.     | Bright black.                      |
| `help_key`            | Keys of the help screen.                               | Cyan.                              |
| `help_action`         | Action names of the help screen.                       | Bold yellow.                       |

A face can be customized with [`TerminalPager.set_face!`](@ref), which accepts the keywords
of `StyledStrings.Face` (`foreground`, `background`, `weight`, `slant`, `underline`,
`strikethrough`, `inverse`, and `inherit`) or a `Face`. The attributes are merged into the
current face, applied to the next pager, and persisted with Preferences.jl. For example, to
show the active search match in white over red:

```julia
julia> TerminalPager.set_face!("search_active_match"; foreground = :white, background = :red)
```

The colors can be the names of the 16 terminal colors (`black`, `red`, `green`, `yellow`,
`blue`, `magenta`, `cyan`, `white`, and their `bright_` variants) or 24-bit colors written as
`"#rrggbb"`. The default face can be restored with:

```julia
julia> TerminalPager.drop_face!("search_active_match")
```

The faces are stored in the preference `faces` with the same format as `faces.toml`, so they
can also be edited directly in the `LocalPreferences.toml` of the active environment:

```toml
[TerminalPager.faces.search_active_match]
foreground = "white"
background = "red"
```

Finally, since the faces are registered with StyledStrings.jl, they can also be customized
in the file `config/faces.toml` of the Julia depot, usually `~/.julia/config/faces.toml`:

```toml
[terminalpager.search_active_match]
foreground = "white"
background = "red"
```

The pager applies the built-in defaults first, then `faces.toml`, and finally the
preferences set with [`TerminalPager.set_face!`](@ref).

## Keybindings

The user can also change the default keybindings to perform actions inside the pager. For
more information, see the functions: [`TerminalPager.set_keybinding`](@ref),
[`TerminalPager.delete_keybinding`](@ref), and [`TerminalPager.reset_keybindings`](@ref).
Notice that those modifications **do not** persist between Julia sessions. Hence, if the
user wants a permanent configuration, they should add those commands to the `startup.jl`
script.
