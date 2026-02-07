clc; clear; close all;

%% 1) 修改为你的 result 目录（绝对路径）
baseDir = "D:\yjs\taiwandata\result";

%% 2) 产品目录与文件名（按你的实际）
dataDir = fullfile(baseDir, "20161212_split_Orb_Cal_deb_TC.data");
hdrPath = fullfile(dataDir, "Sigma0_IW2_VV.hdr");
imgPath = fullfile(dataDir, "Sigma0_IW2_VV.img");

assert(isfolder(dataDir), "找不到目录: %s", dataDir);
assert(isfile(hdrPath), "找不到文件: %s", hdrPath);
assert(isfile(imgPath), "找不到文件: %s", imgPath);

%% 3) 读取并解析 HDR（鲁棒）
txt0 = fileread(hdrPath);
txt  = lower(regexprep(txt0, '[\r\n]+', ' ')); % 小写 + 压平换行

lines      = local_get_int(txt, 'lines');
samples    = local_get_int(txt, 'samples');
bands      = local_get_int(txt, 'bands');
dtype      = local_get_int(txt, 'data type');
byte_order = local_get_int(txt, 'byte order');

m = regexp(txt, 'interleave\s*=\s*(\w+)', 'tokens', 'once');
assert(~isempty(m), "HDR 里找不到 interleave 字段");
interleave = m{1};

assert(bands == 1, "本脚本期望 bands=1，但读到 bands=%d", bands);

% ENVI data type -> MATLAB precision
switch dtype
    case 1,  precision = 'uint8';
    case 2,  precision = 'int16';
    case 3,  precision = 'int32';
    case 4,  precision = 'single';
    case 5,  precision = 'double';
    case 12, precision = 'uint16';
    case 13, precision = 'uint32';
    otherwise, error("Unsupported ENVI data type: %d", dtype);
end

% byte order -> machfmt
if byte_order == 0
    machfmt = 'ieee-le';
elseif byte_order == 1
    machfmt = 'ieee-be';
else
    error("未知 byte order=%d（期望 0 或 1）", byte_order);
end

fprintf("✅ HDR parsed: lines=%d samples=%d dtype=%d(%s) interleave=%s byte_order=%d(%s)\n", ...
    lines, samples, dtype, precision, interleave, byte_order, machfmt);

%% 4) 读取 Sigma0（线性）
sig = multibandread(imgPath, [lines samples 1], precision, 0, interleave, machfmt);
sig = double(sig(:,:,1));

%% 5) 屏蔽无效/近零像素（只用于显示）
% 你的统计 p1=-156 dB，说明有大量极小值；建议阈值从 1e-6 开始
minValid = 1e-6;              % 可调：1e-7 / 1e-6 / 1e-5
sig_show = sig;
sig_show(sig_show <= minValid) = NaN;  % 屏蔽近零

%% 6) 转 dB
sig_dB = 10*log10(sig_show);

% 打印统计（确认不再出现 -150 dB）
v = sig_dB(isfinite(sig_dB));
fprintf("📊 masked(minValid=%.1e) dB p1/p50/p99 = %.2f / %.2f / %.2f\n", ...
    minValid, prctile(v,1), prctile(v,50), prctile(v,99));

%% 7) 图 1：分位数拉伸（更通用）
lo = prctile(v, 5);
hi = prctile(v, 95);

figure('Color','w','Name','Sigma0 IW2 VV (dB) percentile stretch');
imagesc(sig_dB, [lo hi]);
axis image off; colormap gray; colorbar;
title(sprintf("Sigma0\\_IW2\\_VV (dB)  %s  mask<=%.1e  stretch=[%.1f, %.1f]", ...
    machfmt, minValid, lo, hi), 'Interpreter','none');

outPng1 = fullfile(dataDir, "Sigma0_IW2_VV_dB_p5_p95.png");
exportgraphics(gcf, outPng1, 'Resolution', 300);
fprintf("✅ Saved: %s\n", outPng1);

%% 8) 图 2：固定显示范围（更像 SNAP 常用）
figure('Color','w','Name','Sigma0 IW2 VV (dB) fixed [-30,0]');
imagesc(sig_dB, [-30 0]);
axis image off; colormap gray; colorbar;
title(sprintf("Sigma0\\_IW2\\_VV (dB) fixed [-30, 0]  %s  mask<=%.1e", ...
    machfmt, minValid), 'Interpreter','none');

outPng2 = fullfile(dataDir, "Sigma0_IW2_VV_dB_fixed_-30_0.png");
exportgraphics(gcf, outPng2, 'Resolution', 300);
fprintf("✅ Saved: %s\n", outPng2);

%% ====== local helper ======
function v = local_get_int(txt, key)
    pat = [key '\s*=\s*([0-9]+)'];
    t = regexp(txt, pat, 'tokens', 'once');
    assert(~isempty(t), "HDR 里找不到字段: %s", key);
    v = str2double(t{1});
    assert(isfinite(v), "字段 %s 解析失败", key);
end