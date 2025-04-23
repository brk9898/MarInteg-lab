%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%  COMBINED FOPID / PID ANALYSIS – CONTINUOUS → OUSTALOUP → BALRED → DISCRETE
%  -------------------------------------------------------------------------
%  This single script merges the functionality of the user‑supplied files
%      • FOPID_1.m   – four‑controller performance comparison (PSO / DEA).
%      • FOTF2DISC.m – fractional‑order → integer‑order → discrete workflow.
%  -------------------------------------------------------------------------
%  Pipeline for each fractional‑order controller (FOPID):
%      1.  Oustaloup recursive approximation (user‑defined freq band & N).
%      2.  Balanced truncation to a low‑order rational model (rOrder).
%      3.  Discretisation via Tustin (sampling period  Ts = 1/Fs).
%  All integer‑order PID controllers are discretised directly (Tustin).
%  The plant is discretised once with the same Ts so closed‑loop LTI objects
%  stay in a common domain.  The script then evaluates:
%      • time‑domain step responses  (nominal & with additive sinusoidal noise)
%      • integral control‑effort metrics
%      • closed‑loop Bode magnitude & phase overlays
%  -------------------------------------------------------------------------
%  USER KNOBS (edit as desired):
%  -------------------------------------------------------------------------
Fs      = 200;     % [Hz]  sampling frequency          ( ⇒ Ts = 1/Fs )
wb      = 1e-2;     % [rad/s] lower freq for Oustaloup  (default 0.01)
wh      = 1e+3;     % [rad/s] upper freq for Oustaloup  (default 100 )
N       = 10;        % Oustaloup approximation order  (→ 2N+1 poles/zeros)
rOrder  = 2;        % balanced‑truncation target order  (2–6 typical)
T_end   = 3;      % [s]  simulation horizon
addNoise= true;     % toggle second scenario with input disturbance
% -------------------------------------------------------------------------

%% 0. House‑keeping
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
 clc; close all;
Ts   = 1/Fs;                        % sampling period
s    = tf('s');                     % Laplace variable for definitions
tvec = 0:Ts:T_end;                 % common time grid (discrete)

%% 1. PLANT DEFINITION  (motor × robot)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Motor transfer function (user‑provided – experimental)
G_motor = tf([330.8 16550 5854], [1 135.1 18130 550400 134700]);
% Robot translational dynamics  (mass = 2 kg ⇒ 1/(m·s))
G_robot = 1/(2*s);
% Continuous‑time plant
G_c     = minreal(G_motor*G_robot);
% Discretise plant once (Tustin) – no reduction needed (real‑world poles)
G_d     = c2d(G_c, Ts, 'tustin');

%% 2. CONTROLLER PARAMETER BANK
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Fractional‑order PID syntax :  C = fracpid(Kp, Ki, Kd, lambda, mu)
% Integer‑order PID syntax     :  C = pid(Kp, Ki, Kd)

% –– PSO optimised FOPID –––––––––––––––––––––––––––––––––––––––––––––––––––
C_PSO_FOPID_frac = fracpid( 950.8, 980.7540, 1.0, 0.95, 0.2828);
% –– DEA optimised FOPID –––––––––––––––––––––––––––––––––––––––––––––––––––
C_DEA_FOPID_frac = fracpid( 998.75, 99.8, 0.1791, 0.95, 0.2828);
% –– DEA PID –––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
C_DEA_PID_cont   = pid(702.15, 18.1695, 0);
% –– PSO PID –––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
C_PSO_PID_cont   = pid(1000, 778.2756, 0);

%% 3. HELPER FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 3‑A.  Oustaloup → balred → discrete   (for FOPID)
makeDiscFromFrac = @(Cfrac) c2d( balred( tf( oustapp(Cfrac, wb, wh, N) ) * tf(1,[1e-6 1]), rOrder ), Ts, 'tustin');

% 3‑B.  Direct continuous PID → discrete
makeDiscPID      = @(Cpid) c2d( tf(Cpid), Ts, 'tustin');

%% 4. BUILD DISCRETE CONTROLLERS + CLOSED LOOPS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
contrNames = { 'PSO FOPID', 'DEA FOPID', 'DEA PID', 'PSO PID' };

Cdisc = cell(1,4);   % store discrete controllers
CL    = cell(1,4);   % closed‑loop transfer functions (tracking)
S     = cell(1,4);   % sensitivity functions (disturbance → output)

