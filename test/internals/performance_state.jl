## Description #############################################################################
#
# Tests for session configuration, ordered search metadata, and yank assembly.
#
############################################################################################

using About

module InlineHelpModule end

@testset "Display Configuration" begin
    config = @inferred TerminalPager._display_config()
    @test config isa TerminalPager.DisplayConfig
    @test isconcretetype(typeof(config))
    @test @inferred(TerminalPager._validate_preference("active_search_decoration", "44")) ==
        "44"

    defaults = TerminalPager._AVAILABLE_PREFERENCES
    default_config = TerminalPager.DisplayConfig()
    @test default_config.active_search_decoration == defaults["active_search_decoration"]
    @test default_config.inactive_search_decoration ==
        defaults["inactive_search_decoration"]
    @test default_config.visual_mode_active_line_background ==
        defaults["visual_mode_active_line_background"]
    @test default_config.visual_mode_line_background ==
        defaults["visual_mode_line_background"]

    for (preference, default) in defaults
        invalid = default isa Bool ? "true" : true
        @test_throws ArgumentError TerminalPager._validate_preference(preference, invalid)
        @test_throws ArgumentError TerminalPager.set_preference!(preference, invalid)
    end
    @test_throws ArgumentError TerminalPager._validate_preference("unknown", true)

    pagerd = _create_pagerd("text")
    old_config = pagerd.display_config
    new_config = TerminalPager.DisplayConfig("a", "b", "c", "d")
    @test pagerd.display_config === old_config
    @test new_config !== old_config

    @test_throws UndefKeywordError TerminalPager.Pager(term = pagerd.term, buf = pagerd.buf)

    default_lines = ["default α", "second"]
    default_layout = TerminalPager.TextViewLayout(default_lines)
    compatible_pager = TerminalPager.Pager(;
        term = pagerd.term, buf = pagerd.buf, num_lines = 2, text_layout = default_layout
    )
    @test compatible_pager.text_layout === default_layout
    @test compatible_pager.num_lines == length(default_layout)
    @test compatible_pager.text_layout[2] == "second"

    values = copy(defaults)
    get_preference = preference -> values[preference]
    first_session = TerminalPager._display_config(get_preference)
    values["active_search_decoration"] = "first changed"
    values["visual_mode_line_background"] = "99"
    second_session = TerminalPager._display_config(get_preference)
    @test first_session.active_search_decoration != second_session.active_search_decoration
    @test first_session.visual_mode_line_background !=
        second_session.visual_mode_line_background

    pagerd = _create_pagerd("match")
    pagerd.display_config = TerminalPager.DisplayConfig(
        "\e[30;43m", "\e[30;47m", "196", "22"
    )
    TerminalPager._find_matches!(pagerd, r"match")
    @test pagerd.text_layout[1] == "match"
    TerminalPager._change_active_match!(pagerd)
    TerminalPager._view!(pagerd)
    @test occursin("\e[30;43m", String(take!(pagerd.buf.io)))

    view_source = read(joinpath(dirname(pathof(TerminalPager)), "view.jl"), String)
    @test !occursin("_get_preference", view_source)
end

@testset "Ordered Search Navigation" begin
    pagerd = _create_pagerd("zero\nα x x\nnone\nx")
    pagerd.display_size = (5, 8)
    pagerd.search_matches = TerminalPager.SearchMatches(
        4 => [(1, 1)], 2 => [(5, 1), (3, 1)]
    )
    source_keys = collect(keys(pagerd.search_matches))
    source_vectors = Dict(
        line => copy(matches) for (line, matches) in pagerd.search_matches
    )
    pagerd.ordered_search_matches = TerminalPager._ordered_search_matches(
        pagerd.search_matches, pagerd.num_lines
    )
    pagerd.num_matches = length(pagerd.ordered_search_matches)

    @test [(m.line, m.column, m.width) for m in pagerd.ordered_search_matches] == [(2, 5, 1), (2, 3, 1), (4, 1, 1)]
    @test [m.index_in_line for m in pagerd.ordered_search_matches] == [1, 2, 1]
    @test collect(keys(pagerd.search_matches)) == source_keys
    @test pagerd.search_matches == source_vectors

    pagerd.active_search_match_id = 3
    TerminalPager._change_active_match!(pagerd, true)
    @test pagerd.active_search_match_id == 1
    pagerd.start_row = 4
    pagerd.start_column = 7
    TerminalPager._move_view_to_match!(pagerd)
    @test pagerd.start_row == 2
    @test pagerd.start_column == 5

    TerminalPager._change_active_match!(pagerd, false)
    @test pagerd.active_search_match_id == 3

    TerminalPager._quit_search!(pagerd)
    @test isempty(pagerd.search_matches)
    @test isempty(pagerd.ordered_search_matches)
    @test pagerd.num_matches == 0
    @test pagerd.active_search_match_id == 0

    pagerd.search_matches = TerminalPager.SearchMatches(99 => [(99, 99)])
    pagerd.ordered_search_matches = [TerminalPager.SearchMatch(99, 1, 99, 99)]
    pagerd.num_matches = 1
    pagerd.active_search_match_id = 1
    TerminalPager._find_matches!(pagerd, r"x")
    @test [(m.line, m.column) for m in pagerd.ordered_search_matches] == [(2, 3), (2, 5), (4, 1)]
    TerminalPager._find_matches!(pagerd, r"absent")
    @test isempty(pagerd.search_matches)
    @test isempty(pagerd.ordered_search_matches)
    @test pagerd.num_matches == 0
    @test pagerd.active_search_match_id == 0
