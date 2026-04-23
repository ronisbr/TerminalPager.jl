## Description #############################################################################
#
# Tests for the `_get_help` helper used by the `@help` macro.
#
############################################################################################

using TerminalPager: _get_help

@testset "Help" begin
    # Existing binding: should return some documentation text.
    str = _get_help("write")
    @test str isa AbstractString
    @test !isempty(str)

    # Unqualified unknown identifier: should not throw and should indicate the binding
    # does not exist.
    str = _get_help("function_does_not_exist")
    @test str isa AbstractString
    @test occursin("function_does_not_exist", str)

    # Qualified unknown identifier in an existing module: should not throw.
    str = _get_help("Base.function_does_not_exist")
    @test str isa AbstractString
    @test occursin("does not exist", str)

    # Qualified identifier in a non-existing module: this used to throw
    # `UndefVarError: ModuleDoesNotExist`. See issue #89.
    str = _get_help("ModuleDoesNotExist.anything")
    @test str isa AbstractString
    @test occursin("does not exist", str)

    # Deeply nested non-existing module.
    str = _get_help("A.B.C.d")
    @test str isa AbstractString
    @test occursin("does not exist", str)

    # Spelling error: should suggest the correct spelling.
    str = _get_help("eachindexx")
    @test str isa AbstractString
    @test occursin("Perhaps you meant eachindex", str)
end
