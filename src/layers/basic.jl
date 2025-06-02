@doc raw"""
    FourierFeature(in_dims::Int, std::NTuple{N,Pair{S,T}}) where {N,S,T<:Int}
    FourierFeature(in_dims::Int, frequencies::NTuple{N, T}) where {N, T <: Real}
    FourierFeature(in_dims::Int, out_dims::Int, std::Real)
Fourier Feature Network.

# Arguments

  - `in_dims`: Number of the input dimensions.
  - `std`: A tuple of pairs of `sigma => out_dims`, where `sigma` is the standard deviation
    of the Gaussian distribution.

```math
\phi^{(i)}(x)=\left[\sin \left(2 \pi W^{(i)} x\right) ; \cos 2 \pi W^{(i)} x\right],\ W^{(i)} \sim \mathcal{N}\left(0, \sigma^{(i)}\right),\ i\in 1, \dots, D
```

  - `frequencies`: A tuple of frequencies ``(f1,f2,...,fn)``.

```math
\phi^{(i)}(x)=\left[\sin \left(2 \pi f_i x\right) ; \cos 2 \pi f_i x\right]
```
# Parameters

  If `std` is used, then parameters are `W`s in the formula.

# Inputs

  - `x`: `AbstractArray` with `size(x, 1) == in_dims`.

# Returns

  - ``[\phi^{(1)}, \phi^{(2)}, ... ,\phi^{(D)}]`` with `size(y, 1) == sum(last(modes) * 2)`.

# Examples

```julia
julia> f = FourierFeature(2,10,1) # Random Fourier Feature
FourierFeature(2 => 10)

julia> f = FourierFeature(2, (1 => 3, 50 => 4)) # Multi-scale Random Fourier Features
FourierFeature(2 => 14)

julia>  f = FourierFeature(2, (1,2,3,4)) # Predefined frequencies
FourierFeature(2 => 16)
```

# References

[rahimi2007random](@cite)

[tancik2020fourier](@cite)

[wang2021eigenvector](@cite)
"""
struct FourierFeature{F} <: AbstractLuxLayer
    in_dims::Int
    out_dims::Int
    frequencies::F
end

function Base.show(io::IO, f::FourierFeature)
    return print(io, "FourierFeature($(f.in_dims) => $(f.out_dims))")
end

function FourierFeature(in_dims::Int, std::NTuple{N, Pair{S, T}}) where {N, S, T <: Int}
    out_dims = map(x -> 2 * last(x), std)
    return FourierFeature{typeof(std)}(in_dims, sum(out_dims), std)
end

function FourierFeature(in_dims::Int, frequencies::NTuple{N, T}) where {N, T <: Real}
    out_dims = length(frequencies) * 2 * in_dims
    return FourierFeature{typeof(frequencies)}(in_dims, out_dims, frequencies)
end

function FourierFeature(in_dims::Int, out_dims::Int, std::Real)
    @assert iseven(out_dims) "The number of output dimensions must be even."
    return FourierFeature(in_dims, (std => out_dims ÷ 2,))
end

function initialstates(rng::AbstractRNG,
                       f::FourierFeature{NTuple{N, Pair{S, T}}}) where {N, S, T <: Int}
    std_dims = f.frequencies
    frequency_matrix = mapreduce(vcat, std_dims) do sigma
        return init_normal(rng, last(sigma), f.in_dims; std=first(sigma))
    end
    return (; weight=frequency_matrix)
end

function initialstates(rng::AbstractRNG,
                       f::FourierFeature{NTuple{N, T}}) where {N, T <: Real}
    return NamedTuple()
end

function (l::FourierFeature{NTuple{N, T}})(x::AbstractArray, ps,
                                           st::NamedTuple) where {N, T <: Real}
    x = 2.0f0π .* x
    y = mapreduce(vcat, l.frequencies) do f
        return [sin.(f * x); cos.(f * x)]
    end
    return y, st
end

function (l::FourierFeature{NTuple{N, Pair{S, T}}})(x::AbstractVecOrMat, ps,
                                                    st::NamedTuple) where {N, S, T <: Int}
    W = st.weight
    y = [sin.(W * x); cos.(W * x)]
    return y, st
