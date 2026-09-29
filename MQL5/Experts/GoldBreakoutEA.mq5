//+------------------------------------------------------------------+
//|                                               GoldBreakoutEA.mq5 |
//|         Trend-filtered breakout robot for gold (XAUUSD) on MT5   |
//+------------------------------------------------------------------+
//
//  HOW TO READ THIS FILE
//  ---------------------
//  Lines that start with // are notes for people. MetaTrader ignores
//  them. Everything else is the program itself.
//
//  WHAT THE ROBOT DOES
//  -------------------
//  1. DIRECTION (4-hour chart): buys are only allowed while the last
//     FINISHED 4-hour candle closed above the 100-period EMA (a smoothed
//     average price). Sells are only allowed while it closed below it.
//  2. ENTRY (1-hour chart): each time a 1-hour candle finishes, the robot
//     checks whether it closed above the highest high of the 20 candles
//     before it (buy signal) or below their lowest low (sell signal).
//     It only ever looks at finished candles, never the one still forming.
//  3. EXITS: the stop starts 2 x ATR away from the entry price. ATR
//     (Average True Range) is the typical size of a 1-hour candle, so the
//     stop adapts to how jumpy the market is. When the trade is ahead by
//     as much as it risked, the stop moves to the entry price (break-even).
//     After that the stop follows the best price at 3 x ATR behind it.
//     There is no fixed profit target.
//  4. RISK: each trade is sized so that hitting the first stop loses about
//     0.5% of the balance. One trade at a time. No grid, no martingale,
//     no adding to a trade.
//  5. SAFETY: no new trades after a 2% loss day (until the next day), and a
//     kill switch that closes everything and stops for good if equity falls
//     15% below its highest point. It also skips entries when the spread is
//     too wide and around high-impact USD news.
//  6. RANDOM TWIN MODE: for testing only. Enters at random times in a random
//     direction but uses exactly the same exits, sizing and safety rules, so
//     you can see whether the entry signal is better than luck.
//  7. LOG: every finished trade becomes one line in a CSV file (MQL5/Files).
//
//  Every number above is a setting ("input") you can change in the EA's
//  Inputs tab without touching this code.
//
//  One rule is deliberately NOT a setting: the robot never holds more than
//  one trade. Allowing more would mean adding to positions, which is exactly
//  what this robot must never do.
//+------------------------------------------------------------------+
#property version     "1.00"
#property description "Gold breakout robot: H4 EMA trend filter + H1 20-candle breakout."
#property description "ATR stop, break-even, ATR trailing stop, 0.5% risk per trade."
#property description "Daily loss limit, equity kill switch, spread and news filters."
#property description "Random twin mode for comparison tests. CSV trade log in MQL5/Files."

// MetaTrader's standard helper for sending orders (comes with every MT5).
#include <Trade\Trade.mqh>

#define EA_NAME          "GoldBreakoutEA"
#define SECONDS_PER_YEAR 31557600.0

//====================================================================
//  SETTINGS ("INPUTS")
//  These appear in the Inputs tab when you attach the EA to a chart or
//  pick it in the Strategy Tester. The names there are the ones below
//  (for example RiskPercentPerTrade).
//====================================================================

input group "=== 1. Symbol ==="
// The exact name of gold at your broker, as shown in Market Watch
// (for example XAUUSD, XAUUSDm, XAUUSD.pro or GOLD). The EA must run on a
// chart of this symbol; in the Strategy Tester, choose it as the "Symbol".
// If your broker only adds letters at the end (XAUUSD -> XAUUSDm),
// "XAUUSD" also works: a chart whose name STARTS with it is accepted.
input string TradeSymbol = "XAUUSD";

input group "=== 2. Direction filter (4-hour chart) ==="
// The chart that decides which direction is allowed (default: 4 hours).
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_H4;
// Length of the EMA on that chart. Buys only if the last finished candle
// closed above it, sells only if it closed below it.
input int TrendEMAPeriod = 100;

input group "=== 3. Entry signal (1-hour chart) ==="
// The chart on which breakouts are checked (default: 1 hour).
input ENUM_TIMEFRAMES EntryTimeframe = PERIOD_H1;
// How many earlier candles set the breakout level. With 20, a buy needs the
// just-finished candle to close above the highest high of the 20 candles
// before it (a sell: below their lowest low).
input int BreakoutLookbackCandles = 20;

input group "=== 4. Exits ==="
// Chart and length of the ATR used for all stop distances.
input ENUM_TIMEFRAMES ATRTimeframe = PERIOD_H1;
input int ATRPeriod = 14;
// Initial stop: this many ATRs away from the entry price.
input double InitialStopATRMultiplier = 2.0;
// Move the stop to break-even once the trade is in profit by this many times
// the initial stop distance (1.0 = profit equal to what the trade risked).
input double BreakEvenTriggerMultiple = 1.0;
// Optional: place the break-even stop this far beyond the entry, in price
// units (0.10 = 10 cents on gold), to cover costs. 0 = exactly at entry.
input double BreakEvenExtraUSD = 0.0;
// After break-even, the stop trails this many ATRs behind the best price
// reached. It only ever moves in your favour, never back.
input double TrailingStopATRMultiplier = 3.0;
// So the broker isn't sent a new stop on every tiny tick, the trailing stop
// only moves when it can improve by at least this many ATRs (0.1 = a tenth
// of an ATR). 0 = move on every improvement.
input double TrailingStepATR = 0.1;

input group "=== 5. Risk and safety ==="
// Money risked per trade, in % of the account BALANCE. The lot size comes
// from the stop distance and the symbol's tick value, rounded DOWN to the
// broker's lot step.
input double RiskPercentPerTrade = 0.5;
// If even the broker's smallest lot would risk more than this % of the
// balance, the trade is skipped.
input double MaxRiskPercentAtMinLot = 1.0;
// Daily loss limit, in % of the balance at the start of the (server) day.
// Once today's closed plus open losses reach it, no NEW trades are opened
// until the next day. 0 = off.
input double DailyLossLimitPercent = 2.0;
// Kill switch: if equity falls this % below its highest point, the EA closes
// its trades and stops trading for good, until you reset it. 0 = off.
input double KillSwitchDrawdownPercent = 15.0;
// To reset a triggered kill switch: set this to true and press OK. The EA
// clears the kill switch and restarts the equity peak from today's equity,
// but opens nothing while this is true. Then set it back to false and
// trading resumes. (So it can never be left "reset" by accident.)
input bool ResetKillSwitch = false;
// No new entries while the spread (Ask minus Bid) is wider than this, in
// price units: on gold 0.50 = 50 cents. Market Watch shows the spread in
// "points": with 2-decimal gold prices 50 points = 0.50, with 3-decimal
// prices 500 points = 0.50. 0 = no spread filter.
input double MaxSpreadUSD = 0.50;
// Largest slippage accepted on market orders, in price units. (Only used by
// brokers with "instant execution"; most use market execution and ignore it.)
input double MaxSlippageUSD = 0.50;

