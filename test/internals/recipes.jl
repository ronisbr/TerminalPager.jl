## Description #############################################################################
#
# Tests for the pager recipes.
#
############################################################################################

struct _RecipeObject end
struct _RenderedRecipeObject end
struct _BadRecipeObject end

Base.show(io::IO, ::MIME"text/plain", ::_RecipeObject) = print(io, "recipe\nobject")
Base.show(io::IO, ::MIME"text/plain", ::_RenderedRecipeObject) = print(io, "ab│cd\n──")
Base.show(io::IO, ::MIME"text/plain", ::_BadRecipeObject) = print(io, "bad")

TerminalPager.pager_options(::_RecipeObject) = (; frozen_rows = 2, show_ruler = true)
TerminalPager.pager_options(::_RenderedRecipeObject) = (; frozen_rows = 9)
function TerminalPager.pager_options(::_RenderedRecipeObject, rendered::String)
    return (; frozen_columns = textwidth(first(split(rendered, '\n'))))
end
TerminalPager.pager_options(::_BadRecipeObject) = [1, 2]

@testset "Pager Recipes" begin
    # The fallbacks are empty, the method with the rendered text wins over the other one,
    # and the explicit keywords win over the recipe.
    @test TerminalPager.pager_options(1) == (;)
    @test TerminalPager.pager_options("x", "x") == (;)
    @test TerminalPager._pager_options(_RecipeObject(), "recipe\nobject") ==
        (; frozen_rows = 2, show_ruler = true)
    @test TerminalPager._pager_options(_RenderedRecipeObject(), "ab│cd\n──") ==
        (; frozen_columns = 5)
    @test TerminalPager._merge_options((; frozen_rows = 2, show_ruler = true), (; frozen_rows = 3)) ==
        (; frozen_rows = 3, show_ruler = true)
    @test_throws ArgumentError TerminalPager._pager_options(_BadRecipeObject(), "bad")

    rendered, options = TerminalPager._object_pager_call(_RecipeObject(), (;))
    @test rendered == "recipe\nobject"
    @test options == (; frozen_rows = 2, show_ruler = true)
    _, options = TerminalPager._object_pager_call(_RecipeObject(), pairs((; frozen_rows = 3)))
    @test options == (; frozen_rows = 3, show_ruler = true)

    # The arrays with a summary line keep it on top; the others have no recipe.
    render(x) = TerminalPager._render_object(x)
    frozen = (; frozen_rows = 1, title_rows = 1)
    @test TerminalPager.pager_options(rand(2, 2), render(rand(2, 2))) == frozen
    @test TerminalPager.pager_options([1, 2, 3], render([1, 2, 3])) == frozen
    @test TerminalPager.pager_options(fill(1), render(fill(1))) == frozen
    @test TerminalPager.pager_options(zeros(2, 2, 2), render(zeros(2, 2, 2))) == frozen
    @test TerminalPager.pager_options(Int[], render(Int[])) == (;)
    @test TerminalPager.pager_options(zeros(0, 0), render(zeros(0, 0))) == (;)
    @test TerminalPager.pager_options(1:3, render(1:3)) == (;)
    _, options = TerminalPager._object_pager_call(rand(2, 2), (;))
    @test options == frozen

    # The public entry point applies the recipe when it prints the object.
    old_stdout = stdout
    output = IOBuffer()

    try
        Base.eval(:(stdout = $(IOContext(output, :bypass_pager => true))))
        pager(_RecipeObject())
        @test String(take!(output)) == "recipe\nobject"
    finally
        Base.eval(:(stdout = $old_stdout))
    end
end

@testset "Table Recipe" begin
    table = """
        3×2 DataFrame
         Row │ a      b
             │ Int64  Int64
        ─────┼──────────────
           1 │     1      4
           2 │     2      5
           3 │     3      6
        """
    expected = (; frozen_rows = 4, title_rows = 1, frozen_columns = 6)
    @test TerminalPager._table_options(table) == expected

    # The decorations do not count in the widths.
    decorated = replace(table, "Row" => "\e[1mRow\e[0m", "Int64" => "\e[90mInt64\e[0m")
    @test TerminalPager._table_options(decorated) == expected

    # A text without a header or a separator has no options.
    @test TerminalPager._table_options("plain text\nmore") == (;)
    @test TerminalPager._table_options("a │ b\nc │ d") == (;)
    @test TerminalPager._table_options("") == (;)
end

@testset "REPL Mode Recipe" begin
    value = rand(2, 2)
    rendered = TerminalPager._render_object(value) * "\n"

    # The recipe applies only when the output is the rendering of the value, and the
    # automatic mode is always on.
    @test TerminalPager._repl_mode_options(value, rendered, true) ==
        (; frozen_rows = 1, title_rows = 1, auto = true)
    @test TerminalPager._repl_mode_options(value, "printed\n" * rendered, false) ==
        (; auto = true)
    @test TerminalPager._repl_mode_options(nothing, "printed\n", false) == (; auto = true)
end
