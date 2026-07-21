%% 输入参数

CAP = 20; % 以20MW为基本单元
% type = 5;

%% 系统拓扑相关设备设计参数

param_dir = fileparts(mfilename('fullpath'));
ev_root = fileparts(fileparts(param_dir));
workflow_root = fileparts(ev_root);
project_root = fileparts(workflow_root);
topology_file = fullfile(fileparts(mfilename('fullpath')), 'data', 'topology.xlsx');
coe = readmatrix(topology_file, 'Sheet', 'Sheet1', 'Range', 'D2:J16');
N = readmatrix(topology_file, 'Sheet', 'Sheet2', 'Range', 'B2:H8');
coe = coe';
N = N';

N_st = N(type,1); % 电解槽台数
N_sp = N(type,2); % 气液分离框架的数量
N_pu = N(type,3); % 纯化框架的数量，默认和分离一致
N_lyep = N(type,4); % 碱液循环泵的数量
N_cl = N(type,5); % 水冷换热器的数量
B_ht = N(type,6); % 代表是否配置加热器的布尔量（0代表没有配置，1代表有配置）
N_ht = N(type,7); % 加热器的数量

% Fangshan validation object: one 5 MW Stack A subsystem with one-to-one BOP.
% The manuscript M1 topology contains four such independent subsystems; the
% field data available here correspond to only one physical subsystem.
N_st = 1;
N_sp = 1;
N_pu = 1;
N_lyep = 1;
N_cl = 1;
B_ht = 0;
N_ht = 1;

R_st2sp = N_st/N_sp; % 电解槽台数与气液分离框架数量之比（需要注意让R_st2sp能整除N_st，这里暗含的假设是制氢集群中的每一组电解槽与气液分离框架均为相同的N进1形式）
R_sp2pu = N_sp/N_pu; % 气液分离框架与纯化框架数量之比（需要注意让R_sp2pu能整除N_sp，这里暗含的假设是制氢集群中的每一组气液分离框架与纯化框架均为相同的N进1形式）
R_st2lyep = N_st/N_lyep; % 电解槽台数与碱液循环泵数量之比（需要注意让R_st2lyep能整除R_st2sp）
R_st2cl = N_st/N_cl; % 电解槽台数与水冷换热器数量之比（需要注意让R_st2cl能整除R_st2sp）
R_st2ht = N_st/N_ht; % （如果有配置加热器）电解槽台数与加热器数量之比（需要注意让R_st2ht能整除R_st2sp）

% 电解槽
Pn_st = CAP/N_st*coe(type,1); % 每一台电解槽的设计额定功率（单位：MW）
I_UL_st = 14000*coe(type,2); % 每一台电解槽允许通过单小室的最大电流（单位：A）（注意：对于一正两负电解槽，该值为电解槽允许最大电流的一半）
I_LL_coef = coe(type,3);
I_shunt_coef = coe(type,3);
I_LL_st = 1381*I_LL_coef; % 每一台电解槽开电流情况下允许的最小电流（单位：A）（开始电解的最小电流）
I_shunt = 1381*I_shunt_coef; % 每一台电解槽在电解状态下的漏电流（简化假设为定值）（单位：A）
N_cell = 200*coe(type,4); % 电堆小室数
A_cell = pi*1^2*coe(type,5); % 单个小室的电极/隔膜有效截面积（单位：m2）
C_st = 31.62e6*coe(type,6); % 每一台电解槽的热容（主要是由金属的热容+碱液的热容组成，34375是来自房山的估算数据）（单位：J/K）
HR_st = 0.0067*coe(type,7); % 每一台电解槽向环境散热的热阻（辐射换热的热阻实际还受温度影响，此处简化不考虑温度的影响。0.0011是来自房山的估算数据）（单位：K/W）
Qlye_st = 70*coe(type,8); % 通过单台电解槽的额定碱液流量（单位：m3/h）

% Stack A parameters from the Fangshan/Sha thesis table.
Pn_st = 4.752;      % 720 V * 6600 A
I_UL_st = 6600;
I_LL_st = 1000;
I_shunt = 600;      % calibrated from rated H2 flow, used as constant shunt-current approximation
N_cell = 400;
A_cell = 1.54;
Qlye_st = 100;

% 液路
P_lyep = 0; % 37/1000*coe(type,9); % 每一台碱液循环泵的额定功率（单位：MW）（和额定流量、扬程正相关。作为参考：一个1000标方的1进1系统，会配置一个额定流量100m3/h、扬程50m的碱液循环泵，其额定功率为37kW）

