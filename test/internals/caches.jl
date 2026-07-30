## Description #############################################################################
#
# Tests for the preference and help screen caches.
#
############################################################################################

@testset "Preference Cache" begin
    TerminalPager._invalidate_preference_cache!()
    @test isempty(TerminalPager._PREFERENCE_CACHE)

    value = TerminalPager._get_preference("pager_mode")
    @test haskey(TerminalPager._PREFERENCE_CACHE, "pager_mode")
    @test TerminalPager._get_preference("pager_mode") == value

    # Every mutating entry point must drop the cache, otherwise a changed preference would only
    # be honored after restarting Julia.
    for mutate in (
        () -> TerminalPager.set_preference!("pager_mode", "default"),
        () -> TerminalPager.drop_preference!("pager_mode"),
        () -> TerminalPager.drop_all_preferences!(),
    )
        TerminalPager._get_preference("pager_mode")
        @test !isempty(TerminalPager._PREFERENCE_CACHE)
        mutate()
        @test isempty(TerminalPager._PREFERENCE_CACHE)
    end

    # A cached `false` must not be mistaken for a missing entry.
    TerminalPager._invalidate_preference_cache!()
    @test TerminalPager._get_preference("block_alternate_screen_buffer") == false
    @test haskey(TerminalPager._PREFERENCE_CACHE, "block_alternate_screen_buffer")
    @test TerminalPager._get_preference("block_alternate_screen_buffer") == false

    # A value stored with the wrong type must still be rejected before it is cached.
    @test_throws ArgumentError TerminalPager._validate_preference("pager_mode", true)
end

@testset "Key Binding Generation" begin
    initial = TerminalPager._KEYBINDINGS_GENERATION[]

    TerminalPager.set_keybinding("Z", :quit)
    @test TerminalPager._KEYBINDINGS_GENERATION[] > initial

    generation = TerminalPager._KEYBINDINGS_GENERATION[]
    TerminalPager.delete_keybinding("Z")
    @test TerminalPager._KEYBINDINGS_GENERATION[] > generation

    generation = TerminalPager._KEYBINDINGS_GENERATION[]
    TerminalPager.reset_keybindings()
    @test TerminalPager._KEYBINDINGS_GENERATION[] > generation
end

@testset "Action Key Bindings" begin
    TerminalPager.reset_keybindings()
    bindings = TerminalPager._action_keybindings()

    # The cache must be reused while the keybindings do not change.
    @test TerminalPager._action_keybindings() === bindings

    # Every action in `_KEYBINDINGS` must be described.
    for action in values(TerminalPager._KEYBINDINGS)
        @test haskey(bindings, action)
        @test !isempty(bindings[action])
    end

    # The descriptions must be sorted, so that the help screen is deterministic instead of
    # depending on the iteration order of a `Dict`.
    for description in values(bindings)
        keys_listed = split(description, ", ")
        @test keys_listed == sort(keys_listed)
    end

    # An unbound action must yield an empty description instead of throwing.
    @test TerminalPager._getkb(:action_that_does_not_exist) == ""

    try
        TerminalPager.set_keybinding("Z", :quit)
        updated = TerminalPager._action_keybindings()
        @test occursin("Z", updated[:quit])
        @test !occursin("Z", bindings[:quit]) || bindings === updated
    finally
        TerminalPager.reset_keybindings()
    end

    @test !occursin("Z", TerminalPager._action_keybindings()[:quit])
end

@testset "Help Screen Cache" begin
    TerminalPager.reset_keybindings()

    text, layout = TerminalPager._help_screen(true)
    @test occursin("TerminalPager.jl", text)
    @test collect(layout) == split(text, '\n')

    # A second call must reuse the text and its prepared layout.
    cached_text, cached_layout = TerminalPager._help_screen(true)
    @test cached_text === text
    @test cached_layout === layout

    # The colorless screen is cached separately.
    plain_text, plain_layout = TerminalPager._help_screen(false)
    @test plain_text !== text
    @test plain_layout !== layout
    @test !occursin('\e', plain_text)

    # Changing a keybinding must rebuild it.
    try
        TerminalPager.set_keybinding("Z", :quit)
        new_text, new_layout = TerminalPager._help_screen(true)
        @test new_text !== text
        @test new_layout !== layout
        @test occursin("Z", new_text)
    finally
        TerminalPager.reset_keybindings()
    end
end

@testset "Auto-Fit With A Prepared Layout" begin
    lines = ["plain", "α界 wide", "\e[31mred\e[0m", "", repeat("y", 100)]
    layout = TerminalPager.TextViewLayout(lines)

    # The layout already measured every line, so the overload must agree with the one that
    # scans the text again.
    for size in ((10, 5), (10, 20), (10, 200), (2, 200), (3, 200), (7, 100), (7, 99))
        @test TerminalPager._pager_content_fits(layout, size) ==
            TerminalPager._pager_content_fits(lines, size)
    end

    # `split` yields `SubString`s, which must be accepted without being copied.
    sub_lines = split("plain\nα界 wide\n", '\n')
    @test eltype(sub_lines) <: SubString
    @test TerminalPager._pager_content_fits(sub_lines, (10, 40)) ==
        TerminalPager._pager_content_fits(String.(sub_lines), (10, 40))
    @test TerminalPager.TextViewLayout(sub_lines) isa TerminalPager.TextViewLayout
end
