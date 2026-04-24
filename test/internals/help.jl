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

# Tests for evaluating help in a specific module (see issue #90). Define a module with a
# documented binding to check that `_get_help` looks in the given module, and separately
# document a `Main`-level function to check the fallback from a non-`Main` active module.
module HelpModuleTest
    """
        local_documented_function()

    This is the documentation of a function local to `HelpModuleTest`.
    """
    local_documented_function() = 1
end

"""
    main_only_documented_function()

This is the documentation of a function defined in `Main`.
"""
main_only_documented_function() = 1

@testset "Module-specific help" begin
    # Binding defined in the given module: should return its documentation.
    str = _get_help("local_documented_function", HelpModuleTest)
    @test occursin("function local to", str)
    @test occursin("HelpModuleTest", str)

    # Binding only defined in `Main` but queried in a different module: `REPL.helpmode`
    # does not throw in this case (it returns a "No documentation found" Markdown), so we
    # must detect that and fall back to `Main` to provide the user with a useful result.
    str = _get_help("main_only_documented_function", HelpModuleTest)
    @test occursin("function defined in", str)
    @test occursin("Main", str)

    # Qualified identifier in a non-existing module, evaluated in a non-`Main` module:
    # should not throw and should return a "not found" message. This exercises the
    # `UndefVarError` fallback path to `Main`.
    str = _get_help("ModuleDoesNotExist.anything", HelpModuleTest)
    @test occursin("No documentation found", str)

    # When `mod === Main` and the binding is missing, we must still produce the fallback
    # Markdown rather than propagating an error.
    str = _get_help("ModuleDoesNotExist.anything", Main)
    @test occursin("No documentation found", str)

    # A genuinely non-existing binding, queried from a non-`Main` module: the fallback to
    # `Main` also cannot find it, so the result should still be "not found" (not an
    # error).
    str = _get_help("binding_that_does_not_exist_anywhere", HelpModuleTest)
    @test occursin("No documentation found", str)
end