% –– loop through & generate objects ––
Cdisc{1} = makeDiscFromFrac(C_PSO_FOPID_frac);
Cdisc{2} = makeDiscFromFrac(C_DEA_FOPID_frac);
Cdisc{3} = makeDiscPID     (C_DEA_PID_cont);
Cdisc{4} = makeDiscPID     (C_PSO_PID_cont);

for k = 1:4
    CL{k} = feedback( Cdisc{k} * G_d, 1 );   % reference tracking
    S{k}  = feedback( 1, Cdisc{k} * G_d );   % sensitivity (input disturbance)
end

%% 5. NOMINAL (NOISE‑FREE) STEP RESPONSES & CONTROL EFFORT
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
ref = ones(size(tvec));   % unit‑step reference

Y_nom  = cell(1,4);   U_nom = cell(1,4);
stepInfo_nom = cell(1,4); Iu_nom = zeros(1,4);

for k = 1:4
    [y,~]     = step(CL{k}, tvec);                  Y_nom{k} = y;
    u         = lsim(Cdisc{k} * S{k}, ref, tvec);   U_nom{k} = u;
    stepInfo_nom{k} = stepinfo(y, tvec, 1, 'SettlingTimeThreshold',0.05);
    Iu_nom(k)      = trapz(tvec, abs(u));
end

%% 6. OPTIONAL NOISE SCENARIO
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if addNoise
    d = 0.5*sin(0.5*tvec) + 0.002*randn(size(tvec));   % same for all
    Y_noise  = cell(1,4);   U_noise = cell(1,4);
    stepInfo_noise = cell(1,4);   Iu_noise = zeros(1,4);
    for k = 1:4
        y   = lsim(CL{k}, ref,   tvec) + lsim(S{k}, d, tvec);  Y_noise{k}  = y;
        u   = lsim(Cdisc{k} * S{k}, ref, tvec);                U_noise{k}  = u;
        stepInfo_noise{k} = stepinfo(y, tvec, 1,'SettlingTimeThreshold',0.05);
        Iu_noise(k)       = trapz(tvec, abs(u));
    end
end

%% 7. PLOTS – STEP RESPONSE (NOMINAL & NOISE) + CONTROL EFFORT
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
col = lines(4);
figure('Name','Step – Nominal','Color','w'); hold on; grid on;
for k = 1:4, stairs(tvec,Y_nom{k},'LineWidth',1.5,'Color',col(k,:)); end
legend(contrNames,'Location','best'); title('Nominal step response'); xlabel('t [s]'); ylabel('y');

figure('Name','Control effort – Nominal','Color','w'); hold on; grid on;
for k = 1:4, plot(tvec,U_nom{k},'LineWidth',1.5,'Color',col(k,:)); end
legend(contrNames,'Location','best'); title('Control effort (nominal)'); xlabel('t [s]'); ylabel('u');

if addNoise
    figure('Name','Step – With disturbance','Color','w'); hold on; grid on;
    for k = 1:4, stairs(tvec,Y_noise{k},'LineWidth',1.5,'Color',col(k,:)); end
    legend(contrNames,'Location','best'); title('Step response with additive disturbance'); xlabel('t [s]'); ylabel('y');

    figure('Name','Control effort – With disturbance','Color','w'); hold on; grid on;
    for k = 1:4, plot(tvec,U_noise{k},'LineWidth',1.5,'Color',col(k,:)); end
    legend(contrNames,'Location','best'); title('Control effort (disturbance case)'); xlabel('t [s]'); ylabel('u');
end

%% 8. BODE COMPARISON (CLOSED LOOPS)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
w = logspace(-2,4,2000);
mag = zeros(4,numel(w));  pha = zeros(4,numel(w));
for k = 1:4
    [m,p] = bode(CL{k},w); mag(k,:) = squeeze(m); pha(k,:) = squeeze(p);
end
figure('Name','Closed‑loop Bode','Color','w');
ax1=subplot(2,1,1); hold(ax1,'on'); grid(ax1,'on');
for k=1:4, semilogx(ax1,w,20*log10(mag(k,:)),'LineWidth',1.4,'Color',col(k,:)); end
legend(ax1,contrNames,'Location','southwest'); ylabel('|CL(jω)| [dB]'); title(ax1,'Closed‑loop magnitude');
ax2=subplot(2,1,2); hold(ax2,'on'); grid(ax2,'on');
pha = mod(pha+180,360)-180;      % wrap to ±180°
for k=1:4, semilogx(ax2,w,pha(k,:),'LineWidth',1.4,'Color',col(k,:)); end
ylabel('Phase [°]'); xlabel('ω [rad/s]'); title(ax2,'Closed‑loop phase'); linkaxes([ax1 ax2],'x');

