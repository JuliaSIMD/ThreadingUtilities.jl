# To add support for loading/storing...
@inline function load(p::Ptr{UInt}, ::Type{T}) where {T<:Ptr}
    reinterpret(T, __vload(p, False(), register_size()))
end
@inline function load(p::Ptr{UInt32}, ::Type{T}) where {T<:Union{UInt32,Int32,Float32}}
    reinterpret(T, __vload(p, False(), register_size()))
end
@inline function load(p::Ptr{UInt64}, ::Type{T}) where {T<:Union{UInt64,Int64,Float64}}
    reinterpret(T, __vload(p, False(), register_size()))
end
@inline load(p::Ptr{UInt}, ::Type{T}) where {T} = unsafe_load(Base.unsafe_convert(Ptr{T}, p))
@inline function store!(p::Ptr{UInt}, x::T) where {T <: Ptr}
    __vstore!(p, reinterpret(UInt, x), False(), False(), False(), register_size())
end
@inline function store!(p::Ptr{UInt32}, x::T) where {T <: Union{UInt32,Int32,Float32}}
    __vstore!(p, reinterpret(UInt, x), False(), False(), False(), register_size())
end
@inline function store!(p::Ptr{UInt64}, x::T) where {T <: Union{UInt64,Int64,Float64}}
    __vstore!(p, reinterpret(UInt, x), False(), False(), False(), register_size())
end
@inline store!(p::Ptr{UInt}, x::T) where {T} = (unsafe_store!(Base.unsafe_convert(Ptr{T}, p), x); nothing)

@inline load(p::Ptr{UInt}, ::Type{StaticInt{N}}, i) where {N} = i, StaticInt{N}()
@inline store!(p::Ptr{UInt}, ::StaticInt, i) = i





@generated function load(p::Ptr{UInt}, ::Type{StridedPointer{T,N,C,B,R,X,O}}, i) where {T,N,C,B,R,X,O}
    q = quote
        $(Expr(:meta,:inline))
        i, ptr = load(p, Ptr{$T}, i)
    end
    xt = Expr(:tuple)
    Xp = X.parameters
    for n ∈ 1:N
        x = Symbol(:x_,n)
        push!(xt.args, x)
        push!(q.args, :((i, $x) = load(p, $(Xp[n]), i)))
    end
    ot = Expr(:tuple)
    Op = O.parameters
    for n ∈ 1:N
        o = Symbol(:o_,n)
        push!(ot.args, o)
        push!(q.args, :((i, $o) = load(p, $(Op[n]), i)))
    end
    push!(q.args, :((i, StridedPointer{$T,$N,$C,$B,$R}(ptr, $xt, $ot))))
    q
end
@generated function store!(p::Ptr{UInt}, ptr::StridedPointer{T,N,C,B,R,X,O}, i) where {T,N,C,B,R,X,O}
    q = quote
        $(Expr(:meta,:inline))
        i = store!(p, pointer(ptr), i)
        strd = strides(ptr)
        offs = offsets(ptr)
    end
    for n ∈ 1:N
        push!(q.args, :(i = store!(p, strd[$n], i)))
    end
    for n ∈ 1:N
        push!(q.args, :(i = store!(p, offs[$n], i)))
    end
    push!(q.args, :i)
    q
end

@inline function load(p::Ptr{UInt}, ::Type{T}, i) where {T}
    i + sizeof(T), load(p + i, T)
end
@inline function store!(p::Ptr{UInt}, x, i)
    store!(p + i, x)
    i + sizeof(x)
end

@generated function load(p::Ptr{UInt}, ::Type{T}, i) where {T<:Tuple}
    q = Expr(:block, Expr(:meta,:inline))
    tup = Expr(:tuple)
    for (i,t) ∈ enumerate(T.parameters)
        ln = Symbol(:l_,i)
        push!(tup.args, ln)
        push!(q.args, :((i,$ln) = load(p, $t, i)))
    end
    push!(q.args, :(i, $tup))
    q
end

@inline function store!(p::Ptr{UInt}, tup::Tuple{A,B,Vararg{Any,N}}, i) where {A,B,N}
    i = store!(p, first(tup), i)
    store!(p, Base.tail(tup), i)
end
@inline function store!(p::Ptr{UInt}, tup::Tuple{A}, i) where {A}
    store!(p, first(tup), i)
end
@inline store!(p::Ptr{UInt}, tup::Tuple{}, i) = i
@inline store!(p::Ptr{UInt}, tup::Nothing, i) = i

