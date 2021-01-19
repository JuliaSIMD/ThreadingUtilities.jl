# TODO: Is atomic volatile really necessary?
#       Early on my attempts weren't syncing / atomics
#       weren't behaving atomically between threads so
#       I got a bit defensive.
for (ityp,jtyp) ∈ [("i32", UInt32), ("i64", UInt64), ("i128", UInt128)]
    @eval begin
        @inline function _atomic_load(ptr::Ptr{$jtyp})
            Base.llvmcall($("""
              %p = inttoptr $(ityp) %0 to $(ityp)*
              %v = load atomic $(ityp), $(ityp)* %p acquire, align $(Base.gc_alignment(jtyp))
              ret $(ityp) %v
            """), $jtyp, Tuple{Ptr{$jtyp}}, ptr)
        end
        @inline function _atomic_store!(ptr::Ptr{$jtyp}, x::$jtyp)
            Base.llvmcall($("""
              %p = inttoptr $(ityp) %0 to $(ityp)*
              store atomic $(ityp) %1, $(ityp)* %p release, align $(Base.gc_alignment(jtyp))
              ret void
            """), Cvoid, Tuple{Ptr{$jtyp}, $jtyp}, ptr, x)
        end
        @inline function _atomic_cas_cmp!(ptr::Ptr{$jtyp}, cmp::$jtyp, newval::$jtyp)
            Base.llvmcall($("""
              %p = inttoptr $(ityp) %0 to $(ityp)*
              %c = cmpxchg $(ityp)* %p, $(ityp) %1, $(ityp) %2 acq_rel acquire
              %bit = extractvalue { $ityp, i1 } %c, 1
              %bool = zext i1 %bit to i8
              ret i8 %bool
            """), Bool, Tuple{Ptr{$jtyp}, $jtyp, $jtyp}, ptr, cmp, newval)
        end
    end
end
for op ∈ ["xchg", "add", "sub", "and", "nand", "or", "xor", "max", "min", "umax", "umin"] # "fadd", "fsub"
    f = Symbol("_atomic_", op, '!')
    for (ityp,jtyp) ∈ [("i32", UInt32), ("i64", UInt64), ("i128", UInt128)]
        @eval begin
            @inline function $f(ptr::Ptr{$jtyp}, x::$jtyp)
                Base.llvmcall($("""
                  %p = inttoptr $(ityp) %0 to $(ityp)*
                  %v = atomicrmw $op $(ityp)* %p, $(ityp) %1 acq_rel
                  ret $(ityp) %v
                """), $jtyp, Tuple{Ptr{$jtyp}, $jtyp}, ptr, x)
            end
        end
    end
    @eval begin
        @inline function $f(ptr::Ptr{UInt}, x::ThreadState)
            reinterpret(ThreadState, $f(ptr, reinterpret(UInt, x)))
        end
    end
end
@inline function _atomic_cas_cmp!(ptr::Ptr{UInt}, cmp::ThreadState, newval::ThreadState)
    _atomic_cas_cmp!(ptr, reinterpret(UInt, cmp), reinterpret(UInt, newval))
end


# To add support for loading/storing...
@inline function _atomic_load(p::Ptr{UInt}, ::Type{T}) where {T}
    reinterpret(T, _atomic_load(p))
end
@inline function _atomic_store!(p::Ptr{UInt}, x)
    _atomic_store!(p, reinterpret(UInt, x))
end

@inline function _atomic_load(p::Ptr{UInt}, ::Type{StaticInt{N}}, i) where {N}    i, StaticInt{N}()
end
@inline _atomic_store!(p::Ptr{UInt}, ::StaticInt, i) = i


@generated function _atomic_load(p::Ptr{UInt}, ::Type{StridedPointer{T,N,C,B,R,X,O}}, i) where {T,N,C,B,R,X,O}
    q = quote
        $(Expr(:meta,:inline))
        i, ptr = _atomic_load(p, Ptr{$T}, i)
    end
    xt = Expr(:tuple)
    Xp = X.parameters
    for n ∈ 1:N
        x = Symbol(:x_,n)
        push!(xt.args, x)
        push!(q.args, :((i, $x) = _atomic_load(p, $(Xp[n]), i)))
    end
    ot = Expr(:tuple)
    Op = O.parameters
    for n ∈ 1:N
        o = Symbol(:o_,n)
        push!(ot.args, o)
        push!(q.args, :((i, $o) = _atomic_load(p, $(Op[n]), i)))
    end
    push!(q.args, :((i, StridedPointer{$T,$N,$C,$B,$R}(ptr, $xt, $ot))))
    q
end
@generated function _atomic_store!(p::Ptr{UInt}, ptr::StridedPointer{T,N,C,B,R,X,O}, i) where {T,N,C,B,R,X,O}
    q = quote
        $(Expr(:meta,:inline))
        i = _atomic_store!(p, pointer(ptr), i)
        strd = strides(ptr)
        offs = offsets(ptr)
    end
    for n ∈ 1:N
        push!(q.args, :(i = _atomic_store!(p, strd[$n], i)))
    end
    for n ∈ 1:N
        push!(q.args, :(i = _atomic_store!(p, offs[$n], i)))
    end
    push!(q.args, :i)
    q
end

@inline function _atomic_load(p::Ptr{UInt}, ::Type{T}, i) where {T}
    i += 1
    i, _atomic_load(p + i * sizeof(UInt), T)
end
@inline function _atomic_store!(p::Ptr{UInt}, x, i)
    _atomic_store!(p + sizeof(UInt)*(i += 1), x)
    i
end

@generated function _atomic_load(p::Ptr{UInt}, ::Type{T}, i) where {T<:Tuple}
    q = Expr(:block, Expr(:meta,:inline))
    tup = Expr(:tuple)
    for (i,t) ∈ enumerate(T.parameters)
        ln = Symbol(:l_,i)
        push!(tup.args, ln)
        push!(q.args, :((i,$ln) = _atomic_load(p, $t, i)))
    end
    push!(q.args, :(i, $tup))
    q
end

@inline function _atomic_store!(p::Ptr{UInt}, tup::Tuple{A,B,Vararg{Any,N}}, i) where {A,B,N}
    i = _atomic_store!(p, first(tup), i)
    _atomic_store!(p, Base.tail(tup), i)
end
@inline function _atomic_store!(p::Ptr{UInt}, tup::Tuple{A}, i) where {A}
    _atomic_store!(p, first(tup), i)
end
@inline _atomic_store!(p::Ptr{UInt}, tup::Tuple{}, i) = i