%% 9. PRINT METRICS TO COMMAND WINDOW
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for k=1:4
    fprintf('\n=== %s ===\n', contrNames{k});
    fprintf('• Settling time (nominal): %.3f s\n', stepInfo_nom{k}.SettlingTime);
    fprintf('• Overshoot     (nominal): %.2f %%\n', stepInfo_nom{k}.Overshoot);
    fprintf('• Integral |u|  (nominal): %.3f\n', Iu_nom(k));
    if addNoise
        fprintf('• Settling time (noise)  : %.3f s\n', stepInfo_noise{k}.SettlingTime);
        fprintf('• Overshoot     (noise)  : %.2f %%\n', stepInfo_noise{k}.Overshoot);
        fprintf('• Integral |u|  (noise)  : %.3f\n', Iu_noise(k));
    end
end

%% 10. SANITY: POLE MAGNITUDES OF DISCRETE CONTROLLERS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for k=1:2   % only fractional controllers went through Oustaloup → balred
    fprintf('\nPole magnitudes of %s (discrete):\n', contrNames{k});
    disp(abs(pole(Cdisc{k})));
end

%% 11. BODE COMPARISON OF EACH APPROXIMATION STAGE (FOPID)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

fopid_names = {'PSO FOPID', 'DEA FOPID'};
fopid_controllers = {C_PSO_FOPID_frac, C_DEA_FOPID_frac};

for idx = 1:2
    C_frac = fopid_controllers{idx};

    % Fractional (original)
    CL_frac = feedback(C_frac*G_c,1);

    % Oustaloup Approximation
    C_oust = tf(oustapp(C_frac, wb, wh, N)) * tf(1,[1e-6 1]);
    CL_oust = feedback(C_oust*G_c,1);

    % Balanced Reduction
    C_bal = balred(C_oust, rOrder);
    CL_bal = feedback(C_bal*G_c,1);

    % Discrete Approximation
    C_disc = c2d(C_bal, Ts, 'tustin');
    CL_disc = feedback(C_disc*G_d,1);

    % Frequency vector for plots
    w = logspace(-2,4,2000);
    stages = {CL_frac, CL_oust, CL_bal, CL_disc};
    labels = {'Fractional', 'Oustaloup', 'Balanced-Reduced', 'Discrete'};
    styles = {'-', '--', '-.', ':'};
    colors = lines(4);

    % Preallocate arrays
    mag = zeros(4, length(w));
    phase = zeros(4, length(w));

    % Calculate magnitude and phase
    for j = 1:4
        [m,p] = bode(stages{j},w);
        mag(j,:) = squeeze(m);
        phase(j,:) = squeeze(p);
    end

    % Plotting Bode comparison
    figure('Name', ['Bode Comparison Stages – ', fopid_names{idx}], 'Color', 'w');

    % Magnitude plot
    ax1 = subplot(2,1,1); hold(ax1, 'on'); grid(ax1, 'on');
    for j = 1:4
        semilogx(ax1, w, 20*log10(mag(j,:)), 'LineWidth', 1.5, ...
            'DisplayName', labels{j}, 'LineStyle', styles{j}, 'Color', colors(j,:));
    end
    ylabel('|CL(j\omega)| [dB]');
    title(['Bode Magnitude – ', fopid_names{idx}]);
    legend('Location', 'best');

    % Phase plot
    ax2 = subplot(2,1,2); hold(ax2, 'on'); grid(ax2, 'on');
    phase_wrapped = mod(phase + 180, 360) - 180; % Wrap phase to [-180,180]
    for j = 1:4
        semilogx(ax2, w, phase_wrapped(j,:), 'LineWidth', 1.5, ...
            'LineStyle', styles{j}, 'Color', colors(j,:));
    end
    ylabel('Phase [°]');
    xlabel('\omega [rad/s]');
    title(['Bode Phase – ', fopid_names{idx}]);

    linkaxes([ax1, ax2], 'x');
end
