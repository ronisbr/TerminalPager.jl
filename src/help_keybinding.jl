## Description #############################################################################
#
# This script adds keybindings to the Julia REPL to show help for the identifier under the
# cursor.
#
############################################################################################

"""
    _extract_identifier(input::AbstractString, cursor_pos::Integer) -> String

Extract identifier from the input line using the cursor position.

Identifiers are functions, operators, constructors, modules, closures, macros, types consts
and literals. If the cursor is on a identifier (including module hierarchy like A.B.C) or on
the character behind it, return that identifier.

Callables are functions, operators, constructors, callable objects (functors) including
modules, closures, macros and type parameters of a constructor. If the cursor is not on a
identifier, but in the argument/parameter list of a valid callable, return the callable
name. However, if the callable is a value.

Extraction works even for invalid (i.e. incomplete) input.

It returns an empty string otherwise.
"""
function _extract_identifier(input::AbstractString, cursor_pos::Integer)::String
    isempty(strip(input)) && return ""

    _to_string(x::SyntaxNode) = kind(x) == K"." ? input[_range(x)] : Base.string(x)

    # Get the syntax node the cursor is on.
    node = _find_cursor_node(_tryparsestmt(input), cursor_pos)

    # If cursor is on an identifier, macro name or literal, return it. If cursor is on a
    # part of a qualified identifier, return the full qualified identifier. The literals are
    # taken from
    #
    #   https://github.com/JuliaLang/JuliaSyntax.jl/blob/99e975a726a82994de3f8e961e6fa8d39aed0d37/src/julia/kinds.jl#L253.
    #
    # `K"Bool"` is only supported since Julia 1.12.
    if kind(node) in (
        K".",
        K"Identifier",
        K"MacroName",
        @static(VERSION < v"1.12-" ? K"." : K"Bool"),
        K"Integer",
        K"BinInt",
        K"HexInt",
        K"OctInt",
        K"Float",
        K"Float32",
        K"String",
        K"Char",
        K"CmdString"
    )
        return _to_string(node)
    end

    # If cursor is in argument/parameter list, return the callable.
    if kind(node) in (K"call", K"curly", K"macrocall")
        return _to_string(node.children[1])
    end

    # If cursor is on an error node (incomplete expression), check if its parent is a
    # callable.
    if (
        (kind(node) == K"error") &&
        (node.parent !== nothing) &&
        kind(node.parent) in (K"call", K"curly", K"macrocall")
    )
        return _to_string(node.parent[1])
    end

    return ""
end

# Find the most specific node containing the cursor.
"""
    _find_cursor_node(node, cursor_pos::Integer) -> SyntaxNode

Recursively find the most specific syntax node in `node` containing the cursor position
`cursor_pos`.
"""
function _find_cursor_node(node, cursor_pos::Integer)
    # Return the parent node if the current node is part of a qualified identifier, as it
    # was too specific.
    node.parent !== nothing && kind(node.parent) == K"." && return node.parent

    # Return the node if it does not have children, as it is then most specific.
    node.children === nothing && return node

    # If a child contains the cursor, return the most specific descendant, otherwise return
    # the current node.
    id = findfirst(
        c -> 0 <= cursor_pos - c.data.position <= c.data.raw.span,
        node.children
    )

    isnothing(id) && return node

    return _find_cursor_node(node.children[id], cursor_pos)
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
        escapes['O']['P'] = _show_pager_help          # <F1>
        escapes['h']      = _show_pager_help          # <Alt> + h
        escapes['H']      = _show_pager_extended_help # <Alt> + H

        return nothing
    end
end

"""
    _show_pager_help(s, _, _) -> Symbol

Show the pager help for the identifier under the cursor in the REPL.
"""
function _show_pager_help(s, _, _)
    # The following accesses private identifier. This is not ideal, but REPL does not seem
    # to provide a public API for this.
    input           = LineEdit.input_string(s)
    cursor_position = LineEdit.buffer(s).ptr
    identifier      = _extract_identifier(input, cursor_position)

    isempty(identifier) && return :ok

    # Execute @help macro which will temporarily take over terminal control.
    @eval(@help $identifier)

    # After pager exits, put REPL back in raw mode.
    REPL.Terminals.raw!(Base.active_repl.t, true)

    return :ok
end

"""
    _show_pager_extended_help(s, _, _) -> Symbol

Show the pager extended help for the identifier under the cursor in the REPL.
"""
function _show_pager_extended_help(s, _, _)
    # The following accesses private identifier. This is not ideal, but REPL does not seem
    # to provide a public API for this.
    input           = LineEdit.input_string(s)
    cursor_position = LineEdit.buffer(s).ptr
    identifier      = _extract_identifier(input, cursor_position)

    isempty(identifier) && return :ok

    ext_identifier = "?" * identifier

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
    _range(x::SyntaxNode) -> UnitRange{Int}

Get the range of the input string corresponding to the syntax node `x`.
"""
function _range(x::SyntaxNode)
    return Base.range(x.data.position, length = x.data.raw.span)
end

"""
_tryparsestmt(x) -> SyntaxNode

Try to parse `x` into a `SyntaxNode`. If there are errors or warnings, they are ignored.
"""
function _tryparsestmt(x)
    return parsestmt(SyntaxNode, x, ignore_errors = true, ignore_warnings = true)
end

