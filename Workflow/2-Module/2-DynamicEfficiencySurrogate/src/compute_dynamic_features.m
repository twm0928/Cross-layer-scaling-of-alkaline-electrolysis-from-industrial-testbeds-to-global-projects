function features = compute_dynamic_features(xMW, PmaxMW)
% Compute dynamic features used by the module dynamic surrogate.
%
% Feature definitions (all available from the module power trajectory only):
%   1) mean load level
%   2) longest low-load residence ratio
%   3) average absolute ramping intensity
%   4) high-frequency fluctuation ratio
%   5) load standard deviation
%   6) load range

if nargin < 2 || isempty(PmaxMW)
    PmaxMW = 20;
end

x = reshape(xMW, 1, []);
n = numel(x);
features = zeros(1, 6);

features(1) = mean(x) / PmaxMW;

threshold = 0.2 * PmaxMW;
below = x < threshold;
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

if n > 1
    features(3) = mean(abs(diff(x))) / PmaxMW;
else
    features(3) = 0;
end

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

features(5) = std(x, 0, 2) / PmaxMW;
features(6) = (max(x) - min(x)) / PmaxMW;

features(isnan(features)) = 0;
end
