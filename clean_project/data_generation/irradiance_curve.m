function Irradiance = irradiance_curve(time, save_excel)
%IRRADIANCE_CURVE Generate a synthetic solar irradiance curve.
%   Irradiance = IRRADIANCE_CURVE(time, save_excel) returns a synthetic
%   daily irradiance profile (W/m^2) evaluated at the given time vector
%   (minutes). If save_excel is true, the curve is also written to an
%   Excel file for inspection.
%
%   Inputs:
%     time       - vector of time points in minutes
%     save_excel - (optional, default false) whether to export to Excel
%
%   Output:
%     Irradiance - irradiance value (W/m^2) at each point in time

    if nargin < 2
        save_excel = false;
    end

    t_hours = mod(time / 60, 24);
    day_idx = floor(time / 1440);
    Irradiance = zeros(size(time));

    t_start = 7;
    t_peak_start = 9;
    t_peak_end = 15;
    t_end = 17;

    I_max = 1000;

    rise_idx = (t_hours >= t_start) & (t_hours < t_peak_start);
    rise_t = (t_hours(rise_idx) - t_start) / (t_peak_start - t_start);
    Irradiance(rise_idx) = I_max * (rise_t.^2.5);

    plateau_idx = (t_hours >= t_peak_start) & (t_hours <= t_peak_end);
    Irradiance(plateau_idx) = I_max;

    fall_idx = (t_hours > t_peak_end) & (t_hours <= t_end);
    fall_t = (t_hours(fall_idx) - t_peak_end) / (t_end - t_peak_end);
    Irradiance(fall_idx) = I_max * (1 - fall_t).^2.5;

    unique_days = unique(day_idx);

    for d = unique_days'
        day_mask = (day_idx == d);
        active_mask = day_mask & (t_hours >= t_start) & (t_hours <= t_end);

        t_active = t_hours(active_mask);

        n_knots = 10;
        knot_t = linspace(t_start, t_end, n_knots);
        knot_noise = 0.95 + 0.10 * rand(1, n_knots);
        smooth_noise = interp1(knot_t, knot_noise, t_active, 'pchip');

        Irradiance(active_mask) = Irradiance(active_mask) .* smooth_noise;
    end

    if save_excel
        if ~exist('outputs/data', 'dir')
            mkdir('outputs/data');
        end

        timestamp = datestr(now, 'yyyy-mm-dd_HHMMSS');
        excel_file = fullfile('outputs/data', sprintf('IrradianceCurve_%s.xlsx', timestamp));

        T = table;
        T.Minute = time(:);
        T.Hour = t_hours(:);
        T.Irradiance_Wm2 = Irradiance(:);

        writetable(T, excel_file, 'Sheet', 'IrradianceCurve');
        fprintf('✅ Irradiance curve saved to %s\n', excel_file);
    end
end
