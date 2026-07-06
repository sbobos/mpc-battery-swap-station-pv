function BatteryQueue_mod = apply_extreme_arrival_case(BatteryQueue, mode, config, disturbed_days)
%APPLY_EXTREME_ARRIVAL_CASE Inject extreme arrival scenarios on given days.
%   BatteryQueue_mod = APPLY_EXTREME_ARRIVAL_CASE(BatteryQueue, mode, config,
%   disturbed_days) modifies a copy of BatteryQueue to stress-test the
%   station on specific days.
%
%   Inputs:
%     BatteryQueue   - baseline battery arrival queue
%     mode           - 'peak_cluster' (many arrivals at the same time) or
%                      'rare_focus' (arrivals concentrated in rare hours)
%     config         - simulation config struct (see prep_sim_config.m)
%     disturbed_days - (optional) vector of days to modify, e.g. [5 10 15].
%                      If omitted, 3 random days are chosen automatically.
%
%   Output:
%     BatteryQueue_mod - modified battery queue with the scenario applied

    BatteryQueue_mod = BatteryQueue;

    % Extract info
    times = [BatteryQueue.AvailableAt];
    num_batt = length(BatteryQueue);
    num_days = config.num_days;

    % Determine which days to modify
    if nargin < 4 || isempty(disturbed_days)
        disturbed_days = randperm(num_days, min(3, num_days));  % random 3 days
    end

    fprintf('⚠️ Extreme case "%s" applied on days: %s\n', mode, num2str(disturbed_days));

    % Track which batteries are modified
    modified_idx = [];

    for d = disturbed_days
        % Get time window for that day (in minutes)
        day_start = (d - 1) * 1440;
        day_end = day_start + 1440;

        % Index of batteries arriving that day
        idx_day = find(times >= day_start & times < day_end);

        switch lower(mode)
            case 'peak_cluster'
                % Cluster 40% of arrivals within a 10-minute window
                if isempty(idx_day), continue; end
                n_mod = round(0.4 * numel(idx_day));
                cluster_idx = idx_day(randperm(numel(idx_day), n_mod));

                cluster_hour = randi([8, 16]); % 8 AM–4 PM
                cluster_base = day_start + (cluster_hour - 1) * 60;

                for i = cluster_idx
                    BatteryQueue_mod(i).AvailableAt = cluster_base + randi([0, 10]);
                end
                modified_idx = [modified_idx cluster_idx];

            case 'rare_focus'
                % Move 40% of arrivals to rare hours
                if isempty(idx_day), continue; end
                n_mod = round(0.4 * numel(idx_day));
                rare_idx = idx_day(randperm(numel(idx_day), n_mod));

                rare_hours = [1 2 3 4 5 22 23 24];
                for i = rare_idx
                    hr = rare_hours(randi(length(rare_hours)));
                    BatteryQueue_mod(i).AvailableAt = day_start + (hr - 1) * 60 + randi([0, 59]);
                end
                modified_idx = [modified_idx rare_idx];

            otherwise
                warning('Unknown extreme arrival mode: %s', mode);
        end
    end

    % Resort by time (important for simulation)
    [~, idx] = sort([BatteryQueue_mod.AvailableAt]);
    BatteryQueue_mod = BatteryQueue_mod(idx);

    % --- Save Excel Output ---
    if ~exist('outputs/data', 'dir')
        mkdir('outputs/data');
    end

    timestamp = datestr(now, 'yyyy-mm-dd_HHMMSS');
    excel_file = fullfile('outputs/data', sprintf('BatteryQueue_Extreme_%s_%s.xlsx', mode, timestamp));

    % Convert struct to table
    T_original = struct2table(BatteryQueue);
    T_mod = struct2table(BatteryQueue_mod);

    % Add human-readable time columns
    for T = {T_original, T_mod}
        TT = T{1};
        TT.Hour = floor(TT.AvailableAt / 60);
        TT.Day = floor(TT.AvailableAt / 1440) + 1;
        TT.MinuteOfDay = mod(TT.AvailableAt, 1440);
        TT.Time_HHMM = string(duration(0, TT.MinuteOfDay, 0, 'Format','hh:mm'));
        T{1} = TT;
    end

    % Save to Excel
    writetable(T_original, excel_file, 'Sheet', 'Original');
    writetable(T_mod, excel_file, 'Sheet', 'Modified');

    % Comparison summary
    diff_table = table((1:num_batt)', ...
                       string({BatteryQueue.Brand})', ...
                       [BatteryQueue.AvailableAt]', ...
                       [BatteryQueue_mod.AvailableAt]', ...
                       'VariableNames', {'Index', 'Brand', 'OldTime', 'NewTime'});
    diff_table.DeltaMin = diff_table.NewTime - diff_table.OldTime;
    diff_table.Modified = ismember((1:height(diff_table))', modified_idx(:));

    writetable(diff_table, excel_file, 'Sheet', 'Difference');

    fprintf('📘 Extreme arrival case saved to: %s\n', excel_file);
end
