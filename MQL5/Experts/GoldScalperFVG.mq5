//+------------------------------------------------------------------+
//|                                               GoldScalperFVG.mq5 |
//|     Gold (XAUUSD) scalper: many small trades in the direction of |
//|     a top-down vote; gaps, breaks and pullbacks on 1 minute.     |
//+------------------------------------------------------------------+
//
//  HOW TO READ THIS FILE
//  ---------------------
//  Lines that start with // are notes for people. MetaTrader ignores
//  them. Everything else is the program itself.
//
//  WHAT THE ROBOT DOES
//  -------------------
//  1. DIRECTION - a top-down vote, the way TJR / ICT / smart-money traders
//     read the chart, plus a momentum check that research on trend
//     following supports. Five checks each vote BUY, SELL or "not sure":
//       - market structure on the 4-hour, 1-hour and 15-minute charts
//         (a candle CLOSING above the last swing high = bullish "break of
//         structure", closing below the last swing low = bearish),
//       - EMA 50 above / below EMA 200 on the 15-minute chart,
//       - momentum: price higher / lower than 6 and 24 hours ago.
//     It buys only when at least 4 of the 5 vote BUY and the 4-hour chart
//     is one of them (the 4-hour chart is "the boss": it is never traded
//     against). Selling is the mirror image. Otherwise it waits. If the
//     direction flips against open trades, it closes them.
//  2. ENTRIES - three kinds, all only in that direction, on the 1-minute
//     chart, at most one new trade per minute:
//       a) GAP: three candles where the 1st and 3rd do not overlap leave a
//          "fair value gap"; trade when the price comes back into it.
//       b) BREAK: a 1-minute candle closes beyond the last small swing in
//          the trend's direction; join the move in the next minute.
//       c) PULLBACK: the price dips back to the 1-minute EMA 20 after a
//          candle closed on the trend's side of it; trade the dip.
//  3. MANY SMALL TRADES: each trade is 0.01 lots, up to 4 open at once.
//  4. EXITS: every trade gets a take-profit at +10% of the money it ties
//     up (its margin) and a stop-loss at -20% of it. With gold near $4,000
//     and 1:100 leverage that is about +$4 and -$8 of price movement. Both
//     are placed with the broker the moment the trade opens.
//  5. SAFETY: no new trades after a 2% losing day (until the next day), a
//     kill switch that closes everything and stops for good if equity
//     falls 15% below its highest point, and no new entries while the
//     spread is too wide or around high-impact USD news.
//  6. LOG: every closed trade becomes one line in a CSV file (MQL5/Files),
//     including which entry kind opened it.
//
//  To get the old version 2 behaviour back: UseTopStructure = false,
//  UseMomentum = false, ChecksAllowedToDisagree = 0, TopTimeframeMustAgree =
//  false, UseBreakEntries = false, UsePullbackEntries = false.
//
//  Every number above is a setting ("input") in the EA's Inputs tab.
//
//  IMPORTANT: it needs a "hedging" account, because it holds several
//  trades at once. Demo accounts opened with "Use hedge in trading"
//  ticked are hedging accounts.
//+------------------------------------------------------------------+
#property version     "3.00"
#property description "Gold scalper: 1-minute gap, break and pullback entries in the direction of a 4h/1h/15m structure + EMA + momentum vote."
#property description "Up to 4 trades of 0.01 lots, take-profit +10% / stop-loss -20% of margin."
#property description "Daily loss limit, equity kill switch, spread and news filters, CSV trade log."

// MetaTrader's standard helper for sending orders (comes with every MT5).
#include <Trade\Trade.mqh>

#define EA_NAME   "GoldScalperFVG"
#define MAX_GAPS  50

//====================================================================
//  SETTINGS ("INPUTS")
//====================================================================

input group "=== 1. Symbol ==="
// The exact name of gold at your broker, as shown in Market Watch. A chart
// whose name STARTS with it (e.g. XAUUSDm) is accepted too.
input string TradeSymbol = "XAUUSD";

input group "=== 2. Direction of the market (top-down vote) ==="
// The robot reads the market from the top down, like TJR / ICT / smart-money
// traders do, and adds a momentum check that is backed by research on
// trend following. Each CHECK below votes BUY, SELL or "not sure":
//   a) structure of the TOP chart (default 4 hours)
//   b) structure of the HIGHER chart (default 1 hour)
//   c) structure of the MIDDLE chart (default 15 minutes)
//   d) EMA 50 above/below EMA 200 (default on the 15-minute chart)
//   e) momentum: price now higher/lower than 6 AND 24 candles ago (1 hour)
// "Structure" = the last break of a swing: a candle CLOSING above the last
// swing high is bullish, one closing below the last swing low is bearish.
input bool UseTopStructure = true;
input ENUM_TIMEFRAMES TopTimeframe = PERIOD_H4;
input bool UseHigherStructure = true;
input ENUM_TIMEFRAMES HigherTimeframe = PERIOD_H1;
input bool UseMiddleStructure = true;
input ENUM_TIMEFRAMES MiddleTimeframe = PERIOD_M15;
// A swing high is a candle with this many lower highs on EACH side (a swing
// low: this many higher lows on each side). Bigger = only major swings.
input int SwingStrength = 3;
// How many finished candles back the structure is read.
input int StructureLookback = 300;
input bool UseEMAFilter = true;
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_M15;
input int TrendFastEMA = 50;
input int TrendSlowEMA = 200;
input bool UseMomentum = true;
input ENUM_TIMEFRAMES MomentumTimeframe = PERIOD_H1;
input int MomentumShortCandles = 6;
input int MomentumLongCandles = 24;
// How many of the switched-on checks may say "no" (or "not sure") while the
// robot still trades. 0 = every check must agree (strictest, fewest trades).
// 1 = one check may disagree, e.g. the 15-minute chart pulling back inside
// a bigger uptrend - that is where many good buys are.
input int ChecksAllowedToDisagree = 1;
// The TOP chart is the boss: never trade against it, whatever the others say.
input bool TopTimeframeMustAgree = true;
// Premium/discount: buy only in the lower half of the current middle-chart
// swing range ("discount"), sell only in the upper half ("premium").
// Fewer but better-placed trades. false = off.
input bool UsePremiumDiscount = false;
// Close open trades as soon as the direction flips against them.
input bool CloseOnTrendChange = true;
// Trade only between these server hours (0 and 24 = all day). Example for
// the London + New York sessions at a GMT+3 broker: 10 and 20.
input int TradingHourStart = 0;
input int TradingHourEnd = 24;

input group "=== 3. Entries (three kinds, all in the direction above) ==="
// Chart on which entries are found (default: 1 minute). At most ONE new
// trade starts per candle of this chart.
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_M1;
// Most trades open at the same time.
input int MaxOpenTrades = 4;
// --- Entry kind 1: fair value gap retest. Three candles in a row where the
// 1st and the 3rd do not overlap leave a "gap"; buy/sell when the price
// comes back into it.
input bool UseGapEntries = true;
// Smallest gap that counts, in price units (0.50 = 50 cents on gold).
input double MinGapUSD = 0.50;
// A gap is forgotten after this many candles if the price never came back.
input int GapExpiryCandles = 30;
// How many trades one gap may give.
input int EntriesPerGap = 2;
// --- Entry kind 2: small break of structure. A 1-minute candle closes above
// the last small swing high (uptrend) or below the last small swing low
// (downtrend): the move continues, join it in the next candle.
input bool UseBreakEntries = true;
input int EntrySwingStrength = 2;
input int EntryStructureLookback = 60;
// --- Entry kind 3: pullback. In an uptrend, buy when the price dips down to
// the 1-minute EMA after a candle closed above it (sells: the mirror image).
input bool UsePullbackEntries = true;
input int PullbackEMA = 20;

input group "=== 4. Trade size and exits ==="
// Size of every trade, in lots (0.01 = the smallest normal size).
input double LotSize = 0.01;
// Take-profit: close the trade when it is up this % of its margin.
input double TakeProfitPercentOfMargin = 10.0;
// Stop-loss: close the trade when it is down this % of its margin.
input double StopLossPercentOfMargin = 20.0;

input group "=== 5. Safety ==="
// No NEW trades for the rest of the (server) day once equity is this % below
// the balance at the start of the day. 0 = off.
input double DailyLossLimitPercent = 2.0;
// Kill switch: close this EA's trades and stop for good when equity is this
// % below its highest point. 0 = off.
input double KillSwitchDrawdownPercent = 15.0;
// To reset a triggered kill switch: set to true, press OK (the EA then waits
// without trading), then set it back to false.
input bool ResetKillSwitch = false;
// No new entries while the spread is wider than this (price units; 0 = off).
input double MaxSpreadUSD = 0.50;
// Largest slippage accepted on market orders, in price units.
input double MaxSlippageUSD = 0.50;

