#!/bin/bash
# research/run.sh <name> <from> <to> <scale> <extraSpread> "<data files>" [--set Input=Value ...]
# Builds GoldScalperFVG with the given settings and runs it on real ticks.
cd "$(dirname "$0")/.." || exit 1
name=$1 from=$2 to=$3 scale=$4 extra=$5 files=$6; shift 6
mkdir -p build/research
python3 mq5_to_cpp.py ../../MQL5/Experts/${EA:-GoldScalperFVG}.mq5 --header mql5_sim.h --set 'CsvFilePrefix=""' --set KillSwitchDrawdownPercent=0 "$@" > build/research/$name.inc || exit 1
sed "s|research_ea.inc|$name.inc|" research/research_main.cpp > build/research/$name.cpp
g++ -std=c++17 -O2 -I. -Ibuild/research -o build/research/$name build/research/$name.cpp || exit 1
echo "== $name  ($*)"
./build/research/$name $from $to $scale $extra $files
