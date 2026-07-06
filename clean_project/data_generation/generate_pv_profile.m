function PV_profile = generate_pv_profile(config)
%GENERATE_PV_PROFILE Build a minute-resolution PV generation profile.
%   PV_profile = GENERATE_PV_PROFILE(config) uses IRRADIANCE_CURVE to build
%   a solar irradiance curve over the simulation period and converts it to
%   a PV power profile using the panel/array parameters in config.
%
%   Input:
%     config - simulation config struct (see prep_sim_config.m)
%
%   Output:
%     PV_profile - PV power output per minute over the simulation period
time = (0:1:config.total_minutes)';
Ir = irradiance_curve(time, true);
PV_profile = Ir .* config.PV.Area .* config.PV.Efficiency * config.Inverter.Efficiency * config.Regulator.Efficiency * config.PV.Number;

f = figure('Visible', 'off');
plot(1:config.total_minutes, Ir(1:config.total_minutes), 'LineWidth', 1.5);
xlabel('Time (minutes)');
ylabel('Irradiance (W/m²)');
title('Solar Irradiance Profile Over Time');
grid on;

exportgraphics(f, 'outputs/plots/SolarIrradianceProfile.pdf', 'ContentType', 'vector');

d = figure('Visible', 'off');
plot(1:1440, Ir(1:1440), 'LineWidth', 1.5);
xlabel('Time (minutes)');
ylabel('Irradiance (W/m²)');
title('Solar Irradiance Profile Over Time (One Day)');
grid on;

exportgraphics(d, 'outputs/plots/SolarIrradianceProfile.pdf', 'ContentType', 'vector', 'Append', true);
close(f);

%bad resolution
% block-average then expand to full resolution
step = config.ResolutionStep;
total_blocks = floor(config.total_minutes / step);
tail = mod(config.total_minutes, step);

reshaped = reshape(Ir(1:total_blocks * step), step, []);
avg_blocks = mean(reshaped, 1);

% Repeat each average to fill back minute resolution
repeated = repelem(avg_blocks, step);

% Handle tail (if minutes not perfectly divisible)
if tail > 0
    tail_block = Ir(end - tail + 1:end);
    tail_avg = mean(tail_block);
    repeated = [repeated, repmat(tail_avg, 1, tail)];
end

pv_forecast = repeated';

% --- Plot bad-resolution profile (prediction simulation) ---
f = figure('Visible', 'off');
plot(1:config.total_minutes, pv_forecast, 'LineWidth', 1.5);
xlabel('Time (minutes)');
ylabel('Irradiance (W/m²)');
title('Simulated PV Forecast (Low Resolution)');
grid on;
exportgraphics(f, 'outputs/plots/SolarIrradianceProfile.pdf', 'ContentType', 'vector', 'Append', true);

d = figure('Visible', 'off');
plot(1:1440, pv_forecast(1:1440), 'LineWidth', 1.5);
xlabel('Time (minutes)');
ylabel('Irradiance (W/m²)');
title('Simulated PV Forecast (Low Resolution, Day One)');
grid on;
exportgraphics(d, 'outputs/plots/SolarIrradianceProfile.pdf', 'ContentType', 'vector', 'Append', true);

close(f);
close(d);

% --- Save profiles to Excel ---
timestamp = datestr(now, 'yyyy-mm-dd_HHMMSS');
excel_file = fullfile('outputs/data', sprintf('PV_Profile_%s.xlsx', timestamp));

T = table;
T.Minute = time(1:config.total_minutes);
T.Irradiance = Ir(1:config.total_minutes);
T.PV_Power = PV_profile(1:config.total_minutes);
T.PV_Power_kW = PV_profile(1:config.total_minutes) / 1000;
T.LowResForecast = pv_forecast(1:config.total_minutes);

writetable(T, excel_file, 'Sheet', 'PV_Profile');

end