#!/usr/bin/env python3
"""Fetch Daymet daily weather and write SWAT+ AW observed station files.

Usage: fetch_daymet.py <weather_dir> <lat> <lon> <start_year> <end_year>

Writes pcp.txt/tmp.txt (station index) + <name>pcp.txt/<name>tmp.txt (data:
line1=YYYYMMDD start, then daily values; tmp is "tmax,tmin"). SWAT+ generates
solar/humidity/wind from the WGN, so only precip + temperature are supplied as
observed. Daymet uses a 365-day calendar (no Dec 31 in leap years); we fill the
gap by repeating the prior day so the series is continuous.

Source: Daymet V4 single-pixel API (ORNL DAAC), free, no auth.
"""
import sys, csv, io, datetime, urllib.request

wdir, lat, lon, y0, y1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])

url = (f"https://daymet.ornl.gov/single-pixel/api/data?lat={lat}&lon={lon}"
       f"&vars=prcp,tmax,tmin&start={y0}-01-01&end={y1}-12-31")
raw = urllib.request.urlopen(url, timeout=120).read().decode()

# skip preamble up to the 'year,yday,...' header
lines = raw.splitlines()
hi = next(i for i, l in enumerate(lines) if l.startswith("year,yday"))
rdr = csv.reader(io.StringIO("\n".join(lines[hi+1:])))
by_date = {}
for r in rdr:
    if len(r) < 5:
        continue
    yr, yday, prcp, tmax, tmin = int(r[0]), int(r[1]), float(r[2]), float(r[3]), float(r[4])
    by_date[datetime.date(yr, 1, 1) + datetime.timedelta(days=yday-1)] = (prcp, tmax, tmin)

start, end = datetime.date(y0, 1, 1), datetime.date(y1, 12, 31)
days = []
d = start
while d <= end:
    v = by_date.get(d) or by_date.get(d - datetime.timedelta(days=1), (0.0, 0.0, 0.0))
    days.append(v)
    d += datetime.timedelta(days=1)

sd = start.strftime("%Y%m%d")
with open(f"{wdir}/pcp.txt", "w") as f:
    f.write(f"ID,NAME,LAT,LONG,ELEVATION\n0,tiffinpcp,{lat},{lon},260.0\n")
with open(f"{wdir}/tiffinpcp.txt", "w") as f:
    f.write(sd + "\n"); [f.write(f"{p:.1f}\n") for p, _, _ in days]
with open(f"{wdir}/tmp.txt", "w") as f:
    f.write(f"ID,NAME,LAT,LONG,ELEVATION\n0,tiffintmp,{lat},{lon},260.0\n")
with open(f"{wdir}/tiffintmp.txt", "w") as f:
    f.write(sd + "\n"); [f.write(f"{tx:.1f},{tn:.1f}\n") for _, tx, tn in days]

tot = sum(p for p, _, _ in days)
print(f"wrote SWAT+ weather: {len(days)} days, {tot/ (y1-y0+1):.0f} mm/yr precip")
