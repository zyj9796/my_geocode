function meta = read_abs_meta(dimPath)
doc = xmlread(dimPath);
meta = struct();

% Raster size：直接用 Abstracted_Metadata 里的 num_output_lines/num_samples_per_line 更稳
meta.Naz = mdattr_num(doc, 'num_output_lines', NaN);
meta.Nrg = mdattr_num(doc, 'num_samples_per_line', NaN);

% PRF / dtAz
meta.PRF  = mdattr_num(doc, 'pulse_repetition_frequency', NaN);
meta.dtAz = mdattr_num(doc, 'line_time_interval', NaN);   % seconds

% R0
meta.R0 = mdattr_num(doc, 'slant_range_to_first_pixel', NaN);

% range sampling rate (MHz -> Hz)
fs_mhz = mdattr_num(doc, 'range_sampling_rate', NaN);
if isfinite(fs_mhz)
    meta.fsR = fs_mhz * 1e6;  % Hz
else
    meta.fsR = NaN;
end

c = 299792458;
if isfinite(meta.fsR)
    meta.dtR = 1/meta.fsR;
    meta.dR  = c * meta.dtR / 2;
else
    meta.dtR = NaN;
    meta.dR  = NaN;
end

% t0：先用 0（相对秒）。若你想绝对时间一致，后面再把 first_line_time 解析成秒基准
meta.t0 = 0;

% 默认 band 名称：先给一个常见值；若不对，main 里手动改
meta.defaultBandName = 'Intensity_VV';

% sanity
if ~isfinite(meta.Naz) || ~isfinite(meta.Nrg)
    warning('Raster size not found (Naz/Nrg).');
end
if ~isfinite(meta.dtAz)
    warning('line_time_interval not found -> meta.dtAz NaN.');
end
if ~isfinite(meta.R0)
    warning('slant_range_to_first_pixel not found -> meta.R0 NaN.');
end
if ~isfinite(meta.dR)
    warning('range_sampling_rate not found -> meta.dR NaN.');
end
end

% ====== 内嵌：从 MDATTR name="xxx" 读取数值 ======
function v = mdattr_num(doc, key, defaultVal)
v = defaultVal;
nodes = doc.getElementsByTagName('MDATTR');
for i = 1:nodes.getLength
    n = nodes.item(i-1);
    if n.hasAttributes
        a = n.getAttributes.getNamedItem('name');
        if ~isempty(a) && strcmp(char(a.getValue), key)
            txt = strtrim(char(n.getTextContent));
            vv = str2double(txt);
            if ~isnan(vv), v = vv; end
            return;
        end
    end
end
end
