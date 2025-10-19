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

    # Find the most specific syntax node containing the search_index.
    # This descents the AST.
    descendant = _descend(head, search_index)

    # Find the least generic syntax node containing all the information needed for `@help`.
    # This ascends the AST.
    ascendant = _ascend(descendant)

    # Extract the string from the syntax node to be provided for `@help`.
    # This can go downwards into a *different branch* of the AST.
    return _helpstring(ascendant)
end

"""
    _collaterate(input::String, cursor_pos::Integer) -> Integer

Based on cursor position, collaterate (branch) to the intended token's index.
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
"""
function _ascend(node::SyntaxNode)
    # Now that we have the most specific descendant containing the cursor, we need to find
    # the most specific ascendant (ancestor) which contains all the needed information.
    # The K"…" type is described here:
    # https://github.com/JuliaLang/JuliaSyntax.jl/blob/main/src/julia/kinds.jl
    # This is wider than 92 characters, but it is more readable this way.
    while (parent = node.parent) !== nothing && (
        kind(node) == K"error" ||                                  # incomplete expression
        kind(node) == K"MacroName" ||                              # MacroName does not contain the @
        kind(node) == K"String" && kind(parent) == K"string" ||    # string part of non-standard string literal
        kind(node) == K"string" && kind(parent) == K"macrocall" || # string-r part of non-standard string literal
        kind(parent) == K"."                                       # part of a qualified identifier
    )
        node = parent
    end

    return node
end

"""
    _helpstring(x::SyntaxNode) -> String

Extract the string from syntax node `x` to be provided for `@help`.
"""
function _helpstring(x::SyntaxNode)
    kind(x) in KSet"call curly macrocall" && return x[1] |> _helpstring    # First child is callable.
    kind(x) in KSet". module block error" && return x |> sourcetext        # Use plain text.
    kind(x) in KSet"string String" && return "String"                      # String literals are special in `help?>`.
    kind(x) in KSet"char Char" && return "Char"                            # Avoid converting Char literal to String.
    kind(x) in KSet"cmdstring CmdString" && return "@cmd"                  # Unclear what to show for `cmd`.
    (kind(x) == K"->" || is_keyword(x) ) && return x |> kind |> untokenize # Extract as string.
    return x |> string                                                     # Fallback: Convert to string.
end

"""
    _register_help_shortcuts(repl) -> Nothing

Register the `<Alt> + h` and `<F1>` shortcuts in the REPL to show help for the identifier
under the cursor.
"""
function _register_help_shortcuts(repl)
    # When atreplinit is called, repl.interface is still an undefined reference. So use
    # @async, to first finish initialization.
    @async begin
        # According to tests, this while loop is currently not needed. However, as long as
        # we don't know whether this is guaranteed, better be safe than sorry. If this is
        # not needed, it is only evaluating the condition once at runtime without never
        # actually sleeping.
        while !isdefined(repl, :interface)
            sleep(0.1)
        end
        escapes = repl.interface.modes[1].keymap_dict['\e']
        escapes['O']['P'] = _show_pager_extended_help  # <F1>
        escapes['h']      = _show_pager_extended_help  # <Alt> + h

        return nothing
    end
end

"""
    _show_pager_regular_help(s, _, _) -> Symbol

Show the pager help for the identifier under the cursor in the REPL.
"""
_show_pager_regular_help(s, _, _) = _show_pager_help(s)

"""
    _show_pager_extended_help(s, _, _) -> Symbol

Show the pager extended help for the identifier under the cursor in the REPL.
"""
_show_pager_extended_help(s, _, _) = _show_pager_help(s, extended = true)

"""
    _show_pager_help(s, extended) -> Symbol

Show either the regular or the extended pager help for the identifier under the cursor.
"""
function _show_pager_help(s; extended = false)
    input           = input_string(s)
    cursor_position = buffer(s).ptr
    identifier      = _extract_identifier(input, cursor_position)

    isempty(identifier) && return :ok

    # Switch between regular and extended help.
    ext_identifier = extended ? "?" * identifier : identifier

    # Execute @help macro which will temporarily take over terminal control.
    @eval(@help $ext_identifier)

    # After pager exits, put REPL back in raw mode.
    REPL.Terminals.raw!(Base.active_repl.t, true)

    return :ok
end

############################################################################################
#                                   Auxiliary Functions                                    #
############################################################################################

"""
    _tryparsestmt(x::String) -> SyntaxNode

Try to parse `x` into a `SyntaxNode`. If there are errors or warnings, they are ignored.
"""
function _tryparsestmt(x::String)
    return parsestmt(SyntaxNode, x; ignore_errors = true, ignore_warnings = true)
end