end

function (f::FourierFeature{NTuple{N, Pair{S, T}}})(x::AbstractArray, ps,
                                                    st::NamedTuple) where {N, S, T <: Int}
    W = st.weight
    y = [sin.(W ⊠ x); cos.(W ⊠ x)]
    return y, st
end

@doc raw"""
    DiscreteFourierFeature(in_dims::Int, out_dims::Int, N::Int, period::Real)

The discrete Fourier filter proposed in [lindell2021bacon](@cite). For a periodic function
with period ``P``, the Fourier series in amplitude-phase form is
```math
s_N(x)=\frac{a_0}{2}+\sum_{n=1}^N{a_n}\cdot \sin \left( \frac{2\pi}{P}nx+\varphi _n \right)
```

The output is guaranteed to be periodic.
## Arguments
  - `in_dims`: Number of the input dimensions.
  - `out_dims`: Number of the output dimensions.
  - `N`: ``N`` in the formula.
  - `period`: ``P`` in the formula.
"""
struct DiscreteFourierFeature{P, F} <: AbstractLuxLayer
    in_dims::Int
    out_dims::Int
    period::P
    N::F
end

function Base.show(io::IO, f::DiscreteFourierFeature)
    return print(io, "DiscreteFourierFeature($(f.in_dims) => $(f.out_dims))")
end

function DiscreteFourierFeature(in_dims::Int, out_dims::Int, N::Int, period::Real)
    return DiscreteFourierFeature{typeof(period), typeof(N)}(in_dims, out_dims, period, N)
end

function DiscreteFourierFeature(ch::Pair{<:Int, <:Int}, N::Int, period::Real)
    return DiscreteFourierFeature(first(ch), last(ch), N, period)
end

function initialstates(rng::AbstractRNG, m::DiscreteFourierFeature{<:Int})
    s = 2 / m.period
    s = s ≈ round(s) ? Int(s) : Float32(s)
    weight = rand(rng, 0:(m.N), m.out_dims, m.in_dims)
    return (; weight=weight, fundamental_freq=s)
end
function initialstates(rng::AbstractRNG, m::DiscreteFourierFeature)
    s = 2π / m.period
    s = s ≈ round(s) ? Int(s) : Float32(s)
    weight = rand(rng, 0:(m.N), m.out_dims, m.in_dims)
    return (; weight=weight, fundamental_freq=s)
end

function initialparameters(rng::AbstractRNG, m::DiscreteFourierFeature{<:Int})
    bias = init_uniform(rng, m.out_dims, 1)
    return (; bias=bias)
end
function initialparameters(rng::AbstractRNG, m::DiscreteFourierFeature)
    bias = init_uniform(rng, m.out_dims, 1; scale=1.0f0π)
    return (; bias=bias)
end

function parameterlength(b::DiscreteFourierFeature)
    return b.out_dims
end

statelength(b::DiscreteFourierFeature) = b.out_dims * b.in_dims

@inline function (b::DiscreteFourierFeature{<:Int})(x::AbstractVector, ps, st::NamedTuple)
    return sinpi.(st.weight * x .* st.fundamental_freq .+ vec(ps.bias)), st
end
@inline function (b::DiscreteFourierFeature)(x::AbstractVector, ps, st::NamedTuple)
    return sin.(st.weight * x .* st.fundamental_freq .+ vec(ps.bias)), st
end

@inline function (d::DiscreteFourierFeature{<:Int})(x::AbstractMatrix, ps, st::NamedTuple)
    return sinpi.(st.weight * x .* st.fundamental_freq .+ ps.bias), st
end

@inline function (d::DiscreteFourierFeature)(x::AbstractMatrix, ps, st::NamedTuple)
    return sin.(st.weight * x .* st.fundamental_freq .+ ps.bias), st
end

"""
    Sine(in_dims::Int, out_dims::Int; omega::Real)

Sinusoidal layer.

## Example

```julia
s = Sine(2, 2; omega=30.0f0) # first layer
s = Sine(2, 2) # hidden layer
```
"""
function Sine(ch::Pair{T, T}; omega::Union{Real, Nothing}=nothing) where {T <: Int}
    return Sine(first(ch), last(ch); omega=omega)
