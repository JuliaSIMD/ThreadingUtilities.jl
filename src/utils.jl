@generated function load(p::Ptr{T}) where {T}
  if Base.allocatedinline(T)
    Expr(:block, Expr(:meta,:inline), :(unsafe_load(p)))
  else
    Expr(:block, Expr(:meta,:inline), :(ccall(:jl_value_ptr, Ref{$T}, (Ptr{Cvoid},), unsafe_load(Base.unsafe_convert(Ptr{Ptr{Cvoid}}, p)))))
  end
end
@inline load(p::Ptr{UInt}, ::Type{T}) where {T} = load(reinterpret(Ptr{T}, p))
@generated function store!(p::Ptr{T}, v::T) where {T}
  if Base.allocatedinline(T)
    Expr(:block, Expr(:meta,:inline), :(unsafe_store!(p, v); return nothing))
  else
    Expr(:block, Expr(:meta,:inline), :(unsafe_store!(Base.unsafe_convert(Ptr{Ptr{Cvoid}}, p), Base.pointer_from_objref(v)); return nothing))
  end
end
offsetsize(::Type{T}) where {T} = Base.allocatedinline(T) ? sizeof(T) : sizeof(Int)

function load_aggregate(::Type{T}, offset::Int) where {T}
  numfields = fieldcount(T)
  call = (T <: Tuple) ? Expr(:tuple) : Expr(:new, T)
  for f ∈ 1:numfields
    TF = fieldtype(T, f)
    if Base.issingletontype(TF)
      push!(call.args, TF.instance)
    elseif fieldcount(TF) ≡ 0
      ptr = :(p + (offset + $offset))
      ptr = TF === UInt ? ptr : :(reinterpret(Ptr{$TF}, $ptr))
      push!(call.args, :(load($ptr)))
      offset += offsetsize(TF)
    else
      arg, offset = load_aggregate(TF, offset)
      push!(call.args, arg)
    end
  end
  return call, offset
end
@generated function load(p::Ptr{UInt}, ::Type{T}, offset::Int) where {T}
  if Base.issingletontype(T)
    call = Expr(:tuple, :offset, T.instance)
  elseif fieldcount(T) ≡ 0
    ptr = :(p + offset)
    ptr = T === UInt ? ptr : :(reinterpret(Ptr{$T}, $ptr))
    call = :(((offset + $(offsetsize(T)), load($ptr))))
  else
    call, off = load_aggregate(T, 0)
    call = Expr(:tuple, :(offset + $off), call)
  end
  Expr(:block, Expr(:meta,:inline), call)
end

function store_aggregate!(q::Expr, sym, ::Type{T}, offset::Int) where {T}
  gf = GlobalRef(Core,:getfield)
  for f ∈ 1:fieldcount(T)
    TF = fieldtype(T, f)
    Base.issingletontype(TF) && continue
    gfcall = Expr(:call, gf, sym, f)
    if fieldcount(TF) ≡ 0
      ptr = :(p + (offset + $offset))
      ptr = TF === UInt ? ptr : :(reinterpret(Ptr{$TF}, $ptr))
      push!(q.args, :(store!($ptr, $gfcall)))
      offset += offsetsize(TF)
    else
      newsym = gensym(sym)
      push!(q.args, Expr(:(=), newsym, gfcall))
      offset = store_aggregate!(q, newsym, TF, offset)
    end
  end
  return offset
end
@generated function store!(p::Ptr{UInt}, x::T, offset::Int) where {T}
  Base.issingletontype(T) && return :offset
  body = Expr(:block, Expr(:meta,:inline))
  if fieldcount(T) ≡ 0
    ptr = :(p + offset)
    ptr = T === UInt ? ptr : :(reinterpret(Ptr{$T}, $ptr))
    push!(body.args, :(store!($ptr, x)))
    off = offsetsize(T)
  else
    off = store_aggregate!(body, :x, T, 0)
  end
  push!(body.args, Expr(:call, +, :offset, off))
  return body
end