% 分离器
V_anspg = 1.5*coe(type,10); % 氧气液分离器气相的体积（假设液位稳定）（单位：m3）
C_sp = 30000*1000*coe(type,11); % 氢分离器和氧分离器及附属管路的总热容（主要是由金属的热容+碱液的热容组成，5282+4545+2170是来自房山的估算数据）（单位：J/K）
HR_H2sp = 0.0148*coe(type,12); % 每一台氢分离器向环境散热的热阻（辐射换热的热阻实际还受温度影响，此处简化不考虑温度的影响。0.0431是来自房山的估算数据）（单位：K/W）
HR_O2sp = 0.0148*coe(type,13); % 每一台氧分离器向环境散热的热阻（辐射换热的热阻实际还受温度影响，此处简化不考虑温度的影响。0.0535是来自房山的估算数据）（单位：K/W）

% 换热
Q_cl_max = 2*coe(type,14); % 单个水冷换热器能提供的最大冷却功率（单位：MW）
Q_ht_max = 0.1*coe(type,15); % 单个加热器能提供的最大加热功率（单位：MW）


%% 共享参数

%% 功率指令
% load Ptot_command; % 加载预存的制氢集群系统总电功率指令，为N行2列的矩阵形式，第一列为时刻（单位：时），第二列为总电功率指令（单位：MW）
t_command = size(Ptot_command,1); % 系统总电功率指令包含的时刻点数
delta_t = 0.25; % 系统总电功率指令的时间颗粒度（单位：时）
% Ptot_command(:,2)=20;
% t_command = 4;

%% 经济效益
% 目标函数采用（售氢收入-购电成本）最高。需要注意：一方面电价和氢价的设置需要保证制氢是有收益的，否则，如果电价太高/氢价太低，则优化结果会是不制氢；另一方面电价不能太低/氢价不能太高，否则优化可能出现高于实际功率的虚假功率。建议电价、氢价取值原则是使得制氢有收益但不高
price_ele = 0; % 电价（单位：元/kWh）
price_H2 = 2.5; % 氢价（单位：元/Nm3）
eta_st = 0.95; % 电解槽的整流变效率（假设每一台都相同）

%% 单电池参数，与stack保持一致

% 计算电解槽小室电压（单位：V）与电流（单位：A）、温度（单位：℃）关系的半经验公式中的系数（假设每一台都相同）
% Stack A voltage fit from Step 2:
% V_stack = N_cell * (beta0 + beta1 * J + beta2 * J * T), J = I / A_cell.
beta0_stackA = 1.464658;
beta1_stackA = 1.685082e-4;
beta2_stackA = -1.240050e-6;
un = beta0_stackA;
r1 = beta1_stackA / A_cell;
r2 = beta2_stackA / A_cell;

T=60:1:90;
I=0:I_UL_st/50:I_UL_st;
for i=1:51
    for t=1:31
        U_cell(i,t) = un + (r1 + r2*T(t)).*I(i); % 与温度、电流决策变量对应的小室电压
    end
