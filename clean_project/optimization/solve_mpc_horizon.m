function I_opt = solve_mpc_horizon(soc_ev, soc_bss, V_nom, pv_forecast, grid_price, deadline, H, config, cap_ev)
%SOLVE_MPC_HORIZON Solve one MPC charging-current optimization over a horizon.
%   I_opt = SOLVE_MPC_HORIZON(soc_ev, soc_bss, V_nom, pv_forecast, grid_price,
%   deadline, H, config, cap_ev) runs fmincon over the prediction horizon H
%   to find the charging current profile that minimizes grid cost, waiting
%   time, and PV spillage (see compute_total_cost.m), subject to the grid
%   import limit (see grid_limit_constraint.m).
%
%   Inputs:
%     soc_ev, soc_bss   - current state of charge for each EV slot / the BSS
%     V_nom             - nominal voltage per EV slot
%     pv_forecast       - forecast PV power over the horizon
%     grid_price        - grid electricity price over the horizon
%     deadline          - swap deadline per EV slot
%     H                 - horizon length (timesteps)
%     config            - simulation config struct (weights, limits, dt, ...)
%     cap_ev            - battery capacity per EV slot
%
%   Output:
%     I_opt - optimized charging current, size [N x H]
%
%   Note: uses a persistent warm-start (last_u) to speed up repeated calls.

    N = length(soc_ev); % number of EV batteries

    % Weights and constants
    w1 = config.w1;
    w2 = config.w2;
    w3 = config.w3;
    dt = config.dt;
    cap_bss = config.BSS.Wh;
    eta_discharge = config.Bidirectional.Efficiency;
    eta_carging = config.Charger.Efficiency;

    % Optimization variable: u = [I(:); P_bss(:)]
    % Size = N*H + H = (N+1)*H
    total_vars = (N + 1) * H;

    % Initial guess (warm-start if available)
    persistent last_u
    if isempty(last_u) || length(last_u) ~= total_vars
        u0 = zeros(total_vars, 1);
    else
        u0 = last_u;
    end

    % Bounds
    I_max = config.max_current;
    P_bss_max = config.BSS.discharge_limit;

    lb = zeros(total_vars, 1);
    ub = [repmat(I_max(:), N * H, 1); repmat(P_bss_max, H, 1)];

    % Cost and constraint functions (vectorized versions)
    cost_fun = @(u) compute_total_cost(u, soc_ev, soc_bss, V_nom, pv_forecast, grid_price, ...
        deadline, H, dt, cap_ev, cap_bss, eta_discharge, eta_carging, w1, w2, w3);

    nonlcon = @(u) grid_limit_constraint(u, V_nom, pv_forecast, H, N, cap_ev, eta_carging, config.grid_power_limit);

    % Solver options
    options = optimoptions('fmincon', ...
        'Display', 'none', ...
        'MaxFunctionEvaluations', 1e5, ...
        'UseParallel', false);

    % Solve
    [u_opt, ~] = fmincon(cost_fun, u0, [], [], [], [], lb, ub, nonlcon, options);

    % Store last solution for warm start
    last_u = u_opt;

    % Unpack result
    I_opt = reshape(u_opt(1:N*H), N, H);
end