input group "=== 6. News filter (high-impact USD events) ==="
input bool UseNewsFilter = true;
input int NewsMinutesBefore = 30;
input int NewsMinutesAfter = 30;
// MetaTrader's economic calendar does NOT work in the Strategy Tester. There
// only these listed times are avoided (live: the calendar AND these lists).
// (a) Times in your broker's SERVER time, separated by ";", for example
//     2024.01.05 15:30; 2024.02.02 15:30
input string ManualNewsTimes = "";
// (b) The file made by the GoldBreakout_ExportNews script (Common Files).
input string NewsTimesFile = "GoldBreakout_news.csv";

input group "=== 7. Trade log and identification ==="
// Start of the CSV file name (the file is created in MQL5/Files).
input string CsvFilePrefix = "GoldScalper";
// Tag on this EA's trades so it never touches any others.
input long MagicNumber = 20261007;

//====================================================================
//  THE ROBOT'S MEMORY WHILE IT RUNS
//====================================================================
CTrade   g_trade;
string   g_symbol        = "";
bool     g_isTester      = false;
bool     g_isOptimizing  = false;
bool     g_showStatus    = false;
int      g_digits        = 0;
double   g_point         = 0.0;
double   g_tickSize      = 0.0;
string   g_gvPrefix      = "";
string   g_csvFile       = "";

// Trend
int      g_fastHandle    = INVALID_HANDLE;
int      g_slowHandle    = INVALID_HANDLE;
int      g_pullbackHandle = INVALID_HANDLE;
int      g_trendDir      = 0;            // +1 buys only, -1 sells only, 0 wait
int      g_topDir        = 0;            // votes: structure on the top chart
int      g_higherDir     = 0;            // structure on the higher chart
int      g_middleDir     = 0;            // structure on the middle chart
int      g_emaDir        = 0;            // EMA check
int      g_momentumDir   = 0;            // momentum check
int      g_votesBuy      = 0;
int      g_votesSell     = 0;
int      g_checksOn      = 0;            // how many checks are switched on
double   g_rangeLow      = 0.0;          // current middle-chart swing range
double   g_rangeHigh     = 0.0;
double   g_emaFast       = 0.0;
double   g_emaSlow       = 0.0;
long     g_trendClosedIds[];             // trades closed because the direction flipped

// Fair value gaps waiting for the price to come back
struct Gap
{
   int      dir;                         // +1 bullish gap (buy), -1 bearish gap (sell)
   double   low;                         // bottom of the gap
   double   high;                        // top of the gap
   datetime made;                        // open time of the candle that completed it
   int      entries;                     // trades already taken from it
   bool     used;                        // no more trades from it
};
Gap      g_gaps[];
datetime g_lastSignalCandle = 0;         // last 1-minute candle we processed
datetime g_lastEntryCandle  = 0;         // candle in which we last tried to open a trade
datetime g_lastSkipLog      = 0;         // candle in which we last logged a skipped entry
int      g_gapsFound        = 0;
int      g_tradesOpened     = 0;
int      g_tradesByKind[4];              // trades opened per entry kind (1 gap, 2 break, 3 pullback)
// Entry kind 2: a small break of structure in the trend's direction, valid
// during the candle right after it
int      g_breakDir         = 0;
datetime g_breakCandle      = 0;
// Entry kind 3: the 1-minute EMA and close of the last finished candle
double   g_pullbackEma      = 0.0;
double   g_pullbackClose    = 0.0;
double   g_tpDistance       = 0.0;       // last take-profit distance in price (for the status text)
double   g_slDistance       = 0.0;

// News (checked once per candle)
bool     g_newsBlocked      = false;
string   g_newsWhat         = "";
long     g_newsTimes[];
datetime g_calendarWarnAfter = 0;

// Open trades we know about (to write them to the CSV when they close)
long     g_openIds[];
datetime g_goneSince[];

// Safety switches
double   g_peakEquity      = 0.0;
bool     g_killSwitchOn    = false;
long     g_dayNumber       = -1;
double   g_dayStartBalance = 0.0;
bool     g_dailyLimitHit   = false;
datetime g_nextFlush       = 0;
datetime g_closeRetryAfter = 0;
datetime g_firstTickTime   = 0;

//====================================================================
//  SMALL HELPERS
//====================================================================

// Write a line to the Experts/Journal log (silent during optimization,
// where thousands of test passes would otherwise flood it).
void LogMsg(const string text)
{
   if(!g_isOptimizing)
      Print(text);
}

// Important message: a pop-up in live trading, a log line in the tester.
void WarnMsg(const string text)
{
   if(g_isOptimizing)
      return;
   if(g_isTester)
      Print(text);
   else
      Alert(EA_NAME, ": ", text);
}

string DirText(const int dir)
{
   if(dir > 0)
      return "BUY";
   if(dir < 0)
      return "SELL";
   return "-";
}

// Short names of the entry kinds (order comment and CSV).
string KindName(const int kind)
{
   if(kind == 1)
      return "gap";
   if(kind == 2)
      return "break";
   if(kind == 3)
      return "pullback";
   return "?";
}

// "PERIOD_H4" -> "H4"
string TfName(const ENUM_TIMEFRAMES tf)
{
   string name = EnumToString(tf);
   if(StringFind(name, "PERIOD_") == 0)
      name = StringSubstr(name, 7);
   return name;
}

// Server day number (changes at midnight server time)
long DayNumber(const datetime t)
{
   return (long)t / 86400;
}

// Round a price to the nearest / next lower / next higher allowed price step.
double RoundToTick(const double price)
{
   return NormalizeDouble(MathRound(price / g_tickSize) * g_tickSize, g_digits);
}

double RoundDownToTick(const double price)
{
   return NormalizeDouble(MathFloor(price / g_tickSize + 1e-8) * g_tickSize, g_digits);
}

double RoundUpToTick(const double price)
{
   return NormalizeDouble(MathCeil(price / g_tickSize - 1e-8) * g_tickSize, g_digits);
}

// How many decimals the broker's lot step has (0.01 -> 2).
int LotDigits()
{
   double step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      return 2;
   int digits = 0;
   while(digits < 8 && MathAbs(step * MathPow(10, digits) - MathRound(step * MathPow(10, digits))) > 1e-8)
      digits++;
   return digits;
}

// Round a lot size DOWN to the broker's lot step (never up, so the risk
// never ends up above the target).
double RoundLotsDown(const double lots)
{
   double step = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   return NormalizeDouble(MathFloor(lots / step + 1e-8) * step, LotDigits());
}

// Did the broker accept the request?
bool RequestSucceeded(const uint retcode)
{
   return (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL ||
           retcode == TRADE_RETCODE_PLACED || retcode == TRADE_RETCODE_NO_CHANGES);
}

// ---- Values saved in the terminal ("global variables", F3 in MetaTrader).
// They survive a restart of MetaTrader, which is how the kill switch stays
// on "permanently". In the Strategy Tester they are wiped at every start.
string GvName(const string key)
{
   return g_gvPrefix + key;
}

double GvGet(const string key, const double fallback)
{
   string name = GvName(key);
   if(GlobalVariableCheck(name))
      return GlobalVariableGet(name);
   return fallback;
}

void GvSet(const string key, const double value)
{
   GlobalVariableSet(GvName(key), value);
}

void GvDelete(const string key)
{
   string name = GvName(key);
   if(GlobalVariableCheck(name))
      GlobalVariableDel(name);
}

// Make sure saved values are written to disk (live trading only; at most
// once a minute unless it is urgent).
void GvFlush(const bool urgent)
{
   if(g_isTester)
      return;
   if(urgent || TimeCurrent() >= g_nextFlush)
   {
      GlobalVariablesFlush();
      g_nextFlush = TimeCurrent() + 60;
   }
}

bool PositionIsOpen(const long positionId)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) != 0 && PositionGetInteger(POSITION_IDENTIFIER) == positionId)
         return true;
   }
   return false;
}


//====================================================================
//  CHECKING THE SETTINGS AT START-UP
//====================================================================

// How many direction checks are switched on.
int CountChecksOn()
{
   int count = 0;
   if(UseTopStructure)
      count++;
   if(UseHigherStructure)
      count++;
   if(UseMiddleStructure)
      count++;
   if(UseEMAFilter)
      count++;
   if(UseMomentum)
      count++;
   return count;
}

