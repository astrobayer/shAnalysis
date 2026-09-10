#!/usr/bin/env python3
"""Oracle for shLowLevel.readGrid (WP5 5e): an independent reading of CF
time axes and of one real GravIS Level-3 grid.

CLAIM 1  CF time units -> decimal years, by Python's datetime and the
         toolbox's calendar definition (year + (t - 1 January) / length of
         that year), for the unit strings the MATLAB tests use - including
         GravIS's one-digit month, "days since 2002-4-18 00:00:00", which
         shLowLevel.readMascon's own pattern could not read before v5.8.0.
CLAIM 2  writeGrid's forward map (decimal year -> days since 2002-01-01)
         followed by this inverse returns the epoch; the largest error of
         the double-precision chain is reported.
CLAIM 3  The GravIS TWS grid read by scipy.io.netcdf_file, a reader that
         shares nothing with MATLAB's ncread: latitude and longitude axes,
         the epochs, the NaN count of the first epoch, and tws at fixed
         land cells in the first and last epoch. PIN values for the
         MATLAB real-file test. Skipped when the file is not there.

Run: python3 tools/dev/validate_readgrid.py
Exit 0 when every claim holds.

Developed by Matthias Weigelt with the help of Claude (Opus 5), 2026-09-10.
"""
import datetime as dt
import glob
import math
import os
import sys

import numpy as np

UNIT = {"day": 86400.0, "hour": 3600.0, "minute": 60.0, "second": 1.0}


def dec_year(t):
    """datetime -> decimal year, the toolbox's calendar definition."""
    y0 = dt.datetime(t.year, 1, 1)
    y1 = dt.datetime(t.year + 1, 1, 1)
    return t.year + (t - y0).total_seconds() / (y1 - y0).total_seconds()


def cf_decode(values, units):
    """An independent CF decoder: '<unit> since Y-M-D[ h:m[:s]]'."""
    head, ref = units.split(" since ")
    unit = head.strip().lower().rstrip("s")
    ref = ref.strip().replace("T", " ").rstrip("Z").strip()
    date, _, clock = ref.partition(" ")
    y, m, d = (int(x) for x in date.split("-"))
    hh = mm = 0
    ss = 0.0
    if clock:
        parts = clock.split(":")
        hh = int(parts[0])
        mm = int(parts[1]) if len(parts) > 1 else 0
        ss = float(parts[2]) if len(parts) > 2 else 0.0
    t0 = dt.datetime(y, m, d, hh, mm) + dt.timedelta(seconds=ss)
    return [dec_year(t0 + dt.timedelta(seconds=v * UNIT[unit])) for v in values]


def claim1():
    cases = [
        ("days since 2002-4-18 00:00:00", [0.29, 15.5, 8764.0]),
        ("days since 2002-01-01", [0.0, 365.0, 3652.5]),
        ("hours since 2000-01-01 00:00:00", [0.0, 36.0, 8784.0]),
        ("seconds since 1970-01-01T00:00:00Z", [0.0, 1.0e9]),
        ("minutes since 2010-06-15 12:00", [0.0, 1440.0]),
    ]
    for units, vals in cases:
        out = cf_decode(vals, units)
        print("PIN time %-38r %s -> %s" % (units, vals,
              ", ".join("%.12f" % v for v in out)))
    # a leap year is 366 days long: noon on 2004-12-31 is 2004 + 365.5/366
    got = cf_decode([365.5], "days since 2004-01-01")[0]
    want = 2004 + 365.5 / 366
    assert abs(got - want) < 1e-12, (got, want)
    print("CLAIM 1 ok: the leap-year length enters (noon 31 Dec 2004 -> %.12f)" % got)


def claim2():
    worst = 0.0
    t0 = dt.datetime(2002, 1, 1)
    for ep in np.linspace(2002.01, 2025.99, 997):
        yy = math.floor(ep)
        frac = ep - yy
        span = (dt.datetime(yy + 1, 1, 1) - dt.datetime(yy, 1, 1)).total_seconds()
        stamp = dt.datetime(yy, 1, 1) + dt.timedelta(seconds=frac * span)
        days = (stamp - t0).total_seconds() / 86400.0
        back = cf_decode([days], "days since 2002-01-01")[0]
        worst = max(worst, abs(back - ep))
    print("CLAIM 2 ok: writeGrid forward + this inverse, worst error %.3g yr" % worst)
    assert worst < 1e-9


def claim3():
    folder = os.environ.get("SHX_GRAVIS_FOLDER", "E:/DATAPOOL/GravityField/GravIS")
    path = os.path.join(folder, "GRAVIS-3_GFZOP_0600_TWS_GRID_GFZ_0006.nc")
    if not os.path.isfile(path):
        print("CLAIM 3 skipped: %s not found" % path)
        return
    from scipy.io import netcdf_file
    f = netcdf_file(path, "r", mmap=False, maskandscale=False)
    try:
        lat = np.asarray(f.variables["lat"][:], dtype=float)
        lon = np.asarray(f.variables["lon"][:], dtype=float)
        tv = f.variables["time"]
        tunits = tv.units.decode() if isinstance(tv.units, bytes) else tv.units
        ep = cf_decode(np.asarray(tv[:], dtype=float).tolist(), tunits)
        v = f.variables["tws"]
        fill = float(v._FillValue)
        dims = v.dimensions
        x = np.asarray(v[:], dtype=float)
    finally:
        f.close()
    x[x == fill] = np.nan
    print("PIN grid dims %s shape %s units %r" % (dims, x.shape, tunits))
    assert dims == (b"time", b"lat", b"lon") or dims == ("time", "lat", "lon"), dims
    print("PIN lat %.4f .. %.4f (%d)  lon %.4f .. %.4f (%d)" % (
        lat[0], lat[-1], lat.size, lon[0], lon[-1], lon.size))
    print("PIN epochs %d, first %.12f, last %.12f" % (len(ep), ep[0], ep[-1]))
    print("PIN NaN in epoch 1: %d of %d" % (np.isnan(x[0]).sum(), x[0].size))
    for la, lo in ((-3.5, 299.5), (0.5, 20.5), (61.5, 99.5), (45.5, 10.5)):
        i = int(np.argmin(abs(lat - la)))
        j = int(np.argmin(abs(lon - lo)))
        print("PIN tws lat %6.2f lon %7.2f: first %.15g  last %.15g" % (
            lat[i], lon[j], x[0, i, j], x[-1, i, j]))
    print("CLAIM 3 ok: read by scipy, independent of MATLAB")


if __name__ == "__main__":
    claim1()
    claim2()
    claim3()
    sys.exit(0)
