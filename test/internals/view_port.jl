## Description #############################################################################
#
# Tests of the view renderer over a large set of view combinations. The bytes and the crop
# counters of every combination are compared with the checksums in `view_port_golden.txt`,
# which were recorded when the renderer produced exactly the output of the function it
# replaced, `StringManipulation.textview`.
#
# If the output of the renderer changes on purpose, the checksums are recorded again by
# running the tests with the environment variable `TERMINALPAGER_UPDATE_GOLDEN` set to
# `true`.
#
############################################################################################

const _VIEW_PORT_GOLDEN_FILE = joinpath(@__DIR__, "view_port_golden.txt")

"""
    _ported_view(lines::Vector{String}, view::NTuple{4, Int}; kwargs...) ->
        Tuple{String, Int, Int}

Render `lines` with the renderer of this package and return the bytes and the crop counters.

# Arguments

- `lines::Vector{String}`: Lines of the text.
- `view::NTuple{4, Int}`: View passed to the renderer.
"""
function _ported_view(lines::Vector{String}, view::NTuple{4, Int}; kwargs...)
    return TerminalPager._textview(TerminalPager.ViewLayout(lines), view; kwargs...)
end

"""
    _view_checksum(
        lines::Vector{String},
        view::NTuple{4, Int},
        kwargs::NamedTuple
    ) -> UInt32

Render `lines` with the renderer of this package and return the 32-bit FNV-1a checksum of
the bytes and the crop counters, which does not depend on the Julia version.

# Arguments

- `lines::Vector{String}`: Lines of the text.
- `view::NTuple{4, Int}`: View passed to the renderer.
- `kwargs::NamedTuple`: Keywords passed to the renderer.
"""
function _view_checksum(lines::Vector{String}, view::NTuple{4, Int}, kwargs::NamedTuple)
    text, cropped_lines, cropped_columns = _ported_view(lines, view; kwargs...)
    checksum = 0x811c9dc5

    for byte in codeunits(string(text, '\0', cropped_lines, '\0', cropped_columns))
        checksum = (checksum ⊻ byte) * 0x01000193
    end

    return checksum
end

"""
    _read_view_port_golden() -> Dict{String, Vector{UInt32}}

Read the recorded checksums of every group of view combinations, keyed by the group name.
"""
function _read_view_port_golden()
    golden = Dict{String, Vector{UInt32}}()
    isfile(_VIEW_PORT_GOLDEN_FILE) || return golden

    for line in eachline(_VIEW_PORT_GOLDEN_FILE)
        name, checksums = split(line, '\t')
        golden[name] = [parse(UInt32, c; base = 16) for c in split(checksums)]
    end

    return golden
end

"""
    _write_view_port_golden(golden::Dict{String, Vector{UInt32}}) -> Nothing

Write the checksums in `golden` to the golden file, one group per line, sorted by name.

# Arguments

- `golden::Dict{String, Vector{UInt32}}`: Checksums of every group, keyed by its name.
"""
function _write_view_port_golden(golden::Dict{String, Vector{UInt32}})
    open(_VIEW_PORT_GOLDEN_FILE, "w") do io
        for name in sort!(collect(keys(golden)))
            checksums = (string(c; base = 16, pad = 8) for c in golden[name])
            println(io, name, '\t', join(checksums, ' '))
        end
    end

    return nothing
end

"""
    _lcg(state::UInt64) -> UInt64

Return the next state of a linear congruential generator, so that the sampled combinations
are the same in every run without a dependency on `Random`.

# Arguments

- `state::UInt64`: Current state.
"""
_lcg(state::UInt64) = state * 0x5851f42d4c957f2d + 0x14057b7ef767814f

"""
    _pick(state::UInt64, options) -> Tuple{UInt64, Any}

Return the next state of the generator and one of `options` selected with it.

# Arguments

- `state::UInt64`: Current state.
- `options`: Collection to pick from.
"""
function _pick(state::UInt64, options)
    state = _lcg(state)
    return state, options[Int(state >> 33) % length(options) + 1]
end

