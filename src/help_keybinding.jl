## Description #############################################################################
#
# This script adds keybindings to the Julia REPL to show help for the identifier under the
# cursor.
#
############################################################################################

"""
    _extract_identifier(input::AbstractString, cursor_pos::Integer) -> String

Extract identifier from the input line using the cursor position.

If the cursor is on an identifier (including module hierarchy like A.B.C) or on
the character behind it, return that identifier. If the cursor is not on an identifier,
but in the argument/parameter list of a valid callable, return the callable name.

Extraction works even for invalid (i.e. incomplete) input.

# Arguments

- `input::AbstractString`: REPL input text to inspect.
- `cursor_pos::Integer`: Character cursor position in `input`.
"""
function _extract_identifier(input::AbstractString, cursor_pos::Integer)::String
    input_str = string(input)
    isempty(strip(input_str)) && return ""

    # Parse the input string into an AST.
    head = _tryparsestmt(input_str)

    # Use the cursor position to find the byte index in the input string to search for.
    # This might virtually shift the cursor position to match the intended identifier.
    # This collaterates (moving sideways) the AST or enters a branch if out-of-tree.
    search_index = _collaterate(input_str, cursor_pos)

    # Find the most specific syntax node containing `search_index` by descending the AST.
    descendant = _descend(head, search_index)

    # Find the least generic syntax node containing all the information needed for `@help`.
    # This ascends the AST.
    ascendant = _ascend(descendant)

    # Extract the string from the syntax node to be provided for `@help`.
    # This can go downwards into a *different branch* of the AST.
    return _helpstring(ascendant)
end

"""
    _collaterate(input::String, cursor_pos::Integer) -> Int

Based on cursor position, collaterate (branch) to the intended token's index.

# Arguments

- `input::String`: REPL input text to inspect.
- `cursor_pos::Integer`: Character cursor position in `input`.
"""
function _collaterate(input::String, cursor_pos::Integer)
    # Some operations seem to be easier to do on the character level than on the AST,
    # so do them here.
    # Convert character cursor position to byte index to cover multi-byte code points.
    search_index = nextind(input, 0, cursor_pos)

    # Get the syntax node the cursor is on or which is trivially to the cursor's left.
    # If the cursor is at the end of the input, the REPL provides a position one code point
    # beyond the number of code points in `input` (i.e. its length). In this case the
    # search index is deliberately left outside `input` to support the correct help on
    # macro calls without parentheses to get help about the macro even if the cursor is
    # after a newly written macro argument.
    while 1 < search_index <= ncodeunits(input) && isspace(input[search_index])
        search_index = prevind(input, search_index)
    end

    # If the cursor is at the end of the input without trailing space, refer to the last
    # identifier.
    if search_index == ncodeunits(input) + 1 && !isspace(input[end])
        return search_index - 1
    else
        return search_index
    end
end

"""
    _descend(node::SyntaxNode, search_index::Integer) -> SyntaxNode

Descend to the most specific syntax node containing `search_index`.

# Arguments

- `node::SyntaxNode`: Root syntax node to search.
- `search_index::Integer`: Byte index that the result must contain.
"""
function _descend(node::SyntaxNode, search_index::Integer)
    # Return the node if it does not have children, as it is then most specific.
    node.children === nothing && return node

    # Return the current node or the most specific descendant containing the cursor.
    # Start searching from the last child, as it is more likely that the cursor is there.
    id = findlast(c -> 0 <= search_index - c.data.position < span(c), node.children)
    return isnothing(id) ? node : _descend(node[id], search_index)
end

"""
    _ascend(node::SyntaxNode) -> SyntaxNode

Ascend to the most specific SyntaxNode containing all the information needed for `@help`.

# Arguments

- `node::SyntaxNode`: Syntax node from which to ascend.
"""
function _ascend(node::SyntaxNode)
    # Depending on Julia version, macros are handled differently in JuliaSyntax.jl.
    is_macro_part(n) = @static if VERSION >= v"1.13-"
        kind(n) == K"Identifier" && n.parent !== nothing && kind(n.parent) == K"macro_name"
    else
        kind(n) == K"MacroName"
    end

    # Now that we have the most specific descendant containing the cursor, we need to find
    # the most specific ascendant (ancestor) which contains all the needed information.
    # The K"…" type is described here:
    # https://github.com/JuliaLang/JuliaSyntax.jl/blob/main/src/julia/kinds.jl
    # Continue through incomplete expressions, macro names, non-standard string literals,
    # and qualified identifiers.
    while (parent = node.parent) !== nothing && (
        kind(node) == K"error" ||
        is_macro_part(node) ||
        kind(node) == K"String" && kind(parent) == K"string" ||
        kind(node) == K"string" && kind(parent) == K"macrocall" ||
        kind(parent) == K"."
    )
        node = parent
    end

    return node
end

