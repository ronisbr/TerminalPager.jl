## Description #############################################################################
#
# Tests related to the faces and their customization.
#
############################################################################################

const _SS = TerminalPager.StyledStrings
const _Face = TerminalPager.Face
const _SimpleColor = TerminalPager.SimpleColor

@testset "Face Rendering" begin
    sgr = TerminalPager._face_sgr

    @test sgr(_Face()) == "\e[0m"
    @test sgr(_Face(; inverse = true)) == "\e[0;7m"
    @test sgr(_Face(; weight = :bold, foreground = :bright_white, background = :blue)) ==
        "\e[0;1m\e[97m\e[44m"
    @test sgr(_Face(; weight = :light, slant = :italic, underline = true)) == "\e[0;2;3;4m"
    @test sgr(_Face(; strikethrough = true, underline = (:red, :curly))) == "\e[0;4;9m"
    @test sgr(_Face(; underline = false, strikethrough = false, inverse = false)) == "\e[0m"

    # The default colors are already selected by the reset.
    @test sgr(_Face(; foreground = :default, background = :default)) == "\e[0m"

    # Merged faces carry the defaults of every attribute, which must not be written.
    @test sgr(_SS.getface(_Face(; weight = :bold))) == "\e[0;1m"

    # A 24-bit color is written as such or approximated, depending on the terminal.
    rgb = sgr(_Face(; foreground = "#ff8800", background = 0x005f87))
    @test startswith(rgb, "\e[0m\e[38;")
    @test occursin("m\e[48;", rgb)
    @test endswith(rgb, "m")

    background = TerminalPager._face_background_sgr
    @test background(_Face(; background = :blue)) == "44"
    @test background(_Face(; background = :bright_black)) == "100"
    @test background(_Face(; foreground = :red)) == ""
    @test background(_Face(; background = :default)) == ""
    @test background(_Face()) == ""
    @test startswith(background(_Face(; background = "#005f87")), "48;")
end

@testset "Face Registration" begin
    TerminalPager._register_faces!()

    # Registering again must keep the current faces.
    TerminalPager._register_faces!()

    for (name, face) in TerminalPager._FACES
        @test TerminalPager._current_face(name) == _SS.getface(face)
    end

    config = TerminalPager._display_config()
    @test config == TerminalPager.DisplayConfig()
    @test config.status_bar == "\e[0;7m"
    @test config.badge_normal == "\e[0;1m\e[97m\e[44m"
    @test config.search_match == "\e[0m\e[30m\e[47m"
    @test config.search_active_match == "\e[0m\e[30m\e[43m"
    @test config.visual_line == "100"
    @test config.visual_active_line == "44"
    @test config.scrollbar_track == "\e[0m\e[90m"
    @test config.scrollbar_thumb == "\e[0m"
    @test config.help_title == "\e[0;1m\e[36m"

    @test_throws ArgumentError TerminalPager._face_name("unknown")
    @test TerminalPager._face_name("badge_normal") == :terminalpager_badge_normal
end

@testset "Face Specification" begin
    spec = TerminalPager._face_spec

    face = _Face(;
        weight = :bold,
        slant = :italic,
        foreground = :black,
        background = "#005f87",
        underline = (:red, :curly),
        strikethrough = true,
        inverse = false,
        inherit = [:bold],
    )
    face_spec = spec(face)
    @test face_spec == Dict{String, Any}(
        "weight" => "bold",
        "slant" => "italic",
        "foreground" => "black",
        "background" => "#005f87",
        "underline" => ["red", "curly"],
        "strikethrough" => true,
        "inverse" => false,
        "inherit" => ["bold"],
    )
    @test convert(_Face, face_spec) == face

    @test spec(_Face()) == Dict{String, Any}()
    @test spec(_Face(; underline = :red)) == Dict{String, Any}("underline" => "red")
    @test spec(_Face(; underline = true)) == Dict{String, Any}("underline" => true)

    # A style-only underline has no color.
    curly = _Face(; underline = :curly)
    @test spec(curly) == Dict{String, Any}("underline" => ["", "curly"])
    @test convert(_Face, spec(curly)) == curly
end

@testset "Face Preferences" begin
    name = "search_active_match"
    face_name = :terminalpager_search_active_match
    default = _SS.getface(TerminalPager._DEFAULT_FACES[:search_active_match])

    try
        # Setting a face merges the attributes into the current face and persists them.
        TerminalPager.set_face!(name; background = :red)
        @test _SS.getface(face_name).background == _SimpleColor(:red)
        @test _SS.getface(face_name).foreground == _SimpleColor(:black)
        @test TerminalPager._face_preferences()[name] ==
            Dict{String, Any}("background" => "red")

        # Successive calls merge the stored attributes too.
        TerminalPager.set_face!(name, _Face(; weight = :bold))
        @test _SS.getface(face_name).weight == :bold
        @test _SS.getface(face_name).background == _SimpleColor(:red)
        @test TerminalPager._face_preferences()[name] ==
            Dict{String, Any}("background" => "red", "weight" => "bold")

        # The persisted faces are applied on top of the defaults at initialization.
        _SS.resetfaces!(face_name)
        @test _SS.getface(face_name) == default
        TerminalPager._load_face_preferences!()
        @test _SS.getface(face_name).background == _SimpleColor(:red)
        @test _SS.getface(face_name).weight == :bold

        # The next session renders the customized face.
        @test TerminalPager._display_config().search_active_match == "\e[0;1m\e[30m\e[41m"

        # Dropping the face restores the default and removes the preference.
        TerminalPager.drop_face!(name)
        @test _SS.getface(face_name) == default
        @test !haskey(TerminalPager._face_preferences(), name)
        @test TerminalPager._display_config() == TerminalPager.DisplayConfig()

        # Invalid inputs.
        @test_throws ArgumentError TerminalPager.set_face!("unknown"; background = :red)
        @test_throws ArgumentError TerminalPager.set_face!(name; bold = true)
        @test_throws ArgumentError TerminalPager.drop_face!("unknown")
        @test !haskey(TerminalPager._face_preferences(), name)

        # The replaced preferences point to the faces.
        for (preference, face) in TerminalPager._REPLACED_PREFERENCES
            @test_throws ArgumentError TerminalPager.set_preference!(preference, "44")
            @test_throws ArgumentError TerminalPager.drop_preference!(preference)
            error = try
                TerminalPager.set_preference!(preference, "44")
            catch err
                err
            end
            @test occursin("\"$face\"", error.msg)
            @test occursin("set_face!", error.msg)
        end

        # Dropping all preferences resets the faces.
        TerminalPager.set_face!("badge_normal"; background = :green)
        TerminalPager.set_face!("ruler"; foreground = :red)
        @test _SS.getface(:terminalpager_badge_normal).background == _SimpleColor(:green)
        TerminalPager.drop_all_preferences!()
        @test _SS.getface(:terminalpager_badge_normal).background == _SimpleColor(:blue)
        @test _SS.getface(:terminalpager_ruler).foreground == _SimpleColor(:bright_black)
        @test isempty(TerminalPager._face_preferences())
    finally
        TerminalPager.drop_all_preferences!()
    end
end
