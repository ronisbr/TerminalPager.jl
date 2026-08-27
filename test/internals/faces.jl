## Description #############################################################################
#
# Tests related to the faces.
#
############################################################################################

const _SS = TerminalPager.StyledStrings
const _Face = TerminalPager.Face

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
    end
end
