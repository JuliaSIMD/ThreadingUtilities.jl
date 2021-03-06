struct ThreadTask
    p::Ptr{UInt}
end
Base.pointer(tt::ThreadTask) = tt.p

@inline taskpointer(tid) = THREADPOOLPTR[] + tid*(THREADBUFFERSIZE*sizeof(UInt))

function _call(p::Ptr{UInt})
    fptr = load(p + sizeof(UInt), Ptr{Cvoid})
    assume(fptr ≠ C_NULL)
    ccall(fptr, Cvoid, (Ptr{UInt},), p)
end

function (tt::ThreadTask)()
    p = pointer(tt)
    max_wait = 1 << 20
    wait_counter = max_wait
    GC.@preserve THREADPOOL begin
        while true
            if _atomic_cas_cmp!(p, TASK, LOCK)
                _call(p)
                _atomic_cas_cmp!(p, LOCK, SPIN)
                wait_counter = 0
                continue
            end
            pause()
            if (wait_counter += 1) > max_wait
                wait_counter = 0
                if _atomic_cas_cmp!(p, SPIN, WAIT)
                    wait()
                    _call(p)
                    _atomic_cas_cmp!(p, LOCK, SPIN)
                end
            end
        end
    end
end

# 1-based tid, pushes into task 2-nthreads()
function wake_thread!(tid)
    assume(length(Base.Workqueues) > tid)
    assume(length(TASKS) ≥ (tid))
    assume(isassigned(Base.Workqueues, tid+1))
    @inbounds workqueue = Base.Workqueues[tid+1]
    @inbounds task = TASKS[tid]
    push!(workqueue, task)
    ccall(:jl_wakeup_thread, Cvoid, (Int16,), tid % Int16)
end

# 1-based tid
@inline __wait(tid::Integer) = __wait(taskpointer(tid))
@inline function __wait(p::Ptr{UInt})
    # note: based on relative values (SPIN = 0, WAIT = 1)
    # thus it should spin for as long as the task is doing anything else
    while reinterpret(UInt, _atomic_load(p)) > reinterpret(UInt, WAIT)
        pause()
    end
end


# function launch_thread(f::F, tid) where {F}
#     cfunc = @cfunction($mapper, Cvoid, ());

#     fptr = Base.unsafe_convert(Ptr{Cvoid}, cfunc)

#     ccall(fptr, Cvoid, ())

# end