input group "=== 6. News filter (high-impact USD events) ==="
// Skip new entries this many minutes before and after high-impact USD news.
input bool UseNewsFilter = true;
input int NewsMinutesBefore = 30;
input int NewsMinutesAfter = 30;
// IMPORTANT: MetaTrader's economic calendar does NOT work in the Strategy
// Tester. In backtests only the times you list below are avoided. In live
// trading the EA uses the calendar AND these lists.
// (a) Type news times here in your broker's SERVER time, format
//     YYYY.MM.DD HH:MM, separated by ";"
//     example: 2024.01.05 15:30; 2024.02.02 15:30
input string ManualNewsTimes = "";
// (b) ...or keep many times in a text file (one per line, same format) in
//     MetaTrader's COMMON Files folder. The helper script
//     GoldBreakout_ExportNews creates this file from the calendar for you.
//     Leave empty to not use a file.
input string NewsTimesFile = "GoldBreakout_news.csv";

input group "=== 7. Random twin mode (for comparison tests) ==="
// true = ignore the trend filter and the breakout signal. Instead, open
// trades at random 1-hour candle closes in a random direction, with EXACTLY
// the same stops, trailing, lot sizing, filters and safety switches.
input bool RandomEntryMode = false;
// Same seed = the same "random" trades every run (repeatable tests).
input int RandomSeed = 12345;
// How many trades per year the random twin should aim for. Use the number
// the EA prints at the end of a normal test over the same dates
// ("...trades per year"). Must be above 0 when RandomEntryMode = true.
input double RandomTradesPerYear = 0;

input group "=== 8. Trade log and identification ==="
// Start of the CSV file name (the file is created in MQL5/Files).
input string CsvFilePrefix = "GoldBreakout";
// A tag number stamped on this EA's trades so it never touches any others.
input long MagicNumber = 20260929;

//====================================================================
//  THE ROBOT'S MEMORY WHILE IT RUNS
//====================================================================
CTrade   g_trade;                        // sends orders to the broker
string   g_symbol          = "";         // the symbol actually traded
bool     g_isTester        = false;      // running in the Strategy Tester?
bool     g_isOptimizing    = false;      // running an optimization (many passes)?
bool     g_showStatus      = false;      // write the status text on the chart?
int      g_digits          = 0;          // decimals in the price
double   g_point           = 0.0;        // price value of one "point"
double   g_tickSize        = 0.0;        // smallest price change allowed
int      g_emaHandle       = INVALID_HANDLE;
int      g_atrHandle       = INVALID_HANDLE;
string   g_gvPrefix        = "";         // name prefix for values saved in the terminal

// Candles and indicator values
datetime g_lastDecisionCandle = 0;       // entry candle we already made a decision for
datetime g_lastAtrCandle      = 0;       // ATR candle the stored ATR belongs to
double   g_atr                = 0.0;     // ATR of the last FINISHED candle
int      g_trendDir           = 0;       // +1 buys allowed, -1 sells allowed, 0 neither
int      g_breakoutDir        = 0;       // +1 upside breakout, -1 downside, 0 none
double   g_trendClose         = 0.0;     // last finished 4-hour close (for the status text)
double   g_trendEma           = 0.0;     // EMA at that candle (for the status text)
bool     g_trendLagWarned     = false;

// The open trade (there is never more than one)
bool     g_hasTrade        = false;
ulong    g_tradeTicket     = 0;
long     g_tradeId         = 0;          // MetaTrader's position ID, used to find its history
int      g_tradeDir        = 0;          // +1 long (buy), -1 short (sell)
double   g_tradeEntry      = 0.0;        // entry price
double   g_tradeRisk       = 0.0;        // distance from entry to the initial stop
double   g_tradeBest       = 0.0;        // best price reached (long: highest Bid, short: lowest Ask)
double   g_tradeStop       = 0.0;        // stop currently set at the broker
int      g_tradeStage      = 0;          // 0 initial stop, 1 break-even, 2 trailing
datetime g_tradeGoneSince  = 0;          // when we noticed it had closed

// Safety switches
double   g_peakEquity      = 0.0;        // highest equity seen
bool     g_killSwitchOn    = false;
long     g_dayNumber       = -1;         // server day we are in
double   g_dayStartBalance = 0.0;        // balance at the start of that day
bool     g_dailyLimitHit   = false;
datetime g_nextFlush       = 0;

// Pauses after a refused request, so errors don't flood the log
datetime g_modifyRetryAfter  = 0;
datetime g_closeRetryAfter   = 0;
datetime g_calendarWarnAfter = 0;

// News times from ManualNewsTimes and the news file, sorted, in server time
long     g_newsTimes[];

// Counters (used by the random twin and the end-of-test summary)
uint     g_rng               = 0;
int      g_decisionCount     = 0;        // finished entry candles evaluated
int      g_eligibleCount     = 0;        // ...when flat and allowed to trade (random mode)
int      g_entryCount        = 0;        // trades opened
datetime g_firstDecisionTime = 0;
datetime g_firstTickTime     = 0;

// CSV trade log
string   g_csvFile           = "";

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

// ---- Repeatable random numbers for the random twin ("Mulberry32").
// The same RandomSeed always produces the same sequence.
uint NextRandom()
{
   g_rng += 0x6D2B79F5;
   uint z = g_rng;
   z = (z ^ (z >> 15)) * (z | 1);
   z ^= z + (z ^ (z >> 7)) * (z | 61);
   return z ^ (z >> 14);
}

// A random number between 0 (included) and 1 (not included).
double Random01()
{
   return NextRandom() / 4294967296.0;
}

//====================================================================
//  CHECKING THE SETTINGS AND THE SYMBOL AT START-UP
//====================================================================

