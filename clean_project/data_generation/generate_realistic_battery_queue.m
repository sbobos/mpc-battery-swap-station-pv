function BatteryQueue = generate_realistic_battery_queue(config)
%GENERATE_REALISTIC_BATTERY_QUEUE Simulate a realistic battery arrival queue.
%   BatteryQueue = GENERATE_REALISTIC_BATTERY_QUEUE(config) generates a
%   struct array of arriving batteries (brand, arrival time, initial SoC,
%   etc.) across config.num_days days, including an initial set of
%   batteries already occupying slots at t = 0.
%
%   Input:
%     config - simulation config struct (see prep_sim_config.m)
%
%   Output:
%     BatteryQueue - struct array, one entry per battery arrival
num_days = config.num_days;
batteries_per_day = config.batteries_per_day;
% (then same as your current implementation…)
% Hourly total demand from chart (approximate sum of both battery types)
hourly_demand = [0 0 0 0 0 0 0 1 5 57 18 36 2 36 44 26 32 19 46 4 0 0 0 0];

% Normalize to probabilities
prob_per_hour = hourly_demand / sum(hourly_demand);

% Weighted brand list (original setup)
weighted_brands = ["gesits", "gesits", "gesits", "gesits", "viar", "viar", "volta", "volta"];

% Preallocate total number of batteries
total_bat = 8 + (batteries_per_day * num_days);
BatteryQueue = repmat(struct('Brand', "", 'SoC', 0, 'AvailableAt', 0, 'WaitingTime', NaN), 1, total_bat);

% --- Initial 8 slots ---
initial_brands = ["gesits", "gesits", "gesits", "gesits", "viar", "viar", "volta", "volta"];
initial_soc = rand(1, 8) * 0.1 + 0.9;

for i = 1:8
    BatteryQueue(i).Brand = initial_brands(i);
    BatteryQueue(i).SoC = round(initial_soc(i), 2);
    BatteryQueue(i).AvailableAt = 0;
    BatteryQueue(i).WaitingTime = NaN;
end

% --- Generate arrivals for each day ---
i = 9;
for day = 1:num_days
    base_time = (day - 1) * 1440; % minutes since simulation start

    % Sample hours for arrivals based on hourly demand probabilities
    hours_sampled = randsample(1:24, batteries_per_day, true, prob_per_hour);

    for b = 1:batteries_per_day
        hr = hours_sampled(b);
        minute_offset = randi([0, 59]); % random minute within the hour
        time = base_time + (hr - 1) * 60 + minute_offset;

        % Assign brand weighted by your original list
        brand = weighted_brands(randi(length(weighted_brands)));
        soc = round(rand() * 0.5 + 0.1, 2); % Random SoC between 0.1 and 0.6

        BatteryQueue(i).Brand = brand;
        BatteryQueue(i).SoC = soc;
        BatteryQueue(i).AvailableAt = time;
        BatteryQueue(i).WaitingTime = NaN;

        i = i + 1;
    end
end

% Sort by AvailableAt time
[~, idx] = sort([BatteryQueue.AvailableAt]);
BatteryQueue = BatteryQueue(idx);

% Extract arrival times and brands
arrival_times = [BatteryQueue.AvailableAt];
arrival_hours = floor(arrival_times / 60);
arrival_brands = string({BatteryQueue.Brand});

% Define unique brands and initialize counts
brands = unique(arrival_brands);
hours_range = 0:24*num_days-1;
brand_counts = zeros(length(brands), length(hours_range));

% Count arrivals per brand per hour
for b = 1:length(brands)
    for h = hours_range
        brand_counts(b, h+1) = sum((arrival_hours == h) & (arrival_brands == brands(b)));
    end
end

% Create figure (but don't show it if you're running many plots)
f = figure('Visible', 'off');
bar(hours_range, brand_counts', 'stacked');
xlabel('Hour of Simulation');
ylabel('Number of Batteries Arriving');
title('Hourly Battery Arrival Demand by Brand');
legend(brands, 'Location', 'northwest');
grid on;

% Save figure to PDF
exportgraphics(f, 'outputs/plots/BatteryArrivalProfile.pdf', 'ContentType', 'vector');

% Close figure to free memory
close(f);

% --- Save BatteryQueue to Excel for analysis ---
if ~exist('outputs/data', 'dir')
    mkdir('outputs/data');
end

timestamp = datestr(now, 'yyyy-mm-dd_HHMMSS');
excel_file = fullfile('outputs/data', sprintf('BatteryQueue_%s.xlsx', timestamp));

% Convert struct to table
T = struct2table(BatteryQueue);

% Add human-readable time columns
T.Hour = floor(T.AvailableAt / 60);
T.Day = floor(T.AvailableAt / 1440) + 1;
T.MinuteOfDay = mod(T.AvailableAt, 1440);
T.Time_HHMM = string(duration(0, T.MinuteOfDay, 0, 'Format','hh:mm'));

% Save main queue data
writetable(T, excel_file, 'Sheet', 'BatteryQueue');

% Save hourly demand by brand
T_demand = array2table(brand_counts', 'VariableNames', cellstr(brands));
T_demand.Hour = hours_range';
writetable(T_demand, excel_file, 'Sheet', 'HourlyDemand');

end