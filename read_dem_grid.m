function [H, R, xVec, yVec] = read_dem_grid(demTifPath)
% Output:
%   H    : Ny x Nx elevation
%   R    : raster reference
%   xVec : 1 x Nx pixel-center X (lon for geographic DEM)
%   yVec : Ny x 1 pixel-center Y (lat for geographic DEM)

[H, R] = readgeoraster(demTifPath);
H = double(H);
H(H < -1000) = NaN;

[Ny, Nx] = size(H);

% GeographicCellsReference (lon/lat)
if isprop(R,'LongitudeLimits') && isprop(R,'LatitudeLimits')
    lonlim = R.LongitudeLimits;
    latlim = R.LatitudeLimits;

    dlon = (lonlim(2) - lonlim(1)) / Nx;
    dlat = (latlim(2) - latlim(1)) / Ny;

    xVec = lonlim(1) + ((1:Nx) - 0.5) * dlon;             % lon
    yVec = (latlim(2) - ((1:Ny) - 0.5) * dlat).';         % lat (north->south)
    return;
end

% MapCellsReference (projected x/y)
if isprop(R,'XWorldLimits') && isprop(R,'YWorldLimits')
    xlim = R.XWorldLimits;
    ylim = R.YWorldLimits;

    dx = (xlim(2) - xlim(1)) / Nx;
    dy = (ylim(2) - ylim(1)) / Ny;

    xVec = xlim(1) + ((1:Nx) - 0.5) * dx;                 % x
    yVec = (ylim(2) - ((1:Ny) - 0.5) * dy).';             % y (top->bottom)
    return;
end

error('Unsupported raster reference object: cannot derive coordinate vectors.');
end