end

@testset "Prepared Layout Lifecycle" begin
    pagerd = _create_pagerd("\e[31mrow α one\e[0m\nrow 界 two\nrow three")
    layout = pagerd.text_layout
    @test pagerd.num_lines == length(layout)
    @test collect(layout) == ["\e[31mrow α one\e[0m", "row 界 two", "row three"]

    TerminalPager._view!(pagerd)
    @test pagerd.text_layout === layout
    take!(pagerd.buf.io)

    pagerd.display_size = (1, 1)
    TerminalPager._update_display_size!(pagerd)
    @test pagerd.text_layout === layout

    pagerd.start_row = 2
    pagerd.start_column = 2
    pagerd.display_size = (8, 20)
    pagerd.frozen_rows = 1
    pagerd.frozen_columns = 1
    pagerd.title_rows = 1
    pagerd.show_ruler = true
    pagerd.visual_mode = true
    pagerd.visual_mode_selected_lines = [3]
    TerminalPager._find_matches!(pagerd, r"row")
    TerminalPager._change_active_match!(pagerd)
    TerminalPager._move_view_to_match!(pagerd)
    TerminalPager._view!(pagerd)

    @test pagerd.text_layout === layout
    @test pagerd.text_layout[2] == "row 界 two"
    @test pagerd.ordered_search_matches[1].index_in_line == 1
    @test !isempty(String(take!(pagerd.buf.io)))

    TerminalPager._quit_search!(pagerd)
    pagerd.show_ruler = false
    pagerd.visual_mode = false
    @test pagerd.text_layout === layout
    @test TerminalPager._assemble_yank_text(pagerd.text_layout, [3, 1, 3]) ==
        ("row α one\nrow three\n", 2)
    @test pagerd.text_layout === layout

    layout_calls = Ref(0)
    fit_lines = ["fits"]
    fit_layout_factory = lines -> begin
        layout_calls[] += 1
        return TerminalPager.TextViewLayout(lines)
    end
    @test TerminalPager._pager_content_fits(fit_lines, (10, 40))
    @test layout_calls[] == 0

    input_stream = IOBuffer("q")
    output_stream = IOContext(IOBuffer(), :displaysize => (5, 20), :color => false)
    term = REPL.Terminals.TTYTerminal("", input_stream, output_stream, output_stream)
    TerminalPager._pager!(
        term,
        join(fill("long line", 10), '\n');
        input = TerminalPager.PagerInput(input_stream),
        _layout_factory = fit_layout_factory,
    )
    @test layout_calls[] == 1

    comparison_lines = [
        "title α", "\e[31mrow match 界 match\e[0m", "visual e\u0301 row", "last row"
    ]
    comparison_layout = TerminalPager.TextViewLayout(comparison_lines)
    comparison_matches = TerminalPager.string_search_per_line(comparison_layout, r"match")
    raw_buffer = IOBuffer()
    prepared_buffer = IOBuffer()
    raw_crop = TerminalPager.textview(
        raw_buffer,
        comparison_lines,
        (2, -1, 2, -1);
        active_match = 2,
        frozen_columns_at_beginning = 1,
        frozen_lines_at_beginning = 1,
        maximum_number_of_columns = 24,
        maximum_number_of_lines = 4,
        search_matches = comparison_matches,
        show_ruler = true,
        title_lines = 1,
        visual_lines = [3],
        visual_line_backgrounds = "44",
    )
    prepared_crop = TerminalPager.textview(
        prepared_buffer,
        comparison_layout,
        (2, -1, 2, -1);
        active_match = 0,
        active_match_location = (2, 2),
        frozen_columns_at_beginning = 1,
        frozen_lines_at_beginning = 1,
        maximum_number_of_columns = 24,
        maximum_number_of_lines = 4,
        search_matches = comparison_matches,
        show_ruler = true,
        title_lines = 1,
        visual_lines = [3],
        visual_line_backgrounds = "44",
    )
    @test prepared_crop == raw_crop
    @test String(take!(prepared_buffer)) == String(take!(raw_buffer))