end
% 根据电解槽小室电压与电流、温度关系的半经验公式计算电解槽小室电压与电流、温度的线性近似表达式的系数（Ucell=a0*Icell+a1*T+a2）（该近似在小室电压较高的范围内准确性较好，可以用于小室电压上限约束中）
a0_I1 = 0.55 * I_UL_st;
a0_I2 = 0.85 * I_UL_st;
a0_It = 0.70 * I_UL_st;
a0 = ((un+(r1+r2*60)*a0_I2)-(un+(r1+r2*60)*a0_I1))/(a0_I2-a0_I1); % （单位：V/A）
a1 = ((un+(r1+r2*50)*a0_It)-(un+(r1+r2*30)*a0_It))/20; % （单位：V/℃）
a2 = (un+(r1+r2*30)*a0_It) - a0*a0_It - a1*30; % （单位：V）
U_cell_UL = 2.5; % 平均小室电压的上限（单位：V）
% 利用电解槽小室电压与电流、温度关系的半经验公式，计算直流功率(x)-温度(y)-电流(z)曲面的double description(DD)近似的多个平面的表达式系数
% 利用电解槽小室电压与电流、温度关系的半经验公式得到多组相邻的（直流功率-温度-电流）点的坐标，并计算出相邻三个点确定的三角形所在平面的方程（ax+by+cz=d）的系数
plane_P_T_I_equations = []; % 初始化平面方程系数矩阵
dT=20; % 温度取值间隔
dI=1000; % 电流取值间隔，这里跟4位2进制电流分段无关，分段只限制杂质约束
for T=10:dT:70
    for I=1000:dI:I_UL_st-dI
        % 第1个点的坐标
        T1 = T; % 电解槽平均温度（单位：℃）
        I1 = I; % 电解槽电流（单位：A）
        U1 = un + (r1 + r2*T1)*I1/coe(type,2); % 电解槽小室电压（单位：V）
        P1 = N_cell * I1 * U1 /(10^6); % 电解槽直流功率（单位：MW）
        % 第2个点的坐标
        T2 = T+dT; % 电解槽平均温度（单位：℃）
        I2 = I; % 电解槽电流（单位：A）
        U2 = un + (r1 + r2*T2)*I2/coe(type,2); % 电解槽小室电压（单位：V）
        P2 = N_cell * I2 * U2 /(10^6); % 电解槽直流功率（单位：MW）
        % 第3个点的坐标
        T3 = T+dT; % 电解槽平均温度（单位：℃）
        I3 = I+dI; % 电解槽电流（单位：A）
        U3 = un + (r1 + r2*T3)*I3/coe(type,2); % 电解槽小室电压（单位：V）
        P3 = N_cell * I3 * U3 /(10^6); % 电解槽直流功率（单位：MW）
        % 第4个点的坐标
        T4 = T; % 电解槽平均温度（单位：℃）
        I4 = I+dI; % 电解槽电流（单位：A）
        U4 = un + (r1 + r2*T4)*I4/coe(type,2); % 电解槽小室电压（单位：V）
        P4 = N_cell * I4 * U4 /(10^6); % 电解槽直流功率（单位：MW）
        % 计算第1、2、3点构成的三角形平面的方程（ax+by+cz=d）的系数
        % 获取三个点
        p1 = [P1,T1,I1]; % 第1个点
        p2 = [P2,T2,I2]; % 第2个点
        p3 = [P3,T3,I3]; % 第3个点
        % 计算法向量
        v1 = p2 - p1;
        v2 = p3 - p1;
        normal_vector = cross(v1, v2);
        % 计算平面方程的常数项 d
        d = dot(normal_vector, p1);
        % 将平面方程的系数存储到结果矩阵中
        plane_P_T_I_equations = [plane_P_T_I_equations; normal_vector, d];
        % 计算第1、3、4点构成的三角形平面的方程（ax+by+cz=d）的系数
        % 获取三个点
        p1 = [P1,T1,I1]; % 第1个点
        p2 = [P3,T3,I3]; % 第3个点
        p3 = [P4,T4,I4]; % 第4个点
        % 计算法向量
        v1 = p2 - p1;
        v2 = p3 - p1;
        normal_vector = cross(v1, v2);
        % 计算平面方程的常数项 d
        d = dot(normal_vector, p1);
        % 将平面方程的系数存储到结果矩阵中
        plane_P_T_I_equations = [plane_P_T_I_equations; normal_vector, d];
    end
end

%% 液路参数
Blye_st = 0; % 表示是否强制要求对每一台电解槽而言关闭电流后碱液循环至少需要保持一定的时间（0代表不强制要求，1代表强制要求）
tlye_st = 0; % 对每一台电解槽而言，关闭电流后碱液循环至少需要保持的时间（单位：时）
clye_st = ceil(tlye_st/delta_t); % 关闭电流后碱液循环至少需要保持的时间包含的时刻点数
eta_ht = 0.95; % 每一台加热器的电-热转换效率
PR_aux2stn = 0; % 冷却循环水系统、纯水系统、纯化系统等与电解槽运行状态相对独立的公辅系统的功耗（接近常量）与所有电解槽设计额定功率之比

%% 温路参数
T_stout_ini = ones(N_st,1)*70; % 每一台电解槽氢碱氧碱出口的初始温度（需要注意与制氢集群系统总电功率指令的初始值相匹配）（单位：℃）
T_stin_ini = ones(N_st,1)*50; % 每一台电解槽碱液入口的初始温度（严格来说需要由初始的氢碱氧碱出口温度、初始的电解产热、向环境散热、碱液流量等计算出，此处为了方便直接给出这个初始值，根据运行经验，稳态下碱液入口温度一般比氢碱氧碱出口温度低20℃左右）（单位：℃）
T_spout_ini = ones(N_sp,1)*70; % 每一台气液分离器碱液出口的初始温度（严格来说需要由初始的氢碱氧碱出口温度、向环境散热、碱液流量等计算出，此处为了方便直接给出这个初始值，由于散热热阻较大、散热功率较小，因此分离器的出入口温差较小，粗略假设初始的分离器出入口温度相等）（单位：℃） 
c_lye = 3000; % 碱液的比热容（温度对该值有一些影响但不显著，此处简化取定值）（单位：J/(kg*K)）
rho_lye = 1300; % 碱液的密度（温度对该值有一些影响但不显著，此处简化取定值）（单位：kg/m3）
T_env = 20; % 制氢系统所在厂房内的环境温度（单位：℃）

