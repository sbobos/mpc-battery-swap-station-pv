function config = prep_sim_config()
%PREP_SIM_CONFIG Build the simulation configuration struct.
%   config = PREP_SIM_CONFIG() returns a struct with all fixed simulation
%   parameters: horizon length, timestep, station/slot/battery sizing,
%   charger and BSS efficiencies, grid pricing, and MPC weight placeholders.
%   Individual runs (see main.m) may override fields such as w1/w2/w3,
%   WeightMode, and ResolutionMode after calling this function.
    config.num_days = 30;
    config.minutes_per_day = 1440;
    config.total_minutes = config.num_days * config.minutes_per_day;

    config.batteries_per_day = 20;
    config.num_slots = 10;
    config.reserve_slots = 3;

    config.BSS.Wh = 2400;
    config.BSS.SoC = 0;
    config.BSS.discharge_limit = 2000;

    config.Regulator.Efficiency = 0.8;
    config.Inverter.Efficiency = 0.8;
    config.Bidirectional.Efficiency = 0.8;
    config.Charger.Efficiency = 10/8;
    config.price_per_kWh_IDR = 1114.7;
    config.max_current = 5;
    config.grid_power_limit = 2000;  % max allowed grid draw in W

    config.UMR = 4482914;
    config.H = 160;
    config.k = 0.5;
    
    config.PV.Area = 2.5;
    config.PV.Efficiency = 0.22;
    config.PV.Number = 3;

    config.prediction_horizon = 15;  % in minutes\
    config.dt = 1;

    config.ResolutionMode = 1;  % 1 = full minute, 2 = PV hourly, 3 = Queue hourly, 4 = both hourly
    config.ResolutionStep = 60; % 60 min per hour, used for grouping

    config.WeightMode = 1;
end
