## Description #############################################################################
#
# Test related to the help key binding functionality in TerminalPager.jl.
#
############################################################################################

using TerminalPager: _extract_identifier

const Mapping = Pair{String, String}

"""
    CursorState

Minimal stand-in for a REPL line-edit state, exposing only the buffer the cursor lives in.

# Fields

- `buf::IOBuffer`: Buffer holding the REPL input, positioned at the cursor.
"""
struct CursorState
    buf::IOBuffer
end

"""
    CursorState(input::AbstractString, cursor_characters::Int) -> CursorState

Create a state holding `input` with the cursor after `cursor_characters - 1` characters.

# Arguments

- `input::AbstractString`: REPL input text.
- `cursor_characters::Int`: One-based character position of the cursor.
"""
function CursorState(input::AbstractString, cursor_characters::Int)
    buf = IOBuffer()
    write(buf, input)
    seek(buf, nextind(input, 0, cursor_characters) - 1)
    return CursorState(buf)
end

REPL.LineEdit.buffer(state::CursorState) = state.buf
REPL.LineEdit.input_string(state::CursorState) = String(take!(copy(state.buf)))

@testset "Help Shortcut Registration" begin
    function create_mode()
        escapes = Dict{Char, Any}('O' => Dict{Char, Any}())
        return (; keymap_dict = Dict{Char, Any}('\e' => escapes))
    end

    regular_mode = create_mode()
    pager_mode = create_mode()
    repl = (; interface = (; modes = [regular_mode, pager_mode]))

    fetch(TerminalPager._register_help_shortcuts(repl))

    for mode in (regular_mode, pager_mode)
        escapes = mode.keymap_dict['\e']
        @test escapes['O']['P'] === TerminalPager._show_pager_help
        @test escapes['h'] === TerminalPager._show_pager_help
        @test !haskey(escapes, 'H')
    end
end

"""
    test(
        input::AbstractString,
        i::Integer,
        result::AbstractString,
    ) -> Test.Result

Test identifier extraction at one cursor position.

# Arguments

- `input::AbstractString`: Provide the source input.
- `i::Integer`: Provide the cursor position.
- `result::AbstractString`: Provide the expected identifier.
"""
test(input, i::Integer, result) = @eval @test _extract_identifier($input, $i) == $result

"""
    test(input::AbstractString, result::AbstractString) -> Test.Result

Test identifier extraction at the end of an input string.

# Arguments

- `input::AbstractString`: Provide the source input.
- `result::AbstractString`: Provide the expected identifier.
"""
test(x, result) = test(x, length(x) + 1, result) # Test at the end of the input.

"""
    test(mapping::Mapping) -> Vector{<:Test.Result}

Test a mapping at every cursor position in its input string.

# Arguments

- `mapping::Mapping`: Provide the input-to-identifier mapping.
"""
test(x::Mapping) = [test(x.first, i, x.second) for i in 1:(length(x.first) + 1)]

"""
    test(input::String) -> Vector{<:Test.Result}

Test an input whose expected identifier is the complete input string.

# Arguments

- `input::String`: Provide the source input and expected identifier.
"""
test(x::String) = test(x => x)

"""
    test(
        input::AbstractString,
        mappings::Vector{Mapping},
    ) -> Nothing

Test every mapped substring at each valid code-point cursor position.

# Arguments

- `input::AbstractString`: Provide the source input.
- `mappings::Vector{Mapping}`: Provide the substring-to-identifier mappings.
"""
function test(input::AbstractString, mappings::Vector{Mapping})
    # Create a lookup table to convert code unit indices to code point indices.
    Mem = @static(VERSION >= v"1.11-" ? Memory : Array)
    to_code_point_index = Mem{Int}(undef, ncodeunits(input))
    to_code_point_index[input |> eachindex |> collect] .= 1:length(input)

    r = 1:1
    for m in mappings
        r = findnext(m.first, input, r[end])
        r === nothing && error("Incorrect test definition: Could not find $m in $input.")
        # Test mapping for all its code point indices.
        [test(input, to_code_point_index[i], m.second) for i in r if isvalid(input, i)]
    end
    return nothing
end

