"""
    PINN(chain, rng::AbstractRNG=Random.default_rng())
    PINN(rng::AbstractRNG=Random.default_rng(); kwargs...)

A container for a neural network, its states and its initial parameters.
The default element type of the parameters is `Float64`.

## Fields

  - `phi`: [`ChainState`](@ref) if there is only one neural network, or an named tuple of [`ChainState`](@ref)s if there are multiple neural networks.
    The names are the same as the dependent variables in the PDE.
  - `init_params`: The initial parameters of the neural network.

## Arguments

  - `chain`: `AbstractLuxLayer` or a named tuple of `AbstractLuxLayer`s.
  - `rng`: `AbstractRNG` to use for initialising the neural network. If yout want to set the seed, write

```julia
using Random
rng = Random.default_rng()
Random.seed!(rng, 0)d
```

and pass `rng` to `PINN` as

```julia
using Sophon

chain = FullyConnected((1, 6, 6, 1), sin);

# sinple dependent varibale
pinn = PINN(chain, rng);

# multiple dependent varibales
pinn = PINN(rng; a=chain, b=chain);
```
"""
struct PINN{PHI, P}
    phi::PHI
    init_params::P
end

function PINN(rng::AbstractRNG=Random.default_rng(); kwargs...)
    return PINN((; kwargs...), rng)
end

function PINN(chain::NamedTuple, rng::AbstractRNG=Random.default_rng())
    phi = map(m -> ChainState(m, rng), chain)
    init_params = initialparameters(rng, phi)

    return PINN{typeof(phi), typeof(init_params)}(phi, init_params)
end

function PINN(chain::AbstractLuxLayer, rng::AbstractRNG=Random.default_rng())
    phi = ChainState(chain, rng)
    init_params = initialparameters(rng, phi)
    return PINN{typeof(phi), typeof(init_params)}(phi, init_params)
end

function initialparameters(rng::AbstractRNG, pinn::PINN)
    return initialparameters(rng, pinn.phi)
end

"""
    ChainState(model, rng::AbstractRNG=Random.default_rng())

It this similar to `Lux.Chain` but wraps it in a stateful container.

## Fields

  - `model`: The neural network.
  - `states`: The states of the neural network.

## Input

  - `x`: The input to the neural network.
  - `ps`: The parameters of the neural network.

## Arguments

  - `model`: `AbstractLuxLayer`, or a named tuple of them, which will be treated as a `Chain`.
  - `rng`: `AbstractRNG` to use for initialising the neural network.
"""
mutable struct ChainState{L, S}
    model::L
    state::S
end

function ChainState(model, rng::AbstractRNG=Random.default_rng())
    states = initialstates(rng, model)
    return ChainState{typeof(model), typeof(states)}(model, states)
end

function ChainState(model, state::NamedTuple)
    return ChainState{typeof(model), typeof(state)}(model, state)
end

function ChainState(; rng::AbstractRNG=Random.default_rng(), kwargs...)
    return ChainState((; kwargs...), rng)
end

@inline ChainState(a::ChainState) = a

@inline function initialparameters(rng::AbstractRNG, s::ChainState)
    return initialparameters(rng, s.model)
end

function (c::ChainState{<:NamedTuple})(x, ps)
    y, st = Lux.applychain(c.model, x, ps, c.state)
    ChainRulesCore.@ignore_derivatives c.state = st
    return y
end

function (c::ChainState{<:AbstractLuxLayer})(x, ps)
    y, st = c.model(x, ps, c.state)
    ChainRulesCore.@ignore_derivatives c.state = st
    return y
end

const NTofChainState{names} = NamedTuple{names, <:Tuple{Vararg{ChainState}}}

for (dev) in (:CPU, :CUDA, :AMDGPU, :Metal)
    ldev = Symbol("$(dev)Device")
    ladaptor = Symbol("$(dev)Adaptor")
    @eval begin
        function (device::$ldev)(cs::ChainState)
            Setfield.@set! cs.state = device(cs.state)
            return cs
        end

        function (device::$ldev)(cs::NTofChainState{names}) where {names}
            return map(cs) do c
                return device(c)
            end
        end

        function (device::$ldev)(pinn::PINN)
            Setfield.@set! pinn.phi = device(pinn.phi)
            Setfield.@set! pinn.init_params = adapt($(ladaptor)(), pinn.init_params)
            return pinn
        end
    end
end

"""
using Sophon, ModelingToolkit, DomainSets
using DomainSets: ×

@parameters x, t
@variables u(..)
Dxx = Differential(x)^2
Dtt = Differential(t)^2
Dt = Differential(t)

C=1
eq  = (Dtt(u(t,x)) ~ C^2*Dxx(u(t,x)), (0.0..1.0) × (0.0..1.0))

bcs = [(u(t,x) ~ 0.0, (0.0..1.0) × (0.0..0.0)),
(u(t,x) ~ 0.0, (0.0..1.0) × (1.0..1.0)),
(u(t,x) ~ x*(1. - x), (0.0..0.0) × (0.0..1.0)),
(Dt(u(t,x)) ~ 0.0, (0.0..0.0) × (0.0..1.0))]

pde_system = Sophon.PDESystem(eq,bcs,[t,x],[u(t,x)])
"""
struct PDESystem
    eqs::Vector
    bcs::Vector
    ivs::Vector
    dvs::Vector
end

function PDESystem(eq::Pair{Symbolics.Equation, <:DomainSets.Domain}, bcs, ivs, dvs)
    return PDESystem([eq], bcs, ivs, dvs)
end

Base.summary(prob::PDESystem) = string(nameof(typeof(prob)))
function Base.show(io::IO, ::MIME"text/plain", sys::PDESystem)
    println(io, summary(sys))
    println(io, "Equations: ")
    map(sys.eqs) do eq
        return println(io, "  ", eq[1], " on ", eq[2])
    end
    println(io, "Boundary Conditions: ")
    map(sys.bcs) do bc
        return println(io, "  ", bc[1], " on ", bc[2])
    end
    println(io, "Dependent Variables: ", sys.dvs)
    println(io, "Independent Variables: ", sys.ivs)
    return nothing
end

struct ParametricPDESystem
    eqs::Vector
    bcs::Vector
    ivs::Vector
    dvs::Vector
    pvs::Vector
end

function ParametricPDESystem(eq::Pair{<:Symbolics.Equation, <:DomainSets.Domain}, bcs, ivs,
                             dvs, pvs)
    return PDESystem([eq], bcs, ivs, dvs, pvs)
end

Base.summary(prob::ParametricPDESystem) = string(nameof(typeof(prob)))
function Base.show(io::IO, ::MIME"text/plain", sys::ParametricPDESystem)
    println(io, summary(sys))
    println(io, "Equations: ")
    map(sys.eqs) do eq
        return println(io, "  ", eq[1], " on ", eq[2])
    end
    println(io, "Boundary Conditions: ")
    map(sys.bcs) do bc
        return println(io, "  ", bc[1], " on ", bc[2])
    end
    println(io, "Dependent Variables: ", sys.dvs)
    println(io, "Independent Variables: ", sys.ivs)
    println(io, "Parametric Variables: ", sys.pvs)
    return nothing
end
