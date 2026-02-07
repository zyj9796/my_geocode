function orbit = read_orbit(dimPath)
doc = xmlread(dimPath);

% 找到 Orbit_State_Vectors 这个 MDElem
mdElems = doc.getElementsByTagName('MDElem');
osvElem = [];
for i = 1:mdElems.getLength
    e = mdElems.item(i-1);
    a = e.getAttributes.getNamedItem('name');
    if ~isempty(a) && strcmp(char(a.getValue), 'Orbit_State_Vectors')
        osvElem = e;
        break;
    end
end
if isempty(osvElem)
    error('Orbit_State_Vectors not found in DIM.');
end

% Orbit_State_Vectors 下的子 MDElem：orbit_vector1/2/...
child = osvElem.getChildNodes;
tList = [];
pos = [];
vel = [];

for i = 1:child.getLength
    nd = child.item(i-1);
    if ~strcmp(char(nd.getNodeName), 'MDElem'), continue; end

    % 读取这个 orbit_vector 的属性（MDATTR）
    timeStr = mdattr_text(nd, 'time', '');
    x = mdattr_num_node(nd, 'x_pos', NaN);
    y = mdattr_num_node(nd, 'y_pos', NaN);
    z = mdattr_num_node(nd, 'z_pos', NaN);
    vx = mdattr_num_node(nd, 'x_vel', NaN);
    vy = mdattr_num_node(nd, 'y_vel', NaN);
    vz = mdattr_num_node(nd, 'z_vel', NaN);

    if isempty(timeStr) || any(~isfinite([x y z vx vy vz]))
        continue;
    end

    tList(end+1,1) = utc_to_datenum(timeStr); %#ok<AGROW>
    pos(end+1,:) = [x y z]; %#ok<AGROW>
    vel(end+1,:) = [vx vy vz]; %#ok<AGROW>
end

if isempty(tList)
    error('No valid orbit vectors parsed.');
end

% 把 UTC datenum 转成相对秒（以第一条为 0）
t0 = tList(1);
orbit.t0_datenum = t0;
tSec = (tList - t0) * 86400;

orbit.t = tSec(:);
orbit.pos = pos;
orbit.vel = vel;

orbit.posI = griddedInterpolant(orbit.t, orbit.pos, 'pchip', 'nearest');
orbit.velI = griddedInterpolant(orbit.t, orbit.vel, 'pchip', 'nearest');
end

% ===== 内嵌工具：在某个 MDElem 节点内找 MDATTR =====
function v = mdattr_num_node(elemNode, key, defaultVal)
v = defaultVal;
kids = elemNode.getElementsByTagName('MDATTR');
for i = 1:kids.getLength
    n = kids.item(i-1);
    a = n.getAttributes.getNamedItem('name');
    if ~isempty(a) && strcmp(char(a.getValue), key)
        txt = strtrim(char(n.getTextContent));
        vv = str2double(txt);
        if ~isnan(vv), v = vv; end
        return;
    end
end
end

function t = mdattr_text(elemNode, key, defaultTxt)
t = defaultTxt;
kids = elemNode.getElementsByTagName('MDATTR');
for i = 1:kids.getLength
    n = kids.item(i-1);
    a = n.getAttributes.getNamedItem('name');
    if ~isempty(a) && strcmp(char(a.getValue), key)
        t = strtrim(char(n.getTextContent));
        return;
    end
end
end

function dn = utc_to_datenum(s)
% 输入示例：'12-DEC-2016 21:52:16.689921'
% MATLAB datenum 解析（用 datetime 更稳）
try
    dt = datetime(s, 'InputFormat','dd-MMM-yyyy HH:mm:ss.SSSSSS', 'Locale','en_US');
catch
    dt = datetime(s, 'InputFormat','dd-MMM-yyyy HH:mm:ss', 'Locale','en_US');
end
dn = datenum(dt);
end
