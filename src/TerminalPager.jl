module TerminalPager

using Printf
using REPL

using Crayons

const CSI = "\x1b["
const PKG_VERSION = v"0.0.1"

include("./command_line.jl")
include("./keybindings.jl")
include("./input.jl")
include("./misc.jl")
include("./pager.jl")
include("./screen.jl")
include("./string.jl")
include("./view.jl")

export pager

function pager(obj::Any)
    str = sprint(show, MIME"text/plain"(), obj, context = :color => true)
    return pager(str)
end

pager(obj::AbstractString) = return _pager(obj)

const less = pager

end # module