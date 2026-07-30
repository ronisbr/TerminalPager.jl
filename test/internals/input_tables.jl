## Description #############################################################################
#
# Tests for the precomputed keystroke and keycode tables.
#
############################################################################################

_loop_ascii_keystroke(n) = (for _ in 1:n
    TerminalPager._ascii_keystroke(UInt8('j'))
end)

_loop_decode_arrow(bytes, n) = (for _ in 1:n
    TerminalPager._decode_keystroke(bytes)
end)

@testset "Precomputed ASCII Keystrokes" begin
    # The table must agree with the function that used to build every keystroke on demand.
    for byte in 0x00:0x7f
        expected = TerminalPager._build_ascii_keystroke(byte)
        actual = TerminalPager._ascii_keystroke(byte)
        @test actual.value == expected.value
        @test actual.raw == expected.raw
        @test actual.alt == expected.alt
        @test actual.ctrl == expected.ctrl
        @test actual.shift == expected.shift
    end

    @test length(TerminalPager._ASCII_KEYSTROKES) == 128
    @test TerminalPager._ascii_keystroke(UInt8('j')).value == "j"

    # A keypress must be a table lookup instead of building a keystroke.
    _loop_ascii_keystroke(1000)
    @test (@allocated _loop_ascii_keystroke(5000)) == 0
end

@testset "Packed Keycode Lookup" begin
    codes = collect(keys(TerminalPager.keycodes))

    @test TerminalPager._MAX_KEYCODE_BYTES <= 7
    @test TerminalPager._MIN_KEYCODE_BYTES >= 1

    # The packing must be injective over every sequence and every proper prefix of them,
    # otherwise two different keys would decode to the same one.
    packed = Dict{UInt64, Vector{UInt8}}()

    for code in codes
        bytes = collect(codeunits(code))

        for len in 1:length(bytes)
            key = TerminalPager._pack_keycode(bytes, len)
            entry = bytes[1:len]

            if haskey(packed, key)
                @test packed[key] == entry
            else
                packed[key] = entry
            end
        end
    end

    @test length(TerminalPager._KEYCODE_EXACT) == length(TerminalPager.keycodes)

    # Every sequence must be found, and every proper prefix must be recognized as incomplete.
    for code in codes
        bytes = collect(codeunits(code))
        key = TerminalPager._pack_keycode(bytes, length(bytes))
        @test haskey(TerminalPager._KEYCODE_EXACT, key)
        @test TerminalPager._KEYCODE_EXACT[key].value == TerminalPager.keycodes[code].value

        for len in 1:(length(bytes) - 1)
            @test TerminalPager._pack_keycode(bytes, len) ∈ TerminalPager._KEYCODE_PREFIXES
        end
    end

    # No sequence may be a strict prefix of another one, otherwise the length at which the
    # decoder stops searching would depend on the iteration order.
    for a in codes, b in codes
        a == b && continue
        @test !startswith(b, a)
    end

    # Decoding an arrow key is the most common escape sequence in the pager.
    arrow = collect(codeunits("\e[B"))
    _loop_decode_arrow(arrow, 1000)
    @test (@allocated _loop_decode_arrow(arrow, 5000)) / 5000 < 64
end

@testset "Control Key Combinations" begin
    # `set_keybinding` documents a `ctrl` keyword, but the decoder reported every control byte
    # with `ctrl = false` and the raw control character as its value, so a CTRL binding could
    # never match.
    named = Dict(
        0x04 => "<eot>", 0x09 => "<tab>", 0x0a => "<enter>", 0x0d => "<enter>",
        0x15 => "<shiftin>",
    )

    for byte in 0x01:0x1a
        key = TerminalPager._ascii_keystroke(byte)

        if haskey(named, byte)
            @test key.value == named[byte]
            @test key.ctrl == false
        else
            @test key.ctrl == true
            @test key.value == string(Char(byte - 0x01 + UInt8('a')))
            @test !key.alt
            @test !key.shift
        end
    end

    @test TerminalPager._ascii_keystroke(0x01).value == "a"
    @test TerminalPager._ascii_keystroke(0x03).value == "c"
    @test TerminalPager._ascii_keystroke(0x1a).value == "z"

    # A CTRL binding must now resolve to its action.
    try
        TerminalPager.set_keybinding("a", :quit; ctrl = true)
        @test TerminalPager._pager_action(TerminalPager._ascii_keystroke(0x01)) == :quit
    finally
        TerminalPager.reset_keybindings()
    end

    # ALT combined with CTRL must keep both modifiers.
    status, key, _ = TerminalPager._decode_keystroke(UInt8[0x1b, 0x01])
    @test status == :complete
    @test key.value == "a"
    @test key.alt
    @test key.ctrl

    # Bytes outside the control letter range are unchanged.
    @test TerminalPager._ascii_keystroke(0x00).ctrl == false
    @test TerminalPager._ascii_keystroke(0x1c).ctrl == false
    @test TerminalPager._ascii_keystroke(UInt8('a')).ctrl == false
end

@testset "Raw Keystroke Bytes" begin
    # `raw` is only used for diagnostics, but its format must not change.
    @test TerminalPager._raw_bytes(UInt8[]) == ""
    @test TerminalPager._raw_bytes(UInt8[27]) == "27"
    @test TerminalPager._raw_bytes(UInt8[27, 91, 66]) == "27, 91, 66"
    @test TerminalPager._raw_bytes(UInt8[0, 255]) == "0, 255"
end

@testset "Concrete Key Binding Keys" begin
    # A `Union` in the key type makes the tuple abstract, so every lookup dereferences a boxed
    # value. `_pager_action` only ever builds `String` keys.
    @test keytype(TerminalPager._KEYBINDINGS) == Tuple{String, Bool, Bool, Bool}
    @test isconcretetype(keytype(TerminalPager._KEYBINDINGS))
    @test keytype(TerminalPager._DEFAULT_KEYBINDINGS) ==
        keytype(TerminalPager._KEYBINDINGS)
end
