# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Description
# ==============================================================================
#
#   Deprecated functions.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

#                       Introduced in TerminalPager v0.1
# ==============================================================================

export @dpr
macro dpr(expr)
    Base.depwarn("@dpr is deprecated, use @help instead.", :dpr)
    return :(@help $(esc(expr)))
end
