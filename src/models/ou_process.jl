# src/models/ou_process.jl

module OrnsteinUhlenbeck
using Revise
using Random
using Distributions
using BayesianINT
using ..Models
using NonlinearSolve
import DifferentialEquations as deq

export OneTimescaleModel, generate_ou_process, informed_prior_one_timescale
"""
Generate an Ornstein-Uhlenbeck process with a single timescale with vanilla Julia code.

# Arguments
- `tau::Float64`: Timescale
- `true_D::Float64`: Variance of data. This will be used to manually scale the OU process so that 
Bayesian inference doesn't have to deal with it. 
- `deltaT::Float64`: Time step size
- `T::Float64`: Total time length
- `num_trials::Int64`: Number of trials/trajectories to generate
- `backend::String`: Backend to use. Must be 'vanilla' or 'sciml'.
- `parallel::Bool`: Whether to use parallelization. Only works with 'sciml' backend.

# Returns
- Matrix{Float64}: Generated OU process data with dimensions (num_trials, num_timesteps)

The process is generated using the Euler-Maruyama method with the specified time step deltaT.
"""
function generate_ou_process(tau::Union{Float64, Vector{Float64}},
                            true_D::Float64,
                            deltaT::Float64,
                            T::Float64,
                            num_trials::Int64;
                            backend::String="sciml",
                            parallel::Bool=false)
    if backend == "vanilla"
        return generate_ou_process_vanilla(tau, true_D, deltaT, T, num_trials)
    elseif backend == "sciml"
        return generate_ou_process_sciml(tau, true_D, deltaT, T, num_trials, parallel)
    else
        error("Invalid backend: $backend. Must be 'vanilla' or 'sciml'.")
    end
end

"""
Generate an Ornstein-Uhlenbeck process with a single timescale using DifferentialEquations.jl.
"""
function generate_ou_process_sciml(
    tau::Union{Float64, Vector{Float64}},
    true_D::Float64,
    deltaT::Float64,
    T::Float64,
    num_trials::Int64,
    parallel::Bool=false
)
    f = (du, u, p, t) -> du .= -u ./ p[1]
    g = (du, u, p, t) -> du .= 1.0 # Handle the variance below
    p = (tau, true_D)
    u0 = randn(num_trials) # Quick hack instead of ensemble problem
    prob = deq.SDEProblem(f, g, u0, (0.0, T), p)
    times = deltaT:deltaT:T
    sol = deq.solve(prob; saveat=times)
    sol_matrix = reduce(hcat, sol.u)
    ou_scaled = ((sol_matrix .- mean(sol_matrix, dims=2)) ./ std(sol_matrix, dims=2)) * true_D
    return ou_scaled
end

"""
Generate an Ornstein-Uhlenbeck process with a single timescale using vanilla Julia code.
"""
function generate_ou_process_vanilla(
    tau::Union{Float64, Vector{Float64}},
    true_D::Float64,
    deltaT::Float64,
    T::Float64,
    num_trials::Int64
)
    num_bin = Int(T / deltaT)
    noise = randn(num_trials, num_bin)
    ou = zeros(num_trials, num_bin)
    ou[:, 1] = noise[:, 1]

    for i in 2:num_bin
        ou[:, i] = @views ou[:, i-1] .- (ou[:, i-1] / tau) * deltaT .+
            sqrt(deltaT) * noise[:, i-1]
    end
    ou_scaled = ((ou .- mean(ou, dims=2)) ./ std(ou, dims=2)) * true_D

    return ou_scaled
end

function informed_prior_one_timescale(data::AbstractMatrix)
    # TODO: Implement this
    data_ac = comp_ac_fft(data; normalize=false)
    # Fit an exponential decay to the data_ac and make informed priors for tau and D
end

"""
One-timescale OU process model
"""
struct OneTimescaleModel <: AbstractTimescaleModel
    data::Matrix{Float64}
    prior::Vector{Distribution}
    data_sum_stats::Vector{Float64}
    epsilon::Float64
    deltaT::Float64
    binSize::Float64
    T::Float64
    numTrials::Int
    data_mean::Float64
    data_var::Float64
end

# Implementation of required methods

function Models.generate_data(model::OneTimescaleModel, theta)
    tau = theta
    return generate_ou_process(tau, model.data_var, model.deltaT, model.T, model.numTrials; backend="sciml", parallel=false)
end

function Models.summary_stats(model::OneTimescaleModel, data; n_lags=3000)
    return comp_ac_fft(data; n_lags=n_lags)
end

function Models.distance_function(model::OneTimescaleModel, sum_stats, data_sum_stats; n_lags=3000)
    # TODO: Implement n_lags throughout the codebase
    return linear_distance(sum_stats[1:n_lags], data_sum_stats[1:n_lags])
end

end # module OrnsteinUhlenbeck