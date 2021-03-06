using StaticArrays, ThreadingUtilities
struct Copy{P} end
function (::Copy{P})(p::Ptr{UInt}) where {P}
    _, (ptry,ptrx) = ThreadingUtilities.load(p, P, 2*sizeof(UInt))
    unsafe_store!(ptry, unsafe_load(ptrx) * 2.7)
    nothing
    # @simd ivdep for n ∈ 1:N
    #     store!(ptry, vload(ptrx, (n,)), (n,))
    # end
end
@generated function copy_ptr(::A, ::B) where {A,B}
    c = Copy{Tuple{A,B}}()
    quote
        @cfunction($c, Cvoid, (Ptr{UInt},))
    end
end

function setup_copy!(p, y::Base.RefValue{SVector{N,T}}, x::Base.RefValue{SVector{N,T}}) where {N,T}
    # py = stridedpointer(y)
    # px = stridedpointer(x)
    py = Base.unsafe_convert(Ptr{SVector{N,T}}, y)
    px = Base.unsafe_convert(Ptr{SVector{N,T}}, x)
    fptr = copy_ptr(py, px)
    offset = ThreadingUtilities.store!(p, fptr, sizeof(UInt))
    ThreadingUtilities.store!(p, (py,px), offset)
end

@inline function launch_thread_copy!(tid, y, x)
    p = ThreadingUtilities.taskpointer(tid)
    setup_copy!(p, y, x)
    while true
        if ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.SPIN, ThreadingUtilities.TASK)
            break
        elseif ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.WAIT, ThreadingUtilities.LOCK)
            ThreadingUtilities.wake_thread!(tid % UInt)
            break
        end
        ThreadingUtilities.pause()
    end
end
# @inline function launch_thread_copy_fast!(tid, y, x)
@inline function launch_thread_copy!(tid, y, x)
    p = ThreadingUtilities.taskpointer(tid)
    setup_copy!(p, y, x)
    state = reinterpret(ThreadingUtilities.ThreadState, unsafe_load(p))
    if ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.SPIN, ThreadingUtilities.TASK)
        nothing
    else
        ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.WAIT, ThreadingUtilities.LOCK)
        ThreadingUtilities.wake_thread!(tid % UInt)
    end
end

function test_copy(a::SVector{N,T}, b::SVector{N,T}, c::SVector{N,T}) where {N,T}
    ra = Ref(a)
    rb = Ref(b)
    rc = Ref(c)
    rx = Ref{SVector{N,T}}()
    ry = Ref{SVector{N,T}}()
    rz = Ref{SVector{N,T}}()
    GC.@preserve ra rb rc rx ry rz begin
        launch_thread_copy!(1, rx, ra)
        launch_thread_copy!(2, ry, rb)
        launch_thread_copy!(3, rz, rc)
        w = muladd.(2.7, a, b)
        ThreadingUtilities.__wait(1)
        ThreadingUtilities.__wait(2)
        ThreadingUtilities.__wait(3)
    end
    rx[],ry[],rz[],w
end


a = @SVector rand(16);
b = @SVector rand(16);
c = @SVector rand(16);
test_copy(a,b,c)

ra = Ref(a); rb = Ref(b); rc = Ref(c);
@code_llvm launch_thread_copy!(1, ra, rb)

const TIMES = zeros(8);
function test_copy_timed(a::SVector{N,T}, b::SVector{N,T}, c::SVector{N,T}) where {N,T}
    tbase = time_ns()
    ra = Ref(a)
    rb = Ref(b)
    rc = Ref(c)
    rx = Ref{SVector{N,T}}()
    ry = Ref{SVector{N,T}}()
    rz = Ref{SVector{N,T}}()
    t0 = time_ns();
    GC.@preserve ra rb rc rx ry rz begin
        launch_thread_copy!(1, rx, ra)
        t1 = time_ns();
        launch_thread_copy!(2, ry, rb)
        t2 = time_ns();
        launch_thread_copy!(3, rz, rc)
        t3 = time_ns();
        ThreadingUtilities.__wait(1)
        t4 = time_ns();
        ThreadingUtilities.__wait(2)
        t5 = time_ns();
        ThreadingUtilities.__wait(3)
        t6 = time_ns();
    end
    @inbounds begin
        TIMES[1] += 1.0
        TIMES[2] += t0 - tbase
        TIMES[3] += t1 - t0
        TIMES[4] += t2 - t1
        TIMES[5] += t3 - t2
        TIMES[6] += t4 - t3
        TIMES[7] += t5 - t4
        TIMES[8] += t6 - t5
    end
    rx[],ry[],rz[]
end

@benchmark test_copy_timed($a,$b,$c) setup=(fill!(TIMES,0.0))
(TIMES ./ first(TIMES))'



# @testset "ThreadingUtilities.jl" begin
#     @test all(i -> isone(unsafe_load(ThreadingUtilities.taskpointer(i))), eachindex(ThreadingUtilities.TASKS))
#     @test all(eachindex(ThreadingUtilities.TASKS)) do tid
#         ThreadingUtilities.load(ThreadingUtilities.taskpointer(tid), ThreadingUtilities.ThreadState) === ThreadingUtilities.WAIT
#     end
#     @test all(eachindex(ThreadingUtilities.TASKS)) do tid
#         ThreadingUtilities._atomic_load(ThreadingUtilities.taskpointer(tid)) === reinterpret(UInt, ThreadingUtilities.WAIT)
#     end
#     foreach(test_copy, eachindex(ThreadingUtilities.TASKS))

#     x = rand(UInt, 3);
#     GC.@preserve x begin
#         ThreadingUtilities._atomic_store!(pointer(x), zero(UInt))
#         @test ThreadingUtilities._atomic_xchg!(pointer(x), ThreadingUtilities.WAIT) == ThreadingUtilities.SPIN
#         @test ThreadingUtilities._atomic_umax!(pointer(x), ThreadingUtilities.STUP) == ThreadingUtilities.WAIT
#         @test ThreadingUtilities.load(pointer(x), ThreadingUtilities.ThreadState) == ThreadingUtilities.STUP
#     end

#     for tid ∈ eachindex(ThreadingUtilities.TASKS)
#         launch_thread_copy!(tid, Float64[], Float64[])
#     end
#     yield()
#     @test all(istaskfailed, ThreadingUtilities.TASKS)
#     ThreadingUtilities.reinitialize_tasks!(false)
#     @test !any(istaskfailed, ThreadingUtilities.TASKS)
#     # test copy on the reinitialized tasks
#     foreach(test_copy, eachindex(ThreadingUtilities.TASKS))
# end