bool ValidateInputs()
{
   string problem = "";
   if(TrendEMAPeriod < 1)
      problem = "TrendEMAPeriod must be 1 or more.";
   else if(BreakoutLookbackCandles < 1)
      problem = "BreakoutLookbackCandles must be 1 or more.";
   else if(ATRPeriod < 1)
      problem = "ATRPeriod must be 1 or more.";
   else if(InitialStopATRMultiplier <= 0.0)
      problem = "InitialStopATRMultiplier must be above 0.";
   else if(BreakEvenTriggerMultiple <= 0.0)
      problem = "BreakEvenTriggerMultiple must be above 0.";
   else if(BreakEvenExtraUSD < 0.0)
      problem = "BreakEvenExtraUSD cannot be negative.";
   else if(TrailingStopATRMultiplier <= 0.0)
      problem = "TrailingStopATRMultiplier must be above 0.";
   else if(TrailingStepATR < 0.0)
      problem = "TrailingStepATR cannot be negative.";
   else if(RiskPercentPerTrade <= 0.0 || RiskPercentPerTrade > 10.0)
      problem = "RiskPercentPerTrade must be above 0 and at most 10.";
   else if(MaxRiskPercentAtMinLot <= 0.0)
      problem = "MaxRiskPercentAtMinLot must be above 0.";
   else if(DailyLossLimitPercent < 0.0 || DailyLossLimitPercent >= 100.0)
      problem = "DailyLossLimitPercent must be between 0 (off) and 100.";
   else if(KillSwitchDrawdownPercent < 0.0 || KillSwitchDrawdownPercent >= 100.0)
      problem = "KillSwitchDrawdownPercent must be between 0 (off) and 100.";
   else if(MaxSpreadUSD < 0.0)
      problem = "MaxSpreadUSD cannot be negative (use 0 to switch the spread filter off).";
   else if(MaxSlippageUSD < 0.0)
      problem = "MaxSlippageUSD cannot be negative.";
   else if(NewsMinutesBefore < 0 || NewsMinutesAfter < 0)
      problem = "NewsMinutesBefore and NewsMinutesAfter cannot be negative.";
   else if(RandomEntryMode && RandomTradesPerYear <= 0.0)
      problem = "RandomEntryMode is on, so RandomTradesPerYear must be above 0. Run a normal test first: "
                "at the end it prints the number of trades per year to use here.";

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

//====================================================================
//  THE CSV TRADE LOG (in MQL5/Files)
//====================================================================

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

string CsvHeader()
{
   return "OpenTime,CloseTime,Direction,EntryPrice,ExitPrice,LotSize,SpreadAtEntry,ProfitMoney,ExitReason,"
          "Mode,Symbol,PositionID,InitialStop";
}

// Create the log file. Tester: a fresh file for every test run.
// Live trading: keep adding to the same file.
void PrepareCsvFile()
{
   g_csvFile = "";
   if(g_isOptimizing || CsvFilePrefix == "")
      return;

   string mode = RandomEntryMode ? "RANDOM-seed" + IntegerToString(RandomSeed) : "REAL";
   g_csvFile = CsvFilePrefix + "_" + SafeFileName(g_symbol) + "_" + mode + (g_isTester ? "_test" : "_live") + ".csv";

   int flags = FILE_TXT | FILE_ANSI | FILE_WRITE | FILE_SHARE_READ;
   if(!g_isTester)
      flags |= FILE_READ;                  // keep what is already in the file
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

// One CSV line. Prices use the symbol's decimals, money uses 2 decimals.
string CsvLine(const datetime openTime, const datetime closeTime, const int dir, const double entryPrice,
               const double exitPrice, const double lots, const double spreadAtEntry, const double money,
               const string reason, const long positionId, const double initialStop)
{
   string direction = "?";
   if(dir > 0)
      direction = "LONG";
   if(dir < 0)
      direction = "SHORT";
   string spreadText = "n/a";
   if(spreadAtEntry >= 0.0)
      spreadText = DoubleToString(spreadAtEntry, g_digits);
   string stopText = "n/a";
   if(initialStop > 0.0)
      stopText = DoubleToString(initialStop, g_digits);
   string mode = RandomEntryMode ? "RANDOM" : "REAL";

   return TimeToString(openTime, TIME_DATE | TIME_SECONDS) + "," +
          TimeToString(closeTime, TIME_DATE | TIME_SECONDS) + "," +
          direction + "," +
          DoubleToString(entryPrice, g_digits) + "," +
          DoubleToString(exitPrice, g_digits) + "," +
          DoubleToString(lots, LotDigits()) + "," +
          spreadText + "," +
          DoubleToString(money, 2) + "," +
          reason + "," +
          mode + "," +
          g_symbol + "," +
          IntegerToString(positionId) + "," +
          stopText;
}

//====================================================================
//  WHICH STOP IS ACTIVE, AND WHY A TRADE ENDED
//====================================================================

// Price of the break-even stop (entry, plus the optional extra).
double BreakEvenPrice(const int dir, const double entry)
{
   return RoundToTick(entry + dir * BreakEvenExtraUSD);
}

// Work out from the stop's position which stage a trade is in:
// 0 = still the initial stop, 1 = at break-even, 2 = trailing beyond it.
int StageFromStop(const int dir, const double entry, const double stop)
{
   if(stop <= 0.0 || dir == 0)
      return 0;
   double breakEven = BreakEvenPrice(dir, entry);
   double tolerance = g_tickSize * 0.5;
   if(dir > 0)
   {
      if(stop > breakEven + tolerance)
         return 2;
      if(stop >= breakEven - tolerance)
         return 1;
   }
   else
   {
      if(stop < breakEven - tolerance)
         return 2;
      if(stop <= breakEven + tolerance)
         return 1;
   }
   return 0;
}

// Turn MetaTrader's technical close reason into plain words for the CSV.
string ExitReasonText(const long dealReason, const string dealComment, const int stage)
{
   if(StringFind(dealComment, "end of test") >= 0)
      return "end of test";
   if(dealReason == DEAL_REASON_SL)
   {
      if(stage == 2)
         return "trailing";
      if(stage == 1)
         return "break-even";
      return "stop";
   }
   if(dealReason == DEAL_REASON_EXPERT)
      return g_killSwitchOn ? "kill switch" : "closed by EA";
   if(dealReason == DEAL_REASON_TP)
      return "take-profit (set by hand)";
   if(dealReason == DEAL_REASON_SO)
      return "margin stop-out";
   if(dealReason == DEAL_REASON_CLIENT || dealReason == DEAL_REASON_MOBILE || dealReason == DEAL_REASON_WEB)
      return "closed by hand";
   return "other";
}

// Gather everything about one finished trade from the account history and
// add it to the CSV. "stage" is the stop stage when it closed (-1 = unknown,
// then it is worked out from the history). Returns false while the closing
// deal is not in the history yet (unless force = true, then it writes
// whatever it has).
bool WriteTradeToCsv(const long positionId, const int stageAtClose, const bool force)
{
   if(positionId <= 0)
      return true;
   if(!HistorySelectByPosition(positionId) && !force)
      return false;

   int      dir = 0;
   double   inVolume = 0.0, inValue = 0.0, outVolume = 0.0, outValue = 0.0, money = 0.0, stopAtExit = 0.0;
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
      // Profit in money = price profit + swap + commission + fees
      money += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) +
               HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
      if(entryType == DEAL_ENTRY_IN)
      {
         inVolume += volume;
         inValue  += volume * price;
         if(openTime == 0 || dealTime < openTime)
            openTime = dealTime;
         if(dir == 0)
            dir = (HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? 1 : -1;
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
            stopAtExit  = HistoryDealGetDouble(deal, DEAL_SL);
         }
      }
   }
   if(outVolume <= 0.0 && !force)
      return false;

   // Details the EA saved itself when it opened the trade.
   string key           = IntegerToString(positionId);
   double spreadAtEntry = GvGet("Spread_" + key, -1.0);
   double initialStop   = GvGet("Stop0_" + key, 0.0);

   double entryPrice = (inVolume > 0.0) ? inValue / inVolume : 0.0;
   double exitPrice  = (outVolume > 0.0) ? outValue / outVolume : 0.0;
   int    stage      = stageAtClose;
   if(stage < 0 && dir != 0)
      stage = StageFromStop(dir, entryPrice, stopAtExit);
   string reason = "unknown (closing deal not found)";
   if(outVolume > 0.0)
      reason = ExitReasonText(dealReason, dealComment, stage);
   if(closeTime == 0)
      closeTime = TimeCurrent();

   AppendCsvLine(CsvLine(openTime, closeTime, dir, entryPrice, exitPrice, inVolume, spreadAtEntry, money,
                         reason, positionId, initialStop));
   LogMsg(StringFormat("Trade closed: %s %s lots, entry %s, exit %s, result %.2f %s, reason: %s",
                       DirText(dir), DoubleToString(inVolume, LotDigits()), DoubleToString(entryPrice, g_digits),
                       DoubleToString(exitPrice, g_digits), money, AccountInfoString(ACCOUNT_CURRENCY), reason));

   GvDelete("Spread_" + key);
   GvDelete("Stop0_" + key);
   GvDelete("Best_" + key);
   return true;
}