"""
    _helpstring(x::SyntaxNode) -> String

Extract the string from syntax node `x` to be provided for `@help`.

# Arguments

- `x::SyntaxNode`: Syntax node to convert to a help query.
"""
function _helpstring(x::SyntaxNode)
    # Use the first child of calls because it is the callable.
    kind(x) in KSet"call curly macrocall" && return x[1] |> _helpstring
    kind(x) in KSet". module block error" && return x |> sourcetext
    @static if VERSION >= v"1.13-"
        kind(x) == K"macro_name" && return x |> sourcetext
    end
    # Handle literals specially to match help-mode identifiers.
    kind(x) in KSet"string String" && return "String"
    kind(x) in KSet"char Char" && return "Char"
    kind(x) in KSet"cmdstring CmdString" && return "@cmd"
    (kind(x) == K"->" || is_keyword(x)) && return x |> kind |> untokenize
    return x |> string
end

"""
    _register_help_shortcuts(repl::Any) -> Task

Register the `<Alt> + h` and `<F1>` shortcuts in the REPL to show help for the identifier
under the cursor.

# Arguments

- `repl::Any`: REPL instance whose keymaps are updated asynchronously.
"""
function _register_help_shortcuts(repl)
    _register_shortcuts(repl) do escapes
        escapes['O']['P'] = _show_pager_help  # <F1>
        escapes['h']      = _show_pager_help  # <Alt> + h
    end
end

"""
    _register_shortcuts(f::Any, repl::Any) -> Task

Register escape shortcuts in the REPL by calling `f(escapes)` to register them.

# Arguments

- `f::Any`: Callable object that adds entries to an escape keymap.
- `repl::Any`: REPL instance whose keymaps are updated asynchronously.
"""
function _register_shortcuts(f, repl)
    # When `atreplinit` is called, `repl.interface` is still undefined. Use `@async` to
    # finish initialization first.
    @async begin
        # According to tests, this while loop is currently not needed. However, as long as
        # we don't know whether this is guaranteed, better be safe than sorry. If this is
        # not needed, it only evaluates the condition once at runtime without actually
        # sleeping.
        while !isdefined(repl, :interface)
            sleep(0.1)
        end

        # Register the keybindings both in the regular REPL mode (always the first one)
        # and in the pager mode (which is the last one, as we just added it).
        for m in repl.interface.modes |> Ref .|> (first, last)
            m.keymap_dict['\e'] |> f
        end

        return nothing
    end
end

"""
    _show_pager_help(state::Any, _key::Any, _context::Any) -> Symbol

Show the extended inline help for the identifier under the cursor in the REPL.

# Arguments

- `state::Any`: Current REPL line-edit state.
- `_key::Any`: Keybinding callback key, which is ignored.
- `_context::Any`: Keybinding callback context, which is ignored.
"""
function _show_pager_help(s, _key, _context)
    _show_pager_cursor(s) do identifier
        _show_extended_help(identifier, s.active_module)
    end
end

"""
    _show_extended_help(identifier::AbstractString, mod::Module) -> Nothing

Route an identifier to extended help in `mod`.

# Arguments

- `identifier::AbstractString`: Identifier whose extended help is displayed.
- `mod::Module`: Module in which to evaluate the help query.
"""
function _show_extended_help(identifier::AbstractString, mod::Module)
    return _show_help("?" * identifier, mod)
end


"""
    _show_pager_cursor(f::Any, state::Any) -> Symbol

Show information about the identifier under the cursor in the REPL by calling `f`.

# Arguments

- `f::Any`: Callable object invoked with the identifier under the cursor.
- `state::Any`: Current REPL line-edit state.
"""
function _show_pager_cursor(f, s)
    input           = input_string(s)
    cursor_position = buffer(s).ptr
    identifier      = _extract_identifier(input, cursor_position)

    isempty(identifier) && return :ok

    _with_raw_restoration(Base.active_repl.t) do
        # Call the provided functionality with the identifier under the cursor.
        f(identifier)
    end

    return :ok
end

"""
    _with_raw_restoration(f::Any, terminal::Any;
        raw_function::Any = REPL.Terminals.raw!) -> Any

Call `f` and restore `terminal` to raw mode even if the callback throws.

# Arguments

- `f::Any`: Callable object to invoke while raw-mode restoration is guarded.
- `terminal::Any`: REPL terminal object passed to `raw_function`.

# Keywords

- `raw_function::Any`: Callable object used to restore raw mode.

# Returns

Return the result of `f`. Its type is polymorphic because `_with_raw_restoration` accepts
any callable object.
"""
function _with_raw_restoration(
    f,
    terminal;
    raw_function = REPL.Terminals.raw!
)
    try
        return f()
    finally
        raw_function(terminal, true)
    end
end

############################################################################################
#                                   Auxiliary Functions                                    #
############################################################################################

"""
    _tryparsestmt(x::String) -> SyntaxNode

Try to parse `x` into a `SyntaxNode`. If there are errors or warnings, they are ignored.

# Arguments

- `x::String`: Julia source text to parse.
"""
function _tryparsestmt(x::String)
    return parsestmt(SyntaxNode, x; ignore_errors = true, ignore_warnings = true)
end
