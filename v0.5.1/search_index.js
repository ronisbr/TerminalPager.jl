var documenterSearchIndex = {"docs":
[{"location":"lib/library/#Library","page":"Library","title":"Library","text":"","category":"section"},{"location":"lib/library/","page":"Library","title":"Library","text":"Documentation for TerminalPager.jl.","category":"page"},{"location":"lib/library/","page":"Library","title":"Library","text":"Modules = [TerminalPager]","category":"page"},{"location":"lib/library/#TerminalPager.Keystroke","page":"Library","title":"TerminalPager.Keystroke","text":"struct Keystorke\n\nStructure that defines a keystroke.\n\nFields\n\nraw::String: Raw keystroke code converted to string.\nvalue::String: String representing the keystroke.\nalt::Bool: true if ALT key was pressed (only valid if value != :char).\nctrl::Bool: true if CTRL key was pressed (only valid if value != :char).\nshift::Bool: true if SHIFT key was pressed (only valid if value != :char).\n\n\n\n\n\n","category":"type"},{"location":"lib/library/#TerminalPager._help!-Tuple{TerminalPager.Pager}","page":"Library","title":"TerminalPager._help!","text":"_help!(pargerd::Pager) -> Nothing\n\nOpen a new pager with the help.\n\n\n\n\n\n","category":"method"},{"location":"lib/library/#TerminalPager._jlgetch-Tuple{IO}","page":"Library","title":"TerminalPager._jlgetch","text":"_jlgetch(stream::IO) -> Keystroke\n\nWait for an keystroke in the stream stream and return it (see Keystroke).\n\n\n\n\n\n","category":"method"},{"location":"lib/library/#TerminalPager.debug_keycode-Tuple{}","page":"Library","title":"TerminalPager.debug_keycode","text":"debug_keycode() -> Nothing\n\nDebug key codes.\n\n\n\n\n\n","category":"method"},{"location":"lib/library/#TerminalPager.delete_keybinding-Tuple{String}","page":"Library","title":"TerminalPager.delete_keybinding","text":"delete_keybinding(key::Union{Char, Symbol}; kwargs...) -> Nothing\n\nDelete the keybinding key. The modifiers keys can be selected using the keywords alt, ctrl, and shift.\n\nFor more information about how specify key see set_keybinding.\n\n\n\n\n\n","category":"method"},{"location":"lib/library/#TerminalPager.drop_all_preferences!-Tuple{}","page":"Library","title":"TerminalPager.drop_all_preferences!","text":"drop_all_preferences!()\n\nDrop all preferences.\n\nExamples\n\njulia> TerminalPager.drop_all_preference!()\n\n\n\n\n\n","category":"method"},{"location":"lib/library/#TerminalPager.drop_preference!-Tuple{String}","page":"Library","title":"TerminalPager.drop_preference!","text":"drop_preference!(pref::String, value) -> Nothing\n\nDrop the preference pref.\n\nExamples\n\njulia> TerminalPager.drop_preference!(\"visual_mode_line_background\")\n\n\n\n\n\n","category":"method"},{"location":"lib/library/#TerminalPager.pager-Tuple{Any}","page":"Library","title":"TerminalPager.pager","text":"pager(obj; kwargs...)\n\nCall the pager to show the output of the object obj.\n\nKeywords\n\ninfo: Info\nSome of the default values shown here can be modified by user-defined preferences.\n\nauto::Bool: If true, then the pager is only shown if the output does not fit into the   display. (Default = false)\nchange_freeze::Bool: If true, then the user can change the number of frozen rows and   columns inside the pager. (Default = true)\nfrozen_columns::Int = 0: Number of columns to be frozen at startup. (Default = 0)\nfrozen_rows::Int = 0: Number of rows to be frozen at startup. (Default = 0)\nhashelp::Bool = true: If true, then the user can see the pager help.   (Default = true)\nhas_visual_mode::Bool = true: If true, the user can use the visual mode.   (Default = true)\nshow_ruler::Bool: If true, a vertical ruler is shown at the pager with the line   numbers. (Default = false)\nuse_alternate_screen_buffer::Bool: If true, the pager will use the alternate screen   buffer, which keeps the current screen when exiting the pager. Notice, however, that we   use the XTerm escape sequences here. Hence, if your terminal is different, this option   can lead to rendering problems.\n\nPreferences\n\nThe user can defined custom preferences using the function TerminalPager.set_preference!. The available preferences are listed as follows:\n\n\"active_search_decoration\": String with the ANSI escape sequence to decorate the   active search element. One can easily obtain this sequence by converting a Crayon to   string. (Default = string(crayon\"black bg:yellow\"))\n\"inactive_search_decoration\": String with the ANSI escape sequence to decorate the   inactive search element. One can easily obtain this sequence by converting a Crayon to   string. (Default = string(crayon\"black bg:light_gray\"))\n\"always_use_alternate_screen_buffer_in_repl_mode\": If true, we will always use the   alternate screen buffer when showing the pager in REPL mode. (Default = false)\n\"block_alternate_screen_buffer\": If true, the alternate screen buffer support will be   globally blocked, regardless of the keyword options. This modification is helpful when   the terminal is not compatible with XTerm. (Default = false)\n\"pager_mode\": If it is \"vi\", some keywords are modified to match the behavior of Vi.   Notice that this change only takes effect when a new Julia session is initialized.   (Default = \"default\")\n\"visual_mode_line_background\": String with the ANSI code of the background for the   selected lines in the visual mode. (Default = \"100\")\n\"visual_mode_active_line_background\": String with the ANSI code of the background for   the active line in the visual mode. (Default = \"44\")\n\nFor more information, see: TerminalPager.set_preference!, TerminalPager.drop_preference!, and TerminalPager.drop_all_preferences!.\n\n\n\n\n\n","category":"method"},{"location":"lib/library/#TerminalPager.reset_keybindings-Tuple{}","page":"Library","title":"TerminalPager.reset_keybindings","text":"reset_keybindings() -> Nothing\n\nReset key bindings to the original ones.\n\n\n\n\n\n","category":"method"},{"location":"lib/library/#TerminalPager.set_keybinding-Tuple{String, Symbol}","page":"Library","title":"TerminalPager.set_keybinding","text":"set_keybinding(key::Union{Char, Symbol}, action::Symbol; kwargs...) -> Nothing\n\nSet key binding key to the action action. The modifiers keys can be selected using the keywords alt, ctrl, and shift.\n\nkey can be a Char or a Symbol indicating one of the following special keys:\n\n\"<up>\", \"<down>\", \"<right>\", \"<left>\", \"<home>\", \"<end>\", \"<F1>\", \"<F2>\",\n\"<F3>\", \"<F4>\", \"<F5>\", \"<F6>\", \"<F7>\", \"<F8>\", \"<F9>\", \"<F10>\", \"<F11>\",\n\"<F12>\", \"<keypad_dot>\", \"<keypad_enter>\", \"<keypad_asterisk>\",\n\"<keypad_plus>\", \"<keypad_minus>\", \"<keypad_slash>\", \"<keypad_equal>\",\n\"<keypad_0>\", \"<keypad_1>\", \"<keypad_2>\", \"<keypad_3>\", \"<keypad_4>\",\n\"<keypad_5>\", \"<keypad_6>\", \"<keypad_7>\", \"<keypad_8>\", \"<keypad_9>\",\n\"<delete>\", \"<pageup>\", \"<pagedown>\", \"<tab>\"\n\naction can be one of the following symbols:\n\n:quit, :help, :up, :down, :left, :right, :fastup, :fastdown, :fastleft,\n:fastright :bol, :eol, :pageup, :pagedown, :home, :end\n\n\n\n\n\n","category":"method"},{"location":"lib/library/#TerminalPager.set_preference!-Tuple{String, Any}","page":"Library","title":"TerminalPager.set_preference!","text":"set_preference!(pref::String, value) -> Nothing\n\nSet the preference pref to the value.\n\nExamples\n\njulia> TerminalPager.set_preference!(\"visual_mode_line_background\", \"44\")\n\n\n\n\n\n","category":"method"},{"location":"lib/library/#TerminalPager.@help-Tuple{Any}","page":"Library","title":"TerminalPager.@help","text":"@help(f)\n\nOpen the documentation of the function f in pager.\n\nExamples\n\njulia> @help write\n\n\n\n\n\n","category":"macro"},{"location":"lib/library/#TerminalPager.@stdout_to_pager-Tuple{Any}","page":"Library","title":"TerminalPager.@stdout_to_pager","text":"@stdout_to_pager(ex_in)\n\nCapture the stdout generated by ex_in and show inside a pager.\n\nnote: Note\nThe command must write to stdout explicitly. For example, @stdout_to_pager 1 shows a blank screen since 1 does not write to stdout, but returns 1. @stdout_to_pager show(1), on the other hand, shows the number 1 inside the pager.\n\nnote: Note\nThis macro can also be called using the shorter name @out2pr.\n\n\n\n\n\n","category":"macro"},{"location":"man/customization/#Customization","page":"Customization","title":"Customization","text":"","category":"section"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"The user can customize some preferences in TerminalPager.jl. We handle those customization using Preferences.jl. Thus, they persist between Julia sessions.","category":"page"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"To add a new value to a preference, use the function:","category":"page"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"TerminalPager.set_preference!(preference, value)","category":"page"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"To drop the customized value for the preference, use:","category":"page"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"TerminalPager.drop_preference!(preference)","category":"page"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"To drop all the customized values, use:","category":"page"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"TerminalPager.drop_all_preferences!()","category":"page"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"The list of available properties are:","category":"page"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"\"active_search_decoration\": String with the ANSI escape sequence to decorate the   active search element. One can easily obtain this sequence by converting a Crayon to   string. (Default = string(crayon\"black bg:yellow\"))\n\"inactive_search_decoration\": String with the ANSI escape sequence to decorate the   inactive search element. One can easily obtain this sequence by converting a Crayon to   string. (Default = string(crayon\"black bg:light_gray\"))\n\"always_use_alternate_screen_buffer_in_repl_mode\": If true, we will always use the   alternate screen buffer when showing the pager in REPL mode. (Default = false)\n\"block_alternate_screen_buffer\": If true, the alternate screen buffer support will be   globally blocked, regardless of the keyword options. This modification is helpful when   the terminal is not compatible with XTerm. (Default = false)\n\"pager_mode\": If it is \"vi\", some keywords are modified to match the behavior of Vi.   Notice that this change only takes effect when a new Julia session is initialized.   (Default = \"default\")\n\"visual_mode_line_background\": String with the ANSI code of the background for the   selected lines in the visual mode. (Default = \"100\")\n\"visual_mode_active_line_background\": String with the ANSI code of the background for   the active line in the visual mode. (Default = \"44\")","category":"page"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"For example, if the user wants to change the active search decoration to blue, they should do:","category":"page"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"julia> using TerminalPager.Crayons\n\njulia> TerminalPager.set_preference!(\"active_search_decoration\", string(crayon\"black bg:red\"))","category":"page"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"The default value can be restored by:","category":"page"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"julia> TerminalPager.drop_preference!(\"active_search_decoration\")","category":"page"},{"location":"man/customization/#Keybindings","page":"Customization","title":"Keybindings","text":"","category":"section"},{"location":"man/customization/","page":"Customization","title":"Customization","text":"The user can also change the default keybindings to perform actions inside the pager. For more information, see the functions: TerminalPager.set_keybinding, TerminalPager.delete_keybinding, and TerminalPager.reset_keybindings. Notice that those modifications do not persist between Julia sessions. Hence, if the user wants a permanent configuration, they should add those commands to the startup.jl script.","category":"page"},{"location":"man/usage/#Usage","page":"Usage","title":"Usage","text":"","category":"section"},{"location":"man/usage/#Getting-started","page":"Usage","title":"Getting started","text":"","category":"section"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"The pager is called using the function pager. If the input object is not a AbstractString, then it will be rendered using show with MIME\"text/plain\".  Thus, you can browse a large matrix, for example, using:","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"julia> rand(100,100) |> pager","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"It is also possible to use the pager to browse the documentation of a specific function:","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"julia> @doc(write) |> pager","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"All the functionalities can be seen in the built-in help system, accessible by typing ? inside the pager.","category":"page"},{"location":"man/usage/#Helpers","page":"Usage","title":"Helpers","text":"","category":"section"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"The following macros are available to help calling the pager.","category":"page"},{"location":"man/usage/#@help","page":"Usage","title":"@help","text":"","category":"section"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"This macro calls the help of any function and redirects it to the pager:","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"julia> @help write","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"(Image: )","category":"page"},{"location":"man/usage/#@stdout_to_pager","page":"Usage","title":"@stdout_to_pager","text":"","category":"section"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"This macro redirects all the stdout to the pager after the command is completed:","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"julia> @stdout_to_pager show(stdout, MIME\"text/plain\"(), rand(100,100))","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"(Image: )","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"This macro also works with blocks such as for loops:","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"julia> @stdout_to_pager for i = 1:100\n       println(\"$(mod(i,9))\"^i)\n       end","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"(Image: )","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"note: Note\nThis macro can also be called using the shorter name @out2pr.","category":"page"},{"location":"man/usage/#REPL-Modes","page":"Usage","title":"REPL Modes","text":"","category":"section"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"TerminalPager.jl comes with a REPL mode that automatically renders the command output to a pager if it does not fit the screen. To access this mode, just type | at the beginning of the REPL command line. If the mode is load correctly, the prompt julia> is changed to pager>.","category":"page"},{"location":"man/usage/","page":"Usage","title":"Usage","text":"In pager mode, you can also type ? at the beginning of the command line to access the pager help mode. In this case, the prompt is changed to pager?>. Any docstring accessed in this mode is rendered inside a pager. By the default, we use the alternate screen buffer, allowing to keep the screen content after exiting the pager.","category":"page"},{"location":"#TerminalPager.jl","page":"Introduction","title":"TerminalPager.jl","text":"","category":"section"},{"location":"","page":"Introduction","title":"Introduction","text":"CurrentModule = TerminalPager\nDocTestSetup = quote\n    using TerminalPager\nend","category":"page"},{"location":"","page":"Introduction","title":"Introduction","text":"This package contains a pager written 100% in Julia. It can be used to scroll through content that does not fit in the screen. It was developed based on the Linux command less.","category":"page"},{"location":"#Installation","page":"Introduction","title":"Installation","text":"","category":"section"},{"location":"","page":"Introduction","title":"Introduction","text":"julia> using Pkg\n\njulia> Pkg.add(\"TerminalPager\")","category":"page"},{"location":"#Automatically-Start-with-Julia","page":"Introduction","title":"Automatically Start with Julia","text":"","category":"section"},{"location":"","page":"Introduction","title":"Introduction","text":"If you want to automatically load TerminalPager.jl, add the following line to the file .julia/config/startup.jl after you have installed the package:","category":"page"},{"location":"","page":"Introduction","title":"Introduction","text":"using TerminalPager","category":"page"},{"location":"","page":"Introduction","title":"Introduction","text":"Another way is to compile the package directly into your Julia system image. For more information, see the documentation of the package PackageCompiler.jl.","category":"page"},{"location":"#Manual-outline","page":"Introduction","title":"Manual outline","text":"","category":"section"},{"location":"","page":"Introduction","title":"Introduction","text":"Pages = [\n    \"man/usage.md\"\n]\nDepth = 2","category":"page"}]
}