// End of a backtest with the trade still open: log it at the last price.
void LogTradeStillOpenAtEnd()
{
   if(!PositionSelectByTicket(g_tradeTicket))
      return;
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return;
   double lots  = PositionGetDouble(POSITION_VOLUME);
   double money = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   // add the commission already charged when the trade was opened
   if(HistorySelectByPosition(g_tradeId))
   {
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal != 0)
            money += HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
      }
   }
   string key = IntegerToString(g_tradeId);
   double exitPrice = (g_tradeDir > 0) ? tick.bid : tick.ask;
   AppendCsvLine(CsvLine((datetime)PositionGetInteger(POSITION_TIME), TimeCurrent(), g_tradeDir, g_tradeEntry,
                         exitPrice, lots, GvGet("Spread_" + key, -1.0), money, "end of test (still open)",
                         g_tradeId, GvGet("Stop0_" + key, 0.0)));
}

//====================================================================
//  KEEPING TRACK OF THE OPEN TRADE
//====================================================================

// Find this EA's open trade on our symbol (0 = none).
ulong FindOurPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;
      return ticket;
   }
   return 0;
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

void ForgetTrade()
{
   g_hasTrade       = false;
   g_tradeTicket    = 0;
   g_tradeId        = 0;
   g_tradeDir       = 0;
   g_tradeEntry     = 0.0;
   g_tradeRisk      = 0.0;
   g_tradeBest      = 0.0;
   g_tradeStop      = 0.0;
   g_tradeStage     = 0;
   g_tradeGoneSince = 0;
}

// Load an open trade into memory: right after opening it, or after
// MetaTrader was restarted while it was open.
void AdoptPosition(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return;
   g_hasTrade       = true;
   g_tradeTicket    = ticket;
   g_tradeId        = PositionGetInteger(POSITION_IDENTIFIER);
   g_tradeDir       = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   g_tradeEntry     = PositionGetDouble(POSITION_PRICE_OPEN);
   g_tradeStop      = PositionGetDouble(POSITION_SL);
   g_tradeGoneSince = 0;
   g_tradeStage     = StageFromStop(g_tradeDir, g_tradeEntry, g_tradeStop);

   string key = IntegerToString(g_tradeId);
   double initialStop = GvGet("Stop0_" + key, 0.0);
   if(initialStop <= 0.0 && g_tradeStage == 0 && g_tradeStop > 0.0)
   {
      initialStop = g_tradeStop;            // not saved: the current stop is still the initial one
      GvSet("Stop0_" + key, initialStop);
   }
   g_tradeRisk = (initialStop > 0.0) ? MathAbs(g_tradeEntry - initialStop) : 0.0;
   g_tradeBest = GvGet("Best_" + key, g_tradeEntry);
}

// Keep the EA's memory in step with the account: pick up our trade if one
// is open, and notice when it has closed (stop hit, closed by hand, kill
// switch) so it gets written to the CSV. "finalCall" = end of the test.
void SyncTrade(const bool finalCall)
{
   ulong found = FindOurPosition();
   if(g_hasTrade && found != g_tradeTicket)
   {
      if(g_tradeGoneSince == 0)
         g_tradeGoneSince = TimeCurrent();
      bool force = finalCall || (TimeCurrent() - g_tradeGoneSince > 60);
      if(!WriteTradeToCsv(g_tradeId, StageFromStop(g_tradeDir, g_tradeEntry, g_tradeStop), force))
         return;                             // history not updated yet: try again on the next tick
      ForgetTrade();
   }
   if(!g_hasTrade && found != 0)
      AdoptPosition(found);
   if(g_hasTrade && PositionSelectByTicket(g_tradeTicket))
      g_tradeStop = PositionGetDouble(POSITION_SL);
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
      if(id <= 0 || (g_hasTrade && id == g_tradeId))
         continue;
      int n = ArraySize(ids);
      ArrayResize(ids, n + 1);
      ids[n] = id;
   }
   for(int k = 0; k < ArraySize(ids); k++)
   {
      if(PositionIsOpen(ids[k]))
         continue;
      WriteTradeToCsv(ids[k], -1, false);
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
   SyncTrade(false);                         // log the closed trade with reason "kill switch"
}

