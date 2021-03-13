struct ThreadTask
    p::Ptr{UInt}
end
Base.pointer(tt::ThreadTask) = tt.p

@inline taskpointer(tid) = THREADPOOLPTR[] + tid*THREADBUFFERSIZE

function _call(p::Ptr{UInt})
    fptr = load(p + sizeof(UInt), Ptr{Cvoid})
    assume(fptr ≠ C_NULL)
    ccall(fptr, Cvoid, (Ptr{UInt},), p)
end
@inline function launch(f::F, tid::Integer, args::Vararg{Any,K}) where {F,K}
    p = taskpointer(tid)
    f(p, args...)
    state = _atomic_xchg!(p, TASK)
    state == WAIT && wake_thread!(tid % Int)
    return nothing
end

function (tt::ThreadTask)()
    p = pointer(tt)
    max_wait = one(UInt32) << 20
    wait_counter = max_wait
    GC.@preserve THREADPOOL begin
        while true
            if _atomic_state(p) == TASK
                _call(p)
                _atomic_store!(p, SPIN)
                wait_counter = zero(UInt32)
                continue
            end
            pause()
            if (wait_counter += one(UInt32)) > max_wait
                wait_counter = zero(UInt32)
                if _atomic_cas_cmp!(p, SPIN, WAIT)
                    Base.wait()
                    _call(p)
                    _atomic_cas_cmp!(p, TASK, SPIN)
                end
            end
        end
    end
end

# 1-based tid, pushes into task 2-nthreads()
# function wake_thread!(tid::T) where {T <: Unsigned}
function wake_thread!(tid::T) where {T <: Integer}
    tidp1 = tid + one(tid)
    assume(unsigned(length(Base.Workqueues)) > unsigned(tid))
    assume(unsigned(length(TASKS)) > unsigned(tidp1))
    @inbounds push!(Base.Workqueues[tidp1], TASKS[tid])
    ccall(:jl_wakeup_thread, Cvoid, (Int16,), tid % Int16)
end

# 1-based tid
@inline wait(tid::Integer) = wait(taskpointer(tid))
@inline function wait(p::Ptr{UInt})
    # note: based on relative values (SPIN = 0, WAIT = 1)
    # thus it should spin for as long as the task is doing anything else
    # while @show(stacktrace(), reinterpret(UInt, _atomic_load(p))) > reinterpret(UInt, WAIT)
    while _atomic_load(p) > reinterpret(UInt, WAIT)
    # while reinterpret(UInt, @show(_atomic_load(p))) > reinterpret(UInt, WAIT)
        pause()
    end
end


# function launch_thread(f::F, tid) where {F}
#     cfunc = @cfunction($mapper, Cvoid, ());

#     fptr = Base.unsafe_convert(Ptr{Cvoid}, cfunc)

#     ccall(fptr, Cvoid, ())

# end
