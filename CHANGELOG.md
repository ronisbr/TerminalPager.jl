TerminalPager.jl
================

Version 0.1.0
-------------

- [Bugfix][badge-bugfix] The number of cropped lines is now correctly computed.
  (Issue [#3][gh-issue-3])
- [Feature][badge-feature] The current position of the view is shown in the
  command line.
- [Feature][badge-feature] The key bindings can now be customized. (Issue
  [#2][gh-issue-2])
- [Feature][badge-feature] The pager now supports searching strings.
- [Feature][badge-feature] The pager can now freeze lines and columns. (Issue
  [#1][gh-issue-1])
- [Feature][badge-feature] The pager now supports features, which are a set of
  actions that can be disable when calling it. For example, the pager is used to
  show the help screen. However, in this case, we remove the `help` feature to
  avoid showing another help screen.
- [Enhancement][badge-enhacement] A new rendering algorithm for better
  performance.
- [Enhancement][badge-enhacement] The new rendering algorithm does not add new
  lines when clearing the screen, but overwrite the current ones. (Issue
  [#4][gh-issue-4])
- [Enhancement][badge-enhacement] The help screen now shows all the important
  information.
- [Enhancement][badge-enhacement] A lot of type instabilities were fixed,
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
