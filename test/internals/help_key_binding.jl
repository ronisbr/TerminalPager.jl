## Description #############################################################################
#
# Test related to the help key binding functionality in TerminalPager.jl.
#
############################################################################################

using TerminalPager: extract_identifier

@testset "Extract identifier" begin
    # == Empty Input =======================================================================

    @test extract_identifier("", 1)    == ""
    @test extract_identifier("   ", 1) == ""

    # == Single Identifier =================================================================

    @test extract_identifier("sin", 1)   == "sin"
    @test extract_identifier("sin", 2)   == "sin"
    @test extract_identifier("sin", 3)   == "sin"
    @test extract_identifier("sin(", 4)  == "sin"
    @test extract_identifier("sin( ", 5) == "sin"

    # == Basic Macro Calls =================================================================

    @test extract_identifier("@time", 1)  == "@time" # cursor on '@'
    @test extract_identifier("@time", 2)  == "@time" # cursor on 't'
    @test extract_identifier("@time", 5)  == "@time" # cursor on 'e'
    @test extract_identifier("@time ", 6) == "@time" # cursor after 'e'

    # == Test Case 1: Incomplete Function Call =============================================

    @test extract_identifier("sin(cos", 1) == "sin" # cursor on 'sin'
    @test extract_identifier("sin(cos", 7) == "cos" # cursor on 'cos'

    # == Test Case 2: Type With Parameters =================================================

    @test extract_identifier("Array{Int64, }", 1)  == "Array" # cursor on 'Array'
    @test extract_identifier("Array{Int64, }", 7)  == "Int64" # cursor on 'Int64'
    @test extract_identifier("Array{Int64, }", 14) == "Array" # cursor after comma -> callable

    # == Test Case 3: Nested Function Call With Comma ======================================

    @test extract_identifier("myfun(sin(x), ", 1)  == "myfun" # cursor on 'myfun'
    @test extract_identifier("myfun(sin(x), ", 7)  == "sin"   # cursor on 'sin'
    @test extract_identifier("myfun(sin(x), ", 11) == "x"     # cursor on 'x'
    @test extract_identifier("myfun(sin(x), ", 15) == "myfun" # cursor after comma -> callable

    # == Test Qualified Identifiers in Module Expressions ==================================

    @test extract_identifier("Base.Core.stdout", 1)   == "Base.Core.stdout" # cursor on Base
    @test extract_identifier("Base.Core.stdout", 5)   == "Base.Core.stdout" # cursor on first .
    @test extract_identifier("Base.Core.stdout", 8)   == "Base.Core.stdout" # cursor on Core
    @test extract_identifier("Base.Core.stdout", 10)  == "Base.Core.stdout" # cursor on second .
    @test extract_identifier("Base.Core.stdout", 11)  == "Base.Core.stdout" # cursor on stdout
    @test extract_identifier("Base.Core.stdout ", 17) == "Base.Core.stdout" # cursor after identifier

    # == Macro With Arguments ==============================================================

    @test extract_identifier("@time sin(x)", 1) == "@time" # cursor on '@time'
    @test extract_identifier("@time ", 7)       == "@time" # cursor on space after @time without content
    @test extract_identifier("@time sin(x)", 7) == "sin"   # cursor on space after @time with content
    @test extract_identifier("@time sin(x)", 8) == "sin"   # cursor on 'sin'

    # == Incomplete Macro Call =============================================================

    @test extract_identifier("@time(", 7) == "@time" # cursor after opening paren

    # == Module Qualified Macros ===========================================================

    @test extract_identifier("Base.@time", 1) == "Base.@time" # cursor on 'Base'
    @test extract_identifier("Base.@time", 6) == "Base.@time" # cursor on '@time'

    @test extract_identifier("InteractiveUtils.@code_lowered(debuginfo=:none, ", 48) == "InteractiveUtils.@code_lowered"
end