bool ValidateInputs()
{
   string problem = "";
   if(SwingStrength < 1 || StructureLookback < 4 * SwingStrength + 2)
      problem = "SwingStrength must be 1 or more and StructureLookback much larger than it.";
   else if(EntrySwingStrength < 1 || EntryStructureLookback < 4 * EntrySwingStrength + 2)
      problem = "EntrySwingStrength must be 1 or more and EntryStructureLookback much larger than it.";
   else if(CountChecksOn() == 0)
      problem = "Switch on at least one direction check (structure, EMA or momentum).";
   else if(ChecksAllowedToDisagree < 0 || 2 * ChecksAllowedToDisagree >= CountChecksOn())
      problem = "ChecksAllowedToDisagree must be 0 or more and less than half of the switched-on checks.";
   else if(TopTimeframeMustAgree && !UseTopStructure)
      problem = "TopTimeframeMustAgree needs UseTopStructure = true.";
   else if(MomentumShortCandles < 1 || MomentumLongCandles < 1)
      problem = "MomentumShortCandles and MomentumLongCandles must be 1 or more.";
   else if(PullbackEMA < 1)
      problem = "PullbackEMA must be 1 or more.";
   else if(!UseGapEntries && !UseBreakEntries && !UsePullbackEntries)
      problem = "Switch on at least one entry kind (gaps, breaks or pullbacks).";
   else if(EntriesPerGap < 1)
      problem = "EntriesPerGap must be 1 or more.";
   else if(TradingHourStart < 0 || TradingHourStart > 24 || TradingHourEnd < 0 || TradingHourEnd > 24)
      problem = "TradingHourStart and TradingHourEnd must be between 0 and 24.";
   else if(TrendFastEMA < 1 || TrendSlowEMA < 1)
      problem = "TrendFastEMA and TrendSlowEMA must be 1 or more.";
   else if(TrendFastEMA >= TrendSlowEMA)
      problem = "TrendFastEMA must be smaller than TrendSlowEMA.";
   else if(MinGapUSD < 0.0)
      problem = "MinGapUSD cannot be negative.";
   else if(GapExpiryCandles < 1)
      problem = "GapExpiryCandles must be 1 or more.";
   else if(MaxOpenTrades < 1 || MaxOpenTrades > 50)
      problem = "MaxOpenTrades must be between 1 and 50.";
   else if(LotSize <= 0.0)
      problem = "LotSize must be above 0.";
   else if(TakeProfitPercentOfMargin <= 0.0 || StopLossPercentOfMargin <= 0.0)
      problem = "TakeProfitPercentOfMargin and StopLossPercentOfMargin must be above 0.";
   else if(DailyLossLimitPercent < 0.0 || DailyLossLimitPercent >= 100.0)
      problem = "DailyLossLimitPercent must be between 0 (off) and 100.";
   else if(KillSwitchDrawdownPercent < 0.0 || KillSwitchDrawdownPercent >= 100.0)
      problem = "KillSwitchDrawdownPercent must be between 0 (off) and 100.";
   else if(MaxSpreadUSD < 0.0 || MaxSlippageUSD < 0.0)
      problem = "MaxSpreadUSD and MaxSlippageUSD cannot be negative.";
   else if(NewsMinutesBefore < 0 || NewsMinutesAfter < 0)
      problem = "NewsMinutesBefore and NewsMinutesAfter cannot be negative.";
   if(problem == "")
      return true;
   WarnMsg("Setting problem: " + problem);
   return false;
}

// Decide which symbol to trade and make sure the EA runs on that chart.
bool ResolveSymbol()
{
   string chart  = _Symbol;
   string wanted = TradeSymbol;
   StringTrimLeft(wanted);
   StringTrimRight(wanted);

   if(wanted == "" || StringCompare(wanted, chart, false) == 0)
   {
      g_symbol = chart;
   }
   else
   {
      // Accept broker suffixes: TradeSymbol "XAUUSD" on an "XAUUSDm" chart.
      string wantedUpper = wanted;
      string chartUpper  = chart;
      StringToUpper(wantedUpper);
      StringToUpper(chartUpper);
      if(StringFind(chartUpper, wantedUpper) == 0)
      {
         g_symbol = chart;
         LogMsg("TradeSymbol is '" + wanted + "' and the chart is '" + chart + "': trading " + chart + ".");
      }
      else
      {
         bool isCustom = false;
         if(!SymbolExist(wanted, isCustom))
            WarnMsg("The symbol '" + wanted + "' does not exist at your broker. Look in Market Watch for the exact "
                    "name of gold (for example XAUUSDm) and type it into TradeSymbol.");
         else
            WarnMsg("TradeSymbol is '" + wanted + "' but the EA is running on a '" + chart + "' chart. Attach it to a "
                    + wanted + " chart (in the Strategy Tester: choose " + wanted + " as the Symbol).");
         return false;
      }
   }
   if(!SymbolSelect(g_symbol, true))
   {
      WarnMsg("Could not add " + g_symbol + " to Market Watch.");
      return false;
   }
   return true;
}

// Characters that are not allowed in file names are replaced by "_".
string SafeFileName(const string text)
{
   string result = text;
   StringReplace(result, "\\", "_");
   StringReplace(result, "/", "_");
   StringReplace(result, ":", "_");
   StringReplace(result, "*", "_");
   StringReplace(result, "?", "_");
   StringReplace(result, "\"", "_");
   StringReplace(result, "<", "_");
   StringReplace(result, ">", "_");
   StringReplace(result, "|", "_");
   return result;
}

void AppendCsvLine(const string line)
{
   if(g_csvFile == "")
      return;
   int handle = FileOpen(g_csvFile, FILE_TXT | FILE_ANSI | FILE_READ | FILE_WRITE | FILE_SHARE_READ);
   if(handle == INVALID_HANDLE)
   {
      LogMsg("Could not write to the trade log (error " + IntegerToString(GetLastError()) + ").");
      return;
   }
   FileSeek(handle, 0, SEEK_END);
   FileWriteString(handle, line + "\r\n");
   FileClose(handle);
}


//====================================================================
//  THE CSV TRADE LOG (in MQL5/Files)
//====================================================================

string CsvHeader()
{
   return "OpenTime,CloseTime,Direction,EntryPrice,ExitPrice,LotSize,SpreadAtEntry,ProfitMoney,ExitReason,"
          "Symbol,PositionID,TakeProfit,StopLoss,EntryKind";
}

// Create the log file. Tester: a fresh file for every test run.
// Live trading: keep adding to the same file.
void PrepareCsvFile()
{
   g_csvFile = "";
   if(g_isOptimizing || CsvFilePrefix == "")
      return;
   g_csvFile = CsvFilePrefix + "_" + SafeFileName(g_symbol) + (g_isTester ? "_test" : "_live") + ".csv";
   int flags = FILE_TXT | FILE_ANSI | FILE_WRITE | FILE_SHARE_READ;
   if(!g_isTester)
      flags |= FILE_READ;
   int handle = FileOpen(g_csvFile, flags);
   if(handle == INVALID_HANDLE)
   {
      LogMsg("Could not create the trade log " + g_csvFile + " (error " + IntegerToString(GetLastError()) + ").");
      g_csvFile = "";
      return;
   }
   if(FileSize(handle) == 0)
      FileWriteString(handle, CsvHeader() + "\r\n");
   FileClose(handle);
   LogMsg("Trade log file: " + TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + g_csvFile);
}

string PriceOrNA(const double price)
{
   if(price > 0.0)
      return DoubleToString(price, g_digits);
   return "n/a";
}

string CsvLine(const datetime openTime, const datetime closeTime, const int dir, const double entryPrice,
               const double exitPrice, const double lots, const double spreadAtEntry, const double money,
               const string reason, const long positionId, const double takeProfit, const double stopLoss)
{
   int kind = (int)GvGet("Kind_" + IntegerToString(positionId), 0.0);
   string direction = "?";
   if(dir > 0)
      direction = "LONG";
   if(dir < 0)
      direction = "SHORT";
   string spreadText = "n/a";
   if(spreadAtEntry >= 0.0)
      spreadText = DoubleToString(spreadAtEntry, g_digits);
   return TimeToString(openTime, TIME_DATE | TIME_SECONDS) + "," +
          TimeToString(closeTime, TIME_DATE | TIME_SECONDS) + "," +
          direction + "," +
          DoubleToString(entryPrice, g_digits) + "," +
          DoubleToString(exitPrice, g_digits) + "," +
          DoubleToString(lots, LotDigits()) + "," +
          spreadText + "," +
          DoubleToString(money, 2) + "," +
          reason + "," +
          g_symbol + "," +
          IntegerToString(positionId) + "," +
          PriceOrNA(takeProfit) + "," +
          PriceOrNA(stopLoss) + "," +
          KindName(kind);
}

// Turn MetaTrader's technical close reason into plain words for the CSV.
string ExitReasonText(const long dealReason, const string dealComment)
{
   if(StringFind(dealComment, "end of test") >= 0)
      return "end of test";
   if(dealReason == DEAL_REASON_TP)
      return "take-profit";
   if(dealReason == DEAL_REASON_SL)
      return "stop-loss";
   if(dealReason == DEAL_REASON_EXPERT)
      return g_killSwitchOn ? "kill switch" : "closed by EA";
   if(dealReason == DEAL_REASON_SO)
      return "margin stop-out";
   if(dealReason == DEAL_REASON_CLIENT || dealReason == DEAL_REASON_MOBILE || dealReason == DEAL_REASON_WEB)
      return "closed by hand";
   return "other";
}

