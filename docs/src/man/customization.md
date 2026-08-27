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

- `"active_search_decoration"`: `String` with the ANSI escape sequence to decorate the
    active search element. One can easily obtain this sequence by converting a `Crayon` to
    string. (**Default** = `string(crayon"black bg:yellow")`)
- `"inactive_search_decoration"`: `String` with the ANSI escape sequence to decorate the
    inactive search element. One can easily obtain this sequence by converting a `Crayon` to
    string. (**Default** = `string(crayon"black bg:light_gray")`)
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
- `"visual_mode_line_background"`: `String` with the ANSI code of the background for the
    selected lines in the visual mode. (**Default** = `"100"`)
- `"visual_mode_active_line_background"`: `String` with the ANSI code of the background for
    the active line in the visual mode. (**Default** = `"44"`)

For example, if the user wants to change the active search decoration to a red background,
they should do:

```julia
julia> using TerminalPager.Crayons

julia> TerminalPager.set_preference!("active_search_decoration", string(crayon"black bg:red"))
```

The default value can be restored by:

```julia
julia> TerminalPager.drop_preference!("active_search_decoration")
```

## Keybindings

The user can also change the default keybindings to perform actions inside the pager. For
more information, see the functions: [`TerminalPager.set_keybinding`](@ref),
[`TerminalPager.delete_keybinding`](@ref), and [`TerminalPager.reset_keybindings`](@ref).
Notice that those modifications **do not** persist between Julia sessions. Hence, if the
user wants a permanent configuration, they should add those commands to the `startup.jl`
script.
