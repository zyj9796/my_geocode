function [az, rg, tStar] = geo2pixel(lat, lon, h, meta, orbit, tInit)
% 输入：lat/lon(deg), h(m), meta(含 t0,dtAz,R0,dR), orbit(含 posI/velI), tInit 初值
% 输出：az, rg 为 1-based 浮点像素坐标；tStar 为求得时刻

% --- 1) LLH -> ECEF (WGS84) ---
P = llh2ecef(lat, lon, h);

% --- 2) 解零多普勒：g(t)=(P-S(t))·V(t)=0 ---
[tStar, ok] = solve_zero_doppler(P, orbit, tInit);
if ~ok || ~isfinite(tStar)
    az = NaN; rg = NaN;
    return;
end

% --- 3) range ---
S = orbit.posI(tStar).';
R = norm(P - S);

% --- 4) 像素坐标 ---
if ~isfinite(meta.dtAz) || ~isfinite(meta.dR) || ~isfinite(meta.R0)
    az = NaN; rg = NaN;
    return;
end
az = (tStar - meta.t0)/meta.dtAz + 1;
rg = (R - meta.R0)/meta.dR + 1;

end

% ===== 子函数（仍在同文件，不算额外函数文件）=====
function P = llh2ecef(lat, lon, h)
a = 6378137.0;
f = 1/298.257223563;
e2 = f*(2-f);

lat = deg2rad(lat); lon = deg2rad(lon);
sinLat = sin(lat); cosLat = cos(lat);
sinLon = sin(lon); cosLon = cos(lon);

N = a / sqrt(1 - e2*sinLat^2);
x = (N + h)*cosLat*cosLon;
y = (N + h)*cosLat*sinLon;
z = (N*(1-e2) + h)*sinLat;
P = [x; y; z];
end

function [tStar, ok] = solve_zero_doppler(P, orbit, tInit)
maxIter = 15;
tol = 1e-6;
t = tInit;
ok = false;

for k = 1:maxIter
    S = orbit.posI(t).';
    V = orbit.velI(t).';
    g = dot(P - S, V);

    if abs(g) < tol
        ok = true; tStar = t; return;
    end

    % 数值导数
    dt = 0.01;
    S2 = orbit.posI(t+dt).';
    V2 = orbit.velI(t+dt).';
    g2 = dot(P - S2, V2);
    dg = (g2 - g)/dt;

    if abs(dg) < 1e-12
        break;
    end
    t = t - g/dg;
end

tStar = NaN;
end