end

function Sine(in_dims::Int, out_dims::Int; omega::Union{Real, Nothing}=nothing)
    init_weight = get_sine_init_weight(omega)
    return Dense(in_dims, out_dims, sin; init_weight=init_weight)
end

get_sine_init_weight(::Nothing) = kaiming_uniform(sin)
function get_sine_init_weight(omega::Real)
    return (rng::AbstractRNG, out_dims::Int, in_dims::Int) -> init_uniform(rng, out_dims,
                                                                           in_dims;
                                                                           scale=Float32(omega) /
                                                                                 in_dims)
end
"""
    RBF(in_dims::Int, out_dims::Int, num_centers::Int=out_dims; sigma::AbstractFloat=0.2f0)

Normalized Radial Basis Fuction Network.
"""
struct RBF{F1, F2} <: AbstractLuxLayer
    in_dims::Int
    out_dims::Int
    num_centers::Int
    sigma::Float32
    init_center::F1
    init_weight::F2
end

function RBF(in_dims::Int, out_dims::Int, num_centers::Int=out_dims,
             sigma::AbstractFloat=0.2f0, init_center=init_uniform,
             init_weight=Lux.glorot_normal)
    return RBF{typeof(init_center), typeof(init_weight)}(in_dims, out_dims, num_centers,
                                                         sigma, init_center, init_weight)
end

function RBF(mapping::Pair{<:Int, <:Int}, num_centers::Int=out_dims,
             sigma::AbstractFloat=0.2f0, init_center=init_uniform,
             init_weight=Lux.glorot_uniform)
    return RBF(first(mapping), last(mapping), num_centers, sigma, init_center, init_weight)
end

function initialparameters(rng::AbstractRNG, s::RBF)
    center = s.init_center(rng, s.num_centers, s.in_dims)
    weight = s.init_weight(rng, s.out_dims, s.num_centers)
    return (center=center, weight=weight)
end

function (rbf::RBF)(x::AbstractVecOrMat, ps, st::NamedTuple)
    x_norm = sum(abs2, x; dims=1)
    center_norm = sum(abs2, ps.center; dims=2)
    d = -2 * ps.center * x .+ x_norm .+ center_norm
    z = -1 / rbf.sigma .* d
    z_shit = z .- maximum(z; dims=1)
    r = exp.(z_shit)
    r = r ./ reshape(sum(r; dims=1), 1, :)
    y = ps.weight * r
    return y, st
end

function Base.show(io::IO, rbf::RBF)
    return print(io, "RBF($(rbf.in_dims) => $(rbf.out_dims))")
end

"""
    ScalarLayer(connection::Function)

Return connection(scalar, x)
"""
struct ScalarLayer{F} <: AbstractLuxLayer
    connection::F
end

ScalarLayer(connection::Function) = ScalarLayer{typeof(connection)}(connection)

initialparameters(rng::AbstractRNG, s::ScalarLayer) = (; scalar=[0.0f0;;])
parameterlength(s::ScalarLayer) = 1

@inline function (s::ScalarLayer)(x::AbstractArray, ps, st::NamedTuple)
    return s.connection(ps.scalar, x), st
end

"""
    ConstantFunction()

A conatiner for scalar parameter. This is useful for the case that you want a dummy layer
that returns the scalar parameter for any input.
"""
struct ConstantFunction <: AbstractLuxLayer end

initialparameters(rng::AbstractRNG, s::ConstantFunction) = (; constant=[0.0f0;;])
parameterlength(s::ConstantFunction) = 1
statelength(s::ConstantFunction) = 0

@inline function (s::ConstantFunction)(x::AbstractArray, ps, st::NamedTuple)
    return ps.constant, st
end

"""
    SplitFunction(indices...)

Split the input along the first demision according to indices.
"""
struct SplitFunction{F} <: AbstractLuxLayer
    indices::F
end

function SplitFunction(indices...)
    indices = map(indices) do i
        return i isa Int ? UnitRange(i, i) : i
    end
    return SplitFunction{typeof(indices)}(indices)
