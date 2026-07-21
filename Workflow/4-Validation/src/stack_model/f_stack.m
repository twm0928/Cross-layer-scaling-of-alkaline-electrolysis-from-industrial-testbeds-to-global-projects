function [i_ele, i_stray, Xi_in_an, Xi_in_ca, Xica, Xicc] = f_stack( ...
    n, R0, U0, Rm_l, Rm_u, Rch_l_an, Rch_l_ca, Rch_u_an, Rch_u_ca, R_end, i0)
% Calculate the current distribution in an alkaline electrolysis stack.
% This local copy preserves the original equivalent-circuit equations so
% the R1 Workflow can run independently as an uploadable code package.

nx = 9 * n - 4;
n_i1 = 1;
n_ichu_an1 = n + 1;
n_ichu_ca1 = 2 * n + 1;
n_imu_an1 = 3 * n + 1;
n_imu_ca1 = 4 * n;
n_ichl_an1 = 5 * n - 1;
n_ichl_ca1 = 6 * n - 1;
n_iml_an1 = 7 * n - 1;
n_iml_ca1 = 8 * n - 2;

A = zeros(nx, nx);
B = zeros(nx, 1);

% KCL: ic(k+1)+ichu_an(k+1)+ichu_ca(k+1)+ich_l_an(k+1)+ich_l_ca(k+1)=ic(k)
A11 = zeros(n - 1, nx);
A11(:, 1:n) = [-eye(n - 1), zeros(n - 1, 1)] + [zeros(n - 1, 1), eye(n - 1)];
A11(:, n_ichu_an1 + 1:(n_ichu_an1 + n - 1)) = eye(n - 1);
A11(:, n_ichu_ca1 + 1:(n_ichu_ca1 + n - 1)) = eye(n - 1);
A11(:, n_ichl_an1 + 1:(n_ichl_an1 + n - 1)) = eye(n - 1);
A11(:, n_ichl_ca1 + 1:(n_ichl_ca1 + n - 1)) = eye(n - 1);
A(1:n - 1, :) = A11;

% KCL along outlet and inlet manifolds.
A12 = zeros(n - 2, nx);
A12(:, n_imu_an1:(n_imu_an1 + n - 2)) = ...
    [-eye(n - 2), zeros(n - 2, 1)] + [zeros(n - 2, 1), eye(n - 2)];
A12(:, n + 2:2 * n - 1) = -eye(n - 2);
A(n:2 * n - 3, :) = A12;

A13 = zeros(n - 2, nx);
A13(:, n_imu_ca1:(n_imu_ca1 + n - 2)) = ...
    [-eye(n - 2), zeros(n - 2, 1)] + [zeros(n - 2, 1), eye(n - 2)];
A13(:, (n_ichu_ca1 + 1):(n_ichu_ca1 + n - 2)) = -eye(n - 2);
A(2 * n - 2:3 * n - 5, :) = A13;

A14 = zeros(n - 2, nx);
A14(:, n_iml_an1:(n_iml_an1 + n - 2)) = ...
    [-eye(n - 2), zeros(n - 2, 1)] + [zeros(n - 2, 1), eye(n - 2)];
A14(:, (n_ichl_an1 + 1):(n_ichl_an1 + n - 2)) = -eye(n - 2);
A(3 * n - 4:4 * n - 7, :) = A14;

A14 = zeros(n - 2, nx);
A14(:, n_iml_ca1:(n_iml_ca1 + n - 2)) = ...
    [-eye(n - 2), zeros(n - 2, 1)] + [zeros(n - 2, 1), eye(n - 2)];
A14(:, (n_ichl_ca1 + 1):(n_ichl_ca1 + n - 2)) = -eye(n - 2);
A(4 * n - 6:5 * n - 9, :) = A14;

% KVL equations for outlet and inlet flow paths.
A21 = zeros(n - 1, nx);
A21(:, n_ichu_an1:(n_ichu_an1 + n - 1)) = ...
    Rch_u_an * ([eye(n - 1), zeros(n - 1, 1)] + [zeros(n - 1, 1), -eye(n - 1)]);
A21(:, n_imu_an1:(n_imu_an1 + n - 2)) = Rm_u * eye(n - 1);
A21(:, n_i1:(n_i1 + n - 2)) = -R0 * eye(n - 1);
A(5 * n - 8:6 * n - 10, :) = A21;
B(5 * n - 8:6 * n - 10, 1) = U0;

