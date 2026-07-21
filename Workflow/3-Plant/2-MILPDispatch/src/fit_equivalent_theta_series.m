function theta = fit_equivalent_theta_series(Pmodule_MW, P_available_MW, cfg, theta_grid)
%FIT_EQUIVALENT_THETA_SERIES Fit theta-rule equivalents to MILP schedules.
%
% For each time step, the module loading vector from MILP is compared with
% theta-rule loading vectors at candidate theta values. The best-fit theta
% is a compact descriptor of the loading concentration induced by MILP.

if nargin < 3 || isempty(cfg)
    cfg = plant_case_config();
end
if nargin < 4 || isempty(theta_grid)
    theta_grid = 0:0.01:1;
end

Pmodule_MW = max(double(Pmodule_MW), 0);
P_available_MW = double(P_available_MW(:));
n_steps = size(Pmodule_MW, 1);
n_modules = size(Pmodule_MW, 2);
Pmax = cfg.module_rating_MW;

if numel(P_available_MW) ~= n_steps
    error('P_available length (%d) does not match schedule steps (%d).', numel(P_available_MW), n_steps);
end

theta_value = zeros(n_steps, 1);
fit_rmse_MW = zeros(n_steps, 1);
active_modules = sum(Pmodule_MW > 1e-9, 2);
used_power_MW = sum(Pmodule_MW, 2);
loading_gini = zeros(n_steps, 1);

target_sorted = sort(Pmodule_MW, 2, 'descend');

for t = 1:n_steps
    P = min(P_available_MW(t), n_modules * Pmax);
    target = target_sorted(t, :);
    best_err = inf;
    best_theta = theta_grid(1);
    for k = 1:numel(theta_grid)
        candidate = theta_rule_single_step(P, theta_grid(k), n_modules, Pmax);
        err = sqrt(mean((target - candidate) .^ 2));
        if err < best_err
            best_err = err;
            best_theta = theta_grid(k);
        end
    end
    theta_value(t) = best_theta;
    fit_rmse_MW(t) = best_err;
    loading_gini(t) = gini_coefficient(Pmodule_MW(t, :));
end

steps_per_day = round(24 / cfg.delta_t_hour);
day_id = ceil((1:n_steps)' / steps_per_day);
step_in_day = mod((1:n_steps)' - 1, steps_per_day) + 1;

theta = table((1:n_steps)', day_id, step_in_day, P_available_MW, used_power_MW, ...
    theta_value, fit_rmse_MW, active_modules, loading_gini, ...
    'VariableNames', {'step_id', 'day_id', 'step_in_day', 'P_available_MW', ...
    'P_used_MW', 'equivalent_theta', 'theta_fit_rmse_MW', ...
    'active_modules', 'loading_gini'});
end

function p = theta_rule_single_step(P, theta, n_modules, Pmax)
Pbase = theta * Pmax;
p = zeros(1, n_modules);
remaining = P;

if Pbase <= 1e-12
    p(:) = min(P, n_modules * Pmax) / n_modules;
    p = sort(p, 'descend');
    return;
end

for m = 1:n_modules
    if remaining >= Pbase
        p(m) = Pbase;
        remaining = remaining - Pbase;
    else
        p(m) = remaining;
        remaining = 0;
        break;
    end
end

if remaining > 0
    room = max(Pmax - p, 0);
    total_room = sum(room);
    if total_room > 0
        p = p + remaining * room / total_room;
    end
end
p = sort(min(max(p, 0), Pmax), 'descend');
end

function g = gini_coefficient(x)
x = sort(max(x(:), 0));
if all(x == 0)
    g = 0;
    return;
end
n = numel(x);
g = (2 * (1:n) * x) / (n * sum(x)) - (n + 1) / n;
end
