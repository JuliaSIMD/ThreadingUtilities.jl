module ThreadingUtilities

using VectorizationBase:
    pause, StaticInt, StridedPointer, stridedpointer, offsets, cache_linesize, align, __vload, __vstore!, num_threads, assume, False, register_size, NativeTypes

@enum ThreadState::UInt begin
    SPIN = 0   # 0: spinning
    WAIT = 1   # 1: waiting, check if ≤ 1 to see if task is free and waiting
    TASK = 2   # 2: task available
    LOCK = 3   # 3: lock
    STUP = 4   # 4: problem being setup. Any reason to have two lock flags?
end
const TASKS = Task[]
const THREADBUFFERSIZE = 64
const THREADPOOL = UInt[]
const THREADPOOLPTR =  Ref{Ptr{UInt}}(C_NULL);

include("atomics.jl")
include("threadtasks.jl")
include("utils.jl")
include("warnings.jl")

function initialize_task(tid::Int)
    t = Task(ThreadTask(taskpointer(tid)));
    t.sticky = true # create and pin
    # set to tid, we have tasks 2...nthread, from 1-based ind perspective
    ccall(:jl_set_task_tid, Cvoid, (Any, Cint), t, tid % Cint)
    TASKS[tid] = t
    wake_thread!(tid) # task should immediately sleep
end
function reinitialize_tasks!(verbose::Bool = true)
    for (tid,t) ∈ enumerate(TASKS)
        if istaskfailed(t)
            verbose && dump(t)
            _atomic_store!(taskpointer(tid), reinterpret(UInt, SPIN))
            initialize_task(tid)
        end
    end
end

function __init__()
    _print_exclusivity_warning()
    nt = min(Threads.nthreads(),(Sys.CPU_THREADS)::Int) - 1
    resize!(THREADPOOL, THREADBUFFERSIZE * nt + (cache_linesize() ÷ sizeof(UInt)) - 1)
    THREADPOOL .= 0
    Threads.atomic_fence() # ensure 0-initialization
    resize!(TASKS, nt)
    GC.@preserve THREADPOOL begin
        THREADPOOLPTR[] = align(pointer(THREADPOOL)) - THREADBUFFERSIZE*sizeof(UInt)
        foreach(initialize_task, 1:nt)
        for tid ∈ 1:nt
            # wait for it to sleep, to be sure
            while _atomic_load(taskpointer(tid)) ≠ reinterpret(UInt, WAIT)
                pause()
            end
        end
    end
end

end # module
