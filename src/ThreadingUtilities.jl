module ThreadingUtilities

using VectorizationBase:
    pause, StaticInt, StridedPointer, offsets, L₁CACHE, align

@enum ThreadState::UInt begin
    SPIN = 0   # 0: spinning
    WAIT = 1   # 1: waiting, check if ≤ 1 to see if task is free and waiting
    TASK = 2   # 2: task available
    LOCK = 3   # 3: lock
    STUP = 4   # 4: problem being setup. Any reason to have two lock flags?
end
const TASKS = Task[]
const THREADBUFFERSIZE = 32
const THREADPOOL = UInt[]
const THREADPOOLPTR =  Ref{Ptr{UInt}}(C_NULL);

include("atomics.jl")
include("threadtasks.jl")

function __init__()
    nt = min(Threads.nthreads(),(Sys.CPU_THREADS)::Int) - 1
    resize!(THREADPOOL, THREADBUFFERSIZE * nt + (something(L₁CACHE.linesize,64) ÷ sizeof(UInt)) - 1)
    THREADPOOL .= 0
    Threads.atomic_fence() # ensure 0-initialization
    resize!(TASKS, nt)
    GC.@preserve THREADPOOL begin
        THREADPOOLPTR[] = align(pointer(THREADPOOL)) - THREADBUFFERSIZE*sizeof(UInt)
        for tid ∈ 1:nt
            t = Task(ThreadTask(taskpointer(tid))); t.sticky = true # create and pin
            # set to tid, we have tasks 2...nthread, from 1-based ind perspective
            ccall(:jl_set_task_tid, Cvoid, (Any, Cint), t, tid % Cint)
            TASKS[tid] = t
            wake_thread!(tid) # task should immediately sleep
        end
        for tid ∈ 1:nt
            # wait for it to sleep, to be sure
            while !_atomic_cas_cmp!(taskpointer(tid), WAIT, WAIT)
                pause()
            end
        end
    end
end

end # module
