#!/bin/bash
# BMP scenario ensemble over the real Tiffin TxtInOut. Each scenario = a
# calibration.cal parameter edit; run SWAT+; extract outlet (ch 1195) daily flow.
set -e
SRC=/model/tiffin/Scenarios/Default/TxtInOut
SWATBIN=/root/.SWAT/SWATPlus/Workflow/editor_api/swat_exe/rev60.5.2_64rel_linux
OUT=/model/ensemble_out
mkdir -p $OUT
SCEN="s01|Baseline|0|0.95|4
s02|Cover crops|-8|0.95|4
s03|Reduced tillage|-4|0.95|4
s04|Drainage water mgmt|0|0.95|8
s05|Higher ET|0|0.80|4
s06|Aggressive BMP combo|-8|0.85|8"

echo "scenario,mean_cms,max_cms,nonzero" > $OUT/summary.csv
while IFS='|' read -r sid label cn2 esco surlag; do
  [ -z "$sid" ] && continue
  d=$OUT/$sid
  rm -rf $d; cp -r $SRC $d
  cp -f $SWATBIN $d/swatplus.bin && chmod +x $d/swatplus.bin
  cat > $d/calibration.cal <<CAL
calibration.cal: aws-swat-demo BMP scenario $sid
 3
NAME           CHG_TYP                  VAL   CONDS  LYR1   LYR2  YEAR1  YEAR2   DAY1   DAY2  OBJ_TOT
cn2             pctchg            $cn2       0     0      0      0      0      0      0        0
esco            absval            $esco       0     0      0      0      0      0      0        0
surlag          absval            $surlag       0     0      0      0      0      0      0        0
CAL
  cd $d
  ./swatplus.bin > run.log 2>&1 || true
  if [ -f channel_sd_day.txt ]; then
    awk 'NR>3 && $5==1195 {printf "%04d-%02d-%02d,%s\n",$4,$2,$3,$48}' channel_sd_day.txt > $OUT/${sid}_flow.csv
    awk -F, '{v=$2+0; s+=v; if(v>mx)mx=v; if(v>0)nz++; n++} END{printf "'"$sid"',%.3f,%.1f,%d\n", s/n, mx, nz}' $OUT/${sid}_flow.csv >> $OUT/summary.csv
    echo "  $sid ($label): done  ($(wc -l < $OUT/${sid}_flow.csv) days)"
  else
    echo "  $sid: NO OUTPUT"; tail -3 run.log; echo "$sid,NA,NA,0" >> $OUT/summary.csv
  fi
done <<< "$SCEN"
echo "=== SUMMARY ==="; cat $OUT/summary.csv
