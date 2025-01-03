using Test
using Distributions
using BayesianINT
using Statistics
using BayesianINT
using BayesianINT.Models
using BayesianINT.OrnsteinUhlenbeck
# using Plots

@testset "OU Parameter Inference" begin
    # Figure 3a of Zeraati et al. paper
    # Generate synthetic data with known parameters (units are in ms)
    true_tau = 20.0
    true_D = 3.0
    dt = 1.0
    T = 1000.0
    num_trials = 500
    n_lags = 50

    # Generate synthetic data
    data = generate_ou_process(true_tau, true_D, dt, T, num_trials)

    # Set up priors
    priors = [
        Uniform(1.0, 100.0)  # tau prior
    ]
    data_acf = comp_ac_fft(data; n_lags=n_lags)

    # Create model
    model = OneTimescaleModel(data,              # data
                              priors,            # prior
                              data_acf,          # data_sum_stats
                              1.0,               # epsilon
                              dt,                # dt
                              T,                 # T
                              num_trials,        # numTrials
                              std(data),         # data_var
                              n_lags)

    # Run PMC-ABC
    results = pmc_abc(model;
                      epsilon_0=1e-1,
                      min_samples=100,
                      steps=60,
                      minAccRate=0.01,
                      max_iter=100)

    # Get final posterior samples
    final_samples = results[end].theta_accepted

    # Calculate posterior means
    posterior_tau = mean(final_samples[1, :])
    tau_std = std(final_samples[1, :])

    # Test if estimates are within reasonable range
    @test abs(posterior_tau - true_tau) < 5.0
    # Plot
    # histogram(final_samples[1, :])
    # vline!([true_tau])
end

@testset "OU with Oscillation Parameter Inference" begin
    # Generate synthetic data with known parameters
    true_tau = 100.0
    true_freq = 10.0 / 1000.0  # mHz
    true_coeff = 0.95  # oscillation coefficient
    dt = 1.0
    T = 30000.0
    num_trials = 10
    n_lags = 100
    epsilon_0 = 1.0

    # Calculate data mean and variance (needed for OneTimescaleAndOscModel)
    data = generate_ou_with_oscillation([true_tau, true_freq, true_coeff],
                                        dt, T, num_trials, 0.0, 1.0)
    data_mean = mean(data)
    data_var = std(data)

    # Set up priors
    priors = [
        Uniform(30.0, 120.0),  # tau prior
        Uniform(1.0 / 1000.0, 60.0 / 1000.0),    # frequency prior
        Uniform(0.0, 1.0)      # oscillation coefficient prior
    ]

    data_sum_stats = comp_psd(data, 1/dt)[1]

    # Create model
    model = OneTimescaleAndOscModel(data,              # data
                                    priors,           # prior
                                    data_sum_stats,   # data_sum_stats
                                    epsilon_0,        # epsilon
                                    dt,               # dt
                                    T,                # T
                                    num_trials,       # numTrials
                                    data_mean,        # data_mean
                                    data_var,         # data_var
                                    [(0.0, 1.0), (0.0, 1.0), (0.0, 1.0)]) # prior_scales (avoid rescaling)

    # Run PMC-ABC
    results = pmc_abc(model;
                      epsilon_0=0.5,
                      min_samples=100,
                      steps=100,
                      minAccRate=0.01,
                      max_iter=100)

    # Get final posterior samples
    final_samples = results[end].theta_accepted

    # Calculate posterior means/MAPs
    posterior_tau = mean(final_samples[1, :])
    posterior_freq = mean(final_samples[2, :])
    posterior_coeff = mean(final_samples[3, :])

    sd_tau = std(final_samples[1, :])
    sd_freq = std(final_samples[2, :])
    sd_coeff = std(final_samples[3, :])

    # Test if estimates are within reasonable range
    @test abs(posterior_tau - true_tau) < 10.0
    @test abs(posterior_freq - true_freq) < 3.0 / 1000.0
    @test abs(posterior_coeff - true_coeff) < 0.2
    # Plot
    # ou_final = generate_ou_with_oscillation([posterior_tau, posterior_freq, posterior_coeff], dt, T, num_trials, 0.0, 1.0)
    # ou_final_sum_stats, freq = comp_psd(ou_final, 1/dt)
    # plot(freq, data_sum_stats, scale=:ln, label="Data")
    # plot!(freq, ou_final_sum_stats, scale=:ln, label="Model")

    # histogram(final_samples[1, :])
    # vline!([true_tau])
    # histogram(final_samples[2, :])
    # vline!([true_freq])
    # histogram(final_samples[3, :])
    # vline!([true_coeff])
    
end
