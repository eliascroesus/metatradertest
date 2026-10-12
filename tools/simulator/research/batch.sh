#!/bin/bash
# research/batch.sh <period: train|test|all> <experiments file>   (lines: name<TAB>--set ... ; runs 4 at a time)
cd "$(dirname "$0")/.." || exit 1
D=${GOLD_DATA:-$PWD/research/data}
case $1 in
  train) from=2012-01-01 to=2016-01-01 files="$D/xau2011.bin $D/xau2012.bin $D/xau2013.bin $D/xau2014.bin $D/xau2015.bin";;
  test)  from=2016-01-01 to=2018-07-01 files="$D/xau2015.bin $D/xau2016.bin $D/xau2017.bin $D/xau2018.bin";;
  all)   from=2012-01-01 to=2018-07-01 files="$D/xau2011.bin $D/xau2012.bin $D/xau2013.bin $D/xau2014.bin $D/xau2015.bin $D/xau2016.bin $D/xau2017.bin $D/xau2018.bin";;
esac
mkdir -p build/research/out
grep -v '^#' "$2" | grep -v '^$' | while IFS=$'\t' read -r name sets; do echo "$name|$sets"; done |
  xargs -P 4 -I{} bash -c 'line="{}"; name="${line%%|*}"; sets="${line#*|}"; eval EA=${EA:-GoldScalperFVG} research/run.sh "${name}_'$1'" '$from' '$to' 3 0 \"'"$files"'\" $sets > build/research/out/${name}_'$1'.txt 2>&1'
for n in $(grep -v '^#' "$2" | grep -v '^$' | cut -f1); do f=build/research/out/${n}_$1.txt; printf "%-28s %s\n" "$n" "$(grep '^ALL' $f | sed 's/ ticks=.*//')"; done
