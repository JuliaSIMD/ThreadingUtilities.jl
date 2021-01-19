struct ThreadTask
    memory::Base.RefValue{NTuple{32,UInt}}
    ThreadTask() = new(Base.RefValue{NTuple{32,UInt}}())
end
Base.pointer(tt::ThreadTask) = Base.unsafe_convert(Ptr{UInt}, pointer_from_objref(tt.memory))

Base.@propagate_inbounds taskpointer(tid) = pointer(THREADPOOL[tid])

function _call(p::Ptr{UInt})
    fptr = _atomic_load(p + sizeof(UInt), Ptr{Cvoid})
    ccall(fptr, Cvoid, (Ptr{UInt},), p)
end

function (tt::ThreadTask)()
    p = pointer(tt)
    @assert unsafe_load(p) === reinterpret(UInt, SPIN)
    memory = tt.memory
    max_wait = 1 << 20
    wait_counter = max_wait
    GC.@preserve memory begin
        while true
            if _atomic_cas_cmp!(p, TASK, LOCK)
                _call(p)
                @assert _atomic_cas_cmp!(p, LOCK, SPIN)
                wait_counter = 0
                continue
            end
            pause()
            if (wait_counter += 1) > max_wait
                wait_counter = 0
                if _atomic_cas_cmp!(p, SPIN, WAIT)
                    wait()
                    _call(p)
                    @assert _atomic_cas_cmp!(p, LOCK, SPIN)
                end
            end
        end
    end
end

# 1-based tid, pushes into task 2-nthreads()
Base.@propagate_inbounds function wake_thread!(tid)
    push!(Base.Workqueues[tid+1], TASKS[tid]);
    # push!(@inbounds(Base.Workqueues[tid+1]), MULTASKS[tid]);
    ccall(:jl_wakeup_thread, Cvoid, (Int16,), tid % Int16)
end

# 1-based tid
Base.@propagate_inbounds function __wait(tid::Int)
    p = taskpointer(tid)
    # note: based on relative values (SPIN = 0, WAIT = 1)
    # thus it should spin for as long as the task is doing anything else
    counter = 0
    while reinterpret(UInt, _atomic_max!(p, SPIN)) > reinterpret(UInt, WAIT)
        pause()
        @boundscheck @assert (counter += 1) < 1_000_000_000
    end
end


# function launch_thread(f::F, tid) where {F}
#     cfunc = @cfunction($mapper, Cvoid, ());

#     fptr = Base.unsafe_convert(Ptr{Cvoid}, cfunc)

#     ccall(fptr, Cvoid, ())

# end
