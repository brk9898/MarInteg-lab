%% ====================== 0.  House‑keeping ==============================
close all; clc;

load CONT-PLANT.mat            % CONTROLLER (T) and PLANT
Fs      = 1000;                % sampling frequency [Hz]
Ts      = 1/Fs;
s       = fotf('s');           % fractional Laplace variable

t_final = 5;                   % simulate 0 … 5 s
t_vec   = 0:Ts:t_final;        % common time base for every step plot

%% user knob ────────────► choose the target reduced order here
rOrder  = 4;                   % e.g. 4, 5, 6 …  (must be < full order)

%% ====================== 1.  Baseline (fractional) ======================
T_frac  = CONTROLLER;
G_frac  = PLANT;
CL_frac = feedback(T_frac*G_frac,1);
[y0,t0] = step(CL_frac, t_vec);

%% ====================== 2.  Oustaloup approximation ====================
wb = 1e-3;  wh = 1e3;  N = 3;            % low/high freq & order per term
T_oust_zpk = oustapp(T_frac, wb, wh, N);

[b,a]  = zp2tf(cell2mat(T_oust_zpk.z), ...
               cell2mat(T_oust_zpk.p), T_oust_zpk.k);
T_oust = tf(b,a) * tf(1, [1e-6 1]);      % conditioning pole

G_oust = oustapp(G_frac, wb, wh, N,'oust');
CL_oust = feedback(T_oust*G_oust,1);
[y1,t1] = step(CL_oust, t_vec);

%% ====================== 3.  Balanced truncation (user‑selected order) ==
T_bal = balred(T_oust, rOrder);
G_bal = balred(G_oust, rOrder);
CL_bal = feedback(T_bal*G_bal, 1);
[y2,t2] = step(CL_bal, t_vec);

%% ====================== 4.  Discretisation (Tustin, Ts = 1/Fs) =========
T_d = c2d(T_bal, Ts, 'tustin');
G_d = c2d(G_bal, Ts, 'tustin');
CL_d = feedback(T_d*G_d, 1);
[y3,t3] = step(CL_d, t_vec);

%% ====================== 5.  Time‑domain comparison =====================
figure('Name','Step responses','Color','w'); hold on; grid on;
plot(t0, y0,'LineWidth',1.4,'DisplayName','Fractional (baseline)');
plot(t1, y1,'LineWidth',1.2,'DisplayName','Oustaloup (full order)');
plot(t2, y2,'LineWidth',1.2,'DisplayName','Balanced‑red. (order = '+string(rOrder)+")");
stairs(t3,y3,'LineWidth',1.0,'DisplayName','Discrete (T_s = 1 ms)');
xlabel('Time [s]'); ylabel('Output');
title('Closed‑loop step response at each conversion stage');
legend('Location','best'); axis tight;

%% ====================== 6.  Frequency‑domain comparison ================
w  = logspace(-2, 4, 2000);          % 10⁻² … 10⁴ rad/s

sysList  = {CL_frac, CL_oust, CL_bal, CL_d};
sysLabel = {'Fractional (baseline)', ...
            'Oustaloup (full order)', ...
            sprintf('Balanced‑red. (%d‑th)', rOrder), ...
            'Discrete (T_s = 1 ms)'};

style  = {'-','--','-.',':'};       % four distinct line styles
cols   = lines(numel(sysList));     % MATLAB’s default colour set

% ── pre‑allocate for speed
mag = zeros(numel(sysList), numel(w));
ph  = zeros(numel(sysList), numel(w));

for k = 1:numel(sysList)
    [m, p] = bode(sysList{k}, w);   % m & p are 1×1×Nω
    mag(k,:) = squeeze(m);         % -> 1×Nω
    ph(k,:)  = squeeze(p);         % -> 1×Nω
end

% ── magnitude subplot
figure('Color','w');
ax1 = subplot(2,1,1); hold(ax1,'on'); grid(ax1,'on');
for k = 1:numel(sysList)
    semilogx(ax1, w, 20*log10(mag(k,:)), ...
        'LineStyle',style{k}, 'Color',cols(k,:), 'LineWidth',1.5, ...
        'DisplayName', sysLabel{k});
end
ylabel(ax1, '|CL(j\omega)|  [dB]');
title(ax1, 'Closed‑loop Bode diagram – magnitude');
legend(ax1,'Location','southwest');

% ── phase subplot (with wrapping to ±180°)
ax2 = subplot(2,1,2); hold(ax2,'on'); grid(ax2,'on');
phWrapped = wrapTo180(ph);          % helper from Mapping Toolbox; or use mod()
for k = 1:numel(sysList)
    semilogx(ax2, w, phWrapped(k,:), ...
        'LineStyle',style{k}, 'Color',cols(k,:), 'LineWidth',1.5);
end
ylabel(ax2, 'Phase  [°]'); xlabel(ax2, '\omega  [rad/s]');
title(ax2, 'Closed‑loop Bode diagram – phase');
linkaxes([ax1 ax2],'x');            % zoom both plots together

%% ====================== 7.  Health check ===============================
fprintf('\nMagnitudes of poles after discretisation (should be < 1):\n');
disp(abs(pole(T_d)));
