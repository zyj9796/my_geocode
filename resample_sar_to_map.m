function [out, valid] = resample_sar_to_map(img, azMap, rgMap)
[Naz, Nrg] = size(img);

valid = isfinite(azMap) & isfinite(rgMap) & ...
        azMap>=1 & azMap<=Naz & rgMap>=1 & rgMap<=Nrg;

out = nan(size(azMap));
out(valid) = interp2(img, rgMap(valid), azMap(valid), 'linear', NaN);
end
