function compare_all_mpc_runs(results_all, labels)
%COMPARE_ALL_MPC_RUNS Compare and plot metrics across multiple simulation runs.
%   COMPARE_ALL_MPC_RUNS(results_all, labels) prints a summary table (grid
%   cost, waiting time, PV spillage, ...) to console and a log file,
%   generates comparison plots (grid usage, cumulative cost, SoC, waiting
%   time, per-slot charging history), and exports everything to an Excel
%   workbook and .mat file under outputs/.
%
%   Inputs:
%     results_all - cell array of result structs, one per run (element 1
%                   is treated as the baseline)
%     labels      - cell array of display names, one per run

output_dir = 'outputs/logs';
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

run_mode = length(labels);

if run_mode == 8
    logfile = fullfile(output_dir, 'Compare_MPC_Text_Summary.txt');
elseif run_mode == 5
    logfile = fullfile(output_dir, 'Compare_Resolution_Text_Summary.txt');
else
    if strcmpi(labels{2}, 'peak')
        logfile = fullfile(output_dir, 'Compare_Extreme_Peak_Text_Summary.txt');
    elseif strcmpi(labels{2}, 'rare')
        logfile = fullfile(output_dir, 'Compare_Extreme_Rare_Text_Summary.txt');
    end
end

if exist(logfile, 'file')
    delete(logfile);
end

diary(logfile);
diary on;

baseline = results_all{1};  % first run is the baseline
num_runs = numel(results_all);

% Preallocate arrays
costs = zeros(1, num_runs);
avg_waits_nonzero = zeros(1, num_runs);
avg_waits = zeros(1, num_runs);
zero_waits = zeros(1, num_runs);
untouched = zeros(1, num_runs);
score = zeros(1, num_runs);
total_PV_gen = zeros(1, num_runs);
excess_PV = zeros(1, num_runs);

for i = 1:num_runs
    sim = results_all{i};
    waits = [sim.BatteryQueue.WaitingTime];

    costs(i) = sim.TotalCost_IDR;
    avg_waits(i) = mean(waits(~isnan(waits)));
    avg_waits_nonzero(i) = mean(waits(waits > 0 & ~isnan(waits)));
    zero_waits(i) = sum(waits == 0);
    untouched(i) = sum(isnan(waits)) - 8;

    score(i) = compute_score(zero_waits(i), costs(i), avg_waits(i));
    
    excess_PV(i) = sum(sim.ExcessEnergy, 'omitnan');
end

base_cost = costs(1);
base_score = score(1);

fprintf('\n=== Multi-MPC Simulation Summary ===\n');
fprintf('Run | Grid Cost (IDR) | Avg Wait | Avg Wait (>0) | Zero-Wait | Untouched | Saved (%%) | Excess PV (W)\n');
fprintf('----|-----------------|----------|---------------|-----------|-----------|-----------|--------------\n');
for i = 1:num_runs
    fprintf('%3d | %15.2f | %8.2f | %13.2f | %9d | %9d | %8.2f%% | %13.2f\n', ...
        i, costs(i), avg_waits(i), avg_waits_nonzero(i), zero_waits(i), untouched(i), ...
        100 * (base_cost - costs(i)) / base_cost, ...
        excess_PV(i));
end

% === Select Best Run
[~, best_run] = max(score(2:end));
best_run = best_run + 1;  % Offset due to baseline being index 1
fprintf('\nAuto-comparing best run (Run #%d) to baseline...\n', best_run);

compare_detailed(baseline, results_all{best_run}, best_run);

diary off;

% === Keep Plot Section for PDF Charts ===
plot_dir = 'outputs/plots';
if run_mode == 8
    output_pdf = fullfile(plot_dir, 'Compare_MPC_Report.pdf');
elseif run_mode == 5
    output_pdf = fullfile(plot_dir, 'Compare_Resolution_Report.pdf');
else
    if strcmpi(labels{2}, 'peak')
        output_pdf = fullfile(output_dir, 'Compare_Extreme_Peak_Report.pdf');
    elseif strcmpi(labels{2}, 'rare')
        output_pdf = fullfile(output_dir, 'Compare_Extreme_Rare_Report.pdf');
    end

end

if exist(output_pdf, 'file')
    delete(output_pdf);