// Gather everything about one finished trade from the account history and
// add it to the CSV. Returns false while the closing deal is not in the
// history yet (unless force = true, then it writes whatever it has).
bool WriteTradeToCsv(const long positionId, const bool force)
{
   if(positionId <= 0)
      return true;
   if(!HistorySelectByPosition(positionId) && !force)
      return false;

   int      dir = 0;
   double   inVolume = 0.0, inValue = 0.0, outVolume = 0.0, outValue = 0.0, money = 0.0;
   double   takeProfit = 0.0, stopLoss = 0.0;
   datetime openTime = 0, closeTime = 0;
   long     dealReason = -1;
   string   dealComment = "";

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      long     entryType = HistoryDealGetInteger(deal, DEAL_ENTRY);
      double   volume    = HistoryDealGetDouble(deal, DEAL_VOLUME);
      double   price     = HistoryDealGetDouble(deal, DEAL_PRICE);
      datetime dealTime  = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      money += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) +
               HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
      if(entryType == DEAL_ENTRY_IN)
      {
         inVolume += volume;
         inValue  += volume * price;
         if(openTime == 0 || dealTime < openTime)
            openTime = dealTime;
         if(dir == 0)
         {
            dir        = (HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? 1 : -1;
            takeProfit = HistoryDealGetDouble(deal, DEAL_TP);
            stopLoss   = HistoryDealGetDouble(deal, DEAL_SL);
         }
      }
      else
      {
         outVolume += volume;
         outValue  += volume * price;
         if(dealTime >= closeTime)
         {
            closeTime   = dealTime;
            dealReason  = HistoryDealGetInteger(deal, DEAL_REASON);
            dealComment = HistoryDealGetString(deal, DEAL_COMMENT);
         }
      }
   }
   if(outVolume <= 0.0 && !force)
      return false;

   string key           = IntegerToString(positionId);
   double spreadAtEntry = GvGet("Spread_" + key, -1.0);
   double entryPrice    = (inVolume > 0.0) ? inValue / inVolume : 0.0;
   double exitPrice     = (outVolume > 0.0) ? outValue / outVolume : 0.0;
   string reason        = "unknown (closing deal not found)";
   if(outVolume > 0.0)
      reason = ExitReasonText(dealReason, dealComment);
   for(int t = ArraySize(g_trendClosedIds) - 1; t >= 0; t--)
   {
      if(g_trendClosedIds[t] != positionId)
         continue;
      if(dealReason == DEAL_REASON_EXPERT)
         reason = "trend changed";
      int last = ArraySize(g_trendClosedIds) - 1;
      g_trendClosedIds[t] = g_trendClosedIds[last];
      ArrayResize(g_trendClosedIds, last);
   }
   if(closeTime == 0)
      closeTime = TimeCurrent();

   AppendCsvLine(CsvLine(openTime, closeTime, dir, entryPrice, exitPrice, inVolume, spreadAtEntry, money,
                         reason, positionId, takeProfit, stopLoss));
   if(!g_isTester)
      LogMsg(StringFormat("Trade closed: %s %s lots, entry %s, exit %s, result %.2f %s, reason: %s",
                          DirText(dir), DoubleToString(inVolume, LotDigits()), DoubleToString(entryPrice, g_digits),
                          DoubleToString(exitPrice, g_digits), money, AccountInfoString(ACCOUNT_CURRENCY), reason));
   GvDelete("Spread_" + key);
   GvDelete("Kind_" + key);
   return true;
}

// End of a backtest with trades still open: log them at the last price.
void LogTradesStillOpenAtEnd()
{
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;
      long   id    = PositionGetInteger(POSITION_IDENTIFIER);
      int    dir   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double money = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      AppendCsvLine(CsvLine((datetime)PositionGetInteger(POSITION_TIME), TimeCurrent(), dir,
                            PositionGetDouble(POSITION_PRICE_OPEN), (dir > 0) ? tick.bid : tick.ask,
                            PositionGetDouble(POSITION_VOLUME), GvGet("Spread_" + IntegerToString(id), -1.0), money,
                            "end of test (still open)", id, PositionGetDouble(POSITION_TP), PositionGetDouble(POSITION_SL)));
   }
}

//====================================================================
//  KEEPING TRACK OF THE OPEN TRADES
//====================================================================

int CountOurPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == g_symbol)
         count++;
   }
   return count;
}

bool IdInList(const long id, const long &list[])
{
   for(int i = 0; i < ArraySize(list); i++)
   {
      if(list[i] == id)
         return true;
   }
   return false;
}

void RemoveTracked(const int index)
{
   int last = ArraySize(g_openIds) - 1;
   for(int i = index; i < last; i++)
   {
      g_openIds[i]   = g_openIds[i + 1];
      g_goneSince[i] = g_goneSince[i + 1];
   }
   ArrayResize(g_openIds, last);
   ArrayResize(g_goneSince, last);
}

// Notice trades that closed (take-profit, stop-loss, by hand, kill switch)
// and write them to the CSV; start tracking newly opened ones.
// "finalCall" = end of the test.
void SyncPositions(const bool finalCall)
{
   long open[];
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;
      int n = ArraySize(open);
      ArrayResize(open, n + 1);
      open[n] = PositionGetInteger(POSITION_IDENTIFIER);
   }
   for(int i = ArraySize(g_openIds) - 1; i >= 0; i--)
   {
      if(IdInList(g_openIds[i], open))
         continue;
      if(g_goneSince[i] == 0)
         g_goneSince[i] = TimeCurrent();
      bool force = finalCall || (TimeCurrent() - g_goneSince[i] > 60);
      if(WriteTradeToCsv(g_openIds[i], force))
         RemoveTracked(i);
   }
   for(int k = 0; k < ArraySize(open); k++)
   {
      if(IdInList(open[k], g_openIds))
         continue;
      int n = ArraySize(g_openIds);
      ArrayResize(g_openIds, n + 1);
      ArrayResize(g_goneSince, n + 1);
      g_openIds[n]   = open[k];
      g_goneSince[n] = 0;
   }
}

// Live trading only: trades that closed while MetaTrader was switched off
// still have their saved note ("Spread_<id>"). Log them now.
void LogTradesClosedWhileOffline()
{
   string prefix = g_gvPrefix + "Spread_";
   long   ids[];
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) != 0)
         continue;
      long id = StringToInteger(StringSubstr(name, StringLen(prefix)));
      if(id <= 0 || IdInList(id, g_openIds))
         continue;
      int n = ArraySize(ids);
      ArrayResize(ids, n + 1);
      ids[n] = id;
   }
   for(int k = 0; k < ArraySize(ids); k++)
   {
      if(!PositionIsOpen(ids[k]))
         WriteTradeToCsv(ids[k], false);
   }
}

//====================================================================
//  SAFETY SWITCHES: DAILY LOSS LIMIT AND KILL SWITCH
//====================================================================

// Profit/loss of all trades closed today (used only if the EA is started
// in the middle of a day and has no saved start-of-day balance).
double ClosedProfitToday(const long today)
{
   datetime dayStart = (datetime)(today * 86400);
   if(!HistorySelect(dayStart, TimeCurrent() + 86400))
      return 0.0;
   double total = 0.0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      long type = HistoryDealGetInteger(deal, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
         continue;                           // ignore deposits and withdrawals
      total += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) +
               HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
   }
   return total;
}

// Load the kill switch, equity peak and today's loss-limit state
// (so a restart of MetaTrader does not forget them).
void LoadSafetyState()
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_killSwitchOn = (GvGet("KillSwitch", 0.0) > 0.5);
   g_peakEquity   = MathMax(GvGet("PeakEquity", 0.0), equity);

   if(ResetKillSwitch)
   {
      g_killSwitchOn = false;
      g_peakEquity   = equity;
      GvSet("KillSwitch", 0.0);
      WarnMsg("Kill switch RESET. Equity peak restarted at " + DoubleToString(equity, 2) +
              ". No trades will be opened while ResetKillSwitch = true: set it back to false to resume trading.");
   }
   else if(g_killSwitchOn)
   {
      WarnMsg("The kill switch is ACTIVE (it was triggered earlier), so this EA will not trade. To reset it: set "
              "ResetKillSwitch = true, press OK, then set it back to false.");
   }
   GvSet("PeakEquity", g_peakEquity);

   long today = DayNumber(TimeCurrent());
   if((long)GvGet("DayNumber", -1.0) == today)
   {
      g_dayNumber       = today;
      g_dayStartBalance = GvGet("DayStartBalance", AccountInfoDouble(ACCOUNT_BALANCE));
      g_dailyLimitHit   = (GvGet("DailyLimitHit", 0.0) > 0.5);
   }
   else
   {
      g_dayNumber = -1;                      // set up on the first price tick
   }
   GvFlush(true);
}

