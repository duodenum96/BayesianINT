# src/models/ou_process.jl

"""
    OrnsteinUhlenbeck

Module for generating Ornstein-Uhlenbeck processes with various configurations.
Uses DifferentialEquations.jl. 
"""
module OrnsteinUhlenbeck
using Revise
using Random
using Distributions: Distribution
using INT
using ..Models
using NonlinearSolve
import DifferentialEquations as deq
using StaticArrays
import SciMLBase

export generate_ou_process, generate_ou_with_oscillation, generate_ou_process_sciml

"""
    generate_ou_process(tau, true_D, dt, duration, num_trials; standardize=true)

Generate an Ornstein-Uhlenbeck process with a single timescale

# Arguments
- `tau::Union{Real, Vector{<:Real}}`: Timescale(s) of the OU process
- `true_D::Real`: Target variance for scaling the process
- `dt::Real`: Time step size
- `duration::Real`: Total time length
- `num_trials::Real`: Number of trials/trajectories
- `standardize::Bool=true`: Whether to standardize output to match true_D

# Returns
- Matrix{Float64}: Generated OU process data with dimensions (num_trials, num_timesteps)

# Notes
- Uses generate_ou_process_sciml internally
- Returns NaN matrix if SciML solver fails
- Standardizes output to have specified variance if standardize=true
"""
function generate_ou_process(tau::Union{Real, Vector{<:Real}},
                            true_D::Real,
                            dt::Real,
                            duration::Real,
                            num_trials::Real;
                            standardize::Bool=true)

    ou, sol = generate_ou_process_sciml(tau, true_D, dt, duration, num_trials, standardize)
    if SciMLBase.successful_retcode(sol.retcode)
        return ou
    else
        ou = NaN * ones(num_trials, Int(duration / dt))
        return ou
    end
end

# OU Process Differential Equations for DifferentialEquations.jl interface
f_inplace = (du, u, p, t) -> du .= -u ./ p[1]
g_inplace = (du, u, p, t) -> du .= 1.0
f_outofplace = (u, p, t) -> SA[(-u ./ p[1])...]
g_outofplace = (u, p, t) -> SA[1.0]
p = [1.0] # example parameter
u0_inplace = [randn()]
u0_outofplace = SA[randn()]
_prob_inplace = deq.SDEProblem(f_inplace, g_inplace, u0_inplace, (0.0, 1.0), p) # This will be reused below
_prob_outofplace = deq.SDEProblem(f_outofplace, g_outofplace, u0_outofplace, (0.0, 1.0), p)

"""
    generate_ou_process_sciml(tau, true_D, dt, duration, num_trials, standardize=true)

Generate an Ornstein-Uhlenbeck process using DifferentialEquations.jl.

# Arguments
- `tau::Union{T, Vector{T}}`: Timescale(s) of the OU process
- `true_D::Real`: Target variance for scaling
- `dt::Real`: Time step size
- `duration::Real`: Total time length
- `num_trials::Integer`: Number of trials/trajectories
- `standardize::Bool=true`: Whether to standardize output

# Returns
- `Tuple{Matrix{Float64}, ODESolution}`: 
  - Scaled OU process data
  - Full SDE solution object

# Notes
- Uses SOSRA solver for efficiency
- Switches between static and dynamic arrays based on num_trials
- Standardizes output to match true_D if standardize=true
"""
function generate_ou_process_sciml(
    tau::Union{T, Vector{T}},
    true_D::Real,
    dt::Real,
    duration::Real,
    num_trials::Integer,
    standardize::Bool=true
) where T <: Real
    
    p = [tau]
    if num_trials <= 20
        u0 = SA[randn(num_trials)...] # Quick hack instead of ensemble problem
        prob = deq.remake(_prob_outofplace, p=p, u0=u0, tspan=(0.0, duration))
    else
        u0 = randn(num_trials)
        prob = deq.remake(_prob_inplace, p=p, u0=u0, tspan=(0.0, duration))
    end
    times = dt:dt:duration
    sol = deq.solve(prob, deq.SOSRA(); saveat=times, verbose=false)
    sol_matrix = reduce(hcat, sol.u)
    if standardize
        ou_scaled = ((sol_matrix .- mean(sol_matrix, dims=2)) ./ std(sol_matrix, dims=2)) * true_D
    else
        ou_scaled = sol_matrix
    end
    return ou_scaled, sol
end


"""
    generate_ou_with_oscillation(theta, dt, duration, num_trials, data_mean, data_var)

Generate a one-timescale OU process with an additive oscillation.

# Arguments
- `theta::Vector{T}`: Parameters [timescale, frequency, coefficient]
- `dt::Real`: Time step size
- `duration::Real`: Total time length
- `num_trials::Integer`: Number of trials
- `data_mean::Real`: Target mean value
- `data_var::Real`: Target variance

# Returns
- Matrix{Float64}: Generated data with dimensions (num_trials, num_timesteps)

# Notes
- Coefficient is bounded between 0 and 1
- Combines OU process with sinusoidal oscillation
- Standardizes and scales output to match target mean and variance
- Returns NaN matrix if SciML solver fails
"""
function generate_ou_with_oscillation(theta::Vector{T},
                                      dt::Real,
                                      duration::Real,
                                      num_trials::Integer,
                                      data_mean::Real,
                                      data_var::Real) where T <: Real
    # Extract parameters
    tau = theta[1]
    freq = theta[2]
    coeff = theta[3]

    # Make sure coeff is bounded between 0 and 1
    if coeff < 0.0
        coeff = 1e-4
    elseif coeff > 1.0
        coeff = 1.0 - 1e-4
    end

    # Generate OU process and oscillation
    ou, sol = generate_ou_process_sciml(tau, data_var, dt, duration, num_trials, false)
    if sol.retcode != deq.ReturnCode.Success
        ou = NaN * ones(num_trials, Int(duration / dt))
    end

    # Create time matrix and random phases
    time_mat = repeat(collect(dt:dt:duration), 1, num_trials)'
    phases = rand(num_trials, 1) * 2π

    # Generate oscillation and combine with OU
    oscil = sqrt(2.0) * sin.(phases .+ 2π * freq * time_mat)
    data = sqrt(1.0 - coeff) * oscil .+ sqrt(coeff) * ou

    data = (data .- mean(data, dims=2)) ./ std(data, dims=2)

    # Scale to match target mean and variance
    data_scaled = data_var * data .+ data_mean

    return data_scaled
end

end # module OrnsteinUhlenbeck