//====================================================================
//  NEWS FILTER
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

//====================================================================
//  READING THE CHARTS (FINISHED CANDLES ONLY)
//====================================================================

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

// Refresh the ATR once per new ATR candle.
void RefreshATR()
{
   datetime candle = iTime(g_symbol, ATRTimeframe, 0);
   if(candle == 0 || candle == g_lastAtrCandle)
      return;
   double value = 0.0;
   if(ReadFinishedCandleValue(g_atrHandle, ATRTimeframe, value) && value > 0.0)
   {
      g_atr           = value;
      g_lastAtrCandle = candle;
   }
}

// Read the trend filter and the breakout levels for the entry candle that
// just finished. Returns false if some chart data is not ready yet (the EA
// then simply tries again on the next tick).
bool ReadSignalData(const datetime entryCandle)
{
   // The ATR must belong to the current candle as well (it sets the stop).
   if(g_atr <= 0.0 || g_lastAtrCandle != iTime(g_symbol, ATRTimeframe, 0))
      return false;

   // The 4-hour chart must have caught up with the new hour, otherwise we
   // could read an out-of-date "last finished" 4-hour candle.
   datetime trendCandle = iTime(g_symbol, TrendTimeframe, 0);
   if(trendCandle == 0)
      return false;
   int trendSeconds = PeriodSeconds(TrendTimeframe);
   bool trendUpToDate = (trendCandle <= entryCandle && (entryCandle - trendCandle) < trendSeconds);
   if(!trendUpToDate && trendSeconds <= 7 * 86400)
   {
      if(TimeCurrent() - entryCandle < 300)
         return false;                       // give it up to 5 minutes, then go on with what we have
      if(!g_trendLagWarned)
      {
         LogMsg("Note: the " + TfName(TrendTimeframe) + " chart was slow to update; using its latest finished candle.");
         g_trendLagWarned = true;
      }
   }

   double ema = 0.0;
   if(!ReadFinishedCandleValue(g_emaHandle, TrendTimeframe, ema) || ema <= 0.0)
      return false;
   double trendClose = iClose(g_symbol, TrendTimeframe, 1);
   if(trendClose <= 0.0)
      return false;

   // Breakout levels: highest high and lowest low of the candles BEFORE the
   // one that just finished (candles 2 ... lookback+1 back).
   int    lookback = BreakoutLookbackCandles;
   double highs[];
   double lows[];
   if(CopyHigh(g_symbol, EntryTimeframe, 2, lookback, highs) != lookback)
      return false;
   if(CopyLow(g_symbol, EntryTimeframe, 2, lookback, lows) != lookback)
      return false;
   double entryClose = iClose(g_symbol, EntryTimeframe, 1);   // close of the candle that just finished
   if(entryClose <= 0.0)
      return false;
   double highest = highs[ArrayMaximum(highs)];
   double lowest  = lows[ArrayMinimum(lows)];

   g_trendClose  = trendClose;
   g_trendEma    = ema;
   g_trendDir    = 0;
   if(trendClose > ema)
      g_trendDir = 1;
   if(trendClose < ema)
      g_trendDir = -1;
   g_breakoutDir = 0;
   if(entryClose > highest)
      g_breakoutDir = 1;
   if(entryClose < lowest)
      g_breakoutDir = -1;
   return true;
}

//====================================================================
//  OPENING A TRADE
//====================================================================

// Everything that must be OK before ANY new trade (real or random).
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
   double spread = tick.ask - tick.bid;
   if(MaxSpreadUSD > 0.0 && spread > MaxSpreadUSD + g_tickSize * 0.01)
   {
      reason = "spread " + DoubleToString(spread, g_digits) + " is wider than MaxSpreadUSD " +
               DoubleToString(MaxSpreadUSD, g_digits);
      return false;
   }
   string news = "";
   if(UseNewsFilter && InNewsBlackout(TimeCurrent(), news))
   {
      reason = "news blackout (" + news + ")";
      return false;
   }
   return true;
}

// Lot size so that hitting the initial stop loses RiskPercentPerTrade % of
// the balance: risk money / (ticks to the stop x value of one tick per lot).
bool CalculateLots(const int dir, const double entry, const double distance, double &lots, string &whyNot)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0)
      tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   double minLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   if(balance <= 0.0 || tickValue <= 0.0 || distance <= 0.0 || minLot <= 0.0)
   {
      whyNot = "could not read the balance, tick value or lot limits";
      return false;
   }

   double lossPerLot = (distance / g_tickSize) * tickValue;    // money lost per 1.00 lot at the stop
   double riskMoney  = balance * RiskPercentPerTrade / 100.0;
   lots = RoundLotsDown(riskMoney / lossPerLot);

   if(lots < minLot)
   {
      double riskAtMinLot = minLot * lossPerLot / balance * 100.0;
      if(riskAtMinLot > MaxRiskPercentAtMinLot)
      {
         whyNot = StringFormat("even the smallest lot (%s) would risk %.2f%% of the balance (limit %.2f%%)",
                               DoubleToString(minLot, LotDigits()), riskAtMinLot, MaxRiskPercentAtMinLot);
         return false;
      }
      lots = minLot;
   }
   if(maxLot > 0.0 && lots > maxLot)
      lots = RoundLotsDown(maxLot);

   // Enough free margin? If not, trade smaller (which also means less risk).
   double margin = 0.0;
   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(OrderCalcMargin(type, g_symbol, lots, entry, margin) && margin > 0.0)
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin * 0.95)
      {
         double affordable = RoundLotsDown(lots * freeMargin * 0.95 / margin);
         if(affordable < minLot)
         {
            whyNot = "not enough free margin";
            return false;
         }
         lots = affordable;
      }
   }
   return true;
}

// Is a stop at this price far enough from the current price for the broker?
bool StopIsAllowed(const int dir, const double stop, const MqlTick &tick)
{
   double minDistance = (double)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point + g_tickSize * 0.5;
   if(dir > 0)
      return (tick.bid - stop >= minDistance);
   return (stop - tick.ask >= minDistance);
}

