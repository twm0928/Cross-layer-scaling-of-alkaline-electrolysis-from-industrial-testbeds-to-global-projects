function features = compute_dynamic_features_richer(xMW, PmaxMW)
%COMPUTE_DYNAMIC_FEATURES_RICHER Richer plant-available features.
%   Uses only power-profile information that remains available at the
%   plant-to-module interface.

if nargin < 2 || isempty(PmaxMW)
    PmaxMW = 20;
end

x = reshape(xMW, 1, []);
n = numel(x);
features = zeros(1, 8);

% f1: mean power
features(1) = mean(x) / PmaxMW;

% f2: longest low-load duration
low_threshold = 0.2 * PmaxMW;
below = x < low_threshold;
maxLen = 0;
currentLen = 0;
for i = 1:n
    if below(i)
        currentLen = currentLen + 1;
        maxLen = max(maxLen, currentLen);
    else
        currentLen = 0;
    end
end
features(2) = maxLen / n;

% f3: average absolute ramping
if n > 1
    dx = diff(x);
    features(3) = mean(abs(dx)) / PmaxMW;
else
    dx = 0;
    features(3) = 0;
end

% f4: high-frequency ratio
X = abs(fft(x));
X = X(2:floor(n / 2));
if isempty(X) || sum(X) == 0
    features(4) = 0;
else
    samplesPerHour = n / 24;
    freqResolution = samplesPerHour / n;
    freqs = (1:length(X)) * freqResolution;
    highIdx = freqs >= 1;
    features(4) = sum(X(highIdx)) / sum(X);
end

% f5: start/stop transition count, based on on/off threshold
on_threshold = 0.05 * PmaxMW;
on_state = x >= on_threshold;
if n > 1
    features(5) = sum(abs(diff(on_state))) / (n - 1);
else
    features(5) = 0;
end

% f6: high-load duration ratio
high_threshold = 0.8 * PmaxMW;
features(6) = mean(x >= high_threshold);

% f7: normalized standard deviation
features(7) = std(x) / PmaxMW;

% f8: normalized load range
features(8) = (max(x) - min(x)) / PmaxMW;

features(~isfinite(features)) = 0;
end