// Runs on every price tick: new-day reset, daily loss limit, equity peak
// and kill switch.
void UpdateSafetySwitches()
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   // A new server day: the daily loss limit starts again from today's balance.
   long today = DayNumber(TimeCurrent());
   if(today != g_dayNumber)
   {
      bool startedMidDay = (g_dayNumber < 0 && !g_isTester);
      g_dayNumber       = today;
      g_dayStartBalance = balance;
      if(startedMidDay)
         g_dayStartBalance = balance - ClosedProfitToday(today);
      g_dailyLimitHit   = false;
      GvSet("DayNumber", (double)today);
      GvSet("DayStartBalance", g_dayStartBalance);
      GvSet("DailyLimitHit", 0.0);
      GvFlush(true);
   }

   // Daily loss limit (closed trades + the open trade, measured on equity).
   if(DailyLossLimitPercent > 0.0 && !g_dailyLimitHit && g_dayStartBalance > 0.0 &&
      equity <= g_dayStartBalance * (1.0 - DailyLossLimitPercent / 100.0))
   {
      g_dailyLimitHit = true;
      GvSet("DailyLimitHit", 1.0);
      GvFlush(true);
      WarnMsg(StringFormat("Daily loss limit reached: equity %.2f vs %.2f at the start of the day. "
                           "No new trades until tomorrow.", equity, g_dayStartBalance));
   }

   // Highest equity so far, and the kill switch.
   if(equity > g_peakEquity)
   {
      g_peakEquity = equity;
      if(!g_isTester)
      {
         GvSet("PeakEquity", g_peakEquity);
         GvFlush(false);
      }
   }
   if(KillSwitchDrawdownPercent > 0.0 && !g_killSwitchOn && g_peakEquity > 0.0 &&
      equity <= g_peakEquity * (1.0 - KillSwitchDrawdownPercent / 100.0))
   {
      g_killSwitchOn = true;
      GvSet("KillSwitch", 1.0);
      GvFlush(true);
      WarnMsg(StringFormat("KILL SWITCH TRIGGERED: equity %.2f is %.1f%% below its peak of %.2f. Closing this EA's "
                           "trades and stopping for good (until you reset it).",
                           equity, (1.0 - equity / g_peakEquity) * 100.0, g_peakEquity));
   }
}


// Kill switch: close every trade carrying this EA's MagicNumber.
void CloseEverythingForKillSwitch()
{
   if(TimeCurrent() >= g_closeRetryAfter)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;
         if(!g_trade.PositionClose(ticket) || !RequestSucceeded(g_trade.ResultRetcode()))
         {
            LogMsg("Kill switch: could not close trade " + IntegerToString((long)ticket) + " (" +
                   g_trade.ResultRetcodeDescription() + "). Trying again in a few seconds.");
            g_closeRetryAfter = TimeCurrent() + 5;
         }
      }
   }
   SyncPositions(false);                     // log the closed trades with reason "kill switch"
}

//====================================================================
//  NEWS FILTER AND CHART DATA
//====================================================================

// Read one "YYYY.MM.DD HH:MM" time (anything after a comma is ignored) and
// add it to the list. Returns true if a time was added.
bool AddNewsTime(const string text)
{
   string s = text;
   StringTrimLeft(s);
   StringTrimRight(s);
   int length = StringLen(s);
   int start  = 0;
   while(start < length)
   {
      ushort c = StringGetCharacter(s, start);
      if(c >= '0' && c <= '9')
         break;
      if(c == '#')
         return false;                       // a comment line
      start++;                               // skip invisible characters before the date
   }
   if(start >= length)
      return false;
   s = StringSubstr(s, start);
   int cut = StringFind(s, ",");
   if(cut >= 0)
      s = StringSubstr(s, 0, cut);
   cut = StringFind(s, "\t");
   if(cut >= 0)
      s = StringSubstr(s, 0, cut);
   StringTrimRight(s);
   StringReplace(s, "-", ".");
   StringReplace(s, "/", ".");
   if(StringLen(s) < 10 || StringGetCharacter(s, 4) != '.' || StringGetCharacter(s, 7) != '.')
      return false;
   datetime t = StringToTime(s);
   if(t <= 0)
      return false;
   int n = ArraySize(g_newsTimes);
   ArrayResize(g_newsTimes, n + 1, 256);
   g_newsTimes[n] = (long)t;
   return true;
}

