## Description #############################################################################
#
# Tests for the precomputed keystroke and keycode tables.
#
############################################################################################

_loop_ascii_keystroke(n) = (
    for _ in 1:n
        TerminalPager._ascii_keystroke(UInt8('j'))
    end
)

_loop_decode_arrow(bytes, n) = (
    for _ in 1:n
        TerminalPager._decode_keystroke(bytes)
    end
)

@testset "Precomputed ASCII Keystrokes" begin
    # The table must agree with the function that used to build every keystroke on demand.
    for byte in 0x00:0x7f
        expected = TerminalPager._build_ascii_keystroke(byte)
        actual = TerminalPager._ascii_keystroke(byte)
        @test actual.value == expected.value
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

@testset "Escape Sequence Parser" begin
    # The special keys were looked up in a table, which missed many combinations of the
    # modifiers. They are now parsed following the xterm conventions.
    for (sequence, fields) in (
        "\e[1;3H" => ("<home>", true, false, false),
        "\e[1;4A" => ("<up>", true, false, true),
        "\e[1;7D" => ("<left>", true, true, false),
        "\e[1;8C" => ("<right>", true, true, true),
        "\e[5;5~" => ("<pageup>", false, true, false),
        "\e[6;3~" => ("<pagedown>", true, false, false),
        "\e[3;2~" => ("<delete>", false, false, true),
        "\e[1;16A" => ("<up>", true, true, true),
        "\eO2P" => ("<F1>", false, false, true),
        "\eO5A" => ("<up>", false, true, false),
        "\e\eOA" => ("<up>", true, false, false),
        "\e\e[1;5A" => ("<up>", true, true, false),
        "\e[1;5Z" => ("<tab>", false, true, true),
    )
        bytes = collect(codeunits(sequence))
        status, key, consumed = TerminalPager._decode_keystroke(bytes)
        @test status === :complete
        @test (key.value, key.alt, key.ctrl, key.shift) == fields
        @test consumed == length(bytes)
    end

    # Sequences that are not keys are undefined and consume the whole sequence: a cursor
    # position report, private sequences, sub-parameters, intermediate bytes, too many
    # parameters, an invalid modifier, an unknown number, the bracketed paste, and numbers
    # large enough to overflow.
    for sequence in (
        "\e[24;80R",
        "\e[2A",
        "\e[?1;2c",
        "\e[>0;95;0c",
        "\e[1:2A",
        "\e[1 A",
        "\e[1;2;3A",
        "\e[1;17A",
        "\e[1;0A",
        "\e[2~",
        "\e[200~",
        "\e[99X",
        "\e[1;18446744073709551621A",
        "\eO18446744073709551621A",
        "\eOz",
    )
        bytes = collect(codeunits(sequence))
        status, key, consumed = TerminalPager._decode_keystroke(bytes)
        @test status === :complete
        @test key.value == "<undefined>"
        @test consumed == length(bytes)
    end

    # A control byte breaks the sequence, which ends before it, so that the byte starts the
    # next keystroke.
    input = TerminalPager.PagerInput(IOBuffer("\eO\e[Aq"))
    @test TerminalPager._read_keystroke!(input).value == "<undefined>"
    @test TerminalPager._read_keystroke!(input).value == "<up>"
    @test TerminalPager._read_keystroke!(input).value == "q"

    input = TerminalPager.PagerInput(IOBuffer("\e[1\nq"))
    @test TerminalPager._read_keystroke!(input).value == "<undefined>"
    @test TerminalPager._read_keystroke!(input).value == "<enter>"
    @test TerminalPager._read_keystroke!(input).value == "q"

    # A sequence is incomplete until its final byte arrives.
    for sequence in ("\eO", "\eO2", "\e[", "\e[1;", "\e[1;5", "\e[200", "\e\eO", "\e\e[1")
        @test first(TerminalPager._decode_keystroke(collect(codeunits(sequence)))) ===
            :incomplete
    end

    # Decoding a key sequence does not allocate, and the arrows are the most common ones.
    for sequence in ("\e[B", "\eOB", "\e[1;5B", "\e[6~", "\e\e[A")
        bytes = collect(codeunits(sequence))
        _loop_decode_arrow(bytes, 1000)
        @test (@allocated _loop_decode_arrow(bytes, 5000)) == 0
    end
