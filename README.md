# Gold Breakout EA for MetaTrader 5

A trading robot ("Expert Advisor", EA) for gold (XAUUSD) on MetaTrader 5, plus two
small helper scripts for honest backtesting.

| File | What it is |
|---|---|
| `MQL5/Experts/GoldBreakoutEA.mq5` | The original robot: few, slow trend trades |
| `MQL5/Experts/GoldScalperFVG.mq5` | The scalper: many small trades in the market's direction (see below) |
| `MQL5/Scripts/GoldBreakout_ExportNews.mq5` | Helper: saves past high-impact USD news times to a file, because MetaTrader's news calendar does not work inside the Strategy Tester |
| `MQL5/Scripts/GoldBreakout_SpreadTestSymbol.mq5` | Helper: makes a copy of gold with double the spread, for the "double spread" stress test |
| `tools/simulator/` | For programmers only: the automated checks used to test the robot's logic. Not needed in MetaTrader. |

---

## GoldScalperFVG (the scalper), version 3

* **Direction (top-down vote):** five checks each vote BUY, SELL or "not sure":
  market structure on the 4-hour, 1-hour and 15-minute charts (a candle closing above the last swing high = bullish
  break of structure, closing below the last swing low = bearish; swings have `SwingStrength` candles each side),
  EMA 50 vs EMA 200 on 15 minutes, and momentum (price vs 6 and 24 hours ago). It buys when at most
  `ChecksAllowedToDisagree` (default 1) checks are not BUY **and** the 4-hour chart is BUY (`TopTimeframeMustAgree`:
  never trade against the big picture). Selling is the mirror image. Each check can be switched off
  (`UseTopStructure`, `UseHigherStructure`, `UseMiddleStructure`, `UseEMAFilter`, `UseMomentum`).
  With `CloseOnTrendChange` it closes trades that end up against a new direction. Optional: `UsePremiumDiscount`
  and `TradingHourStart`/`TradingHourEnd` (server hours, e.g. the London + New York sessions).
* **Entries (three kinds, 1-minute chart, at most one new trade per minute):**
  1. **gap**: price comes back into a fair value gap (three candles where the 1st and 3rd don't overlap, at least
     `MinGapUSD`; up to `EntriesPerGap` trades per gap; forgotten after `GapExpiryCandles` candles or when a candle closes through it);
  2. **break**: a 1-minute candle closes beyond the last small swing (`EntrySwingStrength`) in the trend's direction;
     the robot joins in the next minute;
  3. **pullback**: the price dips back to the 1-minute EMA (`PullbackEMA`, default 20) after a candle closed on the
     trend's side of it.
  Each can be switched off (`UseGapEntries`, `UseBreakEntries`, `UsePullbackEntries`). The CSV log has an
  `EntryKind` column, so you can see which kind makes or loses money.
* **Size and number:** 0.01 lots per trade, up to 4 open at once (`MaxOpenTrades`).
* **Exits:** take-profit at +10% and stop-loss at -20% of each trade's margin, placed with the broker at once.
  With gold near $4,000 and 1:100 leverage that is about +$4 / -$8. Higher leverage makes these distances smaller.
* **Safety:** same daily loss limit, kill switch, spread filter, news filter and CSV log as the original robot.
* Needs a **hedging** account. Because the stop is twice as far as the target, it has to win about 2 out of 3 trades
  (plus the spread) just to break even, so test it before trusting it.
* **Version 2 behaviour** (only gaps, 1h + 15m + EMA must all agree): `UseTopStructure=false`, `UseMomentum=false`,
  `ChecksAllowedToDisagree=0`, `TopTimeframeMustAgree=false`, `UseBreakEntries=false`, `UsePullbackEntries=false`.

Where the ideas come from: the top-down structure read (higher chart for direction, 1 minute for entries, break of
structure, fair value gaps) is how TJR / ICT / "smart money" traders describe their method; there is no published
test of their rules, so the robot is a mechanical version of them. The momentum check comes from academic research
on trend following ("time-series momentum", Moskowitz, Ooi & Pedersen 2012, and Baltas & Kosowski, who found the
effect at daily and weekly horizons too). No method predicts direction reliably all the time; the backtest decides.