# The markdown fixture of StringManipulation.jl, with bold and underlined runs, colored code,
# empty lines, and a quoted block.
const _MARKDOWN_FIXTURE = split(
    """
\e[1m  Si distentae\e[22m
\e[1m  ≡≡≡≡≡≡≡≡≡≡≡≡\e[22m

\e[1m  Carpitur devorat\e[22m
\e[1m  ================\e[22m

  Lorem markdownum ipsi Emathion Neoptolemum et moenia \e[1mviveret spumantis\e[22m
  namque. Iam excepi ignis turbamve, \e[4mcruorem quo nubes\e[24m aevi; sensit esse
  animantis, Chironis infelix \e[4mstabantque\e[24m. Ruit et iuvenemque longo; ut at
  iugis, venit adventus molle adpropera?

  Putat quibus Phaethon manet sanguine elige, orbem palearia iuvenum age prior
  mollibat \e[4mPallas\e[24m est fera curru naribus. Constituis priore orbae generosque
  insidiaeque umbra patulas Laurentes denique senior?

\e[36m  # Compute recursively `sin(m*ϕ)` and `cos(m*ϕ)`.\e[39m
\e[36m  sin_mϕ = 2cos_ϕ * sin_m_1ϕ - sin_m_2ϕ\e[39m
\e[36m  cos_mϕ = 2cos_ϕ * cos_m_1ϕ - cos_m_2ϕ\e[39m

\e[1m  Et carus quo inceptaque urbem quibus loqui\e[22m
\e[1m  ==========================================\e[22m

  Perspicuus \e[4mbello\e[24m, rates siqua profatur tumulumque Taygetenque cauda multas
  ut enixa. Cum aenea est exhibuere procubuere terraeque virgo decimum
  victorem silvis dumque cunctatus excidit piget
  (http://ea.org/pecorumquemunera) nam, tu. Suo quod ab funesta atque
  Thessalus idem trabe et \e[1mquamvis\e[22m lacrimis rerum sed erat per.

  │  Nec male regia, et tela, videns vultibus ut faciem plangore
  │  versantem. Obscena admoveam nominis pater \e[4mest confundas decimo\e[24m
  │  humus indigenae aquae absit. Nos nox acta videt animae, Phineus
  │  caput nec.""",
    '\n',
)

const _VIEW_FIXTURES = Dict{String, Vector{String}}(
    "markdown" => String.(_MARKDOWN_FIXTURE),
    "mixed" => [
        "title α", "\e[31mrow match 界 match\e[0m", "visual é row", "last row"
    ],
    "ascii" => ["line $i" for i in 1:40],
    "ansi" => [
        "\e[1m\e[31mbold red\e[0m then plain match",
        "\e[32mleading escape and trailing\e[0m",
        "mid \e[0m reset match here",
        "\e]8;;https://example.org\e\\link ST\e]8;;\e\\ after",
        "\e]8;;https://example.org\alink BEL\e]8;;\a after match",
        "unknown \e[2K csi sequence match",
        "\e[38;2;10;20;30mtrue color\e[48;5;201m indexed\e[0m",
        "\e[4munderline \e[9mstrike\e[0m match",
        "\e[7minverse\e[27m normal \e[2mfaint\e[22m",
    ],
    "unicode" => [
        "漢字の列と a match",
        "emoji 😀 here and 😀 there match",
        "combining é and ö marks",
        "wide界wide界wide界wide界",
        "αβγδεζηθ match ικλμ",
        "ab界cd界ef界gh界",
    ],
    "blank" => ["", "   ", "", "x", "", ""],
    "trailing" => split("one\ntwo match\nthree\n", '\n') .|> String,
    "long" => [repeat("abcdefghij", 30), "short", repeat("α界", 100)],
    "empty" => String[],
    "single" => ["only line with a match"],
)

const _VIEW_DECORATIONS = (
    (;),
    (
        highlight = "\e[0;30;47m",
        active_highlight = "\e[0;30;43m",
        ruler_decoration = "\e[0;90m",
    ),
)

