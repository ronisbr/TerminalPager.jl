module TerminalPagerAboutExt

using About: about
using TerminalPager: _register_shortcuts, _show_help, _show_pager_cursor, @stdout_to_pager

"""
    __init__() -> Nothing

Register the About keybinding immediately or after REPL initialization.
"""
function __init__()
    if isdefined(Base, :active_repl)
        _register_about_shortcut(Base.active_repl)
    else
        atreplinit(_register_about_shortcut)
    end

    return nothing
end

"""
    _register_about_shortcut(repl::Any) -> Task

Register the `<Alt> + a` shortcut in the REPL to show about information for the identifier
under the cursor.

# Arguments

- `repl::Any`: REPL instance whose keymaps are updated asynchronously.

# Returns

- `Task`: Asynchronous task that updates the keymaps.
"""
function _register_about_shortcut(repl)
    _register_shortcuts(repl) do escapes
        # Bind <Alt> + a to the About callback.
        escapes['a'] = _show_pager_about
    end
end

"""
    _show_pager_about(s::Any, _key::Any, _context::Any) -> Nothing

Show `about` of the identifier under the cursor in the REPL.

# Arguments

- `s::Any`: Current REPL line-edit state.
- `_key::Any`: Keybinding callback key, which is ignored.
- `_context::Any`: Keybinding callback context, which is ignored.
"""
function _show_pager_about(s, _key, _context)
    _show_pager_cursor(s) do identifier
        show_about =
            obj -> @stdout_to_pager(about(stdout, obj), use_alternate_screen_buffer = true)
        _show_about(identifier, s.active_module, Base.eval, show_about, _show_help)
    end
end

"""
    _show_about(
        identifier::AbstractString,
        mod::Module,
        evaluate::Any,
        show_about::Any,
        show_help::Any
    ) -> Nothing

Evaluate and show About information for `identifier`, falling back to help on errors.

# Arguments

- `identifier::AbstractString`: Identifier text to parse and evaluate.
- `mod::Module`: Module passed to `evaluate`.
- `evaluate::Any`: Callable object used to evaluate the parsed identifier.
- `show_about::Any`: Callable object used to display About information.
- `show_help::Any`: Callable fallback used to display help.
"""
function _show_about(identifier, mod, evaluate, show_about, show_help)
    try
        # About needs the object represented by the identifier string.
        obj = evaluate(mod, Meta.parse(identifier))
        show_about(obj)
    catch
        # The help system already has a good error message, so reuse that one.
        show_help(identifier, mod)
    end

    return nothing
end

end