---

## What the robot does (plain language)

1. **Direction (4-hour chart).** It only buys while the last *finished* 4-hour candle closed above
   the 100-period EMA (a smoothed average of the price), and only sells while it closed below it.
2. **Entry (1-hour chart).** Each time a 1-hour candle *finishes*, it checks whether that candle
   closed above the highest high of the 20 candles before it (buy signal) or below their lowest low
   (sell signal). If the signal agrees with the direction filter, it opens a trade. It never looks
   at the candle that is still forming.
3. **Exits.**
   * The first stop is 2 x ATR(14) away from the entry price. ATR is the typical size of a 1-hour
     candle, so the stop is wider when gold is jumpy and tighter when it is calm.
   * When the trade is in profit by as much as it risked, the stop moves to the entry price
     (break-even), so that trade can no longer lose.
   * After that, the stop follows the best price reached, 3 x ATR behind it. It only ever moves
     in your favour.
   * There is no fixed profit target: winners run until the trailing stop catches them.
4. **Risk.**
   * Each trade is sized so that hitting the first stop loses 0.5% of the balance. The lot size
     comes from the stop distance and the symbol's real tick value, rounded *down* to your
     broker's lot step.
   * If even the smallest lot would risk more than 1%, the trade is skipped.
   * One trade at a time. No grid, no martingale, no adding to a trade.
5. **Safety switches.**
   * **Daily loss limit:** once the account is down 2% on the day (closed plus open trades,
     compared with the balance at the start of the broker's day), no new trades until the next day.
   * **Kill switch:** if equity falls 15% below its highest point, the robot closes its trades and
     stops for good, surviving restarts of MetaTrader, until you reset it (see below).
   * **Spread filter:** no new entry while the spread is wider than `MaxSpreadUSD`.
   * **News filter:** no new entry from 30 minutes before to 30 minutes after high-impact USD news.
6. **Random twin mode** (for testing). With `RandomEntryMode = true` the robot ignores its signals.
   It enters at random 1-hour candle closes, in a random direction, about as often as the real
   strategy, with exactly the same exits, sizing, filters and safety switches. If the real
   strategy isn't clearly better than its random twin, the entry signal probably has no real edge.
7. **Trade log.** Every finished trade becomes one line in a CSV file (open time, close time,
   direction, entry, exit, lot size, spread at entry, profit in money, exit reason), readable
   in Excel or Numbers.

Every number above is a setting you can change in the EA's **Inputs** tab. The one exception
is "one trade at a time", which is fixed on purpose: allowing more trades would mean adding to
positions, which this robot must never do.

---

## 1. Put the files on your Mac

MetaTrader 5 for Mac is the Windows program running inside a compatibility layer, so its
"C:" drive lives in this folder:

```
~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/
```

**Easiest way (Terminal, one copy-paste).** Quit MetaTrader first. Open the Terminal app
(Cmd+Space, type *Terminal*), paste all of this, and press Enter:

```bash
MT5="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5"
SRC="https://raw.githubusercontent.com/eliascroesus/metatradertest/claude/charming-darwin-wbh20f/MQL5"
curl -fsSL "$SRC/Experts/GoldBreakoutEA.mq5"                -o "$MT5/Experts/GoldBreakoutEA.mq5" &&
curl -fsSL "$SRC/Scripts/GoldBreakout_ExportNews.mq5"       -o "$MT5/Scripts/GoldBreakout_ExportNews.mq5" &&
curl -fsSL "$SRC/Scripts/GoldBreakout_SpreadTestSymbol.mq5" -o "$MT5/Scripts/GoldBreakout_SpreadTestSymbol.mq5" &&
echo "Done - 3 files copied"
```

**Or by hand (Finder).**
1. On GitHub, open the branch `claude/charming-darwin-wbh20f`, click **Code > Download ZIP**,
   and double-click the ZIP in Downloads to unpack it.
2. In Finder choose **Go > Go to Folder...** (Shift+Cmd+G), paste the path below, and press Enter:
   `~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5`
3. Copy `GoldBreakoutEA.mq5` into the **Experts** folder, and the two `GoldBreakout_...` script
   files into the **Scripts** folder.

## 2. Compile in MetaEditor

1. Start MetaTrader 5. Open MetaEditor with **Tools > MetaQuotes Language Editor**
   (or F4; on a Mac keyboard you may need fn+F4).
2. In MetaEditor's **Navigator** panel on the left (**View > Navigator** if you don't see it),
   open **Experts**. If `GoldBreakoutEA.mq5` isn't listed, right-click **Experts** and choose **Refresh**.
