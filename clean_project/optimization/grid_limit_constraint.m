function [c, ceq] = grid_limit_constraint(u, V_nom, pv, H, N, cap_ev, eta_carging, grid_limit)
%GRID_LIMIT_CONSTRAINT Nonlinear constraint: grid import must stay under limit.
%   [c, ceq] = GRID_LIMIT_CONSTRAINT(u, V_nom, pv, H, N, cap_ev, eta_carging,
%   grid_limit) is passed to fmincon as the nonlcon function for
%   SOLVE_MPC_HORIZON. It computes grid import at each timestep (EV charging
%   power minus PV generation minus BSS discharge) and returns it as the
%   inequality constraint c <= 0 (grid_import - grid_limit <= 0).
%
%   Inputs:
%     u            - decision vector [I(:); P_bss(:)]
%     V_nom        - nominal voltage per EV slot
%     pv           - PV forecast over the horizon
%     H            - horizon length (timesteps)
%     N            - number of EV slots
%     cap_ev       - battery capacity per EV slot (unused directly here)
%     eta_carging  - charger efficiency
%     grid_limit   - maximum allowed grid import power
%
%   Outputs:
%     c   - inequality constraint values (grid_import - grid_limit), c <= 0
%     ceq - equality constraints (none, always empty)
    I = reshape(u(1:N*H), N, H);
    P_bss = u(N*H+1:end);
    ev_power = sum(V_nom .* I * eta_carging, 1);     % 1×H
    grid_import = ev_power - pv(:)' - P_bss';        % 1×H
    c = grid_import' - grid_limit;                   % c ≤ 0
    ceq = [];
end