A22 = zeros(n - 1, nx);
A22(:, n_ichu_ca1:(n_ichu_ca1 + n - 1)) = ...
    Rch_u_ca * ([eye(n - 1), zeros(n - 1, 1)] + [zeros(n - 1, 1), -eye(n - 1)]);
A22(:, n_imu_ca1:(n_imu_ca1 + n - 2)) = Rm_u * eye(n - 1);
A22(:, n_i1:(n_i1 + n - 2)) = -R0 * eye(n - 1);
A(6 * n - 9:7 * n - 11, :) = A22;
B(6 * n - 9:7 * n - 11, 1) = U0;

A23 = zeros(n - 1, nx);
A23(:, n_ichl_an1:(n_ichl_an1 + n - 1)) = ...
    Rch_l_an * ([eye(n - 1), zeros(n - 1, 1)] + [zeros(n - 1, 1), -eye(n - 1)]);
A23(n - 1, n_ichl_an1 + n - 1) = -1 / (1 / Rch_l_an + 1 / R_end);
A23(:, n_iml_an1:(n_iml_an1 + n - 2)) = Rm_l * eye(n - 1);
A23(:, n_i1:(n_i1 + n - 2)) = -R0 * eye(n - 1);
A(7 * n - 10:8 * n - 12, :) = A23;
B(7 * n - 10:8 * n - 12, 1) = U0;

A23 = zeros(n - 1, nx);
A23(:, n_ichl_ca1:(n_ichl_ca1 + n - 1)) = ...
    Rch_l_ca * ([eye(n - 1), zeros(n - 1, 1)] + [zeros(n - 1, 1), -eye(n - 1)]);
A23(n - 1, n_ichl_ca1 + n - 1) = -1 / (1 / Rch_l_ca + 1 / R_end);
A23(:, n_iml_ca1:(n_iml_ca1 + n - 2)) = Rm_l * eye(n - 1);
A23(:, n_i1:(n_i1 + n - 2)) = -R0 * eye(n - 1);
A(8 * n - 11:9 * n - 13, :) = A23;
B(8 * n - 11:9 * n - 13, 1) = U0;

% Boundary conditions.
A(9 * n - 12, n_ichu_an1) = 1;
A(9 * n - 12, n_ichu_ca1) = 1;
A(9 * n - 12, n_i1) = 1;
A(9 * n - 12, n_ichl_an1) = 1;
A(9 * n - 12, n_ichl_ca1) = 1;
B(9 * n - 12, 1) = i0;

A(9 * n - 11, n_ichu_an1) = 1;
A(9 * n - 11, n_imu_an1) = -1;
A(9 * n - 10, n_ichu_ca1) = 1;
A(9 * n - 10, n_imu_ca1) = -1;
A(9 * n - 9, n_imu_an1 + n - 2) = 1;
A(9 * n - 9, n_ichu_an1 + n - 1) = 1;
A(9 * n - 8, n_imu_ca1 + n - 2) = 1;
A(9 * n - 8, n_ichu_ca1 + n - 1) = 1;
A(9 * n - 7, n_ichl_an1) = 1;
A(9 * n - 7, n_iml_an1) = -1;
A(9 * n - 6, n_ichl_ca1) = 1;
A(9 * n - 6, n_iml_ca1) = -1;
A(9 * n - 5, n_ichl_an1 + n - 1) = 1;
A(9 * n - 5, n_iml_an1 + n - 2) = 1;
A(9 * n - 4, n_ichl_ca1 + n - 1) = 1;
A(9 * n - 4, n_iml_ca1 + n - 2) = 1;

X = sparse(A) \ sparse(B);

Xi = X(n_i1:n_i1 + n - 1);
Xica = X(n_ichu_an1:n_ichu_an1 + n - 1);
Xicc = X(n_ichu_ca1:n_ichu_ca1 + n - 1);
Xi_in_an = X(n_ichl_an1:n_ichl_an1 + n - 1);
Xi_in_ca = X(n_ichl_ca1:n_ichl_ca1 + n - 1);

i_ele = Xi;
i_stray = Xi_in_an + Xi_in_ca + Xica + Xicc;
end