3. Double-click `GoldBreakoutEA.mq5` to open it, then click **Compile** in the toolbar (or F7 / fn+F7).
4. Look at the **Errors** tab at the bottom. It must say **0 errors**; warnings are harmless.
   If there is an error, copy the red line(s) and send them to me.
5. Do the same for the two scripts under **Scripts**.
6. Back in MetaTrader, open the **Navigator** (Ctrl+N). The EA appears under **Expert Advisors**
   and the helpers under **Scripts**. If not, right-click there and choose **Refresh**.

## 3. Run it in the Strategy Tester

1. In MetaTrader: **View > Strategy Tester** (Ctrl+R). The tester opens at the bottom.
2. **Settings** tab:
   * **Expert:** `GoldBreakoutEA`
   * **Symbol:** your broker's gold, exactly as in Market Watch (e.g. `XAUUSD` or `XAUUSDm`).
     **Timeframe:** H1. The robot reads its own 1-hour and 4-hour data whatever you pick here.
   * **Date:** *Custom period*, e.g. 2020.01.01 to 2023.12.31. **Forward:** No.
   * **Delays:** leave the default.
   * **Modelling:** **Every tick based on real ticks**.
   * **Deposit / Leverage:** the amount and leverage you really plan to trade with.
   * **Optimization:** Disabled (for a normal single test).
   * **Visual mode:** leave unticked (much faster). Tick it if you want to watch the trades.
3. **Inputs** tab: set `TradeSymbol` to the same gold name as above. Leave the rest at the
   defaults for your first run.
4. Click **Start**. The first real-ticks run downloads years of gold tick data from your broker,
   which can take a long time and several GB. Later runs are much faster.
