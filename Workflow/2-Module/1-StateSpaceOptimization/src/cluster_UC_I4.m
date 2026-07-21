function [output_matrix, output_obj, output_status, diagnostics_out] = cluster_UC_I4(topology, Ptot_command, fault, fault_command, solver_options)
% 暂时没有考虑滚动优化，没有考虑电堆之间开关电流次数的均匀分配，没有考虑开关电流的衰退损失惩罚
% 暂时没有写纯化的最低气体流量约束
% 与v1相比：简化杂质约束，仅保留氧分离器气相的H2的物质的量动态
% 与v2相比：将杂质约束中物质的量和电流的双线性项中的电流用（（电流上限/15））*二进制（4位数） 表示
% clc,clf,clear
% close all
% warning off
if nargin < 5 || isempty(solver_options)
    solver_options = struct();
end
diagnostics_out = struct();
yalmip('clear')
% start_time = clock;
% disp(['程序开始运行的时间为：', num2str(start_time(1)), '/', num2str(start_time(2)), '/', num2str(start_time(3)), ' ', num2str(start_time(4)), ':', num2str(start_time(5)), ':', num2str(start_time(6))]);

type=topology;
cluster_parameters;

%% 定义待决策变量

% 电相关决策变量
P_st = sdpvar(N_st,t_command); % 每一台电解槽在每时刻的直流功率（单位：MW）
I_st = sdpvar(N_st,t_command); % 每一台电解槽在每时刻的直流电流（单位：A）
delta_I = binvar(N_st,t_command); % 每一台电解槽在每时刻的电流开状态（1代表有电流，0代表没有电流）
delta_I_sp = binvar(N_sp,t_command); % 每一台气液分离框架对应的所有电解槽为一组，代表每一组这样的电解槽在每时刻的电流状态（1代表该组电解槽内至少有一台电解槽有电流，0代表该组电解槽内所有电解槽均没有电流）
N_H2_st = sdpvar(N_st,t_command); % 每一台电解槽在每时刻的产氢率（单位：mol/s）

% 碱液流量相关决策变量
delta_lyep = binvar(N_lyep,t_command); % 每一台碱液循环泵在每时刻的开关状态（1代表开着，0代表关着）

% 温度相关决策变量（不知道采用系统总电功率指令的时间颗粒度作为描述温度动态的时间颗粒度精度是否足够）
Q_react_st = sdpvar(N_st,t_command); % 每一台电解槽在每时刻的产热功率（单位：MW）
Q_diss_st = sdpvar(N_st,t_command); % 每一台电解槽在每时刻向环境散热的功率（单位：MW）
Q_diss_sp = sdpvar(N_sp,t_command); % 每一台气液分离框架（包括氢分离器、氧分离器、附属管路）在每时刻向环境散热的功率（单位：MW）
T_stout = sdpvar(N_st,t_command); % 每一台电解槽在每时刻的氢碱氧碱出口温度（假设氢碱和氧碱出口温度相等）（单位：℃）
T_stin = sdpvar(N_st,t_command); % 每一台电解槽在每时刻的碱液入口温度（单位：℃）
delta_lyep_T_stout = sdpvar(N_st,t_command); % 用于对0-1量和实数量的乘积项delta_lyep*T_stout进行线性化而引入的中间量
delta_lyep_T_stin = sdpvar(N_st,t_command); % 用于对0-1量和实数量的乘积项delta_lyep*T_stin进行线性化而引入的中间量
T_spin = sdpvar(N_sp,t_command); % 每一台气液分离器在每时刻的氢碱氧碱入口温度（假设氢分离器和氧分离器温度相等）（单位：℃）
T_spout = sdpvar(N_sp,t_command); % 每一台气液分离器在每时刻的碱液出口温度（假设氢分离器和氧分离器温度相等）（单位：℃）
delta_lyep_T_spin = sdpvar(N_lyep,t_command); % 用于对0-1量和实数量的乘积项delta_lyep*T_spin进行线性化而引入的中间量
delta_lyep_T_spout = sdpvar(N_lyep,t_command); % 用于对0-1量和实数量的乘积项delta_lyep*T_spout进行线性化而引入的中间量
Q_cl = sdpvar(N_cl,t_command); % 每一台水冷换热器在每时刻提供的冷却功率（单位：MW）
if B_ht == 1 % 如果有配置加热器
    Q_ht = sdpvar(N_ht,t_command); % 每一台加热器在每时刻提供的加热功率（单位：MW）
end