// Build the list of news times from ManualNewsTimes and the news file.
void LoadNewsTimes()
{
   ArrayResize(g_newsTimes, 0);
   if(!UseNewsFilter)
   {
      LogMsg("News filter is OFF.");
      return;
   }
   int fromText = 0, fromFile = 0;

   string list = ManualNewsTimes;
   StringReplace(list, ",", ";");
   string parts[];
   int count = StringSplit(list, ';', parts);
   for(int i = 0; i < count; i++)
   {
      if(AddNewsTime(parts[i]))
         fromText++;
      else if(StringLen(parts[i]) > 0 && StringFind(parts[i], ":") >= 0)
         LogMsg("Could not read the news time '" + parts[i] + "' (use YYYY.MM.DD HH:MM).");
   }

   string fileNote = "no news file used";
   if(NewsTimesFile != "")
   {
      if(FileIsExist(NewsTimesFile, FILE_COMMON))
      {
         int handle = FileOpen(NewsTimesFile, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
         if(handle != INVALID_HANDLE)
         {
            while(!FileIsEnding(handle))
            {
               if(AddNewsTime(FileReadString(handle)))
                  fromFile++;
            }
            FileClose(handle);
            fileNote = "file " + NewsTimesFile;
         }
         else
            fileNote = "file " + NewsTimesFile + " could not be opened (error " + IntegerToString(GetLastError()) + ")";
      }
      else
      {
         fileNote = "file " + NewsTimesFile + " NOT FOUND in " + TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files";
      }
   }
   ArraySort(g_newsTimes);
   LogMsg(StringFormat("News filter: %d times from ManualNewsTimes, %d from the news file (%s).", fromText, fromFile,
                       fileNote));
   if(g_isTester)
      LogMsg("Reminder: MetaTrader's economic calendar does not work in the Strategy Tester, so in this test ONLY the "
             "listed news times are avoided.");
}

// Live trading: ask MetaTrader's economic calendar whether a high-impact
// USD event is within the blackout window around "now".
bool CalendarNewsNear(const datetime now, string &what)
{
   MqlCalendarValue values[];
   datetime from = now - NewsMinutesAfter * 60 - 60;
   datetime to   = now + NewsMinutesBefore * 60 + 60;
   ResetLastError();
   if(!CalendarValueHistory(values, from, to, NULL, "USD"))
   {
      int error = GetLastError();
      if(error != 0 && TimeCurrent() >= g_calendarWarnAfter)
      {
         LogMsg("The economic calendar could not be read (error " + IntegerToString(error) +
                "). Only your listed news times are avoided for now.");
         g_calendarWarnAfter = TimeCurrent() + 3600;
      }
      return false;
   }
   for(int i = 0; i < ArraySize(values); i++)
   {
      MqlCalendarEvent eventInfo;
      if(!CalendarEventById(values[i].event_id, eventInfo))
         continue;
      if(eventInfo.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      datetime eventTime = values[i].time;
      if(now >= eventTime - NewsMinutesBefore * 60 && now <= eventTime + NewsMinutesAfter * 60)
      {
         what = eventInfo.name + " at " + TimeToString(eventTime, TIME_DATE | TIME_MINUTES);
         return true;
      }
   }
   return false;
}

// Is "now" inside a news blackout window?
bool InNewsBlackout(const datetime now, string &what)
{
   // 1) The listed times (works in the tester and live). The list is sorted,
   //    so find the first time that is not older than the "after" window.
   int count = ArraySize(g_newsTimes);
   if(count > 0)
   {
      long earliest = (long)now - NewsMinutesAfter * 60;
      int  first = 0, last = count;
      while(first < last)
      {
         int middle = (first + last) / 2;
         if(g_newsTimes[middle] < earliest)
            first = middle + 1;
         else
            last = middle;
      }
      if(first < count && g_newsTimes[first] <= (long)now + NewsMinutesBefore * 60)
      {
         what = "listed news time " + TimeToString((datetime)g_newsTimes[first], TIME_DATE | TIME_MINUTES);
         return true;
      }
   }
   // 2) MetaTrader's economic calendar (live trading only).
   if(!g_isTester && CalendarNewsNear(now, what))
      return true;
   return false;
}

// Value of an indicator on the last FINISHED candle of a chart.
bool ReadFinishedCandleValue(const int handle, const ENUM_TIMEFRAMES tf, double &value)
{
   if(BarsCalculated(handle) <= 0)
      return false;
   datetime finishedCandle = iTime(g_symbol, tf, 1);
   if(finishedCandle == 0)
      return false;
   double buffer[];
   if(CopyBuffer(handle, 0, finishedCandle, 1, buffer) != 1)
      return false;
   value = buffer[0];
   return (value != EMPTY_VALUE && MathIsValidNumber(value));
}


//====================================================================
//  DIRECTION OF THE MARKET (TREND)
//====================================================================

// Market structure on one chart, from finished candles only.
// Returns +1 if the last break of structure was upward (a close above the
// last swing high), -1 if it was downward, 0 if there was none yet.
// Also returns the last swing low and swing high (the current range), and
// in "breakNow" the direction of a break made by the newest finished candle
// itself (0 if that candle broke nothing).
int StructureScan(const ENUM_TIMEFRAMES tf, const int strength, const int count,
                  double &rangeLow, double &rangeHigh, int &breakNow)
{
   rangeLow  = 0.0;
   rangeHigh = 0.0;
   breakNow  = 0;
   double highs[];
   double lows[];
   double closes[];
   if(CopyHigh(g_symbol, tf, 1, count, highs) != count || CopyLow(g_symbol, tf, 1, count, lows) != count ||
      CopyClose(g_symbol, tf, 1, count, closes) != count)
      return 0;                              // not enough history yet
   int    dir = 0;
   double swingHigh = 0.0, swingLow = 0.0;
   bool   highUnbroken = false, lowUnbroken = false;
   for(int i = 0; i < count; i++)            // oldest candle first
   {
      // The candle "strength" places back is now confirmed (or not) as a swing.
      int j = i - strength;
      if(j >= strength)
      {
         bool isHigh = true, isLow = true;
         for(int k = j - strength; k <= j + strength; k++)
         {
            if(k == j)
               continue;
            if(highs[k] >= highs[j])
               isHigh = false;
            if(lows[k] <= lows[j])
               isLow = false;
         }
         if(isHigh)
         {
            swingHigh    = highs[j];
            highUnbroken = true;
         }
         if(isLow)
         {
            swingLow    = lows[j];
            lowUnbroken = true;
         }
      }
      // Break of structure: a CLOSE beyond the last swing.
      if(highUnbroken && closes[i] > swingHigh)
      {
         dir          = 1;
         highUnbroken = false;
         if(i == count - 1)
            breakNow = 1;
      }
      if(lowUnbroken && closes[i] < swingLow)
      {
         dir         = -1;
         lowUnbroken = false;
         if(i == count - 1)
            breakNow = -1;
      }
   }
   rangeLow  = swingLow;
   rangeHigh = swingHigh;
   return dir;
}

// Structure of a direction chart (uses SwingStrength and StructureLookback).
int StructureDirection(const ENUM_TIMEFRAMES tf, double &rangeLow, double &rangeHigh)
{
   int breakNow = 0;
   return StructureScan(tf, SwingStrength, StructureLookback, rangeLow, rangeHigh, breakNow);
}

// Momentum: +1 if the last finished candle closed higher than the candles
// MomentumShortCandles AND MomentumLongCandles before it, -1 if lower than
// both, 0 if mixed.
int MomentumDirection()
{
   int    longest = MathMax(MomentumShortCandles, MomentumLongCandles);
   double closes[];
   if(CopyClose(g_symbol, MomentumTimeframe, 1, longest + 1, closes) != longest + 1)
      return 0;
   double now      = closes[longest];
   double shortAgo = closes[longest - MomentumShortCandles];
   double longAgo  = closes[longest - MomentumLongCandles];
   if(now > shortAgo && now > longAgo)
      return 1;
   if(now < shortAgo && now < longAgo)
      return -1;
   return 0;
}

// Count one check's vote (only if the check is switched on).
void AddVote(const bool on, const int vote)
{
   if(!on)
      return;
   if(vote > 0)
      g_votesBuy++;
   if(vote < 0)
      g_votesSell++;
}

// Decide the direction from the votes of the switched-on checks.
void RefreshTrend()
{
   double low = 0.0, high = 0.0;
   g_topDir      = StructureDirection(TopTimeframe, low, high);
   g_higherDir   = StructureDirection(HigherTimeframe, low, high);
   g_middleDir   = StructureDirection(MiddleTimeframe, g_rangeLow, g_rangeHigh);
   g_momentumDir = MomentumDirection();
   g_emaDir      = 0;
   double fast = 0.0, slow = 0.0;
   if(ReadFinishedCandleValue(g_fastHandle, TrendTimeframe, fast) &&
      ReadFinishedCandleValue(g_slowHandle, TrendTimeframe, slow) && fast > 0.0 && slow > 0.0)
   {
      g_emaFast = fast;
      g_emaSlow = slow;
      if(fast > slow)
         g_emaDir = 1;
      if(fast < slow)
         g_emaDir = -1;
   }
   g_votesBuy  = 0;
   g_votesSell = 0;
   g_checksOn  = CountChecksOn();
   AddVote(UseTopStructure, g_topDir);
   AddVote(UseHigherStructure, g_higherDir);
   AddVote(UseMiddleStructure, g_middleDir);
   AddVote(UseEMAFilter, g_emaDir);
   AddVote(UseMomentum, g_momentumDir);

   // BUY if at most ChecksAllowedToDisagree checks did not vote BUY (SELL: mirror),
   // and the top chart agrees when it must.
   int bias = 0;
   if(g_checksOn - g_votesBuy <= ChecksAllowedToDisagree && (!TopTimeframeMustAgree || g_topDir > 0))
      bias = 1;
   if(g_checksOn - g_votesSell <= ChecksAllowedToDisagree && (!TopTimeframeMustAgree || g_topDir < 0))
      bias = (bias == 0) ? -1 : 0;
   g_trendDir = bias;
}

// Close this EA's trades that point against the direction "dir".
void CloseTradesAgainst(const int dir)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;
      int  tradeDir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      long id       = PositionGetInteger(POSITION_IDENTIFIER);
      if(tradeDir != -dir)
         continue;
      if(g_trade.PositionClose(ticket) && RequestSucceeded(g_trade.ResultRetcode()))
      {
         int n = ArraySize(g_trendClosedIds);
         ArrayResize(g_trendClosedIds, n + 1);
         g_trendClosedIds[n] = id;
      }
      else
         LogMsg("Could not close a trade after the direction changed (" + g_trade.ResultRetcodeDescription() + ").");
   }
   SyncPositions(false);
}

//====================================================================
//  FAIR VALUE GAPS
//====================================================================

void RemoveGap(const int index)
{
   int last = ArraySize(g_gaps) - 1;
   for(int i = index; i < last; i++)
      g_gaps[i] = g_gaps[i + 1];
   ArrayResize(g_gaps, last);
}

// Runs once per finished 1-minute candle: forget old gaps, look for a new one.
void UpdateGaps()
{
   datetime lastCandle = iTime(g_symbol, SignalTimeframe, 1);   // the candle that just finished
   double   lastClose  = iClose(g_symbol, SignalTimeframe, 1);
   if(lastCandle == 0 || lastClose <= 0.0)
      return;

   // 1) Forget gaps that were used, broken by a close right through them,
   //    too old, or that point against the current trend.
   long maxAge = (long)GapExpiryCandles * PeriodSeconds(SignalTimeframe);
   for(int i = ArraySize(g_gaps) - 1; i >= 0; i--)
   {
      bool broken  = (g_gaps[i].dir > 0 && lastClose < g_gaps[i].low) || (g_gaps[i].dir < 0 && lastClose > g_gaps[i].high);
      bool tooOld  = ((long)lastCandle - (long)g_gaps[i].made) >= maxAge;
      if(g_gaps[i].used || broken || tooOld || g_gaps[i].dir != g_trendDir)
         RemoveGap(i);
   }
   if(g_trendDir == 0 || !UseGapEntries)
      return;

   // 2) A new gap? Candle 3 back and the candle that just finished must not
   //    overlap. Bullish: the newest low is above the high 2 candles before.
   double high3 = iHigh(g_symbol, SignalTimeframe, 3);
   double low3  = iLow(g_symbol, SignalTimeframe, 3);
   double high1 = iHigh(g_symbol, SignalTimeframe, 1);
   double low1  = iLow(g_symbol, SignalTimeframe, 1);
   if(high3 <= 0.0 || low3 <= 0.0 || high1 <= 0.0 || low1 <= 0.0)
      return;
   Gap gap;
   gap.dir  = 0;
   gap.low  = 0.0;
   gap.high = 0.0;
   gap.made = lastCandle;
   gap.used = false;
   gap.entries = 0;
   if(g_trendDir > 0 && low1 > high3 && low1 - high3 >= MinGapUSD)
   {
      gap.dir  = 1;
      gap.low  = high3;
      gap.high = low1;
   }
   if(g_trendDir < 0 && low3 > high1 && low3 - high1 >= MinGapUSD)
   {
      gap.dir  = -1;
      gap.low  = high1;
      gap.high = low3;
   }
   if(gap.dir == 0)
      return;
   if(ArraySize(g_gaps) >= MAX_GAPS)
      RemoveGap(0);
   int n = ArraySize(g_gaps);
   ArrayResize(g_gaps, n + 1);
   g_gaps[n] = gap;
   g_gapsFound++;
}

