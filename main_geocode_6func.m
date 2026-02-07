function main_geocode_6func()
clc; clear;

% ======================
% Paths
% ======================
dimPath = 'D:\yjs\taiwandata\result\20161212_split_Orb_Cal_deb.dim';
demPath = 'D:\yjs\taiwandata\result\dem.tif';
outTif  = 'D:\yjs\taiwandata\result\geocoded_on_dem_K32_tile512.tif';

% ======================
% Parameters
% ======================
K    = 32;   % control point spacing (try 16 if you need higher accuracy)
tile = 512;  % tile size (256 if RAM is tight)

% ======================
% 1) Read meta/orbit
% ======================
meta  = read_abs_meta(dimPath);
orbit = read_orbit(dimPath);

% ======================
% 2) Align meta.t0 (CRITICAL)
% meta.t0 = first_line_time - orbit_vector1_time  (seconds)
% ======================
firstLineStr = mdattr_text_from_dim(dimPath, 'first_line_time');
firstLineDN  = utc_to_datenum(firstLineStr);

if ~isfield(orbit, 't0_datenum') || ~isfinite(orbit.t0_datenum)
    error('orbit.t0_datenum missing. In read_orbit.m add: orbit.t0_datenum = t0;');
end

meta.t0 = (firstLineDN - orbit.t0_datenum) * 86400; % seconds
fprintf('✅ Aligned meta.t0 = %.6f s\n', meta.t0);

% ======================
% 3) Read SAR band (auto pick first .img)
% ======================
[folder, base, ~] = fileparts(dimPath);
dataDir = fullfile(folder, [base '.data']);
imgs = dir(fullfile(dataDir, '*.img'));
if isempty(imgs), error('No .img found in %s', dataDir); end
[~, bandName, ~] = fileparts(imgs(1).name);  % e.g. Sigma0_IW2_VV

img = read_image_band(dimPath, bandName);
img_db = 10*log10(max(single(img), eps('single')));
v = img_db(isfinite(img_db));
fprintf('IMG(dB) p1/p50/p99 = %.2f / %.2f / %.2f\n', prctile(v,1), prctile(v,50), prctile(v,99));
[Naz, Nrg] = size(img);
fprintf('Using band: %s  (Naz=%d, Nrg=%d)\n', bandName, Naz, Nrg);

imgS = single(img);

% ======================
% 4) Read DEM (NO full lon/lat grid!)
% read_dem_grid returns coordinate vectors xVec(1xNx), yVec(Nyx1)
% ======================
[H, Rdem, xVec, yVec] = read_dem_grid(demPath);
[Ny, Nx] = size(H);
fprintf('DEM size(H) = %d x %d\n', Ny, Nx);

isProj = isprop(Rdem,'ProjectedCRS') && ~isempty(Rdem.ProjectedCRS);

% ======================
% 5) Control point indices
% ======================
rIdx = 1:K:Ny;  if rIdx(end) ~= Ny, rIdx = [rIdx Ny]; end
cIdx = 1:K:Nx;  if cIdx(end) ~= Nx, cIdx = [cIdx Nx]; end
Nr = numel(rIdx);
Nc = numel(cIdx);

azCtrl = nan(Nr, Nc);
rgCtrl = nan(Nr, Nc);

fprintf('Compute control points: Nr=%d, Nc=%d (K=%d)\n', Nr, Nc, K);

% ======================
% 6) Solve az/rg only on control points
% ======================
for ii = 1:Nr
    r = rIdx(ii);

    % Good initial time for this DEM row (aligned)
    tInit = meta.t0 + (r-1) * meta.dtAz;
    tInit = min(max(tInit, orbit.t(1)), orbit.t(end));

    for jj = 1:Nc
        c = cIdx(jj);

        h = H(r,c);
        if ~isfinite(h), continue; end

        x = xVec(c);
        y = yVec(r);

        if isProj
            [lat, lon] = projinv(Rdem.ProjectedCRS, x, y);
        else
            lon = x;
            lat = y;
        end

        [az, rg, tStar] = geo2pixel(lat, lon, h, meta, orbit, tInit);

        azCtrl(ii,jj) = az;
        rgCtrl(ii,jj) = rg;

        if isfinite(tStar)
            tInit = min(max(tStar, orbit.t(1)), orbit.t(end));
        end
    end

    if mod(ii, max(1,floor(Nr/10)))==0
        fprintf('  ctrl row %d/%d\n', ii, Nr);
    end
