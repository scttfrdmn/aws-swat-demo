#!/usr/bin/env python3
"""Write a SWAT+ usersoil.csv (152-col schema) for the Hoytville series.

SWAT+ AW's editor (DBUtils.writeUsedSoilRow) reads fixed column indices:
12 base cols + 12 cols x 10 layer-slots + SOL_CAL1..10 (idx 132) + SOL_PH1..10
(idx 142) = 152 columns. Layers beyond NLAYERS are zero-filled.

Hoytville: fine, poorly-drained Mollisol (hydrologic group C/D) typical of the
Maumee lake plain; 2 layers with representative SSURGO physical properties.
"""
import sys

base_cols = ["OBJECTID","MUID","SEQN","SNAM","S5ID","CMPPCT","NLAYERS","HYDGRP",
             "SOL_ZMX","ANION_EXCL","SOL_CRK","TEXTURE"]
per = ["SOL_Z","SOL_BD","SOL_AWC","SOL_K","SOL_CBN","CLAY","SILT","SAND","ROCK",
       "SOL_ALB","USLE_K","SOL_EC"]

header = list(base_cols)
for i in range(1, 11):
    header += [f"{c}{i}" for c in per]
header += [f"SOL_CAL{i}" for i in range(1, 11)]
header += [f"SOL_PH{i}" for i in range(1, 11)]
assert len(header) == 152

# (SOL_Z mm, BD g/cm3, AWC, K mm/hr, CBN %, clay/silt/sand %, rock %, albedo, USLE_K, EC)
L1 = [250, 1.35, 0.18, 3.5, 2.5, 33, 48, 19, 0, 0.04, 0.28, 0]
L2 = [1520, 1.45, 0.15, 1.2, 0.4, 45, 38, 17, 0, 0.04, 0.24, 0]
base = [1, "Hoytville", 1, "Hoytville", 0, 100, 2, "C", 1520, 0.5, 0.5, "SICL"]
row = base + L1 + L2 + [0]*12*8 + [0]*10 + [6.5, 6.8] + [0]*8
assert len(row) == 152

out = sys.argv[1] if len(sys.argv) > 1 else "usersoil.csv"
with open(out, "w") as f:
    f.write(",".join(header) + "\n")
    f.write(",".join(str(x) for x in row) + "\n")
print(f"wrote {out}: 152 cols, Hoytville, 2 layers, HYDGRP C")