// Runs once per finished 1-minute candle: entry kinds 2 and 3.
void UpdateBreakAndPullback()
{
   // Kind 2: did the candle that just finished break a small swing in the
   // trend's direction? Then the new candle may give one trade.
   g_breakDir = 0;
   if(UseBreakEntries && g_trendDir != 0)
   {
      double low = 0.0, high = 0.0;
      int breakNow = 0;
      StructureScan(SignalTimeframe, EntrySwingStrength, EntryStructureLookback, low, high, breakNow);
      if(breakNow == g_trendDir)
      {
         g_breakDir    = breakNow;
         g_breakCandle = iTime(g_symbol, SignalTimeframe, 0);
      }
   }
   // Kind 3: the EMA and the close of the candle that just finished.
   g_pullbackEma   = 0.0;
   g_pullbackClose = 0.0;
   double ema = 0.0;
   if(UsePullbackEntries && ReadFinishedCandleValue(g_pullbackHandle, SignalTimeframe, ema) && ema > 0.0)
   {
      g_pullbackEma   = ema;
      g_pullbackClose = iClose(g_symbol, SignalTimeframe, 1);
   }
}

//====================================================================
//  OPENING TRADES
//====================================================================

// Is this server time inside TradingHourStart-TradingHourEnd?
bool InTradingHours(const datetime t)
{
   if(TradingHourStart == TradingHourEnd || (TradingHourStart == 0 && TradingHourEnd == 24))
      return true;
   int hour = (int)(((long)t % 86400) / 3600);
   if(TradingHourStart < TradingHourEnd)
      return (hour >= TradingHourStart && hour < TradingHourEnd);
   return (hour >= TradingHourStart || hour < TradingHourEnd);      // e.g. 22 to 3
}

// Everything that must be OK before ANY new trade.
bool EntriesAllowed(const MqlTick &tick, string &reason)
{
   if(ResetKillSwitch)
   {
      reason = "ResetKillSwitch is true (set it back to false to trade)";
      return false;
   }
   if(g_killSwitchOn)
   {
      reason = "the kill switch is active";
      return false;
   }
   if(g_dailyLimitHit)
   {
      reason = "daily loss limit reached, waiting for the next day";
      return false;
   }
   if(!g_isTester && (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0 || MQLInfoInteger(MQL_TRADE_ALLOWED) == 0))
   {
      reason = "automated trading is switched off (Algo Trading button, or 'Allow Algo Trading' in the EA settings)";
      return false;
   }
   long tradeMode = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED || tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
   {
      reason = "the broker does not allow new trades on " + g_symbol + " right now";
      return false;
   }
   if(!InTradingHours(TimeCurrent()))
   {
      reason = "outside the trading hours " + IntegerToString(TradingHourStart) + "-" + IntegerToString(TradingHourEnd);
      return false;
   }
   double spread = tick.ask - tick.bid;
   if(MaxSpreadUSD > 0.0 && spread > MaxSpreadUSD + g_tickSize * 0.01)
   {
      reason = "spread " + DoubleToString(spread, g_digits) + " is wider than MaxSpreadUSD " +
               DoubleToString(MaxSpreadUSD, g_digits);
      return false;
   }
   if(g_newsBlocked)
   {
      reason = "news blackout (" + g_newsWhat + ")";
      return false;
   }
   return true;
}

// LotSize, kept within the broker's limits and lot step.
double TradeLots()
{
   double minLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double lots   = RoundLotsDown(LotSize);
   if(minLot > 0.0 && lots < minLot)
      lots = minLot;
   if(maxLot > 0.0 && lots > maxLot)
      lots = RoundLotsDown(maxLot);
   return lots;
}

// Open one trade with its take-profit and stop-loss.
bool OpenTrade(const int dir, const int kind, const MqlTick &tick)
{
   double lots   = TradeLots();
   double entry  = (dir > 0) ? tick.ask : tick.bid;            // buys fill at the Ask, sells at the Bid
   double spread = tick.ask - tick.bid;
   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   // Money tied up by the trade (margin) and money won/lost per 1.00 of price.
   double margin = 0.0;
   if(!OrderCalcMargin(type, g_symbol, lots, entry, margin) || margin <= 0.0)
   {
      LogMsg("Could not work out the margin for a trade; skipped.");
      return false;
   }
   double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   double moneyPerPrice = lots * tickValue / g_tickSize;
   if(moneyPerPrice <= 0.0)
   {
      LogMsg("Could not read the tick value; skipped.");
      return false;
   }
   // Take-profit at +TakeProfitPercentOfMargin %, stop-loss at -StopLossPercentOfMargin %.
   g_tpDistance = TakeProfitPercentOfMargin / 100.0 * margin / moneyPerPrice;
   g_slDistance = StopLossPercentOfMargin / 100.0 * margin / moneyPerPrice;
   double brokerMinimum = (double)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point + g_tickSize;
   if(g_tpDistance < 2.0 * spread || g_tpDistance < brokerMinimum || g_slDistance < brokerMinimum + spread)
   {
      LogMsg("Trade skipped: the take-profit would be only " + DoubleToString(g_tpDistance, g_digits) +
             " away, too close to the spread (" + DoubleToString(spread, g_digits) +
             "). With high leverage 10% of the margin is a tiny move: use lower leverage or a bigger TakeProfitPercentOfMargin.");
      return false;
   }
   if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9)
   {
      LogMsg("Trade skipped: not enough free margin.");
      return false;
   }
   double takeProfit = (dir > 0) ? RoundToTick(entry + g_tpDistance) : RoundToTick(entry - g_tpDistance);
   double stopLoss   = (dir > 0) ? RoundToTick(entry - g_slDistance) : RoundToTick(entry + g_slDistance);

   string comment = "GSF " + KindName(kind);
   bool sent = (dir > 0) ? g_trade.Buy(lots, g_symbol, entry, stopLoss, takeProfit, comment)
                         : g_trade.Sell(lots, g_symbol, entry, stopLoss, takeProfit, comment);
   uint retcode = g_trade.ResultRetcode();
   if(!sent || !RequestSucceeded(retcode))
   {
      LogMsg(DirText(dir) + " order failed: " + g_trade.ResultRetcodeDescription() + " (code " +
             IntegerToString(retcode) + ").");
      return false;
   }
   g_tradesOpened++;
   g_tradesByKind[kind]++;
   GvSet("Spread_" + IntegerToString((long)g_trade.ResultOrder()), spread);
   GvSet("Kind_" + IntegerToString((long)g_trade.ResultOrder()), kind);
   SyncPositions(false);
   if(!g_isTester)
      LogMsg(StringFormat("%s (%s) %s lots at %s, take-profit %s, stop-loss %s, spread %s", DirText(dir), KindName(kind),
                          DoubleToString(lots, LotDigits()), DoubleToString(entry, g_digits),
                          DoubleToString(takeProfit, g_digits), DoubleToString(stopLoss, g_digits),
                          DoubleToString(spread, g_digits)));
   return true;
}

// On every tick: does one of the three entry kinds say "go" in the trend's
// direction? (Checked in this order: gap, break, pullback.)
void CheckEntries(const MqlTick &tick)
{
   if(g_trendDir == 0)
      return;
   datetime candle = iTime(g_symbol, SignalTimeframe, 0);
   if(candle == 0 || candle == g_lastEntryCandle)
      return;                                // at most one new trade per candle
   int kind = 0;
   // 1) newest unused gap that the price is in
   int pick = -1;
   for(int i = ArraySize(g_gaps) - 1; i >= 0 && UseGapEntries; i--)
   {
      if(g_gaps[i].used || g_gaps[i].dir != g_trendDir)
         continue;
      if(tick.bid >= g_gaps[i].low && tick.bid <= g_gaps[i].high)
      {
         pick = i;
         break;
      }
   }
   if(pick >= 0)
      kind = 1;
   // 2) the last candle broke a small swing in the trend's direction
   else if(UseBreakEntries && g_breakDir == g_trendDir && g_breakCandle == candle)
      kind = 2;
   // 3) the price is back at the EMA after a candle closed on the trend's side of it
   else if(UsePullbackEntries && g_pullbackEma > 0.0 &&
           ((g_trendDir > 0 && g_pullbackClose > g_pullbackEma && tick.bid <= g_pullbackEma) ||
            (g_trendDir < 0 && g_pullbackClose < g_pullbackEma && tick.bid >= g_pullbackEma)))
      kind = 3;
   if(kind == 0)
      return;
   if(UsePremiumDiscount && g_rangeHigh > g_rangeLow)
   {
      double middle = (g_rangeHigh + g_rangeLow) / 2.0;
      if((g_trendDir > 0 && tick.bid > middle) || (g_trendDir < 0 && tick.bid < middle))
         return;                             // buys only in discount, sells only in premium
   }
   if(CountOurPositions() >= MaxOpenTrades)
      return;                                // already the most trades allowed
   string reason = "";
   if(!EntriesAllowed(tick, reason))
   {
      if(candle != g_lastSkipLog)
      {
         LogMsg(DirText(g_trendDir) + " entry skipped: " + reason + ".");
         g_lastSkipLog = candle;
      }
      return;
   }
   g_lastEntryCandle = candle;
   if(OpenTrade(g_trendDir, kind, tick) && kind == 1)
   {
      g_gaps[pick].entries++;
      if(g_gaps[pick].entries >= EntriesPerGap)
         g_gaps[pick].used = true;
   }
}