T_stout_UL = 95; % 电解槽氢碱氧碱出口温度的允许上限（单位：℃）
T_stout_LL = T_env; % 电解槽氢碱氧碱出口温度的允许下限（单位：℃）
T_stin_UL = 95; % 电解槽碱液入口温度的允许上限（单位：℃）
T_stin_LL = T_env; % 电解槽碱液入口温度的允许下限（单位：℃）
T_spin_UL = 95; % 气液分离器氢碱氧碱入口温度的允许上限（单位：℃）
T_spin_LL = T_env; % 气液分离器氢碱氧碱入口温度的允许下限（单位：℃）
T_spout_UL = 95; % 气液分离器碱液出口温度的允许上限（单位：℃）
T_spout_LL = T_env; % 气液分离器碱液出口温度的允许下限（单位：℃）

%% 杂质参数
delta_t_HTO = 1/60; % 描述杂质动态选取的时间颗粒度（单位：时）
t_HTO = t_command*(delta_t/delta_t_HTO); % 杂质动态相关决策变量包含的时刻点数
T_anspg_nom = 60; % 氧气液分离器气相的额定温度（用于忽略温度变化，简化计算氧气液分离器气相空间的物质的量）（单位：℃）
P_sys = 16; % 系统压力（假设系统正常不会进行泄压，且简化忽略气体泄露带来的停机后压力降低）（单位：bar）
e_t = 0.39; % 每一台电解槽隔膜的porosity/turtosity
D_H2 = 5.5*10^(-9); % 氢在温度90℃（简化忽略了温度变化的影响）的30%wtKOH溶液中的扩散系数（单位：m2/s）
d_sep = 0.00085; % 电解槽隔膜的厚度（单位：m）
S_H2 = 0.095; % 氢在温度90℃（在碱液浓度30%wt下，S_H2在常温到电解槽额定温度（90 ℃左右）区间内随温度变化很小，可以近似取定值）的30%wtKOH溶液中的饱和溶解度系数（单位：mol/m3/bar）
ss_H2 = 5; % 阴极电极表面（对于零极距结构电解槽也就是隔膜阴极侧表面）的过饱和系数（实际与电极结构有关，是电流密度、压力的非线性函数，此处简化为常数，取2.5有点偏小，取4-5可能比较合适）
DCc_H2 = e_t*D_H2/d_sep; % H2跨隔膜进行浓差扩散的系数（单位：m/s）
N_ca2an_H2 = DCc_H2 * S_H2 * P_sys *  ss_H2 * A_cell * N_cell; % 电解槽内H2跨膜速率（需要注意只有有电流进行产气时才有此项。只考虑浓差扩散，压差对流实际很小可以忽略，电曳力较小也可以忽略）（单位：mol/s）
a_H2us = 0.1; % （不可被分离的小氢气泡的产率）（mol/h）——电解电流密度（A/m2）的线性关系中的系数（0.0559来自压力1.6MPa，温度90℃下房山试验数据拟合）
N_anspg_H2_ini = 0.75/100 * ((P_sys*10^5*V_anspg)/(8.314*(T_anspg_nom+273))); % 每一台氧气液分离器在初始时刻气相的H2的物质的量浓度（利用gas_dy_421杂质动态模型在相同参数下仿真得到的氧气液分离器气相中的HTO，与总的气体物质的量相乘得到，注意需要与设定的电解槽初始时刻电解状态对应，例如初始HTO取0.75%对应电解槽初始是额定功率稳态运行）（单位：mol）
HTO_UL = 2/100; % HTO允许上限
N_anspg_H2_UL = HTO_UL * (P_sys*10^5*V_anspg)/(8.314*(T_anspg_nom+273)); % 氧气液分离器气相的H2的物质的量的上限（等于HTO允许上限乘以氧气液分离器气相总的气体物质的量（简化为系统额定压力和温度下的理想气体物质的量））（单位：mol）
N_anspg_H2_LL = 0; % 氧气液分离器气相的H2的物质的量的下限（实际上没有所谓的允许下限，是杂质动态中的一个状态量，当然不能取负数）（单位：mol）
% 用于氧气液分离器气相内的氢的物质的量动态方程中，电流项分区间取不同定值的区间边界值（需要根据电解槽的电流允许上下限和对于区间划分的精细度要求确定）（单位：A）
% I1_st = 0;
% I2_st = I_LL_st;
% I3_st = I2_st+2000*coe(type,2);
% I4_st = I3_st+2000*coe(type,2);
% I5_st = I_UL_st;
