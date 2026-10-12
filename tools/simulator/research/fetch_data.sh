#!/bin/bash
# Downloads real gold (XAUUSD) tick data 2011 - mid 2018 (Dukascopy ticks, published in the
# public GitHub repository FX-Data/FX-Data-XAUUSD-DS, one branch per year) and converts it
# into compact binary files for research_main.cpp. Needs git, g++ and about 3 GB of free disk
# while it runs (1.5 GB at the end).   Usage: research/fetch_data.sh [target folder]
cd "$(dirname "$0")/.." || exit 1
D=${1:-${GOLD_DATA:-$PWD/research/data}}
mkdir -p "$D" build
g++ -O2 -std=c++17 -o build/convert_ticks research/convert_ticks.cpp || exit 1
for y in 2011 2012 2013 2014 2015 2016 2017 2018; do
  [ -f "$D/xau$y.bin" ] && continue
  rm -rf "$D/raw$y"
  git clone -q --depth 1 -b XAUUSD-$y https://github.com/FX-Data/FX-Data-XAUUSD-DS "$D/raw$y" || exit 1
  find "$D/raw$y/XAUUSD" -name '*_ticks.csv' | sort | ./build/convert_ticks "$D/xau$y.bin" && rm -rf "$D/raw$y"
  echo "$y done"
done