// Once per new 1-minute candle: direction, gaps, breaks, EMA and news.
void OnNewSignalCandle()
{
   datetime candle = iTime(g_symbol, SignalTimeframe, 0);
   if(candle == 0 || candle == g_lastSignalCandle)
      return;
   g_lastSignalCandle = candle;
   RefreshTrend();
   if(CloseOnTrendChange && g_trendDir != 0)
      CloseTradesAgainst(g_trendDir);
   UpdateGaps();
   UpdateBreakAndPullback();
   g_newsWhat    = "";
   g_newsBlocked = UseNewsFilter && InNewsBlackout(TimeCurrent(), g_newsWhat);
}

//====================================================================
//  STATUS TEXT AND END-OF-TEST SUMMARY
//====================================================================

string StatusText()
{
   if(g_killSwitchOn)
      return "KILL SWITCH ACTIVE - trading stopped (see ResetKillSwitch)";
   if(ResetKillSwitch)
      return "Kill switch was reset - set ResetKillSwitch = false to resume trading";
   if(g_dailyLimitHit)
      return "Daily loss limit reached - no new trades until tomorrow";
   if(g_newsBlocked)
      return "News time - no new trades (" + g_newsWhat + ")";
   if(g_trendDir == 0)
      return "Waiting: the direction checks don't agree enough yet";
   return "Trading";
}

void ShowStatus(const MqlTick &tick)
{
   if(!g_showStatus)
      return;
   static uint lastDraw = 0;
   uint nowMs = GetTickCount();
   if(nowMs - lastDraw < 1000)
      return;
   lastDraw = nowMs;

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = (g_peakEquity > 0.0) ? (1.0 - equity / g_peakEquity) * 100.0 : 0.0;
   string trend    = "not known yet";
   if(g_trendDir > 0)
      trend = "UP - buys only";
   if(g_trendDir < 0)
      trend = "DOWN - sells only";
   string text = EA_NAME;
   text += "  |  " + g_symbol + "  |  " + IntegerToString(CountOurPositions()) + " of " + IntegerToString(MaxOpenTrades) +
           " trades open\n";
   text += "Status: " + StatusText() + "\n";
   text += "Direction: " + trend + "   (votes: " + IntegerToString(g_votesBuy) + " buy, " + IntegerToString(g_votesSell) +
           " sell, of " + IntegerToString(g_checksOn) + ")\n";
   text += "   structure " + (UseTopStructure ? TfName(TopTimeframe) + " " + DirText(g_topDir) + ", " : "") +
           (UseHigherStructure ? TfName(HigherTimeframe) + " " + DirText(g_higherDir) + ", " : "") +
           (UseMiddleStructure ? TfName(MiddleTimeframe) + " " + DirText(g_middleDir) : "") +
           (UseEMAFilter ? " | EMA " + DirText(g_emaDir) : "") + (UseMomentum ? " | momentum " + DirText(g_momentumDir) : "") + "\n";
   text += "Trades opened: " + IntegerToString(g_tradesOpened) + " (gap " + IntegerToString(g_tradesByKind[1]) + ", break " +
           IntegerToString(g_tradesByKind[2]) + ", pullback " + IntegerToString(g_tradesByKind[3]) + ")  |  gaps waiting: " +
           IntegerToString(ArraySize(g_gaps)) + "\n";
   if(g_tpDistance > 0.0)
      text += "Per trade: take-profit +" + DoubleToString(g_tpDistance, 2) + " / stop-loss -" +
              DoubleToString(g_slDistance, 2) + " in price\n";
   text += StringFormat("Equity %.2f  |  peak %.2f  |  down %.1f%% from peak (kill switch at %.1f%%)\n",
                        equity, g_peakEquity, drawdown, KillSwitchDrawdownPercent);
   text += "Spread " + DoubleToString(tick.ask - tick.bid, g_digits) + " (max " + DoubleToString(MaxSpreadUSD, g_digits) + ")\n";
   Comment(text);
}

void PrintSummary()
{
   if(g_isOptimizing || g_firstTickTime == 0)
      return;
   double days = (double)(TimeCurrent() - g_firstTickTime) / 86400.0;
   if(days <= 0.0)
      return;
   Print(StringFormat("Test summary: %d trades opened in %.0f days (%.1f per calendar day): %d gap, %d break, %d pullback "
                      "entries; %d fair value gaps found.",
                      g_tradesOpened, days, g_tradesOpened / days, g_tradesByKind[1], g_tradesByKind[2], g_tradesByKind[3],
                      g_gapsFound));
}

//====================================================================
//  METATRADER EVENTS
//====================================================================

int OnInit()
{
   g_isTester     = (MQLInfoInteger(MQL_TESTER) != 0);
   g_isOptimizing = (MQLInfoInteger(MQL_OPTIMIZATION) != 0);
   g_showStatus   = (!g_isTester || MQLInfoInteger(MQL_VISUAL_MODE) != 0);

   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;
   if(!ResolveSymbol())
      return INIT_PARAMETERS_INCORRECT;
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      WarnMsg("This EA holds several trades at once, so it needs a HEDGING account. This account is not one. "
              "Open a demo account with 'Use hedge in trading' ticked.");
      return INIT_FAILED;
   }

   g_digits   = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   g_point    = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_tickSize = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_tickSize <= 0.0)
      g_tickSize = g_point;
   if(g_point <= 0.0 || g_tickSize <= 0.0)
   {
      WarnMsg("Could not read the price format of " + g_symbol + ".");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber((ulong)MagicNumber);
   g_trade.SetDeviationInPoints((ulong)MathMax(1.0, MathRound(MaxSlippageUSD / g_point)));
   g_trade.SetTypeFillingBySymbol(g_symbol);
   g_trade.SetMarginMode();
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   g_fastHandle = iMA(g_symbol, TrendTimeframe, TrendFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_slowHandle = iMA(g_symbol, TrendTimeframe, TrendSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_pullbackHandle = iMA(g_symbol, SignalTimeframe, PullbackEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(g_fastHandle == INVALID_HANDLE || g_slowHandle == INVALID_HANDLE || g_pullbackHandle == INVALID_HANDLE)
   {
      WarnMsg("Could not create the EMA indicators.");
      return INIT_FAILED;
   }

   g_gvPrefix = "GSF_" + IntegerToString(MagicNumber) + "_";
   if(g_isTester)
      GlobalVariablesDeleteAll(g_gvPrefix);  // every backtest starts from a clean slate

   LoadSafetyState();
   LoadNewsTimes();
   PrepareCsvFile();

   // MetaTrader keeps the EA's memory when only a setting changes, so start
   // the gap list fresh; new gaps are found from the next candle on.
   ArrayResize(g_gaps, 0);
   ArrayInitialize(g_tradesByKind, 0);
   g_breakDir         = 0;
   g_breakCandle      = 0;
   g_pullbackEma      = 0.0;
   g_lastSignalCandle = 0;
   g_lastEntryCandle  = 0;
   SyncPositions(false);
   if(!g_isTester)
      LogTradesClosedWhileOffline();

   LogMsg(StringFormat("%s started on %s | direction: %d checks, %d may disagree%s | entries on %s:%s%s%s | "
                       "up to %d trades of %s lots | take-profit +%.1f%% / stop-loss -%.1f%% of margin",
                       EA_NAME, g_symbol, CountChecksOn(), ChecksAllowedToDisagree,
                       (TopTimeframeMustAgree ? ", " + TfName(TopTimeframe) + " must agree" : ""), TfName(SignalTimeframe),
                       (UseGapEntries ? " gaps" : ""), (UseBreakEntries ? " breaks" : ""), (UsePullbackEntries ? " pullbacks" : ""),
                       MaxOpenTrades, DoubleToString(TradeLots(), LotDigits()),
                       TakeProfitPercentOfMargin, StopLossPercentOfMargin));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_isTester)
   {
      SyncPositions(true);                   // log trades the tester has just closed...
      LogTradesStillOpenAtEnd();             // ...and any still open at the end
      PrintSummary();
   }
   if(g_fastHandle != INVALID_HANDLE)
      IndicatorRelease(g_fastHandle);
   if(g_slowHandle != INVALID_HANDLE)
      IndicatorRelease(g_slowHandle);
   if(g_pullbackHandle != INVALID_HANDLE)
      IndicatorRelease(g_pullbackHandle);
   GvFlush(true);
   if(g_showStatus)
      Comment("");
}

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return;
   if(g_firstTickTime == 0)
      g_firstTickTime = tick.time;

   SyncPositions(false);                     // 1. trades that closed -> CSV
   UpdateSafetySwitches();                   // 2. daily loss limit, equity peak, kill switch
   if(g_killSwitchOn)
   {
      CloseEverythingForKillSwitch();
      ShowStatus(tick);
      return;
   }
   OnNewSignalCandle();                      // 3. once a minute: direction, gaps, breaks, news
   CheckEntries(tick);                       // 4. gap, break or pullback? -> new trade
   ShowStatus(tick);
}

void OnTrade()
{
   SyncPositions(false);
}
//+------------------------------------------------------------------+
