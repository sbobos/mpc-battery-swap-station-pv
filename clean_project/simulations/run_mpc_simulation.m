function results = run_mpc_simulation(config, BatteryQueue, BatteryQueue_mpc, PV_profile)
%RUN_MPC_SIMULATION Full battery-swap-station simulation using MPC charging.
%   results = RUN_MPC_SIMULATION(config, BatteryQueue, BatteryQueue_mpc, PV_profile)
%   simulates the swap station minute-by-minute: batteries arrive and are
%   swapped into slots, and at each MPC step the charging current for every
%   occupied slot is re-optimized via SOLVE_MPC_HORIZON given a PV forecast
%   and grid price.
%
%   Inputs:
%     config          - simulation config struct (see prep_sim_config.m)
%     BatteryQueue    - ground-truth arriving battery queue
%     BatteryQueue_mpc- battery queue as "seen" by the MPC controller
%                       (may intentionally differ from BatteryQueue to
%                       study forecast/brand-mismatch scenarios)
%     PV_profile      - PV generation forecast over the simulation horizon
%
%   Output:
%     results - struct with fields such as TotalCost_IDR, GridUsage,
%               BatteryQueue (post-sim), SlotHistories, ExcessEnergy, ...

%% ================= CONFIGURATION =================
total_minutes = config.total_minutes;
num_slots     = config.num_slots;
dt_h          = 1/60;

%% ================= INITIALIZATION =================
Chargers = repmat(struct('Brand',"",'SoC',0,'AvailableAt',inf,'WaitingTime',NaN), 1, num_slots);
slot_assignment = zeros(1, num_slots);

SoC_list = [BatteryQueue.SoC];

battery_log = repmat(struct( ...
    'StartTime', nan, ...
    'EndTime', nan, ...
    'SoC_history', nan(1,total_minutes), ...
    'P_history', nan(1,total_minutes)), ...
    1, length(BatteryQueue));

SlotHistories = cell(1, num_slots);
SwapLog = struct('Time', {}, 'Slot', {}, 'BatteryIn', {}, 'BrandIn', {}, 'BatteryOut', {}, 'BrandOut', {});

%% ================= BSS =================
BSS.SoC = 0;
StorageSoC   = zeros(1,total_minutes);
GridUsage_Wh = zeros(1,total_minutes);
ExcessEnergy = zeros(1,total_minutes);

%% ================= BRAND MAPS =================
    function V = BrandVoltage(brand)
        if brand == "gesits"
            V = 72;
        else
            V = 60;
        end
    end

    function Cap = BrandCap(brand)
        if brand == "gesits"
            Cap = 72 * 20;   % Wh
        else
            Cap = 60 * 23;   % Wh
        end
    end

%% ================= INITIAL SLOT LOAD =================
for n = 1:8
    slot_assignment(n) = n;
    Chargers(n) = BatteryQueue(n);
    battery_log(n).StartTime = 1;
    SlotHistories{n} = struct('BatteryID', n, 'StartTime', 1, 'EndTime', []);
end