end

@testset "Control Key Combinations" begin
    # `set_keybinding` documents a `ctrl` keyword, but the decoder reported every control byte
    # with `ctrl = false` and the raw control character as its value, so a CTRL binding could
    # never match.
    named = Dict(
        0x04 => "<eot>",
        0x09 => "<tab>",
        0x0a => "<enter>",
        0x0d => "<enter>",
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
    # The bytes of the keystrokes are shown by `debug_keycode`, and their format must not
    # change.
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
    @test keytype(TerminalPager._DEFAULT_KEYBINDINGS) == keytype(TerminalPager._KEYBINDINGS)
end

@testset "Home and End Sequences" begin
    # The pager enables the application cursor key mode, in which xterm-compatible terminals
    # send SS3 sequences for Home and End. The Linux console, tmux, and rxvt use their own
    # CSI sequences. All of them used to decode to `<undefined>`.
    for (sequence, value) in (
        "\eOH" => "<home>",
        "\eOF" => "<end>",
        "\e[1~" => "<home>",
        "\e[4~" => "<end>",
        "\e[7~" => "<home>",
        "\e[8~" => "<end>",
        "\e[H" => "<home>",
        "\e[F" => "<end>",
    )
        bytes = collect(codeunits(sequence))
        status, key, consumed = TerminalPager._decode_keystroke(bytes)
        @test status === :complete
        @test key.value == value
        @test consumed == length(bytes)
        @test !key.alt && !key.ctrl && !key.shift
    end
end

@testset "Mouse Reports" begin
    # SGR mouse reports carry the button, the modifiers, and the position.
    for (sequence, value, x, y, alt, ctrl, shift) in (
        ("\e[<64;10;5M", "<wheel_up>", 10, 5, false, false, false),
        ("\e[<65;1;1M", "<wheel_down>", 1, 1, false, false, false),
        ("\e[<66;2;3M", "<wheel_left>", 2, 3, false, false, false),
        ("\e[<67;2;3M", "<wheel_right>", 2, 3, false, false, false),
        ("\e[<68;7;8M", "<wheel_up>", 7, 8, false, false, true),
        ("\e[<0;3;4M", "<mouse_press>", 3, 4, false, false, false),
        ("\e[<1;3;4M", "<mouse_press_middle>", 3, 4, false, false, false),
        ("\e[<2;3;4M", "<mouse_press_right>", 3, 4, false, false, false),
        ("\e[<0;3;4m", "<mouse_release>", 3, 4, false, false, false),
        ("\e[<32;3;4M", "<mouse_drag>", 3, 4, false, false, false),
        ("\e[<24;3;4M", "<mouse_press>", 3, 4, true, true, false),
        ("\e[<0;120;45M", "<mouse_press>", 120, 45, false, false, false),
    )
        bytes = collect(codeunits(sequence))
        status, key, consumed = TerminalPager._decode_keystroke(bytes)
        @test status === :complete
        @test key.value == value
        @test (key.x, key.y) == (x, y)
        @test (key.alt, key.ctrl, key.shift) == (alt, ctrl, shift)
        @test consumed == length(bytes)
    end

    # A report is incomplete until its final byte arrives, and a malformed one is undefined.
    for sequence in ("\e[<", "\e[<64", "\e[<64;10;5")
        status, _, consumed = TerminalPager._decode_keystroke(collect(codeunits(sequence)))
        @test status === :incomplete
        @test consumed == 0
    end

    for sequence in ("\e[<64;xM", "\e[<64M", "\e[<64;1;2;3M")
        bytes = collect(codeunits(sequence))
        status, key, consumed = TerminalPager._decode_keystroke(bytes)
        @test status === :complete
        @test key.value == "<undefined>"
        @test 4 <= consumed <= length(bytes)
    end

    # A report followed by a key is split correctly.
    input = TerminalPager.PagerInput(IOBuffer("\e[<64;10;5Mq"))
    @test TerminalPager._read_keystroke!(input).value == "<wheel_up>"
    @test TerminalPager._read_keystroke!(input).value == "q"

    # Keyboard keystrokes have no position.
    @test TerminalPager.Keystroke(; value = "q").x == 0
    @test TerminalPager._ascii_keystroke(UInt8('j')).y == 0
end
