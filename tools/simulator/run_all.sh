#!/bin/bash
# Developer checks for the MQL5 code in this repository.
# Not needed to use the EA in MetaTrader. Needs python3 and g++ (C++17).
#   1. Syntax/type check of every .mq5 file against a stand-in of the MQL5 API (mql5_mock.h).
#   2. Runs the EA on a simulated gold market with a simulated broker (mql5_sim.h) and checks
#      every entry, stop, break-even, trailing move, lot size, safety switch and CSV line
#      against the written rules (sim_main.cpp).
#   3. Tests the two helper scripts the same way (news_main.cpp, spread_main.cpp).
cd "$(dirname "$0")" || exit 1
REPO=../..
B=build
mkdir -p $B
failures=0
pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; failures=$((failures + 1)); }

echo "1) Syntax check"
for f in Experts/GoldBreakoutEA Experts/GoldScalperFVG Scripts/GoldBreakout_ExportNews Scripts/GoldBreakout_SpreadTestSymbol; do
  python3 mq5_to_cpp.py $REPO/MQL5/$f.mq5 > $B/check.cpp &&
    g++ -std=c++17 -fsyntax-only -Wall -Wextra -Wno-unused-parameter -I. $B/check.cpp && pass "$f" || fail "$f"
done

echo "2) EA on a simulated market (each line = one scenario; any rule violation fails it)"
scenario() {  # scenario <label> <market seed> <days> [--set Input=Value ...]   (SIM_* env vars pass through)
  local label=$1 seed=$2 days=$3; shift 3
  python3 mq5_to_cpp.py $REPO/MQL5/Experts/GoldBreakoutEA.mq5 --header mql5_sim.h "$@" > $B/ea_sim.inc || { fail "$label (convert)"; return; }
  g++ -std=c++17 -O2 -I. -I$B -o $B/sim sim_main.cpp 2> $B/build.log || { fail "$label (build)"; head -20 $B/build.log; return; }
  local out; out=$(cd $B && rm -f simout_* && ./sim $seed $days quiet)
  if [ $? -eq 0 ]; then pass "$label | $(echo "$out" | grep -m1 '^balance' | sed 's/ | CSV.*//')"; else fail "$label"; echo "$out" | grep -m5 "CHECK FAILED"; fi
}
for s in 1 2 3 4 5; do scenario "default settings, market seed $s" $s 365; done
scenario "kill switch at 2%"                 3 365 --set KillSwitchDrawdownPercent=2.0
scenario "daily loss limit 0.4%"             3 365 --set DailyLossLimitPercent=0.4
SIM_COMMISSION=3.5 SIM_STOPSLEVEL=50 scenario "commission + broker stop level" 4 365
scenario "tight spread filter"               2 365 --set MaxSpreadUSD=0.24
python3 - <<'PY'
import datetime as dt
lines = ["# test news file", "Time,Event"]
d = dt.date(2023, 1, 2)
while d < dt.date(2024, 6, 1):
    if d.weekday() < 5:
        lines.append(f"{d:%Y.%m.%d} 15:30,Fake US data, with comma")
        lines.append(f"{d:%Y-%m-%d} 09:00")
    d += dt.timedelta(days=1)
open("build/news_test.csv", "w").write("﻿" + "\r\n".join(lines) + "\r\n")
PY
SIM_NEWSFILE=news_test.csv scenario "news file + manual news times" 5 365 --set 'ManualNewsTimes="2023.03.15 14:00; 2023.03.16 11:00,2023.03.17 12:00"'
scenario "random twin, 116/yr, seed 1"       1 365 --set RandomEntryMode=true --set RandomTradesPerYear=116 --set RandomSeed=1
scenario "random twin, 40/yr, seed 2"        1 365 --set RandomEntryMode=true --set RandomTradesPerYear=40 --set RandomSeed=2
SIM_LIVE=1 SIM_RESTART_EVERY=37000 scenario "live mode, restarts" 2 365
SIM_LIVE=1 SIM_RESTART_EVERY=37000 SIM_OFFLINE_TICKS=3000 scenario "live mode, EA off 10h at restarts" 2 365
scenario "break-even +0.10, trailing step 0" 3 365 --set BreakEvenExtraUSD=0.10 --set TrailingStepATR=0
scenario "smallest lot too risky"            1 120 --set RiskPercentPerTrade=0.05 --set MaxRiskPercentAtMinLot=0.1
scenario "ResetKillSwitch = true"            1 60  --set ResetKillSwitch=true

echo "3) GoldScalperFVG on a simulated market"
python3 mq5_to_cpp.py $REPO/MQL5/Experts/GoldScalperFVG.mq5 --header mql5_sim.h > $B/scalp_sim.inc &&
  g++ -std=c++17 -O2 -I. -I$B -o $B/scalp scalp_main.cpp || fail "scalper (build)"
for s in 1 2 3 4 5; do
  r=$(cd $B && rm -f simout_* && ./scalp $s 60); [ $? -eq 0 ] && pass "scalper, market seed $s | ${r%% | balance*}" || { fail "scalper seed $s"; echo "$r" | grep -m5 "CHECK FAILED"; }
done
scalp_set() {  # scalp_set <label> <seed> --set X=Y ...
  local label=$1 seed=$2; shift 2
  python3 mq5_to_cpp.py $REPO/MQL5/Experts/GoldScalperFVG.mq5 --header mql5_sim.h "$@" > $B/scalp_sim.inc &&
    g++ -std=c++17 -O2 -I. -I$B -o $B/scalp2 scalp_main.cpp || { fail "$label (build)"; return; }
  r=$(cd $B && rm -f simout_* && ./scalp2 $seed 60); [ $? -eq 0 ] && pass "scalper, $label | ${r%% | balance*}" || { fail "scalper $label"; echo "$r" | grep -m5 "CHECK FAILED"; }
}
scalp_set "max 2 trades, 5-min gaps" 2 --set MaxOpenTrades=2 --set SignalTimeframe=PERIOD_M5
scalp_set "daily loss limit 0.3%" 3 --set DailyLossLimitPercent=0.3
scalp_set "tight spread filter" 4 --set MaxSpreadUSD=0.24

echo "4) Helper scripts"
python3 mq5_to_cpp.py $REPO/MQL5/Scripts/GoldBreakout_ExportNews.mq5 --header mql5_sim.h > $B/news_sim.inc &&
  g++ -std=c++17 -O1 -I. -I$B -o $B/news_test news_main.cpp || fail "news script (build)"
for clock in ny7 gmt0 eu; do for cal in uniform seasonal; do for month in 1 3 6 11; do
  r=$(cd $B && ./news_test $clock $cal $month | head -1)
  (cd $B && ./news_test $clock $cal $month > /dev/null) && pass "news export: broker clock $clock, calendar $cal, run in month $month" || { fail "news export $clock/$cal/$month"; echo "   $r"; }
done; done; done
python3 mq5_to_cpp.py $REPO/MQL5/Scripts/GoldBreakout_SpreadTestSymbol.mq5 --header mql5_sim.h > $B/spread_sim.inc &&
  g++ -std=c++17 -O1 -I. -I$B -o $B/spread_test spread_main.cpp && r=$(cd $B && ./spread_test | tail -1) && pass "spread copy: $r" || fail "spread copy"

echo
if [ $failures -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "$failures CHECK(S) FAILED"; fi
exit $failures