end

@testset "Yank Text Assembly" begin
    lines = ["first", "\e[31mred\e[0m", "", "αβ"]
    layout = TerminalPager.TextViewLayout(lines)
    line_ids = [4, 2, 3, 2]
    vector_result = @inferred TerminalPager._assemble_yank_text(lines, line_ids)
    layout_result = @inferred TerminalPager._assemble_yank_text(layout, line_ids)
    @test layout_result == vector_result
    result, count = layout_result
    @test result == "red\n\nαβ\n"
    @test count == 3
    @test sizeof(result) == sizeof("red\n\nαβ\n")
    @test @inferred(TerminalPager._assemble_yank_text(layout, Int[])) == ("", 0)
    @test TerminalPager._assemble_yank_text(lines, [1, 1]) == ("first\n", 1)
    @test TerminalPager._assemble_yank_text(lines, [4, 1]) == ("first\nαβ\n", 2)

    lines[1] = "mutated"
    push!(lines, "new")
    @test collect(layout) == ["first", "\e[31mred\e[0m", "", "αβ"]
    @test TerminalPager._assemble_yank_text(layout, [4, 1]) == ("first\nαβ\n", 2)
    @test_throws Base.CanonicalIndexError layout[1] = "changed"
    @test_throws MethodError push!(layout, "new")
end

@testset "Inline-Help Wrappers" begin
    source_root = dirname(pathof(TerminalPager))
    help_source = read(joinpath(source_root, "help_keybinding.jl"), String)
    extension_source = read(
        joinpath(dirname(source_root), "ext", "TerminalPagerAboutExt.jl"), String
    )
    @test !occursin("@eval", help_source)
    @test !occursin("@eval", extension_source)

    old_getter = TerminalPager._HELP_GETTER[]
    old_pager = TerminalPager._HELP_PAGER[]
    queries = Tuple{String, Module}[]
    pages = Any[]
    try
        TerminalPager._HELP_GETTER[] = (query, mod) -> begin
            push!(queries, (query, mod))
            return "help: $query"
        end
        TerminalPager._HELP_PAGER[] = (text; kwargs...) -> push!(pages, (text, kwargs))

        TerminalPager._show_extended_help("write", InlineHelpModule)
        @test queries[end] == ("?write", InlineHelpModule)
        @test pages[end][1] == "help: ?write"

        TerminalPager._show_help("local_name", InlineHelpModule)
        @test queries[end] == ("local_name", InlineHelpModule)

        @eval @help write
        @test queries[end][1] == "write"
        @test pages[end][2] == pairs((use_alternate_screen_buffer = true,))
    finally
        TerminalPager._HELP_GETTER[] = old_getter
        TerminalPager._HELP_PAGER[] = old_pager
    end

    restored = Bool[]
    @test_throws ErrorException TerminalPager._with_raw_restoration(
        () -> error("callback failed"),
        :terminal;
        raw_function = (terminal, raw) -> push!(restored, terminal == :terminal && raw),
    )
    @test restored == [true]

    extension = Base.get_extension(TerminalPager, :TerminalPagerAboutExt)
    @test !isnothing(extension)
    about_values = Any[]
    fallback_calls = Any[]
    extension._show_about(
        "value",
        InlineHelpModule,
        (mod, expression) -> 42,
        value -> push!(about_values, value),
        (identifier, mod) -> push!(fallback_calls, (identifier, mod)),
    )
    @test about_values == [42]
    extension._show_about(
        "missing",
        InlineHelpModule,
        (mod, expression) -> error("missing"),
        value -> nothing,
        (identifier, mod) -> push!(fallback_calls, (identifier, mod)),
    )
    @test fallback_calls == [("missing", InlineHelpModule)]
end
