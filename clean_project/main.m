%MAIN Entry point: run and compare all battery-swap-station simulations.
%   This script:
%     1. Builds the simulation config, battery arrival queue, and PV profile
%     2. Runs the baseline, AMCCCV, and LP simulations
%     3. Sweeps MPC cost-weight combinations to find the best-performing one
%     4. Re-runs the best MPC config across resolution modes and extreme
%        arrival scenarios (peak clustering, rare-hour focus)
%     5. Compares all runs (cost, waiting time, PV spillage) and exports
%        results/plots to outputs/
%
%   Run this file directly (no arguments). Results are written to
%   outputs/plots, outputs/data, and outputs/logs.

clear; clc;
addpath(genpath(fileparts(mfilename('fullpath'))));  % add config/, data_generation/, optimization/, simulations/, comparison/

if ~exist('outputs/plots', 'dir')
    mkdir('outputs/plots');
end
if ~exist('outputs/data', 'dir')
    mkdir('outputs/data');
end

% --- 1. Setup Config and Inputs ---
sim_config = prep_sim_config();  % includes time, efficiency, etc.
rng(42);
BatteryQueue = generate_realistic_battery_queue(sim_config); 
PV_profile = generate_pv_profile(sim_config);
BatteryQueue_peak = apply_extreme_arrival_case(BatteryQueue, "peak_cluster", sim_config, [10 15 25]);
BatteryQueue_rare = apply_extreme_arrival_case(BatteryQueue, "rare_focus", sim_config, [10 15 25]);

weight_sets = [
    0.00000076, 16000, 10;
    0.00000050, 10000, 50;
    0.00000100, 12000, 20;
    0.00000080, 14000, 30;
    0.00000090, 18000, 15
];

% Optional: store results
results_all = cell(size(weight_sets, 1)+2, 1);
results_res = cell(size(weight_sets, 1), 1);
results_peak{1} = cell(size(weight_sets, 1)+2, 1);
results_rare{1} = cell(size(weight_sets, 1)+2, 1);
timings = zeros(size(weight_sets, 1), 1);

% --- 2. Run Simulations ---
results_all{1} = run_normal_simulation(sim_config, BatteryQueue, PV_profile);
results_all{7} = run_amcccv_simulation(sim_config, BatteryQueue, PV_profile);
results_all{8} = run_lp_simulation(sim_config, BatteryQueue, PV_profile);
results_res{1} = results_all{1};
results_peak{1} = run_normal_simulation(sim_config, BatteryQueue_peak, PV_profile);
results_peak{3} = run_amcccv_simulation(sim_config, BatteryQueue_peak, PV_profile);
results_peak{4} = run_lp_simulation(sim_config, BatteryQueue_peak, PV_profile);
results_rare{1} = run_normal_simulation(sim_config, BatteryQueue_rare, PV_profile);
results_rare{3} = run_amcccv_simulation(sim_config, BatteryQueue_rare, PV_profile);
results_rare{4} = run_lp_simulation(sim_config, BatteryQueue_rare, PV_profile);

parfor i = 1:size(weight_sets, 1)

    % Create a local copy of sim_config for each worker
    local_sim_config = sim_config;

    local_sim_config.ResolutionMode = 1;
    local_sim_config.WeightMode = i;
    local_sim_config.w1 = weight_sets(i, 1);
    local_sim_config.w2 = weight_sets(i, 2);
    local_sim_config.w3 = weight_sets(i, 3);
    
    tic;

    % Store the result in a temporary variable
    local_result = run_mpc_simulation(local_sim_config, BatteryQueue, BatteryQueue, PV_profile);

    elapsed_time = toc;
    
    % Store results outside loop
    results_all{i+1} = local_result;
    timings(i) = elapsed_time;

end

for i = 1:size(weight_sets, 1)
    fprintf('MPC run number %d . Elapsed time: %.2f seconds\n', i, timings(i));
end

% --- 3. Find Best Run Based on Scoring ---
baseline = results_all{1};  % Normal sim

seb = zeros(size(weight_sets, 1), 1);

UMR = sim_config.UMR;
H = sim_config.H;
k = sim_config.k;
tau_grid = sim_config.price_per_kWh_IDR;

