function [pv_forecast, deadlines] = prepare_resolution_inputs(t, horizon, PV_profile, BatteryQueue, slot_assignment, brands, config)
%PREPARE_RESOLUTION_INPUTS Build PV forecast & deadlines for one MPC step.
%   [pv_forecast, deadlines] = PREPARE_RESOLUTION_INPUTS(t, horizon,
%   PV_profile, BatteryQueue, slot_assignment, brands, config) prepares the
%   inputs SOLVE_MPC_HORIZON needs for the current timestep, under one of
%   four "resolution modes" (config.ResolutionMode) that control whether
%   the PV forecast is used at full minute resolution or block-averaged,
%   and whether deadlines are expressed in minutes or aligned block indices.
%
%   Inputs:
%     t                - current simulation timestep
%     horizon          - MPC prediction horizon length
%     PV_profile       - full-length PV generation profile
%     BatteryQueue     - battery queue (used to look up swap deadlines)
%     slot_assignment  - which battery (by index) occupies each EV slot
%     brands           - brand assigned to each EV slot
%     config           - simulation config struct (ResolutionMode, ResolutionStep)
%
%   Outputs:
%     pv_forecast - PV forecast over the horizon, at the configured resolution
%     deadlines   - swap deadline (relative to t) for each EV slot
step = config.ResolutionStep;
mode = config.ResolutionMode;

% --- PV Forecast ---
if mode == 1 || mode == 3
    pv_forecast = PV_profile(t : t + horizon - 1);
else
    % block-average then expand to full resolution
    raw_block = PV_profile(t : t + horizon - 1);
    full_blocks = floor(horizon / step);
    tail = mod(horizon, step);

    reshaped = reshape(raw_block(1:full_blocks * step), step, []);
    avg_blocks = mean(reshaped, 1);

    % Repeat each average to fill back minute resolution
    repeated = repelem(avg_blocks, step);

    % Handle tail (if horizon not perfectly divisible)
    if tail > 0
        tail_block = raw_block(end - tail + 1:end);
        tail_avg = mean(tail_block);
        repeated = [repeated, repmat(tail_avg, 1, tail)];
    end

    pv_forecast = repeated';
end
% --- Deadlines ---
deadlines = inf(1, length(slot_assignment));
for n = 1:length(slot_assignment)
    idx = slot_assignment(n);
    if idx == 0
        continue;
    end
    brand = brands(n);
    for q = 1:length(BatteryQueue)
        if BatteryQueue(q).Brand == brand && BatteryQueue(q).AvailableAt > t
            raw_deadline = BatteryQueue(q).AvailableAt;

            if mode == 3 || mode == 4
                % Convert absolute time to aligned hour index relative to aligned_start
                aligned_deadline = floor((raw_deadline - 1) / step);
                aligned_start_block = floor((t - 1) / step);
                dline = aligned_deadline - aligned_start_block;
            else
                dline = raw_deadline - t;
            end

            deadlines(n) = dline;
            break;
        end
    end
end
end
