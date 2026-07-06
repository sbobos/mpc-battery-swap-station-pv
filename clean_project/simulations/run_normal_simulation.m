function results = run_normal_simulation(config, BatteryQueue, PV_profile)
%RUN_NORMAL_SIMULATION Baseline swap-station simulation without MPC.
%   results = RUN_NORMAL_SIMULATION(config, BatteryQueue, PV_profile)
%   simulates the swap station using a simple (non-optimized) charging
%   policy. Used as the baseline against which the MPC, AMCCCV, and LP
%   simulations are compared.
%
%   Inputs:
%     config       - simulation config struct (see prep_sim_config.m)
%     BatteryQueue - arriving battery queue
%     PV_profile   - PV generation forecast over the simulation horizon
%
%   Output:
%     results - struct with fields such as TotalCost_IDR, GridUsage,
%               BatteryQueue (post-sim), SlotHistories, ExcessEnergy, ...

%% ================= CONFIGURATION =================
total_minutes = config.total_minutes;
num_slots     = config.num_slots;
reserve_slots = config.reserve_slots;
dt_h          = 1/60;   % 1 minute in hours

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

%% ================= HELPER FUNCTIONS =================
    function P_grid = charging_profile(B)
        % Grid-side electrical power (W)
        if B.Brand == "gesits"
            V_nom = 72;
        else
            V_nom = 60;
        end

        I_max = 2.2;
        V_min = 0.85 * V_nom;
        V_max = 1.20 * V_nom;

        if B.SoC < 0.8
            I = I_max;
            V = V_min + (V_max - V_min) * (B.SoC / 0.8);
        else
            V = V_max;
            I = I_max * (1 - (B.SoC - 0.8) / 0.2);
        end

        P_grid = max(V * max(I,0), 0);   % W
    end

    function B = charge_battery(P_grid, B)
        % Charger inefficiency affects ONLY battery SOC
        if B.Brand == "gesits"
            V = 72; Ah = 20;
        else
            V = 60; Ah = 23;
        end

        Cap_Wh = V * Ah;
        E_into_battery_Wh = P_grid * dt_h * config.Charger.Efficiency;

        B.SoC = min(B.SoC + E_into_battery_Wh / Cap_Wh, 1);
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

    %% ---- Step 2: swaps / insertions ----
    for i = 1:length(BatteryQueue)

        if BatteryQueue(i).AvailableAt > t ...
           || ismember(i, slot_assignment) ...
           || BatteryQueue(i).SoC >= 0.9
            continue;
        end

        swapped = false;

        % Try swap
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

        % Try empty slot
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

    %% ---- Step 3: charging ----
    TotalGridPower_W = 0;

    for n = 1:num_slots
        idx = slot_assignment(n);
        if idx ~= 0
            P = charging_profile(BatteryQueue(idx));   % GRID POWER
            BatteryQueue(idx) = charge_battery(P, BatteryQueue(idx));
            Chargers(n) = BatteryQueue(idx);

            SoC_list(idx) = BatteryQueue(idx).SoC;
            battery_log(idx).SoC_history(t) = BatteryQueue(idx).SoC;
            battery_log(idx).P_history(t)   = P;

            TotalGridPower_W = TotalGridPower_W + P;
        end
    end

    %% ---- Step 4: PV / BSS / Grid balance ----
    E_load_Wh = TotalGridPower_W * dt_h;
    E_PV_Wh   = PV_profile(t) * dt_h;

    surplus = E_PV_Wh - E_load_Wh;

    if surplus >= 0
        % Charge BSS (bidirectional efficiency ONCE)
        E_into_BSS = surplus * config.Bidirectional.Efficiency;
        cap_left   = (1 - BSS.SoC) * config.BSS.Wh;

        if E_into_BSS <= cap_left
            BSS.SoC = BSS.SoC + E_into_BSS / config.BSS.Wh;
        else
            BSS.SoC = 1;
            ExcessEnergy(t) = E_into_BSS - cap_left;
        end

    else
        % Discharge BSS
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

%% ================= FINALIZE LOGS =================
for i = 1:length(BatteryQueue)
    if SoC_list(i) >= 0.9 && isnan(battery_log(i).EndTime)
        battery_log(i).EndTime = total_minutes;
    end
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

%% ================= SANITY CHECK =================
fprintf("Grid energy: %.1f kWh\n", energy_kWh);
fprintf("Total cost:  %.0f IDR\n", total_cost_IDR);

end
