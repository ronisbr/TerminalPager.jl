Customization
=============

The user can customize some preferences in **TerminalPager.jl**. We handle those
customization using [Preferences.jl](https://github.com/JuliaPackaging/Preferences.jl).
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

The list of available properties are:

- `"active_search_decoration"`: `String` with the ANSI escape sequence to decorate the
    active search element. One can easily obtain this sequence by converting a `Crayon` to
    string. (**Default** = `string(crayon"black bg:yellow")`)
- `"inactive_search_decoration"`: `String` with the ANSI escape sequence to decorate the
    inactive search element. One can easily obtain this sequence by converting a `Crayon` to
    string. (**Default** = `string(crayon"black bg:light_gray")`)
- `"always_use_alternate_screen_buffer_in_repl_mode"`: If `true`, we will always use the
    alternate screen buffer when showing the pager in REPL mode. (**Default** = false)
- `"block_alternate_screen_buffer"`: If `true`, the alternate screen buffer support will be
    globally blocked, regardless of the keyword options. This modification is helpful when
    the terminal is not compatible with XTerm. (**Default** = `false`)
- `"pager_mode"`: If it is "vi", some keywords are modified to match the behavior of Vi.
    Notice that this change only takes effect when a new Julia session is initialized.
    (**Default** = "default")
- `"visual_mode_line_background"`: `String` with the ANSI code of the background for the
    selected lines in the visual mode. (**Default** = "100")
- `"visual_mode_active_line_background"`: `String` with the ANSI code of the background for
    the active line in the visual mode. (**Default** = "44")

For example, if the user wants to change the active search decoration to blue, they should
do:

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