end

% ======================
% 7) Quick sanity on control points (should be mostly in-range)
% ======================
vCtrl = isfinite(azCtrl) & isfinite(rgCtrl) & ...
        azCtrl>=1 & azCtrl<=Naz & rgCtrl>=1 & rgCtrl<=Nrg;

fprintf('ctrl valid ratio = %.2f%%\n', 100*mean(vCtrl(:)));
if any(vCtrl(:))
    fprintf('azCtrl range = [%.1f, %.1f]\n', min(azCtrl(vCtrl)), max(azCtrl(vCtrl)));
    fprintf('rgCtrl range = [%.1f, %.1f]\n', min(rgCtrl(vCtrl)), max(rgCtrl(vCtrl)));
else
    warning('No valid control points. Check t0 alignment / DEM extent.');
end

% ======================
% 8) Build interpolants in DEM index space (col,row)->(az,rg)
% ======================
[CC, RR] = meshgrid(cIdx, rIdx);
mask = isfinite(azCtrl) & isfinite(rgCtrl);

Faz = scatteredInterpolant(CC(mask), RR(mask), azCtrl(mask), 'linear', 'none');
Frg = scatteredInterpolant(CC(mask), RR(mask), rgCtrl(mask), 'linear', 'none');

% ======================
% 9) Tile-by-tile interpolate & resample (NO full azMap/rgMap)
% ======================
out = nan(Ny, Nx, 'single');
validAll = false(Ny, Nx);

fprintf('Tile warping (tile=%d)...\n', tile);

for r0 = 1:tile:Ny
    r1 = min(Ny, r0 + tile - 1);
    rr = r0:r1;

    for c0 = 1:tile:Nx
        c1 = min(Nx, c0 + tile - 1);
        cc = c0:c1;

        [ccTile, rrTile] = meshgrid(cc, rr);

        azTile = Faz(ccTile, rrTile);
        rgTile = Frg(ccTile, rrTile);

        v = isfinite(azTile) & isfinite(rgTile) & ...
            azTile>=1 & azTile<=Naz & rgTile>=1 & rgTile<=Nrg;

        if any(v(:))
            tileOut = nan(size(azTile), 'single');
            tileOut(v) = single(interp2(imgS, rgTile(v), azTile(v), 'linear', NaN));
            out(rr, cc) = tileOut;
            validAll(rr, cc) = v;
        end
    end

    fprintf('  rows %d/%d\n', r1, Ny);
end

% ======================
% 10) Write GeoTIFF (same size as DEM)
% ======================
geotiffwrite(outTif, out, Rdem);
fprintf('✅ Saved: %s\n', outTif);

% ======================
% 11) Visualize
% ======================
figure; imagesc(validAll); axis image; colorbar;
title('Valid mask on DEM grid (tile-based)');

% ===== SNAP-like display: dB + percentile stretch =====
out_db = 10*log10(max(out, eps('single')));      % Sigma0 -> dB
vals = out_db(isfinite(out_db));
p = prctile(vals, [2 98]);                       % SNAP 类似的拉伸范围

figure; imagesc(out_db); axis image; colormap gray;
caxis(p); colorbar;
title(sprintf('Geocoded output (dB, 2-98%% stretch) (K=%d, tile=%d)', K, tile));

end

% =========================================================
% Local helpers (in same file)
% =========================================================

function s = mdattr_text_from_dim(dimPath, key)
doc = xmlread(dimPath);
nodes = doc.getElementsByTagName('MDATTR');
s = '';
for i = 1:nodes.getLength
    n = nodes.item(i-1);
    a = n.getAttributes.getNamedItem('name');
    if ~isempty(a) && strcmp(char(a.getValue), key)
        s = strtrim(char(n.getTextContent));
        return;
    end
end
end

function dn = utc_to_datenum(s)
try
    dt = datetime(s, 'InputFormat','dd-MMM-yyyy HH:mm:ss.SSSSSS', 'Locale','en_US');
catch
    dt = datetime(s, 'InputFormat','dd-MMM-yyyy HH:mm:ss', 'Locale','en_US');
end
dn = datenum(dt);
end