num_runs = numel(results_all);

C_grid = zeros(size(weight_sets, 1), 1);
C_wait = zeros(size(weight_sets, 1), 1);
C_spill = zeros(size(weight_sets, 1), 1);
total_wait = zeros(size(weight_sets, 1), 1);
excess_PV = zeros(size(weight_sets, 1), 1);

VoT = k * (UMR / (H*60));

for i = 1:size(weight_sets, 1)
    result = results_all{i + 1}; % Skip baseline at index 1

    waits = [result.BatteryQueue.WaitingTime];
    total_wait(i) = sum(waits(~isnan(waits)));

    C_grid(i) = result.TotalCost_IDR;
    C_wait(i) = VoT * total_wait(i);
    excess_PV(i) = sum(result.ExcessEnergy, 'omitnan');
    C_spill(i) = excess_PV(i) * tau_grid;

    seb(i) = C_grid(i) + C_wait(i) + C_spill(i);

end

[~, best_idx] = min(seb);  % higher score is better
best_weight = weight_sets(best_idx, :);

compare_all_mpc_runs(results_all,{'Baseline', 'MPC Weights-1', 'MPC Weights-2', 'MPC Weights-3', 'MPC Weights-4', 'MPC Weights-5', 'AMCCCV', 'LP'});
compare_all_mpc_runs_SEB(results_all,{'Baseline', 'MPC Weights-1', 'MPC Weights-2', 'MPC Weights-3', 'MPC Weights-4', 'MPC Weights-5', 'AMCCCV', 'LP'}, sim_config);

parfor mode = 1:4
    local_sim_config = sim_config;
    local_sim_config.w1 = best_weight(1);
    local_sim_config.w2 = best_weight(2);
    local_sim_config.w3 = best_weight(3);
    local_sim_config.ResolutionMode = mode;

    results_res{mode+1} = run_mpc_simulation(local_sim_config, BatteryQueue, BatteryQueue, PV_profile);
end

compare_all_mpc_runs(results_res,{'Baseline', 'Scenario-1', 'Scenario-2', 'Scenario-3', 'Scenario-4'});
compare_all_mpc_runs_SEB(results_res,{'Baseline', 'Scenario-1', 'Scenario-2', 'Scenario-3', 'Scenario-4'}, sim_config);

parfor i = 1:2
    local_sim_config = sim_config;
    local_sim_config.w1 = best_weight(1);
    local_sim_config.w2 = best_weight(2);
    local_sim_config.w3 = best_weight(3);
    local_sim_config.ResolutionMode = 1;
    if i == 1
        results_all{i} = run_mpc_simulation(local_sim_config, BatteryQueue_peak, BatteryQueue, PV_profile);
    end
    if i == 2
        results_all{i} = run_mpc_simulation(local_sim_config, BatteryQueue_rare, BatteryQueue, PV_profile);
    end
end

results_peak{2} = results_all{1};
results_rare{2} = results_all{2};

compare_all_mpc_runs(results_peak,{'Normal', 'peak', 'AMCCCV', 'LP'});
compare_all_mpc_runs_SEB(results_peak,{'Normal', 'peak', 'AMCCCV', 'LP'},sim_config);

compare_all_mpc_runs(results_rare,{'Normal', 'rare', 'AMCCCV', 'LP'});
compare_all_mpc_runs_SEB(results_rare,{'Normal', 'rare', 'AMCCCV', 'LP'}, sim_config);

for a = 1:length(results_all)
    for b = a + 1:length(results_all)
        if isequal(results_all{a}.TotalCost_IDR, results_all{b}.TotalCost_IDR)
            fprintf('[DUP] Weight runs %d and %d have identical total cost: %.2f\n', ...
                a, b, results_all{a}.TotalCost_IDR);
        end
    end
end
for a = 1:length(results_res)
    for b = a + 1:length(results_res)
        if isequal(results_res{a}.TotalCost_IDR, results_res{b}.TotalCost_IDR)
            fprintf('[DUP] Resolution runs %d and %d have identical total cost: %.2f\n', ...
                a, b, results_res{a}.TotalCost_IDR);
        end
    end
end