5. When it finishes, look at the **Backtest** tab (results), the **Graph** tab (balance curve)
   and the **Journal** tab (the robot's own messages). The Journal ends with a line like
   `Test summary: 118 trades opened in 4.00 years = 29.5 trades per year`, which you need
   for the random twin.

## 4. Where is the trade log (CSV)?

* **Backtests:** the tester runs in its own folder. The Journal shows the exact path at the start
  of every test (`Trade log file: C:\...`). Usually it is
  `.../MetaTrader 5/Tester/Agent-127.0.0.1-3000/MQL5/Files/GoldBreakout_<symbol>_REAL_test.csv`
  (the number after `Agent-` can differ). Replace `C:\` with
  `~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/` and use
  Finder's **Go > Go to Folder...** as above. Each test run starts a fresh file; random-twin runs
  write a separate file with the seed in its name.
* **Live/demo trading:** `.../MetaTrader 5/MQL5/Files/GoldBreakout_<symbol>_REAL_live.csv`
  (in MetaTrader: **File > Open Data Folder**, then **MQL5 > Files**). New trades are added to the
  end of the same file.

Exit reasons in the file: `stop` (first stop), `break-even`, `trailing`, `kill switch`,
plus `closed by hand`, `margin stop-out`, `end of test` and `end of test (still open)` when those happen.

## 5. Testing checklist

**Before you start**
- [ ] The EA and both scripts compile with 0 errors.
- [ ] `TradeSymbol` = your broker's exact gold name. The tester's Symbol must be the same one.
- [ ] Create the news file for backtests: open a gold chart in normal MetaTrader (not the tester),
      then drag **Scripts > GoldBreakout_ExportNews** onto it and press OK. The message tells you
      how many news times it saved and how it handled summer time. See "Important limitations".
- [ ] Tester set to **Every tick based on real ticks**, with your real deposit and leverage.

**Step 1: tune on 2020-2023 only**
- [ ] Run with the default settings on 2020.01.01 to 2023.12.31. Write down: net profit, profit
      factor, maximum drawdown, number of trades, and the Journal's "trades per year" figure.
- [ ] If you optimize, change only a few settings, in coarse steps. Examples:
      `TrendEMAPeriod` 50-200, `BreakoutLookbackCandles` 10-40, `InitialStopATRMultiplier` 1.5-3,
      `TrailingStopATRMultiplier` 2-4.
      Prefer a setting whose neighbours are also good (a broad plateau) over the single best
      result. The more you tune, the more you fit the past. If optimizing on real ticks is too slow,
      search with "1 minute OHLC" and re-check the finalists on real ticks.
- [ ] Random twin on the same dates: `RandomEntryMode = true`,
      `RandomTradesPerYear` = the number from the Journal. Run 5-10 times with different
      `RandomSeed` values (1, 2, 3...). The real strategy should clearly beat most of them.
- [ ] **Lock the settings:** in the Inputs tab, right-click > **Save**, and name it e.g.
      `GoldBreakout_locked.set`. From here on, do not change them.

**Step 2: test once on 2024-2026 (the "unseen" years)**
- [ ] Load `GoldBreakout_locked.set` (Inputs tab, right-click > **Load**), set the dates to
      2024.01.01 to today, and run **once**.
- [ ] Compare with Step 1: similar profit factor and drawdown per year? A big drop means the
      tuning fitted the past rather than finding something real.
- [ ] Do not go back and re-tune because of this result. If you do, 2024-2026 is no longer
      "unseen" and the test loses its value.

**Step 3: rerun 2024-2026 with double spread**
- [ ] On a gold chart in normal MetaTrader, drag **Scripts > GoldBreakout_SpreadTestSymbol** onto it,
      with FromDate 2024.01.01, ToDate 2026.12.31 and SpreadMultiplier 2. Wait for the "done"
      message. It creates a copy such as `XAUUSDm_x2spread`.
- [ ] In the tester choose that copy as the **Symbol**, load the locked settings, and set
      `MaxSpreadUSD` to double its value (e.g. 0.50 -> 1.00). That way the same trades still
      get through and you see the pure cost effect. (`TradeSymbol` can stay the same: the EA
      accepts a symbol whose name starts with it.)
- [ ] Run once. If the profit disappears with double spread, the edge is too thin to trade.

**Before real money**
- [ ] Run it on a **demo** account for several weeks and compare with the backtest.
- [ ] The **Algo Trading** button in MetaTrader's toolbar must be on, and so must "Allow Algo Trading"
      in the EA's Common tab. MetaTrader must keep running (a sleeping Mac trades nothing; many
      people use a VPS).

---

## Important limitations (please read)

* **News in the Strategy Tester.** MetaTrader's economic calendar does not work inside the
  Strategy Tester. In backtests the robot only avoids the times listed in the news file (made by
  `GoldBreakout_ExportNews`) and in the `ManualNewsTimes` setting. Without the file, backtests
  have no news filter at all. In live trading it uses the real calendar *and* your lists.
* **Summer time.** For old events, MetaTrader's calendar may be off by one hour if your broker's
  clock changes for summer time. The export script detects this from gold's daily trading break
  and corrects it (`SummerTimeFix = Auto`). Its final message says what it found. If it says it
  could not tell, and your broker's clock changes for summer, run it again with `US` or `European`.
* **Spread in the Strategy Tester.** With real ticks, MetaTrader always uses the spreads your
  broker recorded; there is no "spread" box. That is why the double-spread test uses a copy of the
  symbol. MetaTrader can't copy commissions to such a copy, so if your account type charges
  commission, the stress test shows the wider spread but not the commission.
* **Entries happen right after the 1-hour candle closes.** If the spread is too wide at that
  moment, or it is inside a news window, that signal is skipped, not delayed.
* **Kill switch.** It watches the whole account's equity (not just this robot's trades) and closes
  only this robot's trades. A withdrawal also lowers equity, so reset the kill switch after one.
  **To reset:** set `ResetKillSwitch = true` and press OK. The robot then waits without trading.
  Then set it back to `false` and press OK; trading resumes and the equity peak starts again
  from today.
* **The "day"** for the daily loss limit is your broker's server day (midnight on the
  Market Watch clock).
* **How it was checked.** MetaQuotes' servers weren't reachable from the environment where this
  was written, so it could not be compiled in MetaEditor there. Instead, the code was compiled
  against a stand-in for MetaTrader's functions. The robot then ran on a simulated gold market
  (years of fake ticks, a fake broker) with an independent checker, which confirmed that entries,
  stops, break-even, trailing, lot sizes, the daily limit, the kill switch, the news and spread
  filters, the CSV log, restarts and the random twin all follow the rules. The helper scripts were
  tested the same way. The real compile in MetaEditor is still the final check.
* **No guarantees.** A backtest shows how rules would have behaved in the past, not what will
  happen next. Only trade money you can afford to lose.

---

## All settings

| Setting | Default | Meaning |
|---|---|---|
| `TradeSymbol` | XAUUSD | Your broker's exact gold name. A chart whose name starts with it (XAUUSDm) is accepted too. |
| `TrendTimeframe` | H4 | Chart used for the direction filter |
| `TrendEMAPeriod` | 100 | EMA length for the direction filter |
| `EntryTimeframe` | H1 | Chart used for the breakout |
| `BreakoutLookbackCandles` | 20 | How many earlier candles set the breakout level |
| `ATRTimeframe` / `ATRPeriod` | H1 / 14 | The ATR used for all stop distances |
| `InitialStopATRMultiplier` | 2.0 | First stop = this x ATR from the entry |
| `BreakEvenTriggerMultiple` | 1.0 | Move to break-even when profit = this x the first stop distance |
| `BreakEvenExtraUSD` | 0.0 | Optional cushion beyond entry for the break-even stop (price units) |
| `TrailingStopATRMultiplier` | 3.0 | Trailing distance behind the best price, in ATRs |
| `TrailingStepATR` | 0.1 | Only move the trailing stop in steps of at least this x ATR (fewer broker requests) |
| `RiskPercentPerTrade` | 0.5 | % of balance risked per trade |
| `MaxRiskPercentAtMinLot` | 1.0 | Skip if the smallest lot would risk more than this % |
| `DailyLossLimitPercent` | 2.0 | No new trades for the rest of the day after this % loss (0 = off) |
| `KillSwitchDrawdownPercent` | 15.0 | Close and stop for good at this % below the equity peak (0 = off) |
| `ResetKillSwitch` | false | See "Kill switch" above |
| `MaxSpreadUSD` | 0.50 | Largest spread allowed for a new entry, in price units (0.50 = 50 cents; 0 = off) |
| `MaxSlippageUSD` | 0.50 | Largest accepted slippage (only used by brokers with "instant execution") |
| `UseNewsFilter` | true | Skip entries around high-impact USD news |
| `NewsMinutesBefore` / `NewsMinutesAfter` | 30 / 30 | Size of the news window |
| `ManualNewsTimes` | (empty) | Extra news times in server time, e.g. `2024.01.05 15:30; 2024.02.02 15:30` |
| `NewsTimesFile` | GoldBreakout_news.csv | The file made by the export script (in the Common Files folder) |
| `RandomEntryMode` | false | Random twin mode (tests only) |
| `RandomSeed` | 12345 | Same seed = same random trades |
| `RandomTradesPerYear` | 0 | Trades per year for the twin (from the Journal of a normal test) |
| `CsvFilePrefix` | GoldBreakout | Start of the CSV file name |
| `MagicNumber` | 20260929 | Tag on this robot's trades so it never touches others |
