function compare_all_mpc_runs_SEB(results_all, labels, sim_config)
%COMPARE_ALL_MPC_RUNS_SEB Compare runs using the Social/Economic Benefit (SEB) score.
%   COMPARE_ALL_MPC_RUNS_SEB(results_all, labels, sim_config) computes and
%   plots the SEB cost breakdown for each run: grid energy cost, cost of
%   customer waiting time (via Value of Time), and cost of spilled PV
%   energy, then plots grid usage and BSS SoC over time for each run.
%
%   Inputs:
%     results_all - cell array of result structs, one per run
%     labels      - cell array of display names, one per run
%     sim_config  - simulation config struct (used for VoT, price, etc.)

output_dir = 'outputs/logs';
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

logfile = fullfile(output_dir, 'Compare_MPC_SEB_Summary.txt');
if exist(logfile, 'file')
    delete(logfile);
end

diary(logfile);
diary on;

UMR = sim_config.UMR;
H = sim_config.H;
k = sim_config.k;
tau_grid = sim_config.price_per_kWh_IDR;

num_runs = numel(results_all);

C_grid = zeros(1, num_runs);
C_wait = zeros(1, num_runs);
C_spill = zeros(1, num_runs);
SEB = zeros(1, num_runs);
total_wait = zeros(1, num_runs);
excess_PV = zeros(1, num_runs);

VoT = k * (UMR / (H*60)); % IDR per minute

for i = 1:num_runs
    sim = results_all{i};
    waits = [sim.BatteryQueue.WaitingTime];
    total_wait(i) = sum(waits(~isnan(waits)));

    C_grid(i) = sim.TotalCost_IDR;
    C_wait(i) = VoT * total_wait(i);
    excess_PV(i) = sum(sim.ExcessEnergy, 'omitnan');
    C_spill(i) = excess_PV(i) * tau_grid;

    SEB(i) = C_grid(i) + C_wait(i) + C_spill(i);
end

% Print SEB table
fprintf('\n=== SEB Comparison ===\n');
fprintf('Run | Grid Cost (IDR) | Waiting Cost (IDR) | PV Spill Cost (IDR) | SEB (IDR)\n');
fprintf('----|-----------------|------------------|-------------------|-------------\n');
for i = 1:num_runs
    fprintf('%3d | %15.2f | %16.2f | %17.2f | %12.2f\n', ...
        i, C_grid(i), C_wait(i), C_spill(i), SEB(i));
end

[~, best_run] = min(SEB);
fprintf('\nBest run based on SEB: Run #%d (SEB = %.2f IDR)\n', best_run, SEB(best_run));

% --- Save SEB and operational data ---
data_dir = 'outputs/data';
if ~exist(data_dir, 'dir')
    mkdir(data_dir);
end

timestamp = datestr(now, 'yyyy-mm-dd_HHMMSS');
mat_file = fullfile(data_dir, sprintf('Compare_MPC_SEB_Data_%s.mat', timestamp));
excel_file = fullfile(data_dir, sprintf('Compare_MPC_SEB_Data_%s.xlsx', timestamp));

comparison_data = struct();
comparison_data.Labels = labels;
comparison_data.GridCost = C_grid;
comparison_data.WaitingCost = C_wait;
comparison_data.PVSpillCost = C_spill;
comparison_data.SEB = SEB;
comparison_data.TotalWait_min = total_wait;
comparison_data.ExcessPV_Wh = excess_PV;

save(mat_file, 'comparison_data');

T_summary = table(labels(:), C_grid(:), C_wait(:), C_spill(:), SEB(:), ...
    'VariableNames', {'Label','GridCost_IDR','WaitingCost_IDR','PVSpillCost_IDR','SEB_IDR'});
writetable(T_summary, excel_file, 'Sheet', 'SEB_Summary');

diary off;

% --- Plot SEB Components ---
figure('Name','SEB Comparison','Color','w');
bar_data = [C_grid; C_wait; C_spill]';
bar(bar_data, 'stacked');
xticks(1:num_runs);
xticklabels(labels);
xlabel('Simulation Run');
ylabel('Cost (IDR)');
title('SEB Components per Run');
legend({'Grid Cost','Waiting Cost','PV Spill Cost'}, 'Location','northwest');
grid on;
plot_file1 = fullfile(data_dir, sprintf('SEB_Comparison_%s.png', timestamp));
saveas(gcf, plot_file1);

% --- Plot Grid Usage and BSS SoC ---
time = results_all{1}.time; % assuming all runs same time vector

for i = 1:num_runs
    sim = results_all{i};
    
    % Grid usage over time
    figure('Name',sprintf('Grid Usage - %s', labels{i}),'Color','w');
    plot(time, sim.GridUsage/1000, 'LineWidth', 1.5); % convert Wh → kWh
    xlabel('Time (minutes)');
    ylabel('Grid Usage (kWh)');
    title(sprintf('Grid Usage Over Time - %s', labels{i}));
    grid on;
    plot_file2 = fullfile(data_dir, sprintf('GridUsage_%s_%s.png', labels{i}, timestamp));
    saveas(gcf, plot_file2);

    % BSS SoC over time
    figure('Name',sprintf('BSS SoC - %s', labels{i}),'Color','w');
    plot(time, sim.StorageSoC, 'LineWidth', 1.5);
    xlabel('Time (minutes)');
    ylabel('BSS SoC (0-1)');
    title(sprintf('BSS State of Charge Over Time - %s', labels{i}));
    grid on;
    plot_file3 = fullfile(data_dir, sprintf('BSS_SoC_%s_%s.png', labels{i}, timestamp));
    saveas(gcf, plot_file3);
end

end
