using StaticArrays, ThreadingUtilities
struct MulStaticArray{P} end
function (::MulStaticArray{P})(p::Ptr{UInt}) where {P}
    _, (ptry,ptrx) = ThreadingUtilities.load(p, P, 2*sizeof(UInt))
    unsafe_store!(ptry, unsafe_load(ptrx) * 2.7)
    nothing
end
@generated function mul_staticarray_ptr(::A, ::B) where {A,B}
    c = MulStaticArray{Tuple{A,B}}()
    :(@cfunction($c, Cvoid, (Ptr{UInt},)))
end

function setup_mul_svector!(p, y::Base.RefValue{SVector{N,T}}, x::Base.RefValue{SVector{N,T}}) where {N,T}
    py = Base.unsafe_convert(Ptr{SVector{N,T}}, y)
    px = Base.unsafe_convert(Ptr{SVector{N,T}}, x)
    fptr = mul_staticarray_ptr(py, px)
    offset = ThreadingUtilities.store!(p, fptr, sizeof(UInt))
    ThreadingUtilities.store!(p, (py,px), offset)
end

@inline function launch_thread_mul_svector_v1!(tid, y, x)
    p = ThreadingUtilities.taskpointer(tid)
    setup_mul_svector!(p, y, x)
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
@inline function launch_thread_mul_svector_v2!(tid, y, x)
    p = ThreadingUtilities.taskpointer(tid)
    setup_mul_svector!(p, y, x)
    # state = reinterpret(ThreadingUtilities.ThreadState, unsafe_load(p))
    if ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.SPIN, ThreadingUtilities.TASK)
        nothing
    else
        ThreadingUtilities._atomic_cas_cmp!(p, ThreadingUtilities.WAIT, ThreadingUtilities.LOCK)
        ThreadingUtilities.wake_thread!(tid % UInt)
    end
end

function mul_svector_threads(f!::F, a::SVector{N,T}, b::SVector{N,T}, c::SVector{N,T}) where {F,N,T}
    ra = Ref(a)
    rb = Ref(b)
    rc = Ref(c)
    rx = Ref{SVector{N,T}}()
    ry = Ref{SVector{N,T}}()
    rz = Ref{SVector{N,T}}()
    GC.@preserve ra rb rc rx ry rz begin
        f!(1, rx, ra)
        f!(2, ry, rb)
        f!(3, rz, rc)
        w = muladd.(2.7, a, b)
        ThreadingUtilities.__wait(1)
        ThreadingUtilities.__wait(2)
        ThreadingUtilities.__wait(3)
    end
    rx[],ry[],rz[],w
end
mul_svector_threads_v1(a, b, c) = mul_svector_threads(launch_thread_mul_svector_v1!, a, b, c)
mul_svector_threads_v2(a, b, c) = mul_svector_threads(launch_thread_mul_svector_v2!, a, b, c)

@testset "SVector Test" begin
    a = @SVector rand(16);
    b = @SVector rand(16);
    c = @SVector rand(16);
    w1,x1,y1,z1 = mul_svector_threads_v1(a, b, c)
    w2,x2,y2,z2 = mul_svector_threads_v2(a, b, c)
    @test iszero(@allocated mul_svector_threads_v1(a, b, c))
    @test iszero(@allocated mul_svector_threads_v2(a, b, c))
    @test w1 == w2 == a*2.7
    @test x1 == x2 == b*2.7
    @test y1 == y2 == c*2.7
    @test z1 ≈ z2 ≈ muladd(2.7, a, b)
end

