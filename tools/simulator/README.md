# Developer checks (not needed to use the EA)

MetaEditor only runs on MetaTrader's own platform, so these checks test the MQL5 code
elsewhere:

* `mql5_mock.h` + `mq5_to_cpp.py`: translate each `.mq5` file to C++ and compile it against
  declarations of the MQL5 functions it uses (catches typos, wrong types and wrong arguments).
* `mql5_sim.h` + `sim_main.cpp`: a small simulated market and broker. The EA runs on years of
  synthetic gold ticks, and an independent checker verifies every entry, stop, break-even,
  trailing move, lot size, safety switch and CSV line against the rules.
* `news_main.cpp`, `spread_main.cpp`: the same for the two helper scripts.

Run everything with `./run_all.sh` (needs `python3` and `g++`). These checks do not replace
compiling in MetaEditor and testing in MetaTrader's Strategy Tester.

## Research on real gold prices (`research/`)

* `research/fetch_data.sh` downloads real XAUUSD ticks 2011 - mid 2018 (Dukascopy, from the public GitHub repository
  FX-Data/FX-Data-XAUUSD-DS) and converts them with `convert_ticks.cpp` (broker clock GMT+2/+3, each second keeps
  its first, highest, lowest and last tick).
* `research/run.sh <name> <from> <to> <price scale> <extra spread> "<files>" [--set Input=Value ...]` builds one EA
  (`EA=GoldTrendStacker`, `GoldBreakoutEA` or `GoldScalperFVG`) with those settings and runs the real code on the
  ticks (`research_main.cpp`), printing trades, win rate, profit factor, drawdown, per direction, entry kind and year.
* `research/batch.sh train|test|all <experiments file>` runs a list of setting variations, 4 at a time
  (train = 2012-2015, test = 2016 - mid 2018). `research/exp_*.txt` are the experiments behind the README tables.