// Change the stop of the open trade at the broker.
bool SetStop(const double newStop, const double takeProfit, const string why)
{
   if(!g_trade.PositionModify(g_tradeTicket, newStop, takeProfit) || !RequestSucceeded(g_trade.ResultRetcode()))
   {
      LogMsg("Could not move the stop to " + DoubleToString(newStop, g_digits) + " (" + why + "): " +
             g_trade.ResultRetcodeDescription() + ". Trying again in a few seconds.");
      g_modifyRetryAfter = TimeCurrent() + 10;
      return false;
   }
   g_tradeStop = newStop;
   if(!g_isTester || why != "trailing")      // the tester log would fill up with trailing moves
      LogMsg("Stop moved to " + DoubleToString(newStop, g_digits) + " (" + why + ").");
   return true;
}

// Open a trade in direction dir (+1 buy, -1 sell) with its initial stop.
bool OpenTrade(const int dir, const MqlTick &tick)
{
   if(g_atr <= 0.0)
      return false;
   double spread = tick.ask - tick.bid;
   double entry  = (dir > 0) ? tick.ask : tick.bid;           // buys fill at the Ask, sells at the Bid

   // Initial stop: InitialStopATRMultiplier x ATR from the entry price (but
   // never closer than the broker's minimum distance).
   double distance = InitialStopATRMultiplier * g_atr;
   double brokerMinimum = (double)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point + spread + g_tickSize;
   if(distance < brokerMinimum)
      distance = brokerMinimum;
   double stop = (dir > 0) ? RoundDownToTick(entry - distance) : RoundUpToTick(entry + distance);
   distance = MathAbs(entry - stop);

   double lots   = 0.0;
   string whyNot = "";
   if(!CalculateLots(dir, entry, distance, lots, whyNot))
   {
      LogMsg(DirText(dir) + " skipped: " + whyNot + ".");
      return false;
   }

   string comment = RandomEntryMode ? "GBO random" : "GBO breakout";
   bool   sent    = (dir > 0) ? g_trade.Buy(lots, g_symbol, entry, stop, 0.0, comment)
                              : g_trade.Sell(lots, g_symbol, entry, stop, 0.0, comment);
   uint   retcode = g_trade.ResultRetcode();
   if(!sent || !RequestSucceeded(retcode))
   {
      LogMsg(DirText(dir) + " order failed: " + g_trade.ResultRetcodeDescription() + " (code " +
             IntegerToString(retcode) + ").");
      return false;
   }
   g_entryCount++;

   // Save the details MetaTrader does not keep for us. The trade's position
   // ID is the ticket number of the order that opened it.
   string key = IntegerToString((long)g_trade.ResultOrder());
   GvSet("Spread_" + key, spread);
   GvSet("Stop0_" + key, stop);
   GvSet("Best_" + key, entry);

   // Load the new trade and, if the fill price slipped, move the stop so it
   // is exactly the planned distance from the real entry price.
   ulong ticket = FindOurPosition();
   if(ticket != 0)
   {
      AdoptPosition(ticket);
      double wanted = (g_tradeDir > 0) ? RoundDownToTick(g_tradeEntry - distance) : RoundUpToTick(g_tradeEntry + distance);
      if(MathAbs(wanted - g_tradeStop) >= g_tickSize * 0.5 && StopIsAllowed(g_tradeDir, wanted, tick) &&
         PositionSelectByTicket(g_tradeTicket) &&
         SetStop(wanted, PositionGetDouble(POSITION_TP), "initial stop adjusted to the real fill price"))
      {
         GvSet("Stop0_" + IntegerToString(g_tradeId), wanted);
         g_tradeRisk = distance;
      }
   }

   LogMsg(StringFormat("%s opened (%s): %s lots at %s, stop %s (%.1f x ATR %s), spread %s",
                       DirText(dir), RandomEntryMode ? "random twin" : "breakout", DoubleToString(lots, LotDigits()),
                       DoubleToString(g_hasTrade ? g_tradeEntry : entry, g_digits),
                       DoubleToString(g_hasTrade ? g_tradeStop : stop, g_digits), InitialStopATRMultiplier,
                       DoubleToString(g_atr, g_digits), DoubleToString(spread, g_digits)));
   return true;
}

// Random twin: the chance of entering on this candle. It is tuned so that,
// on average, the twin opens RandomTradesPerYear trades a year even though
// it cannot enter while already in a trade (or while a filter blocks).
double RandomEntryChance()
{
   double candlesPerYear = 52.0 * 5.0 * 23.0 * 3600.0 / PeriodSeconds(EntryTimeframe);   // first guess
   double yearsSoFar     = (double)(TimeCurrent() - g_firstDecisionTime) / SECONDS_PER_YEAR;
   if(g_firstDecisionTime > 0 && yearsSoFar > 30.0 / 365.25)
      candlesPerYear = g_decisionCount / yearsSoFar;                                      // measured
   double candlesPerTrade = candlesPerYear / RandomTradesPerYear;
   // average number of candles per trade on which it could NOT enter
   double busyPerTrade = (double)(g_decisionCount - g_eligibleCount) / MathMax((double)g_entryCount, 1.0);
   double waitCandles  = MathMax(candlesPerTrade - busyPerTrade, 1.0);
   return 1.0 / waitCandles;
}

// Decide whether to open a trade now that an entry candle has finished.
void ConsiderEntry(const MqlTick &tick)
{
   if(g_hasTrade)
      return;                                // one trade at a time, never add to it

   int dir = 0;
   if(!RandomEntryMode)
   {
      // REAL strategy: breakout in the direction the 4-hour trend allows.
      if(g_trendDir > 0 && g_breakoutDir > 0)
         dir = 1;
      if(g_trendDir < 0 && g_breakoutDir < 0)
         dir = -1;
      if(dir == 0)
         return;                             // no signal on this candle
   }

   string reason = "";
   if(!EntriesAllowed(tick, reason))
   {
      if(!RandomEntryMode)
         LogMsg(DirText(dir) + " signal skipped: " + reason + ".");
      return;
   }

   if(RandomEntryMode)
   {
      // RANDOM twin: enter by chance, in a random direction.
      g_eligibleCount++;
      if(Random01() >= RandomEntryChance())
         return;
      dir = (Random01() < 0.5) ? 1 : -1;
   }
   OpenTrade(dir, tick);
}