% 杂质相关决策变量
N_usH2_st = sdpvar(N_st,t_command); % 每时刻通过每一台电解槽的碱液流动最终能进入氧气液分离器气相的氢（小气泡+溶解态）的速率（单位：mol/s）
N_anspg_H2 = sdpvar(N_sp,t_HTO); % 每一台氧气液分离器在每时刻气相中的H2的物质的量（单位：mol）
delta_I_sp_delta_lyep = binvar(N_lyep,t_command); % 用于对两个0-1量的乘积项delta_I_sp*delta_lyep进行线性化而引入的中间量
% 对每一台电解槽在每时刻的直流电流借助二进制表示进行离散化的0-1量（4位二进制数对应的最大十进制数是1111对应15）
y1_st = binvar(N_st,t_command);
y2_st = binvar(N_st,t_command);
y3_st = binvar(N_st,t_command);
y4_st = binvar(N_st,t_command);
y1_st_N_anspg_H2 = sdpvar(N_st,t_HTO); % 用于对0-1量和实数量的乘积项y1_st*N_anspg_H2进行线性化而引入的中间量
y2_st_N_anspg_H2 = sdpvar(N_st,t_HTO); % 用于对0-1量和实数量的乘积项y2_st*N_anspg_H2进行线性化而引入的中间量
y3_st_N_anspg_H2 = sdpvar(N_st,t_HTO); % 用于对0-1量和实数量的乘积项y3_st*N_anspg_H2进行线性化而引入的中间量
y4_st_N_anspg_H2 = sdpvar(N_st,t_HTO); % 用于对0-1量和实数量的乘积项y4_st*N_anspg_H2进行线性化而引入的中间量

%% 约束条件

% 创建空约束
constraint = [];