end

function (sf::SplitFunction)(x::AbstractVector, ps, st::NamedTuple)
    return map(i -> view(x, i), sf.indices), st
end

function (sf::SplitFunction)(x::AbstractMatrix, ps, st::NamedTuple)
    return map(i -> view(x, i, :), sf.indices), st
end

"""
    FactorizedDense(in_dims::Int, out_dims::Int, activation=identity;
                         mean::AbstractFloat=1.0f0, std::AbstractFloat=0.1f0,
                         init_weight=kaiming_uniform(activation), init_bias=zeros32)

Create a `Dense` layer where the weight is factorized into twa parts, the scaling factors for
each row and the weight matrix.

## Arguments

  - `in_dims`: number of input dimensions
  - `out_dims`: number of output dimensions
  - `activation`: activation function

## Keyword Arguments

  - `mean`: mean of the scaling factors
  - `std`: standard deviation of the scaling factors
  - `init_weight`: weight initialization function
  - `init_bias`: bias initialization function

## Input

  - `x`: input vector or matrix

## Returns

  - `y = activation.(scale * weight * x+ bias)`.
  - Empty `NamedTuple()`.

## Parameters

  - `scale`: scaling factors. Shape: `(out_dims, 1)`
  - `weight`: Weight Matrix of size `(out_dims, in_dims)`.
  - `bias`: Bias of size `(out_dims, 1)`.

## References

[wang2022random](@cite)
"""
struct FactorizedDense{F1, F2, F3} <: AbstractLuxLayer
    activation::F1
    in_dims::Int
    out_dims::Int
    mean::AbstractFloat
    std::AbstractFloat
    init_weight::F2
    init_bias::F3
end

function FactorizedDense(in_dims::Int, out_dims::Int, activation=identity;
                         mean::AbstractFloat=1.0f0, std::AbstractFloat=0.1f0,
                         init_weight=kaiming_uniform(activation), init_bias=zeros32)
    activation = NNlib.fast_act(activation)
    return FactorizedDense{typeof(activation), typeof(init_weight), typeof(init_bias)}(activation,
                                                                                       in_dims,
                                                                                       out_dims,
                                                                                       mean,
                                                                                       std,
                                                                                       init_weight,
                                                                                       init_bias)
end

function FactorizedDense(mapping::Pair{<:Int, <:Int}, activation=identity;
                         mean::AbstractFloat=1.0f0, std::AbstractFloat=0.1f0,
                         init_weight=kaiming_uniform(activation), init_bias=zeros32)
    return FactorizedDense(first(mapping), last(mapping), activation; mean=mean, std=std,
                           init_weight=init_weight, init_bias=init_bias)
end

function initialparameters(rng::AbstractRNG, s::FactorizedDense)
    weight = s.init_weight(rng, s.out_dims, s.in_dims)
    scale = init_normal(rng, s.out_dims, 1; mean=s.mean, std=s.std)
    scale = exp.(scale)
    weight = weight ./ scale
    bias = s.init_bias(rng, s.out_dims, 1)
    return (scale=scale, weight=weight, bias=bias)
end

@inline function (fd::FactorizedDense)(x::AbstractVector, ps, st::NamedTuple)
    y = (ps.scale .* ps.weight) * x .+ vec(ps.bias)
    return fd.activation.(y), st
end

@inline function (fd::FactorizedDense)(x::AbstractMatrix, ps, st::NamedTuple)
    y = (ps.scale .* ps.weight) * x .+ ps.bias
    return fd.activation.(y), st
end

@inline function (fd::FactorizedDense{typeof(identity)})(x::AbstractVector, ps,
                                                         st::NamedTuple)
    y = (ps.scale .* ps.weight) * x .+ vec(ps.bias)
    return y, st
end

@inline function (fd::FactorizedDense{typeof(identity)})(x::AbstractMatrix, ps,
                                                         st::NamedTuple)
    y = (ps.scale .* ps.weight) * x .+ ps.bias
    return y, st
end

function Base.show(io::IO, fd::FactorizedDense)
    return print(io, "FactorizedDense($(fd.in_dims) => $(fd.out_dims))")
end