end

if ~exist(plot_dir, 'dir')
    mkdir(plot_dir);
end

n = length(results_all);
total_minutes = length(results_all{1}.GridUsage);  % assumes all runs are same length

%% 1. Grid Usage Comparison
figure;
hold on;
for i = 1:n
    plot(1:total_minutes, results_all{i}.GridUsage, 'LineWidth', 1.5);
end
legend(labels);
title('Grid Usage Over Time');
xlabel('Time (min)');
ylabel('Power (W)');
grid on;
exportgraphics(gcf, output_pdf, 'Append', true);

%% 2. Cumulative Grid Cost
fprintf('\n=== Grid Cost Comparison ===\n');
for i = 1:n
    fprintf('%-12s : IDR %.2f\n', labels{i}, results_all{i}.TotalCost_IDR);
end

% Optional: compare savings vs the first one
base_cost = results_all{i}.TotalCost_IDR;
for i = 2:n
    saved = base_cost - results_all{i}.TotalCost_IDR;
    perc = 100 * saved / base_cost;
    fprintf('Saved vs %s : IDR %.2f (%.2f%%)\n', labels{i}, saved, perc);
end
exportgraphics(gcf, output_pdf, 'Append', true);

%% 3. Storage SoC Comparison
figure;
hold on;
for i = 1:n
    plot(1:total_minutes, results_all{i}.StorageSoC, 'LineWidth', 1.5);
end
legend(labels);
title('Storage Battery State of Charge');
xlabel('Time (min)');
ylabel('SoC');
grid on;
exportgraphics(gcf, output_pdf, 'Append', true);

%% 4. Battery Waiting Time Comparison
all_waits = cell(n, 1);
all_final_soc = cell(n, 1);
zero_waits = zeros(n, 1);
nonzero_counts = zeros(n, 1);
untouched = zeros(n, 1);
avg_wait_all = zeros(n, 1);
avg_wait_nonzero = zeros(n, 1);

uncharged_threshold = 0.5;

for i = 1:n
    waits = [results_all{i}.BatteryQueue.WaitingTime];
    socs = [results_all{i}.BatteryQueue.SoC];

    all_waits{i} = waits;
    all_final_soc{i} = socs;

    zero_waits(i) = sum(waits == 0);
    nonzero = waits(waits > 0 & ~isnan(waits));
    nonzero_counts(i) = numel(nonzero);
    untouched(i) = sum(socs < uncharged_threshold);

    avg_wait_all(i) = mean(waits(~isnan(waits)));
    avg_wait_nonzero(i) = mean(nonzero);
end

% --- Boxplot ---
figure;
waits_mat = padcat(all_waits{:});  % Pad with NaNs for uneven lengths
boxplot(waits_mat, 'Labels', labels);
ylabel('Waiting Time (minutes)');
title('Battery Waiting Time Distribution');
grid on;
exportgraphics(gcf, output_pdf, 'Append', true);

%%Detailed plot
day_minutes = 1440; % 1 day in minutes
start_day   = 1;    % starting minute index for the day you want
end_day     = start_day + day_minutes - 1;