%% ================= MAIN SIMULATION LOOP =================
for t = 1:total_minutes

    %% ---- Step 1: finalize completed batteries ----
    for n = 1:num_slots
        idx = slot_assignment(n);
        if idx ~= 0 && Chargers(n).SoC >= 0.9 && isnan(battery_log(idx).EndTime)
            battery_log(idx).EndTime = t;
            SlotHistories{n}(end).EndTime = t;
        end
    end

    %% ---- Step 2: swaps / insertions (UNCHANGED) ----
    for i = 1:length(BatteryQueue)

        if BatteryQueue(i).AvailableAt > t ...
           || ismember(i, slot_assignment) ...
           || BatteryQueue(i).SoC >= 0.9
            continue;
        end

        swapped = false;

        for n = 1:num_slots
            idx_out = slot_assignment(n);
            if idx_out ~= 0 ...
               && Chargers(n).SoC >= 0.9 ...
               && BatteryQueue(idx_out).Brand == BatteryQueue(i).Brand

                SwapLog(end+1) = struct( ...
                    'Time', t, 'Slot', n, ...
                    'BatteryIn', i, 'BrandIn', BatteryQueue(i).Brand, ...
                    'BatteryOut', idx_out, 'BrandOut', BatteryQueue(idx_out).Brand);

                slot_assignment(n) = i;
                Chargers(n) = BatteryQueue(i);
                battery_log(i).StartTime = t;
                SlotHistories{n}(end+1) = struct('BatteryID', i, 'StartTime', t, 'EndTime', []);
                BatteryQueue(i).WaitingTime = t - BatteryQueue(i).AvailableAt;
                swapped = true;
                break;
            end
        end

        if ~swapped
            for n = 1:num_slots
                if slot_assignment(n) == 0
                    slot_assignment(n) = i;
                    Chargers(n) = BatteryQueue(i);
                    battery_log(i).StartTime = t;
                    SlotHistories{n}(end+1) = struct('BatteryID', i, 'StartTime', t, 'EndTime', []);
                    BatteryQueue(i).WaitingTime = t - BatteryQueue(i).AvailableAt;
                    break;
                end
            end
        end
    end

    %% ---- Step 3: MPC INPUT PREP ----
    horizon = min(config.prediction_horizon, total_minutes - t + 1);

    current_soc = zeros(num_slots,1);
    V_nom       = zeros(num_slots,1);
    cap_ev      = zeros(num_slots,1);
    deadlines   = inf(num_slots,1);

    for n = 1:num_slots
        idx = slot_assignment(n);
        if idx ~= 0
            current_soc(n) = BatteryQueue(idx).SoC;

            % MPC may see wrong brand on purpose
            brands(n) = BatteryQueue(idx).Brand;
            V_nom(n)  = BrandVoltage(BatteryQueue_mpc(idx).Brand);
            cap_ev(n) = BrandCap(BatteryQueue_mpc(idx).Brand);

        end
    end

    [pv_forecast, deadlines] = prepare_resolution_inputs(t, horizon, PV_profile, BatteryQueue_mpc, slot_assignment, brands, config);
    grid_price  = config.price_per_kWh_IDR * ones(horizon,1);

    I_opt = solve_mpc_horizon( ...
        current_soc, BSS.SoC, V_nom, ...
        pv_forecast, grid_price, deadlines, ...
        horizon, config, cap_ev);

    I_now = I_opt(:,1);

    %% ---- 🚨 PLANT GUARDS (THE FIX) ----
    for n = 1:num_slots
        idx = slot_assignment(n);

        % Empty slot → no current
        if idx == 0
            I_now(n) = 0;
            continue;
        end

        % Battery already done → no current
        if BatteryQueue(idx).SoC == 1
            I_now(n) = 0;
        end

        % Hardware current limit
        I_now(n) = min(I_now(n), config.max_current);
        I_now(n) = max(I_now(n), 0);

        % Numerical safety
        if isnan(I_now(n)) || isinf(I_now(n))
            I_now(n) = 0;
        end
    end

    %% ---- Step 4: charging (IDENTICAL accounting to baseline) ----
    TotalGridPower_W = 0;

    for n = 1:num_slots
        idx = slot_assignment(n);
        if idx ~= 0 && I_now(n) > 0
            P = V_nom(n) * I_now(n);

            BatteryQueue(idx).SoC = min( ...
                BatteryQueue(idx).SoC + ...
                (P * dt_h * config.Charger.Efficiency) / cap_ev(n), ...
                1);

            Chargers(n) = BatteryQueue(idx);
            SoC_list(idx) = BatteryQueue(idx).SoC;
            battery_log(idx).SoC_history(t) = BatteryQueue(idx).SoC;
            battery_log(idx).P_history(t)   = P;

            TotalGridPower_W = TotalGridPower_W + P;
        end
    end

    %% ---- Step 5: PV / BSS / Grid balance (UNCHANGED) ----
    E_load_Wh = TotalGridPower_W * dt_h;
    E_PV_Wh   = PV_profile(t) * dt_h;

    surplus = E_PV_Wh - E_load_Wh;

    if surplus >= 0
        E_into_BSS = surplus * config.Bidirectional.Efficiency;
        cap_left   = (1 - BSS.SoC) * config.BSS.Wh;

        if E_into_BSS <= cap_left
            BSS.SoC = BSS.SoC + E_into_BSS / config.BSS.Wh;
        else
            BSS.SoC = 1;
            ExcessEnergy(t) = E_into_BSS - cap_left;
        end
    else
        deficit = -surplus;
        E_needed = deficit / config.Bidirectional.Efficiency;

        if BSS.SoC * config.BSS.Wh >= E_needed
            BSS.SoC = BSS.SoC - E_needed / config.BSS.Wh;
        else
            GridUsage_Wh(t) = deficit - BSS.SoC * config.BSS.Wh * config.Bidirectional.Efficiency;
            BSS.SoC = 0;
        end
    end

    StorageSoC(t) = BSS.SoC;
end

%% ================= COST =================
energy_kWh = sum(GridUsage_Wh) / 1000;
total_cost_IDR = energy_kWh * config.price_per_kWh_IDR;

%% ================= OUTPUT =================
results.BatteryQueue  = BatteryQueue;
results.GridUsage     = GridUsage_Wh;
results.TotalCost_IDR = total_cost_IDR;
results.battery_log   = battery_log;
results.SlotHistories = SlotHistories;
results.SwapLog       = SwapLog;
results.StorageSoC    = StorageSoC;
results.ExcessEnergy  = ExcessEnergy;
results.time          = 1:total_minutes;

fprintf("MPC Grid energy: %.1f kWh\n", energy_kWh);
fprintf("MPC Total cost:  %.0f IDR\n", total_cost_IDR);

end