@testset "View Port Golden Output" begin
    update_golden = get(ENV, "TERMINALPAGER_UPDATE_GOLDEN", "false") == "true"
    golden = _read_view_port_golden()
    recorded = Dict{String, Vector{UInt32}}()

    # Every fixture is rendered with one option changed at a time around a base view, and
    # with a sample of combinations.
    for (name, lines) in _VIEW_FIXTURES
        n = length(lines)
        width = maximum(TerminalPager.printable_textwidth, lines; init = 0)
        matches = TerminalPager.string_search_per_line(lines, r"a|界|match|qu")

        rows = unique((1, 2, 5, n + 3))
        columns = unique((1, 3, 10, width + 2))
        frozen_lines = unique((0, 1, 3, n + 2))
        frozen_columns = (0, 2, 5, 40)
        titles = (0, 1, 2)
        max_lines = (-1, 0, 1, 3, 10)
        max_columns = (-1, 0, 1, 5, 24, 80)
        visuals = (
            (nothing, "44"),
            ([3], "44"),
            ([2, 3, 3, 0, 99], ["41", "42", "43", "44", "45"]),
        )
        searches = (nothing, matches)

        active_locations = [(0, 0)]
        for (line, line_matches) in matches
            for index in eachindex(line_matches)
                push!(active_locations, (line, index))
            end
        end
        sort!(active_locations)

        @testset "$name: Single Axis" begin
            base = (
                view = (2, -1, 3, -1),
                frozen_lines_at_beginning = 1,
                frozen_columns_at_beginning = 2,
                title_lines = 1,
                show_ruler = true,
                maximum_number_of_lines = 10,
                maximum_number_of_columns = 24,
                visual_lines = [3],
                visual_line_backgrounds = "44",
                search_matches = matches,
                active_match_location = (0, 0),
            )

            variations = Any[]
            for r in rows, c in columns
                push!(variations, (; view = (r, -1, c, -1)))
            end
            for f in frozen_lines
                push!(variations, (; frozen_lines_at_beginning = f))
            end
            for f in frozen_columns
                push!(variations, (; frozen_columns_at_beginning = f))
            end
            for t in titles
                push!(variations, (; title_lines = t))
            end
            for m in max_lines
                push!(variations, (; maximum_number_of_lines = m))
            end
            for m in max_columns
                push!(variations, (; maximum_number_of_columns = m))
            end
            for (vl, vb) in visuals
                push!(variations, (; visual_lines = vl, visual_line_backgrounds = vb))
            end
            for s in searches
                push!(variations, (; search_matches = s))
            end
            for loc in active_locations
                push!(variations, (; active_match_location = loc))
            end
            push!(variations, (; show_ruler = false))

            checksums = UInt32[]

            for variation in variations, decorations in _VIEW_DECORATIONS
                options = merge(base, variation, decorations)
                view = options.view
                kwargs = Base.structdiff(options, (; view = nothing))
                push!(checksums, _view_checksum(lines, view, kwargs))
            end

            recorded["$name: Single Axis"] = checksums
            update_golden || @test checksums == get(golden, "$name: Single Axis", UInt32[])
        end

        @testset "$name: Sampled Combinations" begin
            state = UInt64(1986)
            checksums = UInt32[]

            for _ in 1:300
                state, r = _pick(state, rows)
                state, c = _pick(state, columns)
                state, fl = _pick(state, frozen_lines)
                state, fc = _pick(state, frozen_columns)
                state, t = _pick(state, titles)
                state, ml = _pick(state, max_lines)
                state, mc = _pick(state, max_columns)
                state, (vl, vb) = _pick(state, visuals)
                state, s = _pick(state, searches)
                state, loc = _pick(state, active_locations)
                state, ruler = _pick(state, (false, true))
                state, decorations = _pick(state, _VIEW_DECORATIONS)
                isnothing(s) && (loc = (0, 0))

                kwargs = merge(
                    (
                        frozen_lines_at_beginning = fl,
                        frozen_columns_at_beginning = fc,
                        title_lines = t,
                        show_ruler = ruler,
                        maximum_number_of_lines = ml,
                        maximum_number_of_columns = mc,
                        visual_lines = vl,
                        visual_line_backgrounds = vb,
                        search_matches = s,
                        active_match_location = loc,
                    ),
                    decorations,
                )
                push!(checksums, _view_checksum(lines, (r, -1, c, -1), kwargs))
            end

            recorded["$name: Sampled Combinations"] = checksums
            update_golden ||
                @test checksums == get(golden, "$name: Sampled Combinations", UInt32[])
        end
    end

    # The bounded number of rows and columns of the view tuple itself.
    lines = _VIEW_FIXTURES["markdown"]
    checksums = UInt32[]

    for view in ((1, 5, 1, 20), (3, 0, 4, 0), (2, 100, 2, 100), (0, -1, 0, -1))
        push!(checksums, _view_checksum(lines, view, (;)))
        push!(
            checksums,
            _view_checksum(lines, view, (; show_ruler = true, frozen_lines_at_beginning = 2)),
        )
    end

    recorded["markdown: Bounded View"] = checksums
    update_golden || @test checksums == get(golden, "markdown: Bounded View", UInt32[])

    update_golden && _write_view_port_golden(recorded)

    # A vector of backgrounds must have one entry per visual line.
    @test_throws ArgumentError _ported_view(
        lines, (1, -1, 1, -1); visual_lines = [1, 2], visual_line_backgrounds = ["44"]
    )
