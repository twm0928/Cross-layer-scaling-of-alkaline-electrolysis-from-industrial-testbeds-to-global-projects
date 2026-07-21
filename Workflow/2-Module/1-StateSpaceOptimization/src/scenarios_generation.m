% 参数定义
frequencies = [30, 60, 240, 720, 1440]; % 频率（单位：分钟），最小频率为30分钟
amplitudes = 2:2:20; % 幅值（以2为步长，从2到20）
duty_cycles = 0.2:0.2:1; % 占空比（以20%为步长，从20%到100%）

% 时间定义
num_points = 96; % 96个点
t = 1:num_points; % 时间向量（从1到96）

% 初始化存储所有波形的数组
num_frequencies = length(frequencies);
num_amplitudes = length(amplitudes);
num_duty_cycles = length(duty_cycles);
num_waveforms = num_frequencies * num_amplitudes * (2 + num_duty_cycles); % 正弦波+三角波+方波
waveform_data = zeros(num_waveforms, num_points); % 存储波形数据
waveform_info = cell(num_waveforms, 4); % 存储波形信息：[类型, 频率, 幅值, 占空比]

% 生成正弦波和三角波
waveform_index = 1;
for freq = frequencies
    for amp = amplitudes
        % 计算每个频率对应的周期点数
        points_per_period = freq / 15; % 每个周期的点数（15分钟为时间粒度）
        
        % 正弦波（上移，确保最小值为0，最大值为幅值）
        sine_wave = amp * (sin(2 * pi * (t - 1) / points_per_period) + 1) / 2;
        waveform_data(waveform_index, :) = sine_wave;
        waveform_info{waveform_index, 1} = 'Sine';
        waveform_info{waveform_index, 2} = freq;
        waveform_info{waveform_index, 3} = amp;
        waveform_info{waveform_index, 4} = NaN; % 占空比不适用
        waveform_index = waveform_index + 1;
        
        % 三角波（上移，确保最小值为0，最大值为幅值）
        triangle_wave = amp * (sawtooth(2 * pi * (t - 1) / points_per_period, 0.5) + 1) / 2;
        waveform_data(waveform_index, :) = triangle_wave;
        waveform_info{waveform_index, 1} = 'Triangle';
        waveform_info{waveform_index, 2} = freq;
        waveform_info{waveform_index, 3} = amp;
        waveform_info{waveform_index, 4} = NaN; % 占空比不适用
        waveform_index = waveform_index + 1;
    end
end

% 生成方波
for freq = frequencies
    for amp = amplitudes
        for duty = duty_cycles
            % 计算每个频率对应的周期点数
            points_per_period = freq / 15; % 每个周期的点数（15分钟为时间粒度）
            
            % 方波（调整到0到幅值范围）
            square_wave = amp * (square(2 * pi * (t - 1) / points_per_period, duty * 100) + 1) / 2;
            waveform_data(waveform_index, :) = square_wave;
            waveform_info{waveform_index, 1} = 'Square';
            waveform_info{waveform_index, 2} = freq;
            waveform_info{waveform_index, 3} = amp;
            waveform_info{waveform_index, 4} = duty; % 占空比
            waveform_index = waveform_index + 1;
        end
    end
end

% 输出波形数量
fprintf('Total waveforms generated: %d\n', waveform_index - 1);

% 示例：绘制前5个波形
figure;
for i = 1:20
    subplot(20, 1, i);
    plot(t, waveform_data(i+20, :), 'LineWidth', 1.5);
    title(sprintf('%s Wave: Freq = %d min, Amp = %d', ...
        waveform_info{i, 1}, waveform_info{i, 2}, waveform_info{i, 3}));
    xlabel('Time Points (1 to 96)');
    ylabel('Amplitude');
    grid on;
end