% 电相关约束
% 待决策变量是正数
constraint = [constraint, tag(P_st >= 0, '功率下限约束')];
% 所有负载的电功率（包括所有电堆的功率、所有辅机（碱液循环泵（变量）、加热器（变量）、冷却水系统+纯水系统+纯化系统等（常量））的功率）小于等于制氢集群总电功率指令
if B_ht == 1 % 如果有配置加热器
    constraint = [constraint,sum(P_st,1)'/eta_st + sum(delta_lyep,1)'*P_lyep + sum(Q_ht,1)'/eta_ht + N_st*Pn_st*PR_aux2stn <= Ptot_command];
else
    constraint = [constraint, tag(sum(P_st,1)'/eta_st + sum(delta_lyep,1)'*P_lyep + N_st*Pn_st*PR_aux2stn <= Ptot_command, '功率上限约束')];
end
% 开电流情况下允许的电流下限和上限
constraint = [constraint, tag(I_st >= delta_I*I_LL_st, '电流下限约束')];
constraint = [constraint, tag(I_st <= delta_I*I_UL_st, '电流上限约束')];
% 平均小室电压的上限
constraint = [constraint, tag(a0*I_st/coe(type,2) + a1*T_stout + a2 <= U_cell_UL, '电压上限约束')];
% 电解槽的直流电流与直流功率之间的关系（这样通过多个平面的近似可能导致在0点附近出现违背物理的偏差，即计算出的电流和功率可能不同时为0（但应该偏离0点也不远），而实际上电流和功率肯定是同时为0的）xingxuetao天然分段
for i=1:N_st
    for j=1:t_command
        constraint = [constraint, tag(I_st(i,j) <= -plane_P_T_I_equations(:,1)./plane_P_T_I_equations(:,3)*P_st(i,j) - plane_P_T_I_equations(:,2)./plane_P_T_I_equations(:,3)*T_stout(i,j) + plane_P_T_I_equations(:,4)./plane_P_T_I_equations(:,3), '功率-电流温度方程')];
    end
end
% 电解槽的产氢率与直流电流的关系
constraint = [constraint, tag(N_H2_st == 1/(2*96500) * (I_st-delta_I*I_shunt) * N_cell, '产率电流方程')]; % 电解槽的产H2速率（mol/s）
% 每一台电解槽在每时刻的电流开状态 与 每一组气液分离框架对应的所有电解槽作为一个整体在每时刻的电流状态 之间的关系（每一组气液分离框架对应的电解槽中只要有一组开着，就认为这一组电解槽是开的状态）
for i=1:N_sp
    for j=1:t_command
        constraint = [constraint, tag(delta_I_sp(i,j) <= sum(delta_I(((i-1)*(R_st2sp)+1):(i*R_st2sp),j)), '电流状态关联约束')];
        constraint = [constraint, tag(delta_I_sp(i,j) >= sum(delta_I(((i-1)*(R_st2sp)+1):(i*R_st2sp),j)) / R_st2sp, '电流状态关联约束')];
    end
end

% 碱液流量相关约束
if Blye_st == 1 % 对于每一台电解槽而言，开着电流一定对应有碱液流量，关电流后的一段时间内必须保持碱液流量（不一定需要，关了电流后立即关闭碱液循环也不一定会有问题），关着电流且距离关电流超过一段时间后碱液流量可有可无
    for i=1:N_lyep
        % 对于初始时刻
        for j=1:clye_st
            for tau=1:j
                constraint = [constraint,delta_lyep(i,j) >= sum(delta_I(((i-1)*R_st2lyep+1):(i*R_st2lyep),tau))/R_st2lyep];
            end
        end
        % 对于非初始时刻
        for j=(clye_st+1):t_command
            for tau=(j-clye_st):j
                constraint = [constraint,delta_lyep(i,j) >= sum(delta_I(((i-1)*R_st2lyep+1):(i*R_st2lyep),tau))/R_st2lyep];
            end
        end
    end
else % 对于每一台电解槽而言，开着电流一定对应有碱液流量，关着电流碱液流量可有可无
    for i=1:N_st
        i_lyep = ceil(i/R_st2lyep); % 计算第i台电解槽对应的碱液循环泵的编号
        for j=1:t_command
            constraint = [constraint, tag(delta_lyep(i_lyep,j) >= delta_I(i,j), '电质状态关联约束')];
            %             if type == 3 || type == 5 || type == 6
            %                 constraint = [constraint,delta_lyep(i_lyep,j) == 1];
            %             end
        end
    end
end

% 温度相关约束（以下暂时没有考虑运行中的碱液循环泵给碱液的传热。对于一个额定流量100m3/h、扬程50m、额定功率为37kW的碱液循环泵，其发热功率可能有10kW左右，其中可能大部分被碱液循环泵的冷却水带走，小部分则传给了碱液）
% 待决策变量是正数
constraint = [constraint, tag(Q_react_st >= 0, '产热非负约束')];
constraint = [constraint, tag(Q_diss_st >= 0, '散热非负约束')];
if B_ht == 1 % 如果有配置加热器
    constraint = [constraint,Q_ht >= 0];
end
constraint = [constraint, tag(Q_cl >= 0, '换热非负约束')];
% 初始温度值
constraint = [constraint, tag(T_stout(:,1) == T_stout_ini, '槽出口温度初值')];
constraint = [constraint, tag(T_stin(:,1) == T_stin_ini, '槽入口温度初值')];
constraint = [constraint, tag(T_spout(:,1) == T_spout_ini, '分离器出口温度初值')];
constraint = [constraint, tag(T_stout >= T_stout_LL, '槽出口温度下限约束')];
constraint = [constraint, tag(T_stin >= T_stin_LL, '槽入口温度下限约束')];
constraint = [constraint, tag(T_spout >= T_spout_LL, '分离器出口温度下限约束')];
constraint = [constraint, tag(T_spin >= T_spin_LL, '分离器入口温度下限约束')];
constraint = [constraint, tag(T_stout <= T_stout_UL, '槽出口温度上限约束')];
constraint = [constraint, tag(T_stin <= T_stin_UL, '槽入口温度上限约束')];
constraint = [constraint, tag(T_spout <= T_spout_UL, '分离器出口温度上限约束')];
constraint = [constraint, tag(T_spin <= T_spin_UL, '分离器入口温度上限约束')];

% 每一台电解槽的热动态
for i=1:N_st
    for j=1:(t_command-1)
        constraint = [constraint, tag(C_st*(T_stout(i,j+1)-T_stout(i,j))/(delta_t*60*60) == Q_react_st(i,j)*10^6 - Q_diss_st(i,j)*10^6 - c_lye*rho_lye*(Qlye_st/3600)*(delta_lyep_T_stout(i,j)-delta_lyep_T_stin(i,j)), '槽温度动态方程')];
    end
end
% 对于0-1量和实数量的乘积项delta_lyep*T_stout以及delta_lyep*T_stin的线性化
for i=1:N_st
    i_lyep = ceil(i/R_st2lyep); % 计算第i台电解槽对应的碱液循环泵的编号
    for j=1:t_command
        % 对于0-1量和实数量的乘积项delta_lyep(i_lyep,j)*T_stout(i,j)的线性化
        constraint = [constraint,delta_lyep_T_stout(i,j) <= T_stout(i,j)];
        constraint = [constraint,delta_lyep_T_stout(i,j) >= T_stout(i,j) - T_stout_UL*(1-delta_lyep(i_lyep,j))];
        constraint = [constraint,delta_lyep_T_stout(i,j) >= T_stout_LL*delta_lyep(i_lyep,j)];
        constraint = [constraint,delta_lyep_T_stout(i,j) <= T_stout_UL*delta_lyep(i_lyep,j)];
        % 对于0-1量和实数量的乘积项delta_lyep(i_lyep,j)*T_stin(i,j)的线性化
        constraint = [constraint,delta_lyep_T_stin(i,j) <= T_stin(i,j)];
        constraint = [constraint,delta_lyep_T_stin(i,j) >= T_stin(i,j) - T_stin_UL*(1-delta_lyep(i_lyep,j))];
        constraint = [constraint,delta_lyep_T_stin(i,j) >= T_stin_LL*delta_lyep(i_lyep,j)];
        constraint = [constraint,delta_lyep_T_stin(i,j) <= T_stin_UL*delta_lyep(i_lyep,j)];
    end
end
% 电解槽的产热功率与其直流功率、产氢率的关系（产热功率=直流功率-产氢率*氢的高位热值142MJ/kg）
constraint = [constraint, tag(Q_react_st == P_st - N_H2_st*22.4/1000/11.2*142, '产热方程')];
% 电解槽向环境散热的功率与电解槽的温度及环境温度的关系
constraint = [constraint, tag(Q_diss_st == (T_stout - T_env) / HR_st / 10^6, '槽散热方程')];

% 电解槽的氢碱氧碱出口温度与气液分离器入口温度的关系（当气液分离框架中完全没有碱液流量时，无论其分离器入口温度和电解槽出口温度是多少，以下等式恒成立，也就是说，在完全没有碱液流量的时段内优化求解得到的分离器入口温度可能取允许温度范围内的任意值，会与实际不符，但可以忽略这段时间内的分离器入口温度，不影响其他计算）
for i=1:N_sp
    for j=1:t_command
        constraint = [constraint, tag(sum(delta_lyep_T_spin(((i-1)*(N_lyep/N_sp)+1):(i*(N_lyep/N_sp)),j)) == sum(delta_lyep_T_stout(((i-1)*(R_st2sp)+1):(i*R_st2sp),j)) / R_st2lyep, '槽出口与分离器入口温度关联方程')];
    end
end
% 对于0-1量和实数量的乘积项delta_lyep*T_spin以及delta_lyep*T_spout的线性化
for i=1:N_lyep
    i_sp = ceil(i/(N_lyep/N_sp)); % 计算第i台碱液循环泵对应的气液分离框架的编号
    for j=1:t_command
        % 对于0-1量和实数量的乘积项delta_lyep(i,j)*T_spin(i_sp,j)的线性化
        constraint = [constraint,delta_lyep_T_spin(i,j) <= T_spin(i_sp,j)];
        constraint = [constraint,delta_lyep_T_spin(i,j) >= T_spin(i_sp,j) - T_spin_UL*(1-delta_lyep(i,j))];
        constraint = [constraint,delta_lyep_T_spin(i,j) >= T_spin_LL*delta_lyep(i,j)];
        constraint = [constraint,delta_lyep_T_spin(i,j) <= T_spin_UL*delta_lyep(i,j)];
        % 对于0-1量和实数量的乘积项delta_lyep(i,j)*T_spout(i_sp,j)的线性化
        constraint = [constraint,delta_lyep_T_spout(i,j) <= T_spout(i_sp,j)];
        constraint = [constraint,delta_lyep_T_spout(i,j) >= T_spout(i_sp,j) - T_spout_UL*(1-delta_lyep(i,j))];
        constraint = [constraint,delta_lyep_T_spout(i,j) >= T_spout_LL*delta_lyep(i,j)];
        constraint = [constraint,delta_lyep_T_spout(i,j) <= T_spout_UL*delta_lyep(i,j)];
    end
end
% 每一台气液分离器的热动态
for i=1:N_sp
    for j=1:(t_command-1)
        constraint = [constraint, tag(C_sp*(T_spout(i,j+1)-T_spout(i,j))/(delta_t*60*60) == -Q_diss_sp(i,j)*10^6 - c_lye*rho_lye*(Qlye_st/3600)*(sum(delta_lyep_T_spout(((i-1)*(N_lyep/N_sp)+1):(i*(N_lyep/N_sp)),j)) - sum(delta_lyep_T_spin(((i-1)*(N_lyep/N_sp)+1):(i*(N_lyep/N_sp)),j)))*R_st2lyep, '分离器温度动态方程')];
    end
end
% 分离器（包括氢分离器、氧分离器、附属管路）向环境散热的功率与分离器的温度及环境温度的关系
constraint = [constraint, tag(Q_diss_sp == ((T_spout-T_env)/HR_H2sp + (T_spout-T_env)/HR_O2sp) / 10^6, '分离器散热方程')];
% 分离器出口温度与电解槽入口温度的关系（分离器出口与电解槽入口之间隔着水冷器（必选）和加热器（可选））（当通过电解槽的碱液流量为0时，无论电解槽入口温度为多少，等式约束的左侧恒等于0，此时求出的电解槽入口温度是取值范围内的随机值，但可以忽略，不影响其他计算）
if B_ht == 1 % 如果有配置加热器
    for i=1:N_st
        i_lyep = ceil(i/R_st2lyep); % 计算第i台电解槽对应的碱液循环泵的编号
        i_ht = ceil(i/R_st2ht); % 计算第i台电解槽对应的加热器的编号
        i_cl = ceil(i/R_st2cl); % 计算第i台电解槽对应的水冷器的编号
        for j=1:t_command
            constraint = [constraint,c_lye*rho_lye*(Qlye_st/3600)*(delta_lyep_T_stin(i,j)-delta_lyep_T_spout(i_lyep,j)) == Q_ht(i_ht,j)/R_st2ht*10^6 - Q_cl(i_cl,j)/R_st2cl*10^6];
        end
    end
else % 如果没有配置加热器
    for i=1:N_st
        i_lyep = ceil(i/R_st2lyep); % 计算第i台电解槽对应的碱液循环泵的编号
        i_cl = ceil(i/R_st2cl); % 计算第i台电解槽对应的水冷器的编号
        for j=1:t_command
            constraint = [constraint, tag(c_lye*rho_lye*(Qlye_st/3600)*(delta_lyep_T_stin(i,j)-delta_lyep_T_spout(i_lyep,j)) == - Q_cl(i_cl,j)/R_st2cl*10^6, '分离器出口与槽入口温度关联方程')];
        end
    end
end
% 单个水冷器能提供的最大冷却功率
constraint = [constraint, tag(Q_cl <= Q_cl_max, '冷却功率上限约束')];
% 单个加热器（如有）能提供的最大加热功率
if B_ht == 1 % 如果有配置加热器
    constraint = [constraint,Q_ht <= Q_ht_max];
end

% 杂质相关约束
% 各状态量的初始时刻值
constraint = [constraint,N_anspg_H2(:,1) == N_anspg_H2_ini];
% 每时刻通过每一台电解槽的碱液流动最终能进入氧气液分离器气相的氢（小气泡+溶解态）的速率与电流、碱液流量的关系
for i=1:N_st
    i_lyep = ceil(i/R_st2lyep); % 计算第i台电解槽对应的碱液循环泵的编号
    for j=1:t_command
        % 等式右边第一项代表在电解槽有产气时阴极侧会产生不可被分离的小氢气泡，这些小氢气泡出电解槽后首先会进入氢气液分离器，进一步通过碱液回流其中一部分进入到各个电解槽的阳极侧，进一步流入氧气液分离器液相，并由阳极侧产生的大氧气泡"洗气"进入氧气液分离器气相
        % 等式右边第二项代表在同一组气液分离框架内只要有电解槽在产气，且有碱液流量通过本电解槽，则通过本电解槽的碱液中溶解的氢的其中一部分最终能进入到氧气液分离器的气相
        constraint = [constraint, tag(N_usH2_st(i,j) == a_H2us*(I_st(i,j)-delta_I(i,j)*I_shunt)/A_cell/3600 + S_H2*P_sys*Qlye_st/3600*0.5*delta_I_sp_delta_lyep(i_lyep,j), '槽杂质动态方程')];
    end
end

% 氧气液分离器气相内氢的物质的量动态
for i=1:N_sp
    for j=1:(t_HTO-1)
        j_command = ceil(j/(delta_t/delta_t_HTO)); % 计算以delta_t_HTO为时间颗粒度的杂质相关决策变量的时刻j对应的以delta_t为时间颗粒度的决策变量的时刻
        % 氧气液分离器气相内的氢的物质的量动态（需要注意对电流项利用二进制表示进行了离散化，因为电流对HTO影响很大，分区间电流取定值意味着在同一区间内的不同电流对应计算出的HTO相等，如果区间划分太粗则不太能准确反映出不同电流对HTO的影响）
        constraint = [constraint,(N_anspg_H2(i,j+1)-N_anspg_H2(i,j))/(delta_t_HTO*60*60) == N_ca2an_H2*sum(delta_I(((i-1)*(R_st2sp)+1):(i*R_st2sp),j_command)) + sum(N_usH2_st(((i-1)*(R_st2sp)+1):(i*R_st2sp),j_command))/2 - 1/(4*96500)*N_cell/((P_sys*10^5*V_anspg)/(8.314*(T_anspg_nom+273))) * (I_UL_st/15) * (2^0*sum(y1_st_N_anspg_H2(((i-1)*(R_st2sp)+1):(i*R_st2sp),j))+2^1*sum(y2_st_N_anspg_H2(((i-1)*(R_st2sp)+1):(i*R_st2sp),j))+2^2*sum(y3_st_N_anspg_H2(((i-1)*(R_st2sp)+1):(i*R_st2sp),j))+2^3*sum(y4_st_N_anspg_H2(((i-1)*(R_st2sp)+1):(i*R_st2sp),j)))];
    end
end
% HTO上限约束
constraint = [constraint, tag(N_anspg_H2 <= N_anspg_H2_UL, 'HTO上限约束')];
% 每一台电解槽在每时刻的直流电流所属区间对应的二进制数
constraint = [constraint,(I_UL_st/15) * (2^0*y1_st + 2^1*y2_st + 2^2*y3_st + 2^3*y4_st) <= I_st];
constraint = [constraint,(I_UL_st/15) * (2^0*y1_st + 2^1*y2_st + 2^2*y3_st + 2^3*y4_st) >= I_st - (I_UL_st/15)];
% 对于0-1量和实数量的乘积项y1_st*N_anspg_H2、y2_st*N_anspg_H2、y3_st*N_anspg_H2、y4_st*N_anspg_H2的线性化
for i=1:N_st
    i_sp = ceil(i/R_st2sp); % 计算第i台电解槽对应的气液分离框架的编号
    for j=1:t_HTO
        j_command = ceil(j/(delta_t/delta_t_HTO)); % 计算以delta_t_HTO为时间颗粒度的杂质相关决策变量的时刻j对应的以delta_t为时间颗粒度的决策变量的时刻
        % 对于0-1量和实数量的乘积项y1_st(i,j_command)*N_anspg_H2(i_sp,j)的线性化
        constraint = [constraint,y1_st_N_anspg_H2(i,j) <= N_anspg_H2(i_sp,j)];
        constraint = [constraint,y1_st_N_anspg_H2(i,j) >= N_anspg_H2(i_sp,j) - N_anspg_H2_UL*(1-y1_st(i,j_command))];
        constraint = [constraint,y1_st_N_anspg_H2(i,j) >= N_anspg_H2_LL*y1_st(i,j_command)];
        constraint = [constraint,y1_st_N_anspg_H2(i,j) <= N_anspg_H2_UL*y1_st(i,j_command)];
        % 对于0-1量和实数量的乘积项y2_st(i,j_command)*N_anspg_H2(i_sp,j)的线性化
        constraint = [constraint,y2_st_N_anspg_H2(i,j) <= N_anspg_H2(i_sp,j)];
        constraint = [constraint,y2_st_N_anspg_H2(i,j) >= N_anspg_H2(i_sp,j) - N_anspg_H2_UL*(1-y2_st(i,j_command))];
        constraint = [constraint,y2_st_N_anspg_H2(i,j) >= N_anspg_H2_LL*y2_st(i,j_command)];
        constraint = [constraint,y2_st_N_anspg_H2(i,j) <= N_anspg_H2_UL*y2_st(i,j_command)];
        % 对于0-1量和实数量的乘积项y3_st(i,j_command)*N_anspg_H2(i_sp,j)的线性化
        constraint = [constraint,y3_st_N_anspg_H2(i,j) <= N_anspg_H2(i_sp,j)];
        constraint = [constraint,y3_st_N_anspg_H2(i,j) >= N_anspg_H2(i_sp,j) - N_anspg_H2_UL*(1-y3_st(i,j_command))];
        constraint = [constraint,y3_st_N_anspg_H2(i,j) >= N_anspg_H2_LL*y3_st(i,j_command)];
        constraint = [constraint,y3_st_N_anspg_H2(i,j) <= N_anspg_H2_UL*y3_st(i,j_command)];
        % 对于0-1量和实数量的乘积项y4_st(i,j_command)*N_anspg_H2(i_sp,j)的线性化
        constraint = [constraint,y4_st_N_anspg_H2(i,j) <= N_anspg_H2(i_sp,j)];
        constraint = [constraint,y4_st_N_anspg_H2(i,j) >= N_anspg_H2(i_sp,j) - N_anspg_H2_UL*(1-y4_st(i,j_command))];
        constraint = [constraint,y4_st_N_anspg_H2(i,j) >= N_anspg_H2_LL*y4_st(i,j_command)];
        constraint = [constraint,y4_st_N_anspg_H2(i,j) <= N_anspg_H2_UL*y4_st(i,j_command)];
    end
end
% 对于两个0-1量的乘积项delta_I_sp*delta_lyep的线性化
for i=1:N_lyep
    i_sp = ceil(i/(N_lyep/N_sp)); % 计算第i台碱液循环泵对应的气液分离框架的编号
    for j=1:t_command
        % 对于两个0-1量的乘积项delta_I_sp(i_sp,j)*delta_lyep(i,j)的线性化
        constraint = [constraint,delta_I_sp_delta_lyep(i,j) <= delta_I_sp(i_sp,j)];
        constraint = [constraint,delta_I_sp_delta_lyep(i,j) <= delta_lyep(i,j)];
        constraint = [constraint,delta_I_sp_delta_lyep(i,j) >= delta_I_sp(i_sp,j) + delta_lyep(i,j) - 1];
    end
end

%% fault约束
% if fault==1
%     constraint = [constraint, tag(delta_I <= 1e8*(ones(N_st, t_command)-squeeze(fault_command(1,:,:))), '电堆故障约束')];
% elseif fault==2
%         constraint = [constraint, tag(I_st <= 1e8*(ones(N_st, t_command)-squeeze(fault_command(1,:,:))), '电路故障约束')];
% elseif fault==3
%     constraint = [constraint, tag(delta_lyep <= 1e8*(ones(N_lyep, t_command)-squeeze(fault_command(1,:,:))), '液路故障约束')];
% elseif fault==4
%     constraint = [constraint, tag(Q_cl <= 1e8*(ones(N_cl, t_command)-squeeze(fault_command(1,:,:))), '温路故障约束')];
% end

% constraint = remove(constraint, 'redundant');
%% 目标函数
% 制氢集群系统总电功率指令时间周期内总产氢量最大
% obj = sum(N_H2_st(:)) * delta_t*60*60 * 22.4/1000; % 周期内总产氢量（单位：Nm3）

% （售氢收入-制氢电力成本）最高（在目标函数中增加考虑购电的成本，以避免由于电流和功率、温度的关系松弛为了不等式关系，而使得优化结果中出现功率高于电流应该对应的实际功率这样虚假的结果）
obj = sum(N_H2_st(:)) * delta_t*60*60 * 22.4/1000 * price_H2 - sum(sum(P_st)) * 1000 * delta_t * price_ele;

% obj = [];
%% 设置求解器属性
% ops = sdpsettings('solver','cplex');
% ops.showprogress = 1;
% ops.cplex.mip.tolerances.mipgap = 0.01; % 允许优化结果相对偏差
% ops.cplex.timelimit = 240; % 最长优化时长（s）
% ops.cplex.read.constraints = 50000; % 为约束数量预分配内存空间（非必须）
% ops.cplex.workmem = 3072; % 最大允许占用内存（MB）
% 输出CPLEX求解时使用的模型（用于调试debug）
% [model,recoveryalmip,diagnostic,internalmodel]=export(constraint,obj,ops); % 转为cplex模型
% milpt=Cplex('milp for htc');
% milpt.Model.sense='minimize';
% milpt.Model.obj=model.f;
% milpt.Model.lb=model.lb;
% milpt.Model.ub=model.ub;
% milpt.Model.A=[model.Aineq;model.Aeq];
% milpt.Model.lhs=[-inf*ones(size(model.bineq,1),1);model.beq];
% milpt.Model.rhs=[model.bineq;model.beq];
% milpt.Model.ctype=model.ctype;
% milpt.writeModel('ab.lp'); % 输出cplex模型（注意大小写）

% gurobi
ops = sdpsettings('solver','gurobi');
if isfield(solver_options, 'ShowProgress')
    ops.showprogress = solver_options.ShowProgress;
    ops.gurobi.OutputFlag = solver_options.ShowProgress;
else
    ops.showprogress = 1;
    ops.gurobi.OutputFlag = 1;
end
if isfield(solver_options, 'MIPGap')
    ops.gurobi.MIPGap = solver_options.MIPGap;
else
    ops.gurobi.MIPGap = 0.01;
end
if isfield(solver_options, 'TimeLimit')
    ops.gurobi.TimeLimit = solver_options.TimeLimit;
else
    ops.gurobi.TimeLimit = 240;
end
if isfield(solver_options, 'Threads')
    ops.gurobi.Threads = solver_options.Threads;
end

%% 求解问题
% disp('开始求解');
% solve_start_time = clock;
% disp(['开始求解的时间为：', num2str(solve_start_time(1)), '/', num2str(solve_start_time(2)), '/', num2str(solve_start_time(3)), ' ', num2str(solve_start_time(4)), ':', num2str(solve_start_time(5)), ':', num2str(solve_start_time(6))]);
diagnostics = optimize(constraint,-obj,ops);
% solve_stop_time = clock;
% disp(['结束求解的时间为：', num2str(solve_stop_time(1)), '/', num2str(solve_stop_time(2)), '/', num2str(solve_stop_time(3)), ' ', num2str(solve_stop_time(4)), ':', num2str(solve_stop_time(5)), ':', num2str(solve_stop_time(6))]);

feasibility = checkset(constraint);
infeasible_idx = find(feasibility < -1e-6);  % 负值表示不可行

%% 结果输出
if diagnostics.problem == 0 || diagnostics.problem == 3
    % 目标函数
    obj_Vl = value(obj);

    % 电相关决策变量
    P_st_Vl = value(P_st);
    I_st_Vl = value(I_st);
    delta_I_Vl = value(delta_I);
    N_H2_st_Vl = value(N_H2_st);

    % 碱液流量相关决策变量
    delta_lyep_Vl = value(delta_lyep);

    % 温度相关决策变量
    Q_react_st_Vl = value(Q_react_st);
    Q_diss_st_Vl = value(Q_diss_st);
    Q_diss_sp_Vl = value(Q_diss_sp);
    T_stout_Vl = value(T_stout);
    T_stin_Vl = value(T_stin);
    T_spin_Vl = value(T_spin);
    T_spout_Vl = value(T_spout);
    Q_cl_Vl = value(Q_cl);
    % delta_lyep_T_spin_Vl = value(delta_lyep_T_spin);
    % delta_lyep_T_stout_Vl = value(delta_lyep_T_stout);

    % 杂质相关决策变量
    N_anspg_H2_Vl = value(N_anspg_H2);

    % 根据决策变量结果计算的与之相对应的实际值
    % 电相关
    U_cell_real = un + (r1 + r2*T_stout_Vl).*I_st_Vl/coe(type,2); % 与温度、电流决策变量对应的小室电压
    P_st_real = N_cell * I_st_Vl .* U_cell_real /(10^6); % 与温度、电流决策变量对应的电堆直流功率（与P_st_Vl对比可以检查是否有出现不符实际的电堆功率值）
    N_H2_sum = sum(N_H2_st_Vl(:)) * delta_t*60*60 * 22.4/1000; % 周期内总产氢量（单位：Nm3）
    % 温度相关
    Q_react_st_real = P_st_real - N_H2_st_Vl*22.4/1000/11.2*142; % 与温度、电流决策变量对应的电堆产热功率（与Q_react_st_Vl对比可以检查是否有出现不符实际的电堆产热功率值）
    % 杂质相关
    HTO_sp = N_anspg_H2_Vl  / ((P_sys*10^5*V_anspg)/(8.314*(T_anspg_nom+273))); % 每个氧分离器气相HTO
    for i =1:N_sp
        HTO_sp15(i,:) = sum(reshape(HTO_sp(i,:), 15, t_command), 1)/15;
    end

    % 将变量组合为 96×N 矩阵[Nst Nst Nst Nst Nsp Nsp Nsp Nst Nsp Nsp]=5*Nst+5*Nsp
    output_matrix = [P_st_Vl', N_H2_st_Vl', delta_I_Vl', I_st_Vl', ...
        delta_lyep_Vl', Qlye_st*ones(t_command, N_st), Q_cl_Vl', U_cell_real', ...
        T_stout_Vl', HTO_sp15']; % MW, Nm3, 0/1, A, 0/1, MW, V, K, %

    output_matrix = round(output_matrix,4);
    output_obj = obj_Vl;
    output_status = diagnostics.problem;
    diagnostics_out = struct( ...
        'topology', topology, ...
        'fault', fault, ...
        'problem', diagnostics.problem, ...
        'info', diagnostics.info, ...
        'Ptot_command', Ptot_command(:), ...
        'delta_t', delta_t, ...
        'delta_t_HTO', delta_t_HTO, ...
        't_command', t_command, ...
        't_HTO', t_HTO, ...
        'N_st', N_st, ...
        'N_sp', N_sp, ...
        'N_lyep', N_lyep, ...
        'R_st2sp', R_st2sp, ...
        'R_st2lyep', R_st2lyep, ...
        'Qlye_st', Qlye_st, ...
        'P_st', P_st_Vl, ...
        'N_H2_st', N_H2_st_Vl, ...
        'delta_I', delta_I_Vl, ...
        'I_st', I_st_Vl, ...
        'delta_lyep', delta_lyep_Vl, ...
        'Q_cl', Q_cl_Vl, ...
        'U_cell', U_cell_real, ...
        'T_stout', T_stout_Vl, ...
        'HTO_sp15', HTO_sp15, ...
        'HTO_sp_1min', HTO_sp, ...
        'N_anspg_H2', N_anspg_H2_Vl, ...
        'T_spin', T_spin_Vl, ...
        'T_spout', T_spout_Vl, ...
        'solver_options', solver_options);
else
    fprintf('YALMIP diagnostic status %d: %s\n', diagnostics.problem, diagnostics.info);
    output_matrix = 0;
    output_obj = 0;
    output_status = diagnostics.problem;
    diagnostics_out = struct( ...
        'topology', topology, ...
        'fault', fault, ...
        'problem', diagnostics.problem, ...
        'info', diagnostics.info, ...
        'Ptot_command', Ptot_command(:), ...
        'delta_t', delta_t, ...
        'delta_t_HTO', delta_t_HTO, ...
        't_command', t_command, ...
        't_HTO', t_HTO);
end
% % 定义列标题
% headers = {'P_st', 'N_H2', 'delta_I', 'I_st', 'delta_lyep', 'Q_cl', 'U_cell', 'T_avg', 'HTO'};

% % 将列标题和矩阵数据组合为表格
% output_table = array2table(output_matrix, 'VariableNames', headers);

% 提示用户文件已保存
% disp('Optimization results have been saved to optimization_results.xlsx.');

% 冲突检测方法1，无效
% if diagnostics.problem == 0
%     disp('Solver thinks it is feasible');
% elseif diagnostics.problem ~= 0
%     disp('Solver thinks it is infeasible');
%     % 提取 Gurobi 模型
%     [model, ~] = export(constraint,-obj,ops);
%     % 计算 IIS
%     model.params.infeasibilityTol = 1e-6;  % 设置不可行容忍度（可选）
%     model.params.iisfind = 1;  % 强制计算所有冲突（包括边界和约束）
%     result = gurobi_iis(model);  % 计算 IIS
%     if isfield(result, 'minimal') && result.minimal
%         disp('找到最小不可行子系统 (IIS)');
%         % 检查冲突约束
%         if isfield(result, 'arows') && any(result.arows)
%             conflict_idx = find(result.arows);
%             disp('冲突约束内容:');
%             for i = 1:length(conflict_idx)
%                 idx = conflict_idx(i);
%                 % 注意：Gurobi 的约束索引可能从 0 开始，需调整
%                 yalmip_idx = idx + 1; % 如果 Gurobi 索引是 0-based
%                 disp(['约束 ', num2str(idx), ': ']);
%                 disp(Constraints(yalmip_idx)); % 直接显示 YALMIP 约束
%             end
%         end
%         % 检查变量边界冲突
%         if isfield(result, 'lb') && any(result.lb)
%             conflict_lb = find(result.lb);
%             disp('冲突的下界变量:');
%             for i = 1:length(conflict_lb)
%                 idx = conflict_lb(i);
%                 disp(['变量 ', num2str(idx), ' 的下界: ', num2str(model.lb(idx))]);
%             end
%         end
%         if isfield(result, 'ub') && any(result.ub)
%             conflict_ub = find(result.ub);
%             disp('冲突的上界变量:');
%             for i = 1:length(conflict_ub)
%                 idx = conflict_ub(i);
%                 disp(['变量 ', num2str(idx), ' 的上界: ', num2str(model.ub(idx))]);
%             end
%         end
%     else
%         disp('未找到明确的 IIS 结果');
%     end
% end
