#!/usr/bin/env python3
"""Cache a slice of NWM retrospective streamflow from RODA for offline/dev use.

Reads the NOAA National Water Model CONUS Retrospective v3.0 Zarr store
(s3://noaa-nwm-retrospective-3-0-pds, anonymous) for one reach (feature_id ==
NHDPlus COMID) and writes a small CSV the R code falls back to when reticulate/
Python isn't available at runtime.

Usage:
    pip install xarray zarr s3fs fsspec numpy pandas
    python3 data-raw/cache-nwm.py --comid 15634673 --start 2015-01-01 --end 2015-12-31

Writes: data-raw/nwm_cache/nwm_<comid>.csv  (columns: date, flow_cms, source)

15634673 = Maumee River at Waterville, OH (USGS 04193500), resolved via USGS NLDI.
"""
import argparse, os
import xarray as xr

ZARR = "s3://noaa-nwm-retrospective-3-0-pds/CONUS/zarr/chrtout.zarr"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--comid", type=int, required=True)
    ap.add_argument("--start", default="2015-01-01")
    ap.add_argument("--end", default="2015-12-31")
    args = ap.parse_args()

    ds = xr.open_zarr(ZARR, storage_options={"anon": True}, consolidated=True)
    reach = ds.sel(feature_id=args.comid).sel(time=slice(args.start, args.end))
    daily = reach["streamflow"].resample(time="1D").mean()
    df = daily.to_dataframe().reset_index()[["time", "streamflow"]]
    df.columns = ["date", "flow_cms"]
    df["date"] = df["date"].dt.strftime("%Y-%m-%d")
    df["source"] = "RODA NWM v3.0 (cached)"

    out_dir = os.path.join(os.path.dirname(__file__), "nwm_cache")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"nwm_{args.comid}.csv")
    df.to_csv(out, index=False)
    print(f"Wrote {out}  ({len(df)} days, mean flow {df['flow_cms'].mean():.1f} m^3/s)")

if __name__ == "__main__":
    main()
