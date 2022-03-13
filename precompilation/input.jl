# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Descriptions
# ==============================================================================
#
#   Function calls to create the precompilation statements using SnoopCompiler.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function precompilation_input()
    include("../test/runtests.jl")
    rand(100, 100) |> pager
end
