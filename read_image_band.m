function img = read_image_band(dimPath, bandName)
% ✅ Prefer ENVI .hdr if present (most reliable for SNAP .img)
% bandName example: 'Sigma0_IW2_VV'

[folder, base, ~] = fileparts(dimPath);
dataDir = fullfile(folder, [base '.data']);

hdrPath = fullfile(dataDir, [bandName '.hdr']);
imgPath = fullfile(dataDir, [bandName '.img']);

if exist(hdrPath,'file') && exist(imgPath,'file')
    img = read_envi_img(imgPath, hdrPath);
    return;
end

% --- fallback: still try .img without hdr (less reliable) ---
imgPath2 = fullfile(dataDir, [bandName '.img']);
if ~exist(imgPath2, 'file')
    d = dir(fullfile(dataDir,'*.img'));
    names = string({d.name});
    error('Band file not found: %s\nAvailable .img: %s', imgPath2, strjoin(names, ', '));
end

% If no hdr, assume SNAP common default: float32 little-endian BSQ
w = get_abs_meta_int(dimPath,'num_samples_per_line');
h = get_abs_meta_int(dimPath,'num_output_lines');

fid = fopen(imgPath2, 'r', 'ieee-le');
raw = fread(fid, w*h, '*single');
fclose(fid);
img = reshape(raw, [w, h]).';  % (h x w)
end

% =========================================================
% ENVI reader (matches your verified script logic)
% =========================================================
function sig = read_envi_img(imgPath, hdrPath)
txt0 = fileread(hdrPath);
txt  = lower(regexprep(txt0, '[\r\n]+', ' '));

lines      = local_get_int(txt, 'lines');
samples    = local_get_int(txt, 'samples');
bands      = local_get_int(txt, 'bands');
dtype      = local_get_int(txt, 'data type');
byte_order = local_get_int(txt, 'byte order');

m = regexp(txt, 'interleave\s*=\s*(\w+)', 'tokens', 'once');
assert(~isempty(m), "HDR 里找不到 interleave 字段");
interleave = m{1};

assert(bands == 1, "read_image_band: bands must be 1, got %d", bands);

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

if byte_order == 0
    machfmt = 'ieee-le';
elseif byte_order == 1
    machfmt = 'ieee-be';
else
    error("Unknown byte order=%d", byte_order);
end

% ✅ fastest: multibandread
sig = multibandread(imgPath, [lines samples 1], precision, 0, interleave, machfmt);
sig = sig(:,:,1);
end

function v = local_get_int(txt, key)
pat = [key '\s*=\s*([0-9]+)'];
t = regexp(txt, pat, 'tokens', 'once');
assert(~isempty(t), "HDR 里找不到字段: %s", key);
v = str2double(t{1});
assert(isfinite(v), "字段 %s 解析失败", key);
end

function v = get_abs_meta_int(dimPath, key)
doc = xmlread(dimPath);
nodes = doc.getElementsByTagName('MDATTR');
v = NaN;
for i = 1:nodes.getLength
    n = nodes.item(i-1);
    a = n.getAttributes.getNamedItem('name');
    if ~isempty(a) && strcmp(char(a.getValue), key)
        v = str2double(strtrim(char(n.getTextContent)));
        return;
    end
end
end