// Once per finished entry candle: read the charts and consider an entry.
void CheckFinishedEntryCandle(const MqlTick &tick)
{
   datetime candle = iTime(g_symbol, EntryTimeframe, 0);      // the NEW candle that just started
   if(candle == 0 || candle == g_lastDecisionCandle)
      return;
   if(!ReadSignalData(candle))
      return;                                // data not ready yet: try again on the next tick
   g_lastDecisionCandle = candle;
   g_decisionCount++;
   if(g_firstDecisionTime == 0)
      g_firstDecisionTime = candle;
   ConsiderEntry(tick);
}

//====================================================================
//  MANAGING THE OPEN TRADE: BREAK-EVEN AND TRAILING STOP
//====================================================================

bool IsImprovement(const double newStop, const double oldStop)
{
   if(oldStop <= 0.0)
      return true;
   if(g_tradeDir > 0)
      return (newStop > oldStop + g_tickSize * 0.5);
   return (newStop < oldStop - g_tickSize * 0.5);
}

// Is the new stop better than the old one by at least "step"?
bool ImprovesBy(const double newStop, const double oldStop, const double step)
{
   if(g_tradeDir > 0)
      return (newStop >= oldStop + step);
   return (newStop <= oldStop - step);
}

// The tightest stop the broker accepts right now (just beyond its minimum
// distance from the current price).
double ClosestAllowedStop(const MqlTick &tick)
{
   double minDistance = (double)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point + g_tickSize;
   if(g_tradeDir > 0)
      return RoundDownToTick(tick.bid - minDistance);
   return RoundUpToTick(tick.ask + minDistance);
}

// Safety net: if the trade has no stop at all (e.g. removed by hand), put
// the initial stop back. If the price is already past it, close the trade.
void PlaceMissingStop(const MqlTick &tick, const double takeProfit)
{
   if(g_atr <= 0.0)
      return;
   double distance = (g_tradeRisk > 0.0) ? g_tradeRisk : InitialStopATRMultiplier * g_atr;
   double stop = (g_tradeDir > 0) ? RoundDownToTick(g_tradeEntry - distance) : RoundUpToTick(g_tradeEntry + distance);
   if(StopIsAllowed(g_tradeDir, stop, tick))
   {
      if(SetStop(stop, takeProfit, "initial stop restored"))
      {
         g_tradeRisk  = distance;
         g_tradeStage = 0;
      }
      return;
   }
   LogMsg("The trade had no stop and the price is already beyond where it should be: closing it.");
   if(!g_trade.PositionClose(g_tradeTicket) || !RequestSucceeded(g_trade.ResultRetcode()))
      g_modifyRetryAfter = TimeCurrent() + 10;
}

void ManageOpenTrade(const MqlTick &tick)
{
   if(!PositionSelectByTicket(g_tradeTicket))
      return;
   double stop       = PositionGetDouble(POSITION_SL);
   double takeProfit = PositionGetDouble(POSITION_TP);   // normally none; kept if you set one by hand
   g_tradeStop = stop;

   // (a) Remember the best price reached. A long is closed at the Bid, a
   //     short at the Ask, so those are the prices that count.
   double closePrice = (g_tradeDir > 0) ? tick.bid : tick.ask;
   bool   newBest    = (g_tradeBest <= 0.0) || (g_tradeDir > 0 && closePrice > g_tradeBest) ||
                       (g_tradeDir < 0 && closePrice < g_tradeBest);
   if(newBest)
   {
      g_tradeBest = closePrice;
      if(!g_isTester)
         GvSet("Best_" + IntegerToString(g_tradeId), g_tradeBest);
   }

   if(TimeCurrent() < g_modifyRetryAfter)
      return;                                // pause after a refused change

   // (b) No stop at all? Put it back first.
   if(stop <= 0.0)
   {
      PlaceMissingStop(tick, takeProfit);
      return;
   }

   // (c) Break-even: once the profit reaches BreakEvenTriggerMultiple x the
   //     initial stop distance, move the stop to the entry price.
   if(g_tradeStage == 0 && g_tradeRisk > 0.0)
   {
      double profit = (g_tradeDir > 0) ? (g_tradeBest - g_tradeEntry) : (g_tradeEntry - g_tradeBest);
      // (the tiny allowance stops computer rounding from missing an exact hit)
      if(profit >= BreakEvenTriggerMultiple * g_tradeRisk - g_tickSize * 0.001)
      {
         double breakEven = BreakEvenPrice(g_tradeDir, g_tradeEntry);
         if(!IsImprovement(breakEven, stop))
            g_tradeStage = StageFromStop(g_tradeDir, g_tradeEntry, stop);   // already there (moved by hand)
         else if(StopIsAllowed(g_tradeDir, breakEven, tick) && SetStop(breakEven, takeProfit, "break-even"))
         {
            stop         = breakEven;
            g_tradeStage = 1;
         }
      }
   }

   // (d) Trailing: after break-even, keep the stop TrailingStopATRMultiplier
   //     x ATR behind the best price. It only ever moves forward.
   if(g_tradeStage >= 1 && g_atr > 0.0)
   {
      double trail = (g_tradeDir > 0) ? RoundDownToTick(g_tradeBest - TrailingStopATRMultiplier * g_atr)
                                      : RoundUpToTick(g_tradeBest + TrailingStopATRMultiplier * g_atr);
      double minStep = MathMax(TrailingStepATR * g_atr, g_tickSize) - g_tickSize * 0.01;
      if(ImprovesBy(trail, stop, minStep))
      {
         // Right after a new candle the ATR can shrink so much that the new
         // trailing level is already past the current price. The broker won't
         // accept a stop there, so it goes as close as the broker allows.
         if(!StopIsAllowed(g_tradeDir, trail, tick))
            trail = ClosestAllowedStop(tick);
         if(ImprovesBy(trail, stop, minStep) && SetStop(trail, takeProfit, "trailing"))
            g_tradeStage = 2;
      }
   }
}

//====================================================================
//  STATUS TEXT ON THE CHART AND END-OF-TEST SUMMARY
//====================================================================

string StatusText()
{
   if(g_killSwitchOn)
      return "KILL SWITCH ACTIVE - trading stopped (see ResetKillSwitch)";
   if(ResetKillSwitch)
      return "Kill switch was reset - set ResetKillSwitch = false to resume trading";
   if(g_dailyLimitHit)
      return "Daily loss limit reached - no new trades until tomorrow";
   if(g_hasTrade)
      return "In a trade";
   return "Waiting for a signal";
}

