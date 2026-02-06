module TerminalPagerAboutExt

using About: about
using TerminalPager: _register_shortcuts, _show_pager_cursor, @help, @stdout_to_pager

# This is a simplified copy of the function in TerminalPager.jl.
function __init__()
    if isdefined(Base, :active_repl)
        _register_about_shortcut(Base.active_repl)
    else
        _register_about_shortcut |> atreplinit
    end

    return nothing
end

"""
    _register_about_shortcut(repl) -> Nothing

Register the `<Alt> + a` shortcut in the REPL to show about information for the identifier
under the cursor.
"""
function _register_about_shortcut(repl)
    _register_shortcuts(repl) do escapes
        escapes['a'] = _show_pager_about  # <Alt> + a
    end
end

"""
    _show_pager_about(s, _, _) -> Symbol

Show `about` of the identifier under the cursor in the REPL.
"""
function _show_pager_about(s, _, _)
    _show_pager_cursor(s) do identifier
        try
            # We have the identifier as a string, but `about` needs the actual object.
            # So parse it and evaluate it in the REPL's active module.
            obj = Base.eval(s.active_module, identifier |> Meta.parse)
             # Use @stdout_to_pager macro which will temporarily take over terminal control.
            @stdout_to_pager(about(stdout, obj), use_alternate_screen_buffer = true)
        catch
            # The help system already has a good error message, so reuse that one.
            @eval(@help $identifier)
        end
    end
end

end