function execute_help(s, _, _)
    # The following accesses private identifier. This is not ideal, but REPL does not seem to provide a public API for this.
    input = LineEdit.input_string(s)
    cursor_position = LineEdit.buffer(s).ptr
    identifier = extract_identifier(input, cursor_position)
    identifier |> isempty && return :ok

    # Execute @help macro which will temporarily take over terminal control
    @eval(@help $identifier)

    # After pager exits, put REPL back in raw mode.
    REPL.Terminals.raw!(Base.active_repl.t, true)

    return :ok
end

"""
    extract_identifier(input::AbstractString, cursor_pos::Integer)

Extract identifier from the input line using the cursor position

- Identifiers are functions, operators, constructors, modules, closures, macros, types consts and literals.
- If the cursor is on a identifier (including module hierarchy like A.B.C) or on the character behind it, return that identifier.
- Callables are functions, operators, constructors, callable objects (functors) including modules, closures, macros and type parameters of a constructor.
- If the cursor is not on a identifier, but in the argument/parameter list of a valid callable, return the callable name. However, if the callable is a value.
- Extraction works even for invalid (i.e. incomplete) input.
- Return an empty String otherwise.
"""
function extract_identifier(input::AbstractString, cursor_pos::Integer)::String
    tryparsestmt(x) = parsestmt(SyntaxNode, x, ignore_errors=true, ignore_warnings=true)
    range(x::SyntaxNode) = Base.range(x.data.position, length=x.data.raw.span)
    string(x::SyntaxNode) = kind(x) == K"." ? input[range(x)] : Base.string(x)

    input |> strip |> isempty && return ""

    # Get the syntax node the cursor is on.
    node = find_cursor_node(input |> tryparsestmt, cursor_pos)

    # If cursor is on an identifier, macro name or literal, return it. If cursor is on a part of a qualified identifier, return the full qualified identifier. The literals are taken from https://github.com/JuliaLang/JuliaSyntax.jl/blob/99e975a726a82994de3f8e961e6fa8d39aed0d37/src/julia/kinds.jl#L253. `K"Bool"` is only supported since Julia 1.12.
    kind(node) in (K".", K"Identifier", K"MacroName", @static(VERSION < v"1.12-" ? K"." : K"Bool"), K"Integer", K"BinInt", K"HexInt", K"OctInt", K"Float", K"Float32", K"String", K"Char", K"CmdString") && return string(node)

    # If cursor is in argument/parameter list, return the callable
    kind(node) in (K"call", K"curly", K"macrocall") && return string(node.children[1])

    # If cursor is on an error node (incomplete expression), check if its parent is a callable
    kind(node) == K"error" && node.parent !== nothing && kind(node.parent) in (K"call", K"curly", K"macrocall") && return string(node.parent[1])

    return ""
end

# Find the most specific node containing the cursor.
function find_cursor_node(node, cursor_pos::Integer)
    # Return the parent node if the current node is part of a qualified identifier, as it was too specific.
    node.parent !== nothing && kind(node.parent) == K"." && return node.parent

    # Return the node if it does not have children, as it is then most specific.
    node.children === nothing && return node

    # If a child contains the cursor, return the most specific descendant, otherwise return the current node.
    findfirstx(f, xs) = (i = findfirst(f, xs); i === nothing ? nothing : xs[i])
    child = findfirstx(c -> 0 <= cursor_pos - c.data.position <= c.data.raw.span, node.children)
    return child === nothing ? node : find_cursor_node(child, cursor_pos)
end

# When the REPL initializes, register the <alt>+<h> and <F1> shortcuts for showing help.
function register_help_shortcuts(repl)
    # When atreplinit is called, repl.interface is still an undefined reference. So use @async, to first finish initialization.
    @async begin
        # According to tests, this while loop is currently not needed. However, as long as we don't know whether this is guaranteed, better be safe than sorry. If this is not needed, it is only evaluating the condition once at runtime without never actually sleeping.
        while !isdefined(repl, :interface)
            sleep(0.1)
        end
        escapes = repl.interface.modes[1].keymap_dict['\e']
        escapes['h'] = escapes['O']['P'] = execute_help # <alt>+<h> and <F1>
    end
end