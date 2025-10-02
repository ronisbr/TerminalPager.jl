## Description #############################################################################
#
# Test related to the help key binding functionality in TerminalPager.jl.
#
############################################################################################

using TerminalPager: _extract_identifier

const Mapping = Pair{String, String}

# Per defined test, we should check multiple cursor positions. This automates the tests.
test(input, i::Integer, result) = @eval @test _extract_identifier($input, $i) == $result
test(input, range::AbstractRange, result) = [test(input, i, result) for i in range]
test(x::Mapping) = [test(x.first, i, x.second) for i in 1 : length(x.first)+1]
test(x::String) = test(x => x)

function test(input::AbstractString, mappings::Vector{Mapping})
    r = 1:1
    for m in mappings
        r = findnext(m.first, input, r[end])
        r === nothing && error("Incorrect test definition: Could not find $m in $input.")
        test(input, r, m.second)
    end
end


@testset "Extract identifier" begin
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

    test("Base.Core.stdout")

    # Base.JuliaSyntax.byte_range

    # == Macro With Arguments ==============================================================

    test("@time sin(x)", ["@time " => "@time", "sin(" => "sin", "x" => "x"])

    # == Module Qualified Macros ===========================================================

    test("Base.@time")

    test(
        "InteractiveUtils.@code_lowered(debuginfo=:none, ", [
            "InteractiveUtils.@code_lowered(" => "InteractiveUtils.@code_lowered",
            ", " => "InteractiveUtils.@code_lowered"
        ]
    )

    # == Non-Standard String Literals ======================================================

    test("r\"abc\"" => "@r_str")

    # == Keywords ==========================================================================

    test("baremodule")
    test("begin")
    test("break")
    test("const")
    test("continue")
    test("do")
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
    test("`ls`" => "@cmd")
    test("true")
    test("false")
end
