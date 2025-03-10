module DataDrivenSparse

using DataDrivenDiffEq
# Load specific (abstract) types
using DataDrivenDiffEq: AbstractBasis
using DataDrivenDiffEq: AbstractDataDrivenAlgorithm
using DataDrivenDiffEq: AbstractDataDrivenResult
using DataDrivenDiffEq: AbstractDataDrivenProblem
using DataDrivenDiffEq: DDReturnCode, ABSTRACT_CONT_PROB, ABSTRACT_DISCRETE_PROB
using DataDrivenDiffEq: InternalDataDrivenProblem
using DataDrivenDiffEq: is_implicit, is_controlled

using DataDrivenDiffEq.DocStringExtensions
using DataDrivenDiffEq.CommonSolve
using DataDrivenDiffEq.StatsBase
using DataDrivenDiffEq.Parameters
using DataDrivenDiffEq.Setfield

using Reexport
using LinearAlgebra
using Printf

abstract type AbstractSparseRegressionAlgorithm <: AbstractDataDrivenAlgorithm end
abstract type AbstractProximalOperator end

abstract type AbstractSparseRegressionCache <: StatsBase.StatisticalModel end


# 加えたよ
function brd(x)
    return mod(x, 2pi)
end

function brn(x)
    return mod(x, 2pi) - 2pi * (mod(x, 2pi) > pi)
end



#ここを変えたよ
function _set!(x::AbstractSparseRegressionCache,
               y::AbstractSparseRegressionCache) where {T <: Number}
    begin
        foreach(eachindex(x.X)) do i
            x.X[i] = (brd.(y.X[i])./2pi).+floor.(y.X[i]./(2pi)).*2pi
            x.X_prev[i] = (brd.(y.X_prev[i])./2pi).+floor.(y.X_prev[i]./(2pi)).*2pi
            x.active_set[i] = (brd.(y.active_set[i])./2pi).+floor.(y.active_set[i]./(2pi)).*2pi
        end
        return
    end
end

#=
# cleanな状態

function _set!(x::AbstractSparseRegressionCache,
               y::AbstractSparseRegressionCache) where {T <: Number}
    begin
        foreach(eachindex(x.X)) do i
            x.X[i] = y.X[i]
            x.X_prev[i] = y.X_prev[i]
            x.active_set[i] = y.active_set[i]
        end
        return
    end
end
=#


_zero!(x::AbstractSparseRegressionCache) = begin
    x.X .= zero(eltype(x.X))
    return
end

# cleanな状態

function _is_converged(x::AbstractSparseRegressionCache, abstol, reltol)::Bool
    @unpack X, X_prev, active_set = x
    !(any(active_set)) && return true
    Δ = norm(X .- X_prev)
    Δ < abstol && return true
    δ = Δ / norm(X)
    δ < reltol && return true
    return false
end


#=
#brd足したよ
function _is_converged(x::AbstractSparseRegressionCache, abstol, reltol)::Bool
    @unpack X, X_prev, active_set = x
    !(any(active_set)) && return true
    Δ = norm(brd.(X) .- brd.(X_prev).*100)
    Δ < abstol && return true
    δ = Δ / norm(brd.(X))
    δ < reltol && return true
    return false
end
=#

# StatsBase Overload
StatsBase.coef(x::AbstractSparseRegressionCache) = getfield(x, :X)

StatsBase.rss(x::AbstractSparseRegressionCache) = begin
    @unpack Ã, X, B̃ = x
    sum(abs2, X * Ã .- B̃)
end

StatsBase.dof(x::AbstractSparseRegressionCache) = begin
    @unpack active_set = x
    sum(active_set)
end

StatsBase.nobs(x::AbstractSparseRegressionCache) = begin
    @unpack B̃ = x
    return prod(size(B̃))
end

function StatsBase.loglikelihood(x::AbstractSparseRegressionCache)
    begin -nobs(x) / 2 * log(rss(x) / nobs(x)) end
end

function StatsBase.nullloglikelihood(x::AbstractSparseRegressionCache)
    begin
        @unpack B̃ = x
        -nobs(x) / 2 * log(mean(abs2, B̃ .- mean(vec(B̃))))
    end
end

StatsBase.r2(x::AbstractSparseRegressionCache) = r2(x, :CoxSnell)

##

include("algorithms/proximals.jl")
export SoftThreshold, HardThreshold, ClippedAbsoluteDeviation

get_thresholds(x::AbstractSparseRegressionAlgorithm) = getfield(x, :thresholds)
get_relaxation(x::AbstractSparseRegressionAlgorithm) = nothing
get_proximal(x::AbstractSparseRegressionAlgorithm) = SoftThreshold()

include("solver.jl")
export SparseLinearSolver

function (x::X where {X <: AbstractSparseRegressionAlgorithm})(X, Y;
                                                               options::DataDrivenCommonOptions = DataDrivenCommonOptions(),
                                                               kwargs...)
    solver = SparseLinearSolver(x, options = options)
    # cleanな状態
    #results = solver(X, Y) # Keep this here for now

    results = solver(brd.(X), brd.(Y)) # Keep this here for now

    coeff_matrix = zeros(eltype(X), size(Y, 1), size(X, 1))
    optimal_thresholds = []
    optimal_iterations = Int[]

    foreach(enumerate(results)) do (i, res)
        coeff_matrix[i:i, :] .= coef(res[1])
        push!(optimal_thresholds, res[2])
        push!(optimal_iterations, res[3])
    end

    return coeff_matrix, optimal_thresholds, optimal_iterations
end

include("algorithms/STLSQ.jl")
export STLSQ

include("algorithms/ADMM.jl")
export ADMM

include("algorithms/SR3.jl")
export SR3

include("algorithms/Implicit.jl")
export ImplicitOptimizer

include("result.jl")
include("commonsolve.jl")

end # module