end

@testset "View Port Ruler Additions" begin
    lines = ["line $i" for i in 1:12]
    layout = TerminalPager.ViewLayout(lines)

    # The ruler numbers follow `line_numbers`, and its width follows the last number.
    text, _, _ = TerminalPager._textview(
        layout, (1, 3, 1, -1); show_ruler = true, line_numbers = [7, 20, 300, (301:309)...]
    )
    @test text == "\e[90m   7 │\e[0mline 1\n\e[90m  20 │\e[0mline 2\n\e[90m 300 │\e[0mline 3"

    text, _, _ = TerminalPager._textview(
        layout, (1, 3, 1, 4); show_ruler = true, maximum_number_of_columns = 10
    )
    @test text == "\e[90m  1 │\e[0mline\n\e[90m  2 │\e[0mline\n\e[90m  3 │\e[0mline"

    # The foot replaces the bar on the last frozen row only, and follows the display limit.
    text, _, _ = TerminalPager._textview(
        layout, (3, 2, 1, -1); show_ruler = true, frozen_lines_at_beginning = 2, ruler_foot = true
    )
    @test split(text, '\n') == [
        "\e[90m  1 │\e[0mline 1",
        "\e[90m  2 ┴\e[0mline 2\e[0m",
        "\e[90m  3 │\e[0mline 3",
        "\e[90m  4 │\e[0mline 4",
    ]
    text, _, _ = TerminalPager._textview(
        layout, (1, -1, 1, -1); show_ruler = true, ruler_foot = true
    )
    @test !occursin("┴", text)
    text, _, _ = TerminalPager._textview(
        layout,
        (1, -1, 1, -1);
        show_ruler = true,
        frozen_lines_at_beginning = 5,
        maximum_number_of_lines = 3,
        ruler_foot = true,
    )
    @test split(text, '\n') == [
        "\e[90m  1 │\e[0mline 1",
        "\e[90m  2 │\e[0mline 2",
        "\e[90m  3 ┴\e[0mline 3\e[0m",
    ]

    # A marked row starts with the mark instead of the blank.
    text, _, _ = TerminalPager._textview(
        layout, (1, 3, 1, -1); show_ruler = true, ruler_marks = Set([2, 99])
    )
    @test split(text, '\n') == [
        "\e[90m  1 │\e[0mline 1",
        "\e[90m• 2 │\e[0mline 2",
        "\e[90m  3 │\e[0mline 3",
    ]

    # An active match location without a match is ignored instead of throwing.
    matches = TerminalPager.string_search_per_line(lines, r"line 2")
    text, _, _ = TerminalPager._textview(
        layout, (1, 2, 1, -1); search_matches = matches, active_match_location = (5, 7)
    )
    @test text == "line 1\n\e[7mline 2\e[0m"
    text, _, _ = TerminalPager._textview(
        layout, (1, 2, 1, -1); search_matches = matches, active_match_location = (2, 1)
    )
    @test text == "line 1\n\e[30;43mline 2\e[0m"
end
