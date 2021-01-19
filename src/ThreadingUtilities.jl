module ThreadingUtilities

using VectorizationBase:
    pause, StaticInt, StridedPointer, offsets

@enum ThreadState::UInt begin
    SPIN = 0   # 0: spinning
    WAIT = 1   # 1: waiting, check if ≤ 1 to see if task is free and waiting
    TASK = 2   # 2: task available
    LOCK = 3   # 3: lock
    STUP = 4   # 4: problem being setup. Any reason to have two lock flags?
end
const TASKS = Task[]

include("atomics.jl")
include("threadtasks.jl")

function __init__()
    @eval const THREADPOOL = ntuple(_ -> ThreadTask(), Val(Sys.CPU_THREADS-1))
    nt = min(Threads.nthreads()-1, (Sys.CPU_THREADS)::Int - 1)
    resize!(TASKS, nt)
    for tid ∈ 1:nt
        m = THREADPOOL[tid]
        GC.@preserve m _atomic_min!(pointer(m), SPIN) # set to SPIN
        t = Task(m); t.sticky = true # create and pin
        # set to tid, we have tasks 2...nthread, from 1-based ind perspective
        ccall(:jl_set_task_tid, Cvoid, (Any, Cint), t, tid % Cint)
        TASKS[tid] = t
        wake_thread!(tid) # task should immediately sleep
        # wait for it to sleep, to be sure
        counter = 0
        while true
            @assert (counter += 1) < 1_000_000_000
            _atomic_cas_cmp!(pointer(m), WAIT, WAIT) && break
            pause()
        end
    end
end

end # module
