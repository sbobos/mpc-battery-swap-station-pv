function J = compute_total_cost(u, soc_ev_0, soc_bss_0, V_nom, pv, price, deadline, H, dt, cap_ev, cap_bss, eta_discharging, eta_carging, w1, w2, w3)
%COMPUTE_TOTAL_COST MPC objective function (used as fmincon's cost_fun).
%   J = COMPUTE_TOTAL_COST(u, soc_ev_0, soc_bss_0, V_nom, pv, price,
%   deadline, H, dt, cap_ev, cap_bss, eta_discharging, eta_carging, w1, w2, w3)
%   simulates the EV/BSS state of charge forward under decision vector u
%   and returns the weighted sum of grid cost, unmet-deadline penalty, and
%   PV-spillage penalty:
%     J = w1 * (grid cost) + w2 * (deadline violation) + w3 * (PV spillage)
%
%   Inputs:
%     u                - decision vector [I(:); P_bss(:)] to be optimized
%     soc_ev_0, soc_bss_0 - initial SoC for EV slots / BSS
%     V_nom            - nominal voltage per EV slot
%     pv               - PV forecast over the horizon
%     price            - grid price over the horizon
%     deadline         - swap deadline per EV slot
%     H                - horizon length (timesteps)
%     dt               - timestep duration (hours)
%     cap_ev, cap_bss  - battery capacities (EV slots, BSS)
%     eta_discharging, eta_carging - BSS discharge / charger efficiencies
%     w1, w2, w3       - cost/penalty weights
%
%   Output:
%     J - scalar cost value

if any(isnan(u)) || any(isinf(u))
    J = 1e10;
    return;
end

N = length(soc_ev_0);

% ---- Unpack decision variables ----
try
    I     = reshape(u(1:N*H), N, H);
    P_bss = u(N*H+1:end);
catch
    J = 1e10;
    return;
end

% ---- States ----
soc_ev  = zeros(N, H+1);
soc_bss = zeros(1, H+1);

soc_ev(:,1)  = soc_ev_0(:);
soc_bss(1)   = soc_bss_0;

cost = 0;

for t = 1:H

    %% ===== EV SOC UPDATE (FIXED LINE) =====
    soc_ev(:,t+1) = soc_ev(:,t) + ...
        (V_nom .* I(:,t)) .* dt ./ cap_ev;

    soc_ev(:,t+1) = min(max(soc_ev(:,t+1), 0), 1);

    %% ===== BSS SOC =====
    soc_bss(t+1) = soc_bss(t) - (P_bss(t) / eta_discharging) * dt / cap_bss;

    if soc_bss(t+1) < 0
        cost = cost + 1e6 * abs(soc_bss(t+1));
        soc_bss(t+1) = 0;
    elseif soc_bss(t+1) > 1
        soc_bss(t+1) = 1;
    end

    %% ===== GRID IMPORT =====
    ev_power = sum(V_nom .* I(:,t)) * eta_carging;
    grid_import = ev_power - pv(t) - P_bss(t);

    cost = cost + w1 * max(0, grid_import) * price(t) / 1000;

    %% ===== SOC TARGET PENALTIES =====
    for b = 1:N
        soc_gap = max(0, 0.9 - soc_ev(b,t+1))^2;
        cost = cost + w2 * soc_gap;

        if t == deadline(b) && soc_ev(b,t+1) < 0.9
            cost = cost + w3 * 1e6;
        end
    end
end

if sum(I(:)) < 1e-3
    cost = cost + 1e6;
end

if isnan(cost) || isinf(cost)
    J = 1e10;
else
    J = cost;
end

end