figure;
for n = 1:10
    subplot(5,2,n);
    hold on; grid on;
    title(sprintf('Slot %d Charging History', n));
    xlabel('Time (minutes)');
    ylabel('SoC');
    ylim([0 1]);
    xlim([0 day_minutes]);

    % === Baseline ===
    SlotHistories1 = results_all{1}.SlotHistories;
    BatteryLog1    = results_all{1}.battery_log;
    Queue1         = results_all{1}.BatteryQueue;

    if ~isempty(SlotHistories1{n})
        for k = 1:length(SlotHistories1{n})
            entry = SlotHistories1{n}(k);
            startT = entry.StartTime;
            endT   = entry.EndTime;
            if isempty(startT) || isempty(endT) || isnan(startT) || isnan(endT)
                continue;
            end
            % Trim to 1 day window
            if endT < start_day || startT > end_day 
                continue;
            end
            startT = max(start_day, startT) - start_day + 1;
            endT   = min(end_day, endT) - start_day + 1;
            hist   = BatteryLog1(entry.BatteryID).SoC_history;
            hist   = hist(start_day:end_day);
            plot(startT:endT, hist(startT:endT), 'LineWidth', 1.5, ...
                'DisplayName', 'Baseline');
        end
    end

    % === Best Run ===
    SlotHistories2 = results_all{best_run}.SlotHistories;
    BatteryLog2    = results_all{best_run}.battery_log;
    Queue2         = results_all{best_run}.BatteryQueue;

    if ~isempty(SlotHistories2{n})
        for k = 1:length(SlotHistories2{n})
            entry = SlotHistories2{n}(k);
            startT = entry.StartTime;
            endT   = entry.EndTime;
            if isempty(startT) || isempty(endT) || isnan(startT) || isnan(endT)
                continue;
            end
            % Trim to 1 day window
            if endT < start_day || startT > end_day
                continue;
            end
            startT = max(start_day, startT) - start_day + 1;
            endT   = min(end_day, endT) - start_day + 1;
            hist   = BatteryLog2(entry.BatteryID).SoC_history;
            hist   = hist(start_day:end_day);
            plot(startT:endT, hist(startT:endT), '--', 'LineWidth', 1.5, ...
                'DisplayName', 'Best Run');
        end
    end

    legend('show');
end
exportgraphics(gcf, output_pdf, 'Append', true);

%% === Save Data for Analysis ===
timestamp = datestr(now, 'yyyy-mm-dd_HHMMSS');

data_dir = 'outputs/data';
if ~exist(data_dir, 'dir')
    mkdir(data_dir);
end

if run_mode == 8
    mat_file = fullfile(data_dir, sprintf('Compare_MPC_Data_%s.mat', timestamp));
    excel_file = fullfile(data_dir, sprintf('Compare_MPC_Data_%s.xlsx', timestamp));
elseif run_mode == 5
    mat_file = fullfile(data_dir, sprintf('Compare_Resolution_Data_%s.mat', timestamp));
    excel_file = fullfile(data_dir, sprintf('Compare_Resolution_Data_%s.xlsx', timestamp));

else
    if strcmpi(labels{2}, 'peak')
        mat_file = fullfile(data_dir, sprintf('Compare_Extreme_Peak_Data_%s.mat', timestamp));
        excel_file = fullfile(data_dir, sprintf('Compare_Extreme_Peak_Data_%s.xlsx', timestamp));
    elseif strcmpi(labels{2}, 'rare')
        mat_file = fullfile(data_dir, sprintf('Compare_Extreme_Rare_Data_%s.mat', timestamp));
        excel_file = fullfile(data_dir, sprintf('Compare_Extreme_Rare_Data_%s.xlsx', timestamp));
    end

end

% === Create structured data for saving ===
comparison_data = struct();
comparison_data.Labels = labels;
comparison_data.Costs = costs;
comparison_data.AvgWaitAll = avg_wait_all;
comparison_data.AvgWaitNonzero = avg_wait_nonzero;
comparison_data.ZeroWaits = zero_waits;
comparison_data.Untouched = untouched;
comparison_data.Score = score;

