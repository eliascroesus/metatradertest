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
