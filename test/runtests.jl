include("testsetup.jl")

include("test-suite-preamble.jl")

include("internals.jl")
include("threadingutilities.jl")
if !parse(Bool, get(ENV, "GITHUB_ACTIONS", "false"))
    include("staticarrays.jl")
end
include("threadpool.jl")
include("warnings.jl")

include("aqua.jl") # run the Aqua.jl tests last
