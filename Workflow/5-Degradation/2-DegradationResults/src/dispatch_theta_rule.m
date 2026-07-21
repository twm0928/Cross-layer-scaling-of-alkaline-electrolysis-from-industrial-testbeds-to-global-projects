function Pmodule = dispatch_theta_rule(Ptotal, theta, cfg)
%DISPATCH_THETA_RULE Local theta/base dispatch rule for the degradation branch.

if nargin < 3 || isempty(cfg)
    cfg = plant_case_config();
end

if ~isfield(cfg, 'Pmax_module_MW')
    Pmax = cfg.module_rating_MW;
else
    Pmax = cfg.Pmax_module_MW;
end
Pbase = theta * Pmax;
Ptotal = double(Ptotal);
if isvector(Ptotal)
    Ptotal = Ptotal(:)';
end
[days, steps] = size(Ptotal);
if isfield(cfg, 'n_modules')
    nModules = cfg.n_modules;
else
    nModules = max(1, ceil(max(Ptotal(:)) / Pmax));
end
Pmodule = zeros(days, steps, nModules);

for d = 1:days
    for t = 1:steps
        remaining = min(Ptotal(d, t), nModules * Pmax);
        for m = 1:nModules
            if remaining >= Pbase
                Pmodule(d, t, m) = Pbase;
                remaining = remaining - Pbase;
            else
                Pmodule(d, t, m) = remaining;
                remaining = 0;
                break;
            end
        end

        if remaining > 0
            room = squeeze(Pmax - Pmodule(d, t, :));
            room = max(room, 0);
            totalRoom = sum(room);
            if totalRoom > 0
                Pmodule(d, t, :) = squeeze(Pmodule(d, t, :)) + remaining * room / totalRoom;
            end
        end
    end
end
end