@testset "Extract Identifier" begin
    # == Empty Input =======================================================================

    test("", 1, "")
    test("   " => "")

    # == Single Identifier =================================================================

    test("sin(" => "sin")
    test("αβγ " => "αβγ")

    # == Basic Macro Calls =================================================================

    test("@time " => "@time")
    test("@time(" => "@time")

    # == Incomplete Function Call ==========================================================

    test("atand(cos, ", ["atand(" => "atand", "cos" => "cos", ", " => "atand"])

    # == Type With Parameters ==============================================================

    test("Array{Int64, }", ["Array{" => "Array", "Int64" => "Int64", ", " => "Array"])

    # == Nested Function Call With Comma ===================================================

    test("fun(sin(x), ", ["fun(" => "fun", "sin(" => "sin", "x" => "x", ", " => "fun"])

    # == Test Qualified Identifiers in Module Expressions ==================================

    # AST changed between 1.11 and 1.12, i.e. this is only supported 1.12 onwards.
    @static if VERSION >= v"1.12-"
        test("Base.Core.stdout")
    end

    # Base.JuliaSyntax.byte_range.

    # == Macro With Arguments ==============================================================

    test("@time sin(x)", ["@time " => "@time", "sin(" => "sin", "x" => "x"])

    # Test that the cursor after the macro argument provides help about the macro.
    test("@code_native syntax=:intel ", "@code_native")

    # == Module Qualified Macros ===========================================================

    test("Base.@time")

    test(
        "InteractiveUtils.@code_lowered(debuginfo=:none, ",
        [
            "InteractiveUtils.@code_lowered(" => "InteractiveUtils.@code_lowered",
            ", " => "InteractiveUtils.@code_lowered",
        ],
    )

    # == Non-Standard String Literals ======================================================

    test("r\"abc\"" => "@r_str")

    # == Keywords ==========================================================================

    test("baremodule")
    test("begin")
    test("break")
    test("const")
    test("continue")
    # Deactivate this test until JuliaSyntax issue 599 is fixed.
    @static VERSION <= v"1.13-" && test("do")
    test("export")
    test("for")
    test("function")
    test("global")
    test("if")
    test("import")
    test("let")
    test("local")
    test("macro")
    test("module")
    test("quote")
    test("return")
    test("struct")
    test("try")
    test("using")
    test("while")
    test("catch")
    test("finally")
    test("else")
    test("elseif")
    test("end")
    test("abstract")
    test("as")
    test("doc")
    test("mutable")
    test("outer")
    test("primitive")
    test("public")
    test("type")
    test("var")

    # == Literals ==========================================================================

    test("42")
    test("0b101010" => "0x2a")
    test("0o52" => "0x2a")
    test("0x2a")
    test("42.42")
    test("-42.0f0")
    test("\"42\"" => "String")
    test("'c'" => "Char")
    # AST changed between 1.11 and 1.12, i.e. this is only supported 1.12 onwards.
    @static if VERSION >= v"1.12-"
        test("`ls`" => "@cmd")
    end
    test("true")
    test("false")

    # == UTF-8 operators ===================================================================

    test("∈")
    test("∉")
    test("∋")
    test("∌")
    test("∩")
    test("∪")
    test("⊆")
    test("⊇")
    test("⊂")
    test("⊃")
    test("⊄")
    test("⊅")
    test("⊊")
    test("⊋")
    test("⊏")
    test("⊐")
    test("⊑")
    test("⊒")
    test("⊓")
    test("⊔")
    test("⊕")
    test("⊖")
    test("⊗")
    test("⊘")
    test("⊙")
    test("⊚")
    test("⊛")
    test("⊜")
    test("⊞")
    test("⊟")
    test("⊠")
    test("⊡")
    test("⊢")
    test("⊣")
    test("⊤")
    test("⊥")
    test("⊩")
    test("⊬")
    test("⊮")
    test("⊰")
    test("⊱")
    test("⊲")
    test("⊳")
    test("⊴")
    test("⊵")
    test("⊶")
    test("⊷")
    test("⊻")
    test("⊼")
    test("⊽")
    test("⊾")
    test("⊿")
    test("⋀")
    test("⋁")
    test("⋂")
    test("⋃")
    test("⋄")
    test("⋅")
    test("⋆")
    test("⋇")
    test("⋉")
    test("⋊")
    test("⋋")
    test("⋌")
    test("⋍")
    test("⋎")
    test("⋏")
    test("⋐")
    test("⋑")
    test("⋒")
    test("⋓")
    test("⋕")
    test("⋖")
    test("⋗")
    test("⋘")
    test("⋙")
    test("⋚")
    test("⋛")
    test("⋜")
    test("⋝")
    test("⋞")
    test("⋟")
    test("⋠")
    test("⋡")
    test("⫸")

    # == UTF8-operator inside Expression ===================================================

    test("15 ⫸ x", ["15 " => "15", "⫸ " => "⫸", "x" => "x"])

    test(
        "15 ⫸ x -> x - 2 ⫸",
        [
            "15 " => "15",
            "⫸ " => "⫸",
            "x " => "x",
            "-> " => "->",
            "x " => "x",
            "- " => "-",
            "2 " => "2",
            "⫸" => "⫸",
        ],
    )

    # == Real World Examples ===============================================================

    test("cl.platform().id |> unsafe_string", "unsafe_string")
end

@testset "Cursor Character Position" begin
    # `IOBuffer.ptr` is a byte pointer. Passing it straight to `_extract_identifier`, which
    # expects a character position, made `F1` and `ALT-h` show the help of the wrong token
    # whenever the input contained non-ASCII characters.
    for (input, cursor) in (
        ("abc = 1", 1),
        ("abc = 1", 4),
        ("abc = 1", 8),
        ("αβγ = 1", 1),
        ("αβγ = 1", 2),
        ("αβγ = 1", 4),
        ("αβγ = 1", 8),
        ("α + sin", 8),
        ("界界 = 1", 3),
        ("", 1),
    )
        state = CursorState(input, cursor)
        @test TerminalPager._cursor_character_position(state) == cursor
    end

    # The identifier under the cursor must be found for non-ASCII input as well.
    @test TerminalPager._extract_identifier(
        "αβγ = 1", TerminalPager._cursor_character_position(CursorState("αβγ = 1", 4))
    ) == "αβγ"

    @test TerminalPager._extract_identifier(
        "α + sin", TerminalPager._cursor_character_position(CursorState("α + sin", 8))
    ) == "sin"

    @test TerminalPager._extract_identifier(
        "abc = 1", TerminalPager._cursor_character_position(CursorState("abc = 1", 4))
    ) == "abc"
end
