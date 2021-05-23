TerminalPager.jl
================

Version 0.2.1
-------------

- ![Deprecation][badge-deprecation] The macro `@dpr` is now deprecated. It was
  replaced by `@help`.
- ![Enhancement][badge-enhancement] The macro `@stdout_to_pager` can now be
  called using the shorter name `@out2pr`.

Version 0.2.0
-------------

- ![Feature][badge-feature] The macro `@stdout_to_pager` can be used to redirect
  the `stdout` output to the `pager`. (Issue [#13][gh-issue-13])
- ![Feature][badge-feature] The macro `@dpr` can be to easily access the
  documentation of a function using `pager`. (Issue [#14][gh-issue-14])
- ![Feature][badge-feature] A vertical ruler can now be drawn using the
  keybinding `r`.
- ![Enhancement][badge-enhancement] `space` is now bind to `:pagedown` as in
  `less`.

Version 0.1.1
-------------

- ![Bugfix][badge-bugfix] When selecting the new number of columns and rows that
  will be frozen, hitting just enter uses the old value instead of crashing.
  (Issue [#9][gh-issue-9])
- ![Bugfix][badge-bugfix] Avoid a crash when searching something without matches
  after a search with matches. (Issue [#12][gh-issue-12])
- ![Feature][badge-feature] The function `TerminalPager.debug_keycode()` was
  added to help debugging key codes.
- ![Feature][badge-feature] The navigation can now be performed using a set of
  Vi key bindings. However, due to some conflicts, the entire navigation set
  based on Vi key bindings requires the environment key `PAGER_MODE=vi`. (Issue
  [#7][gh-issue-7])
- ![Enhancement][badge-enhancement] `ALT` is now treated like `Meta`, trying to
  equalize the experience among different operation systems. (Issue
  [#8][gh-issue-8])
- ![Enhancement][badge-enhancement] If there is no match, the command line now
  shows `(no match found)` instead of `(0 of 0 matches)`.
- ![Enhancement][badge-enhancement] `ALT up` and `ALT down` now goes to the
  beginning and end of the text to keep consistency of `ALT` modifier. (Issue
  [#8][gh-issue-8])

Version 0.1.0
-------------

- ![Bugfix][badge-bugfix] The number of cropped lines is now correctly computed.
  (Issue [#3][gh-issue-3])
- ![Feature][badge-feature] The current position of the view is shown in the
  command line.
- ![Feature][badge-feature] The key bindings can now be customized. (Issue
  [#2][gh-issue-2])
- ![Feature][badge-feature] The pager now supports searching strings.
- ![Feature][badge-feature] The pager can now freeze lines and columns. (Issue
  [#1][gh-issue-1])
- ![Feature][badge-feature] The pager now supports features, which are a set of
  actions that can be disable when calling it. For example, the pager is used to
  show the help screen. However, in this case, we remove the `help` feature to
  avoid showing another help screen.
- ![Enhancement][badge-enhancement] A new rendering algorithm for better
  performance.
- ![Enhancement][badge-enhancement] The new rendering algorithm does not add new
  lines when clearing the screen, but overwrite the current ones. (Issue
  [#4][gh-issue-4])
- ![Enhancement][badge-enhancement] The help screen now shows all the important
  information.
- ![Enhancement][badge-enhancement] A lot of type instabilities were fixed,
  leading to a much better initialization time.

Version 0.0.1
-------------

- Initial version.

[badge-breaking]: https://img.shields.io/badge/BREAKING-red.svg
[badge-deprecation]: https://img.shields.io/badge/Deprecation-orange.svg
[badge-feature]: https://img.shields.io/badge/Feature-green.svg
[badge-enhancement]: https://img.shields.io/badge/Enhancement-blue.svg
[badge-bugfix]: https://img.shields.io/badge/Bugfix-purple.svg
[badge-info]: https://img.shields.io/badge/Info-gray.svg

[gh-issue-1]: https://github.com/ronisbr/PrettyTables.jl/issues/1
[gh-issue-2]: https://github.com/ronisbr/PrettyTables.jl/issues/2
[gh-issue-3]: https://github.com/ronisbr/PrettyTables.jl/issues/3
[gh-issue-4]: https://github.com/ronisbr/PrettyTables.jl/issues/4
[gh-issue-7]: https://github.com/ronisbr/PrettyTables.jl/issues/7
[gh-issue-8]: https://github.com/ronisbr/PrettyTables.jl/issues/8
[gh-issue-9]: https://github.com/ronisbr/PrettyTables.jl/issues/9
[gh-issue-12]: https://github.com/ronisbr/PrettyTables.jl/issues/12
[gh-issue-13]: https://github.com/ronisbr/PrettyTables.jl/issues/13
[gh-issue-14]: https://github.com/ronisbr/PrettyTables.jl/issues/14