void ShowStatus(const MqlTick &tick)
{
   if(!g_showStatus)
      return;
   static uint lastDraw = 0;
   uint nowMs = GetTickCount();
   if(nowMs - lastDraw < 1000)
      return;                                // redraw at most once a second
   lastDraw = nowMs;

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = (g_peakEquity > 0.0) ? (1.0 - equity / g_peakEquity) * 100.0 : 0.0;
   string trend    = "not known yet";
   if(g_trendDir > 0)
      trend = "LONGS allowed";
   if(g_trendDir < 0)
      trend = "SHORTS allowed";
   if(g_trendDir == 0 && g_trendEma > 0.0)
      trend = "none (close equals EMA)";

   string text = EA_NAME;
   text += "  |  " + g_symbol + "  |  " + (RandomEntryMode ? "RANDOM TWIN mode" : "REAL strategy") + "\n";
   text += "Status: " + StatusText() + "\n";
   text += "Direction (" + TfName(TrendTimeframe) + " close vs EMA " + IntegerToString(TrendEMAPeriod) + "): " + trend + "\n";
   text += StringFormat("Equity %.2f  |  peak %.2f  |  down %.1f%% from peak (kill switch at %.1f%%)\n",
                        equity, g_peakEquity, drawdown, KillSwitchDrawdownPercent);
   text += StringFormat("Day start balance %.2f  |  daily loss limit %.1f%%\n", g_dayStartBalance, DailyLossLimitPercent);
   text += "Spread " + DoubleToString(tick.ask - tick.bid, g_digits) + " (max " + DoubleToString(MaxSpreadUSD, g_digits) +
           ")  |  ATR " + DoubleToString(g_atr, g_digits) + "\n";
   if(g_hasTrade)
   {
      string stage = "initial stop";
      if(g_tradeStage == 1)
         stage = "break-even";
      if(g_tradeStage == 2)
         stage = "trailing";
      text += "Trade: " + DirText(g_tradeDir) + " from " + DoubleToString(g_tradeEntry, g_digits) + "  |  stop " +
              DoubleToString(g_tradeStop, g_digits) + " (" + stage + ")  |  best " + DoubleToString(g_tradeBest, g_digits) + "\n";
   }
   Comment(text);
}

// End of a backtest: how many trades per year (needed for the random twin).
void PrintFrequencyReport()
{
   if(g_isOptimizing)
      return;
   datetime start = (g_firstTickTime > 0) ? g_firstTickTime : g_firstDecisionTime;
   if(start == 0)
      return;
   double years = (double)(TimeCurrent() - start) / SECONDS_PER_YEAR;
   if(years <= 0.0)
      return;
   double perYear = g_entryCount / years;
   Print(StringFormat("Test summary: %d trades opened in %.2f years = %.1f trades per year.", g_entryCount, years, perYear));
   if(!RandomEntryMode)
      Print(StringFormat("For the random twin over the same dates use: RandomEntryMode = true, RandomTradesPerYear = %.1f",
                         perYear));
   else
      Print(StringFormat("Random twin: aimed for %.1f trades per year, made %.1f.", RandomTradesPerYear, perYear));
}

void PrintStartupSummary()
{
   string mode = RandomEntryMode ? "RANDOM TWIN (seed " + IntegerToString(RandomSeed) + ")" : "REAL strategy";
   LogMsg(StringFormat("%s started on %s | %s | risk %.2f%% | stop %.1f x ATR(%d, %s) | break-even at %.1f x risk | "
                       "trailing %.1f x ATR | trend EMA %d on %s | breakout %d candles on %s",
                       EA_NAME, g_symbol, mode, RiskPercentPerTrade, InitialStopATRMultiplier, ATRPeriod,
                       TfName(ATRTimeframe), BreakEvenTriggerMultiple, TrailingStopATRMultiplier, TrendEMAPeriod,
                       TfName(TrendTimeframe), BreakoutLookbackCandles, TfName(EntryTimeframe)));
}

//====================================================================
//  METATRADER EVENTS
//  OnInit   - once, when the EA starts
//  OnTick   - every time the price changes
//  OnTrade  - whenever something happens to orders or trades
//  OnDeinit - once, when the EA stops (or a backtest ends)
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

   g_emaHandle = iMA(g_symbol, TrendTimeframe, TrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_atrHandle = iATR(g_symbol, ATRTimeframe, ATRPeriod);
   if(g_emaHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE)
   {
      WarnMsg("Could not create the EMA / ATR indicators.");
      return INIT_FAILED;
   }

   g_gvPrefix = "GBO_" + IntegerToString(MagicNumber) + "_";
   if(g_isTester)
      GlobalVariablesDeleteAll(g_gvPrefix);  // every backtest starts from a clean slate

   g_rng = (uint)RandomSeed;
   LoadSafetyState();
   LoadNewsTimes();
   PrepareCsvFile();

   // Don't act on an old signal if the EA is attached in the middle of a candle.
   // (MetaTrader keeps the EA's memory when you only change a setting, so the
   // stored ATR is cleared too; it is read again on the next price tick.)
   g_lastDecisionCandle = iTime(g_symbol, EntryTimeframe, 0);
   g_atr                = 0.0;
   g_lastAtrCandle      = 0;

   SyncTrade(false);                         // pick up a trade that is already open (after a restart)
   if(!g_isTester)
      LogTradesClosedWhileOffline();

   if(RandomEntryMode && !g_isTester)
      WarnMsg("RandomEntryMode is ON: this mode is meant for backtests, not for real money.");
   PrintStartupSummary();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_isTester)
   {
      SyncTrade(true);                       // log a trade the tester has just closed...
      if(g_hasTrade)
         LogTradeStillOpenAtEnd();           // ...or one that is still open at the end
      PrintFrequencyReport();
   }
   if(g_emaHandle != INVALID_HANDLE)
      IndicatorRelease(g_emaHandle);
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
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

   SyncTrade(false);                         // 1. did our trade close? -> CSV
   UpdateSafetySwitches();                   // 2. daily loss limit, equity peak, kill switch
   if(g_killSwitchOn)
   {
      CloseEverythingForKillSwitch();        //    kill switch: close everything and do nothing else
      ShowStatus(tick);
      return;
   }
   RefreshATR();                             // 3. ATR of the last finished candle
   if(g_hasTrade)
      ManageOpenTrade(tick);                 // 4. break-even and trailing stop
   CheckFinishedEntryCandle(tick);           // 5. a 1-hour candle just finished? -> look for an entry
   ShowStatus(tick);
}

void OnTrade()
{
   SyncTrade(false);
}
//+------------------------------------------------------------------+
