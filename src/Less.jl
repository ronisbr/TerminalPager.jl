module Less

using REPL

using Crayons

const CSI = "\x1b["
const LESS_VERSION = v"0.0.1"

include("./misc.jl")
include("./input.jl")
include("./screen.jl")
include("./string.jl")
include("./viewer.jl")

function viewer(obj::Any)
    str = sprint(show, MIME"text/plain"(), obj, context = :color => true)
    return viewer(str)
end

viewer(obj::AbstractString) = return _viewer(obj)

end # module