% Save grid, power, and SoC data
comparison_data.Time = (1:total_minutes)';
comparison_data.Labels = labels;
comparison_data.GridUsage = cell2mat(arrayfun(@(x) results_all{x}.GridUsage(:), 1:num_runs, 'UniformOutput', false)');
comparison_data.StorageSoC = cell2mat(arrayfun(@(x) results_all{x}.StorageSoC(:), 1:num_runs, 'UniformOutput', false)');

comparison_data.TotalPVGen = total_PV_gen;
comparison_data.ExcessPV = excess_PV;

% === Save as .mat file ===
save(mat_file, 'comparison_data');

% === Convert to Excel Tables ===
% 1. Summary table
T_summary = table(labels(:), costs(:), avg_wait_all(:), avg_wait_nonzero(:), ...
    zero_waits(:), untouched(:), score(:), total_PV_gen(:), excess_PV(:), ...
    'VariableNames', {'Label','GridCost_IDR','AvgWait_All','AvgWait_GT0','ZeroWaits','Untouched','Score','TotalPVGen_Wh','ExcessPV_Wh'});
writetable(T_summary, excel_file, 'Sheet', 'Summary');

% 2. Power and SoC per time step
time_col = (1:total_minutes)';
T_grid = table(time_col, 'VariableNames', {'Time_min'});
T_soc = table(time_col, 'VariableNames', {'Time_min'});

for i = 1:num_runs
    T_grid = addvars(T_grid, results_all{i}.GridUsage(:), 'NewVariableNames', labels{i});
    T_soc = addvars(T_soc, results_all{i}.StorageSoC(:), 'NewVariableNames', labels{i});
end

writetable(T_grid, excel_file, 'Sheet', 'GridUsage');
writetable(T_soc, excel_file, 'Sheet', 'StorageSoC');

% 3. Waiting time distributions
max_len = max(cellfun(@numel, all_waits));
waits_mat = NaN(max_len, num_runs);
for i = 1:num_runs
    waits_mat(1:numel(all_waits{i}), i) = all_waits{i};
end
T_waits = array2table(waits_mat, 'VariableNames', labels);
writetable(T_waits, excel_file, 'Sheet', 'WaitingTimes');

fprintf('\n=== Data Saved for Analysis ===\n');
fprintf('  MAT File : %s\n', mat_file);
fprintf('  Excel    : %s\n', excel_file);
end

function score = compute_score(zero_waits, cost, wait_avg)
if cost == 0 || wait_avg == 0
    score = 0;
else
    score = zero_waits / (cost * wait_avg);
end
end

function compare_detailed(results_normal, results_mpc, run_index)
total_minutes = length(results_normal.GridUsage);

fprintf('\n=== Grid Cost Comparison ===\n');
cost_n = results_normal.TotalCost_IDR;
cost_m = results_mpc.TotalCost_IDR;
fprintf('Baseline      : IDR %.2f\n', cost_n);
fprintf('MPC Run #%d   : IDR %.2f\n', run_index, cost_m);
fprintf('Saved         : IDR %.2f (%.2f%%)\n', ...
    cost_n - cost_m, 100*(cost_n - cost_m)/cost_n);

% Battery Waiting Time Stats
waits_normal = [results_normal.BatteryQueue.WaitingTime];
waits_mpc = [results_mpc.BatteryQueue.WaitingTime];
socs_normal = [results_normal.BatteryQueue.SoC];
socs_mpc = [results_mpc.BatteryQueue.SoC];
uncharged_threshold = 0.5;

zero_waits_normal = sum(waits_normal == 0);
zero_waits_mpc = sum(waits_mpc == 0);
untouched_normal = sum(socs_normal < uncharged_threshold);
untouched_mpc = sum(socs_mpc < uncharged_threshold);

nonzero_waits_normal = waits_normal(waits_normal > 0 & ~isnan(waits_normal));
nonzero_waits_mpc = waits_mpc(waits_mpc > 0 & ~isnan(waits_mpc));

avg_all_normal = mean(waits_normal(~isnan(waits_normal)));
avg_all_mpc = mean(waits_mpc(~isnan(waits_mpc)));
avg_nonzero_normal = mean(nonzero_waits_normal);
avg_nonzero_mpc = mean(nonzero_waits_mpc);

fprintf('\n=== Battery Waiting Time Comparison ===\n');
fprintf('Zero-wait Batteries       | Baseline: %d   | MPC #%d: %d\n', ...
    zero_waits_normal, run_index, zero_waits_mpc);
fprintf('Untouched Batteries (<%.0f%% SoC) | Baseline: %d   | MPC #%d: %d\n', ...
    uncharged_threshold*100, untouched_normal, run_index, untouched_mpc);
fprintf('Average Wait (All)        | Baseline: %.2f min   | MPC: %.2f min\n', ...
    avg_all_normal, avg_all_mpc);
fprintf('Average Wait (Only >0)    | Baseline: %.2f min   | MPC: %.2f min\n', ...
    avg_nonzero_normal, avg_nonzero_mpc);
fprintf('Improvement (All)         : %.2f%%\n', ...
    100 * (avg_all_normal - avg_all_mpc) / avg_all_normal);
end

function out = padcat(varargin)
    lens = cellfun(@length, varargin);
    maxlen = max(lens);
    out = NaN(maxlen, numel(varargin));
    for k = 1:numel(varargin)
        out(1:lens(k),k) = varargin{k};
    end
end