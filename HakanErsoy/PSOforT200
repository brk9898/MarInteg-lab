clc; clear; close all;

% Transfer Fonksiyonu
num = [330.8, 16550, 5854];
den = [1, 135.1, 18130, 550400, 134700];
G = tf(num, den);

% PSO Parametreleri
nParticles = 70;     % Parçacık sayısını artırdık
nIterations = 200;   % Daha fazla iterasyon
w = 0.5;             % Daha düşük atalet katsayısı
c1 = 2.0;            % Kişisel öğrenme faktörü
c2 = 2.0;            % Sosyal öğrenme faktörü

% PID parametre sınırları
Kp_min = 0;  Kp_max = 100;
Ki_min = 0;  Ki_max = 100;
Kd_min = 0;  Kd_max = 10;

% Başlangıç konumları ve hızlar
Kp = Kp_min + (Kp_max - Kp_min) * rand(nParticles, 1);
Ki = Ki_min + (Ki_max - Ki_min) * rand(nParticles, 1);
Kd = Kd_min + (Kd_max - Kd_min) * rand(nParticles, 1);
vel = zeros(nParticles, 3);

% En iyi çözümleri sakla
pBest = [Kp, Ki, Kd];
pBestCost = zeros(nParticles, 1);

% İlk maliyetleri hesapla
for i = 1:nParticles
    pBestCost(i) = CostFunction(Kp(i), Ki(i), Kd(i), G);
end

% En iyi global çözümü bul
[gBestCost, gIdx] = min(pBestCost);
gBest = pBest(gIdx, :);

% PSO Algoritması
for iter = 1:nIterations
    for i = 1:nParticles
        vel(i, :) = w * vel(i, :) + ...
                    c1 * rand * (pBest(i, :) - [Kp(i), Ki(i), Kd(i)]) + ...
                    c2 * rand * (gBest - [Kp(i), Ki(i), Kd(i)]);

        Kp(i) = max(min(Kp(i) + vel(i, 1), Kp_max), Kp_min);
        Ki(i) = max(min(Ki(i) + vel(i, 2), Ki_max), Ki_min);
        Kd(i) = max(min(Kd(i) + vel(i, 3), Kd_max), Kd_min);

        newCost = CostFunction(Kp(i), Ki(i), Kd(i), G);

        if newCost < pBestCost(i)
            pBest(i, :) = [Kp(i), Ki(i), Kd(i)];
            pBestCost(i) = newCost;
        end

        if newCost < gBestCost
            gBest = [Kp(i), Ki(i), Kd(i)];
            gBestCost = newCost;
        end
    end

    fprintf('Iter: %d, Best Cost: %.6f, Kp: %.2f, Ki: %.2f, Kd: %.2f\n', ...
            iter, gBestCost, gBest(1), gBest(2), gBest(3));
end

C_opt = pid(gBest(1), gBest(2), gBest(3));
T_opt = feedback(C_opt * G, 1);
step(T_opt);
grid on;
title('PSO ile Optimize Edilmiş PID Kontrolü');
xlabel('Zaman (s)');
ylabel('Çıkış');
function cost = CostFunction(Kp, Ki, Kd, G)
    C = pid(Kp, Ki, Kd);
    T = feedback(C * G, 1);

    t = 0:0.001:5;
    [y, ~] = step(T, t);

    if numel(y) > 1
        e = 1 - y(:);
        ITAE = sum(t(:) .* abs(e));

        S = stepinfo(T, 'SettlingTimeThreshold', 0.02);
        overshoot = S.Overshoot;
        settlingTime = S.SettlingTime;
        peak = S.Peak;

        % Exponential hata fonksiyonu
        cost = ITAE + exp(overshoot/10) + exp(settlingTime/2) + exp(peak/2);
    else
        cost = inf;
    end
end
