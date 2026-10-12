//+------------------------------------------------------------------+
//|                                             GoldTrendStacker.mq5 |
//|     Gold (XAUUSD) trend robot: 1-hour breakouts in the 4-hour    |
//|     trend, several trades stacked into a trend that works.       |
//+------------------------------------------------------------------+
//
//  HOW TO READ THIS FILE
//  ---------------------
//  Lines that start with // are notes for people. MetaTrader ignores
//  them. Everything else is the program itself.
//
//  WHY THIS ROBOT EXISTS
//  ---------------------
//  Tested on real gold prices from 2012 to mid-2018 (Dukascopy ticks), the
//  1-minute scalping ideas (fair value gaps, small breaks, pullbacks, with a
//  fixed small take-profit) lost money in every version: at a few dollars
//  of movement gold is close to a coin flip, and the spread decides. What
//  DID make money in both halves of the data is trend following on the
//  1-hour chart: buy breakouts while the 4-hour trend is up, let winners
//  run with a trailing stop. This robot takes that edge and trades it
//  more often by STACKING: every new breakout in a working trend adds a
//  trade, up to 4 at once.
//
//  WHAT THE ROBOT DOES
//  -------------------
//  1. DIRECTION: the last finished 4-hour candle closed above its EMA 100
//     -> only buys. Below -> only sells.
//  2. ENTRY: a 1-hour candle CLOSES above the highest high of the 20
//     candles before it (buys) or below the lowest low (sells), in the
//     direction above. Only finished candles count.
//  3. STACKING: while trades in that direction are open, every new
//     breakout adds one more trade (at most 4 open at once), but ONLY when
//     every trade already open has its stop at break-even or better. So at
//     any moment at most ONE trade can still lose money; the others are
//     protected.
//  4. EXITS (each trade on its own): first stop 2 x ATR(14, 1 hour) from
//     the entry. When the trade is 1 x that distance in profit, the stop
//     moves to the entry price (break-even). After that the stop follows
//     the best price at 4 x ATR and never moves back. No fixed take-profit:
//     winners can run as far as the trend goes.
//  5. A breakout the other way closes the trades of the old direction.
//  6. SIZE: each trade risks 0.4% of the balance at its first stop (lots
//     from the tick value, rounded down). If even the smallest lot would
//     risk more than 1%, the trade is skipped.
//  7. SAFETY: no new trades after a 2% losing day (until the next day), a
//     kill switch that closes everything and stops for good if equity
//     falls 15% below its highest point, and no new entries while the
//     spread is too wide or around high-impact USD news.
//  8. LOG: every closed trade becomes one line in a CSV file (MQL5/Files).
//
//  Every number above is a setting ("input") in the EA's Inputs tab.
//
//  IMPORTANT: it needs a "hedging" account, because it holds several
//  trades at once. Demo accounts opened with "Use hedge in trading"
//  ticked are hedging accounts.
//+------------------------------------------------------------------+
#property version     "1.00"
#property description "Gold trend robot: 1-hour breakouts in the direction of the 4-hour EMA 100, up to 4 stacked trades."
#property description "A trade is added only when all open trades are protected at break-even. ATR stops, break-even, trailing."
#property description "0.4% risk per trade, daily loss limit, equity kill switch, spread and news filters, CSV trade log."

// MetaTrader's standard helper for sending orders (comes with every MT5).
#include <Trade\Trade.mqh>

#define EA_NAME   "GoldTrendStacker"

//====================================================================
//  SETTINGS ("INPUTS")
//====================================================================

input group "=== 1. Symbol ==="
// The exact name of gold at your broker, as shown in Market Watch. A chart
// whose name STARTS with it (e.g. XAUUSDm) is accepted too.
input string TradeSymbol = "XAUUSD";

input group "=== 2. Direction (4-hour trend) ==="
// Buys only while the last finished candle of this chart closed above its
// EMA, sells only while it closed below.
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_H4;
input int TrendEMAPeriod = 100;

input group "=== 3. Entries (1-hour breakouts, stacked) ==="
input ENUM_TIMEFRAMES EntryTimeframe = PERIOD_H1;
// A breakout = a candle closing beyond the highest high / lowest low of
// this many candles before it.
input int BreakoutLookbackCandles = 20;
// Most trades open at the same time.
input int MaxOpenTrades = 4;
// true = add a trade only when every open trade is already at break-even
// or better (at most one trade can lose at any moment). false = add on
// every breakout (more trades, more risk).
input bool StackOnlyWhenProtected = true;
// A breakout in the other direction closes the trades of the old direction.
input bool CloseOnOppositeBreakout = true;

input group "=== 4. Exits (each trade on its own) ==="
input ENUM_TIMEFRAMES ATRTimeframe = PERIOD_H1;
input int ATRPeriod = 14;
// First stop: this many ATRs from the entry.
input double InitialStopATRMultiplier = 2.0;
// Move the stop to the entry price once the profit is this many times the
// first stop distance (1.0 = "1R").
input double BreakEvenTriggerMultiple = 1.0;
// After break-even the stop follows the best price at this many ATRs.
input double TrailingStopATRMultiplier = 4.0;
// Move the trailing stop only in steps of at least this many ATRs (fewer
// changes sent to the broker).
input double TrailingStepATR = 0.1;

input group "=== 5. Risk and safety ==="
// Money risked per trade at its first stop, % of the balance.
input double RiskPercentPerTrade = 0.4;
// If even the smallest lot would risk more than this %, skip the trade.
input double MaxRiskPercentAtMinLot = 1.0;
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
input string CsvFilePrefix = "GoldTrendStacker";
// Tag on this EA's trades so it never touches any others.
input long MagicNumber = 20261012;

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

// Direction, breakout and ATR
int      g_emaHandle     = INVALID_HANDLE;
int      g_atrHandle     = INVALID_HANDLE;
double   g_atr           = 0.0;
datetime g_lastAtrCandle = 0;
int      g_trendDir      = 0;            // +1 buys only, -1 sells only
double   g_trendClose    = 0.0;
double   g_trendEma      = 0.0;
int      g_breakoutDir   = 0;            // breakout of the candle that just finished
datetime g_lastDecisionCandle = 0;
bool     g_trendLagWarned = false;
long     g_trendClosedIds[];             // trades closed by an opposite breakout
int      g_tradesOpened  = 0;
int      g_tradesStacked = 0;
int      g_signals       = 0;

// The open trades this EA manages (one entry per trade)
struct Managed
{
   long     id;                          // position identifier
   ulong    ticket;
   int      dir;                         // +1 buy, -1 sell
   double   entry;                       // open price
   double   risk;                        // first stop distance in price
   double   best;                        // best price so far (buy: highest Bid, sell: lowest Ask)
   int      stage;                       // 0 first stop, 1 break-even, 2 trailing
   datetime retryAfter;                  // pause after the broker refused a change
};
Managed  g_managed[];

// News (checked once per candle)
bool     g_newsBlocked      = false;
string   g_newsWhat         = "";
long     g_newsTimes[];
datetime g_calendarWarnAfter = 0;
datetime g_lastNewsCheck    = 0;

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

// Short names of the entry kinds (CSV).
string KindName(const int kind)
{
   if(kind == 1)
      return "breakout";
   if(kind == 2)
      return "stacked";
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

bool ValidateInputs()
{
   string problem = "";
   if(TrendEMAPeriod < 1)
      problem = "TrendEMAPeriod must be 1 or more.";
   else if(BreakoutLookbackCandles < 1)
      problem = "BreakoutLookbackCandles must be 1 or more.";
   else if(MaxOpenTrades < 1 || MaxOpenTrades > 20)
      problem = "MaxOpenTrades must be between 1 and 20.";
   else if(ATRPeriod < 1)
      problem = "ATRPeriod must be 1 or more.";
   else if(InitialStopATRMultiplier <= 0.0 || TrailingStopATRMultiplier <= 0.0)
      problem = "InitialStopATRMultiplier and TrailingStopATRMultiplier must be above 0.";
   else if(BreakEvenTriggerMultiple <= 0.0)
      problem = "BreakEvenTriggerMultiple must be above 0.";
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
   if(dealReason == DEAL_REASON_SL && StringFind(reason, "end of test") < 0)
   {
      int stage = (int)GvGet("Stage_" + key, 0.0);
      reason = (stage >= 2) ? "trailing stop" : ((stage == 1) ? "break-even stop" : "first stop");
   }
   for(int t = ArraySize(g_trendClosedIds) - 1; t >= 0; t--)
   {
      if(g_trendClosedIds[t] != positionId)
         continue;
      if(dealReason == DEAL_REASON_EXPERT)
         reason = "opposite breakout";
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
   GvDelete("Stop0_" + key);
   GvDelete("Best_" + key);
   GvDelete("Stage_" + key);
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
//  DIRECTION AND BREAKOUT (once per finished 1-hour candle)
//====================================================================

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

// Read the 4-hour trend and the breakout of the entry candle that just
// finished. Returns false if some chart data is not ready yet (the EA then
// simply tries again on the next tick).
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
   int  trendSeconds  = PeriodSeconds(TrendTimeframe);
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

   g_trendClose = trendClose;
   g_trendEma   = ema;
   g_trendDir   = 0;
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
//  THE TRADES THIS EA MANAGES
//====================================================================

// Price of the break-even stop (the entry price).
double BreakEvenPrice(const int dir, const double entry)
{
   return RoundToTick(entry);
}

// Work out from the stop's position which stage a trade is in:
// 0 = still the first stop, 1 = at break-even, 2 = trailing beyond it.
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

int FindManaged(const long id)
{
   for(int i = 0; i < ArraySize(g_managed); i++)
   {
      if(g_managed[i].id == id)
         return i;
   }
   return -1;
}

void SetStage(const int index, const int stage)
{
   if(g_managed[index].stage == stage)
      return;
   g_managed[index].stage = stage;
   GvSet("Stage_" + IntegerToString(g_managed[index].id), stage);
}

// Bring the list of managed trades in line with the open positions: forget
// closed ones, adopt new ones (also after a restart of MetaTrader).
void RefreshManaged()
{
   for(int i = ArraySize(g_managed) - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(g_managed[i].ticket))
         continue;
      int last = ArraySize(g_managed) - 1;
      g_managed[i] = g_managed[last];
      ArrayResize(g_managed, last);
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;
      long id = PositionGetInteger(POSITION_IDENTIFIER);
      if(FindManaged(id) >= 0)
         continue;
      Managed m;
      m.id         = id;
      m.ticket     = ticket;
      m.dir        = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      m.entry      = PositionGetDouble(POSITION_PRICE_OPEN);
      double stop  = PositionGetDouble(POSITION_SL);
      string key   = IntegerToString(id);
      double stop0 = GvGet("Stop0_" + key, stop);
      m.risk       = (stop0 > 0.0) ? MathAbs(m.entry - stop0) : 0.0;
      m.best       = GvGet("Best_" + key, m.entry);
      m.stage      = StageFromStop(m.dir, m.entry, stop);
      m.retryAfter = 0;
      int n = ArraySize(g_managed);
      ArrayResize(g_managed, n + 1);
      g_managed[n] = m;
   }
}

// How many managed trades point in direction dir, and how many of them still
// have their first stop (not protected yet).
int CountManaged(const int dir, int &unprotected)
{
   int count = 0;
   unprotected = 0;
   for(int i = 0; i < ArraySize(g_managed); i++)
   {
      if(g_managed[i].dir != dir)
         continue;
      count++;
      if(g_managed[i].stage == 0)
         unprotected++;
   }
   return count;
}

//====================================================================
//  OPENING TRADES
//====================================================================

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

// Lot size so that the first stop loses RiskPercentPerTrade % of the balance.
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

// Open one trade in direction dir with its first stop. stacked = it joins
// trades already open in the same direction.
bool OpenTrade(const int dir, const bool stacked, const MqlTick &tick)
{
   if(g_atr <= 0.0)
      return false;
   double spread = tick.ask - tick.bid;
   double entry  = (dir > 0) ? tick.ask : tick.bid;           // buys fill at the Ask, sells at the Bid
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
   string comment = stacked ? "GTS stacked" : "GTS breakout";
   bool   sent    = (dir > 0) ? g_trade.Buy(lots, g_symbol, entry, stop, 0.0, comment)
                              : g_trade.Sell(lots, g_symbol, entry, stop, 0.0, comment);
   uint   retcode = g_trade.ResultRetcode();
   if(!sent || !RequestSucceeded(retcode))
   {
      LogMsg(DirText(dir) + " order failed: " + g_trade.ResultRetcodeDescription() + " (code " +
             IntegerToString(retcode) + ").");
      return false;
   }
   g_tradesOpened++;
   if(stacked)
      g_tradesStacked++;
   // Save the details MetaTrader does not keep for us. The trade's position
   // ID is the ticket number of the order that opened it.
   string key = IntegerToString((long)g_trade.ResultOrder());
   GvSet("Spread_" + key, spread);
   GvSet("Stop0_" + key, stop);
   GvSet("Kind_" + key, stacked ? 2 : 1);
   GvSet("Stage_" + key, 0);
   SyncPositions(false);
   RefreshManaged();

   // If the fill price slipped, move the stop so it is exactly the planned
   // distance from the real entry price.
   int index = FindManaged((long)g_trade.ResultOrder());
   if(index >= 0)
   {
      Managed m = g_managed[index];
      double wanted = (m.dir > 0) ? RoundDownToTick(m.entry - distance) : RoundUpToTick(m.entry + distance);
      if(PositionSelectByTicket(m.ticket) && MathAbs(wanted - PositionGetDouble(POSITION_SL)) >= g_tickSize * 0.5 &&
         StopIsAllowed(m.dir, wanted, tick) && g_trade.PositionModify(m.ticket, wanted, PositionGetDouble(POSITION_TP)) &&
         RequestSucceeded(g_trade.ResultRetcode()))
         GvSet("Stop0_" + key, wanted);
      g_managed[index].risk = distance;
   }
   if(!g_isTester)
      LogMsg(StringFormat("%s opened (%s): %s lots at %s, stop %s (%.1f x ATR %s), spread %s", DirText(dir),
                          stacked ? "stacked" : "breakout", DoubleToString(lots, LotDigits()), DoubleToString(entry, g_digits),
                          DoubleToString(stop, g_digits), InitialStopATRMultiplier, DoubleToString(g_atr, g_digits),
                          DoubleToString(spread, g_digits)));
   return true;
}

// Close this EA's trades that point in direction dir.
void CloseTradesInDirection(const int dir)
{
   for(int i = ArraySize(g_managed) - 1; i >= 0; i--)
   {
      if(g_managed[i].dir != dir)
         continue;
      long id = g_managed[i].id;
      if(g_trade.PositionClose(g_managed[i].ticket) && RequestSucceeded(g_trade.ResultRetcode()))
      {
         int n = ArraySize(g_trendClosedIds);
         ArrayResize(g_trendClosedIds, n + 1);
         g_trendClosedIds[n] = id;
      }
      else
         LogMsg("Could not close a trade after an opposite breakout (" + g_trade.ResultRetcodeDescription() + ").");
   }
   SyncPositions(false);
   RefreshManaged();
}

// Decide whether to open a trade now that an entry candle has finished.
void ConsiderEntry(const MqlTick &tick)
{
   int dir = 0;
   if(g_trendDir > 0 && g_breakoutDir > 0)
      dir = 1;
   if(g_trendDir < 0 && g_breakoutDir < 0)
      dir = -1;
   if(dir == 0)
      return;                                // no signal on this candle
   g_signals++;
   int unprotectedAgainst = 0;
   if(CloseOnOppositeBreakout && CountManaged(-dir, unprotectedAgainst) > 0)
      CloseTradesInDirection(-dir);
   int unprotected = 0;
   int same = CountManaged(dir, unprotected);
   if(ArraySize(g_managed) >= MaxOpenTrades)
      return;                                // already the most trades allowed
   if(same > 0 && StackOnlyWhenProtected && unprotected > 0)
      return;                                // stack only onto protected trades
   string reason = "";
   if(!EntriesAllowed(tick, reason))
   {
      LogMsg(DirText(dir) + " signal skipped: " + reason + ".");
      return;
   }
   OpenTrade(dir, same > 0, tick);
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
   ConsiderEntry(tick);
}

//====================================================================
//  MANAGING EACH OPEN TRADE: BREAK-EVEN AND TRAILING STOP
//====================================================================

// Is the new stop better than the old one by at least "step"?
bool ImprovesBy(const int dir, const double newStop, const double oldStop, const double step)
{
   if(oldStop <= 0.0)
      return true;
   if(dir > 0)
      return (newStop >= oldStop + step);
   return (newStop <= oldStop - step);
}

// The tightest stop the broker accepts right now.
double ClosestAllowedStop(const int dir, const MqlTick &tick)
{
   double minDistance = (double)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point + g_tickSize;
   if(dir > 0)
      return RoundDownToTick(tick.bid - minDistance);
   return RoundUpToTick(tick.ask + minDistance);
}

bool MoveStop(const int index, const double newStop, const double takeProfit, const string why)
{
   if(!g_trade.PositionModify(g_managed[index].ticket, newStop, takeProfit) || !RequestSucceeded(g_trade.ResultRetcode()))
   {
      LogMsg("Could not move the stop to " + DoubleToString(newStop, g_digits) + " (" + why + "): " +
             g_trade.ResultRetcodeDescription() + ". Trying again in a few seconds.");
      g_managed[index].retryAfter = TimeCurrent() + 10;
      return false;
   }
   if(!g_isTester)
      LogMsg("Stop moved to " + DoubleToString(newStop, g_digits) + " (" + why + ").");
   return true;
}

void ManageTrade(const int index, const MqlTick &tick)
{
   if(!PositionSelectByTicket(g_managed[index].ticket))
      return;
   int    dir        = g_managed[index].dir;
   double entry      = g_managed[index].entry;
   double stop       = PositionGetDouble(POSITION_SL);
   double takeProfit = PositionGetDouble(POSITION_TP);   // normally none; kept if you set one by hand

   // (a) Best price reached. A buy closes at the Bid, a sell at the Ask.
   double closePrice = (dir > 0) ? tick.bid : tick.ask;
   if((dir > 0 && closePrice > g_managed[index].best) || (dir < 0 && closePrice < g_managed[index].best))
   {
      g_managed[index].best = closePrice;
      if(!g_isTester)
         GvSet("Best_" + IntegerToString(g_managed[index].id), closePrice);
   }
   double best = g_managed[index].best;
   if(TimeCurrent() < g_managed[index].retryAfter)
      return;                                // pause after a refused change

   // (b) No stop at all (removed by hand)? Put the first stop back, or close
   //     the trade if the price is already beyond it.
   if(stop <= 0.0)
   {
      double distance = (g_managed[index].risk > 0.0) ? g_managed[index].risk : InitialStopATRMultiplier * g_atr;
      if(distance <= 0.0)
         return;
      double wanted = (dir > 0) ? RoundDownToTick(entry - distance) : RoundUpToTick(entry + distance);
      if(StopIsAllowed(dir, wanted, tick))
      {
         if(MoveStop(index, wanted, takeProfit, "first stop restored"))
            SetStage(index, 0);
      }
      else if(!g_trade.PositionClose(g_managed[index].ticket) || !RequestSucceeded(g_trade.ResultRetcode()))
         g_managed[index].retryAfter = TimeCurrent() + 10;
      return;
   }

   // (c) Break-even once the profit reaches BreakEvenTriggerMultiple x the
   //     first stop distance.
   double risk = g_managed[index].risk;
   if(g_managed[index].stage == 0 && risk > 0.0)
   {
      double profit = (dir > 0) ? (best - entry) : (entry - best);
      if(profit >= BreakEvenTriggerMultiple * risk - g_tickSize * 0.001)
      {
         double breakEven = BreakEvenPrice(dir, entry);
         if(!ImprovesBy(dir, breakEven, stop, g_tickSize * 0.5))
            SetStage(index, StageFromStop(dir, entry, stop));     // already there (moved by hand)
         else if(StopIsAllowed(dir, breakEven, tick) && MoveStop(index, breakEven, takeProfit, "break-even"))
         {
            stop = breakEven;
            SetStage(index, 1);
         }
      }
   }

   // (d) Trailing: after break-even, keep the stop TrailingStopATRMultiplier
   //     x ATR behind the best price. It only ever moves forward.
   if(g_managed[index].stage >= 1 && g_atr > 0.0)
   {
      double trail = (dir > 0) ? RoundDownToTick(best - TrailingStopATRMultiplier * g_atr)
                               : RoundUpToTick(best + TrailingStopATRMultiplier * g_atr);
      double minStep = MathMax(TrailingStepATR * g_atr, g_tickSize) - g_tickSize * 0.01;
      if(ImprovesBy(dir, trail, stop, minStep))
      {
         if(!StopIsAllowed(dir, trail, tick))
            trail = ClosestAllowedStop(dir, tick);
         if(ImprovesBy(dir, trail, stop, minStep) && MoveStop(index, trail, takeProfit, "trailing"))
            SetStage(index, 2);
      }
   }
}

void ManageOpenTrades(const MqlTick &tick)
{
   for(int i = 0; i < ArraySize(g_managed); i++)
      ManageTrade(i, tick);
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
   return "Trading - waiting for a " + TfName(EntryTimeframe) + " breakout";
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
   int protectedCount = 0;
   for(int i = 0; i < ArraySize(g_managed); i++)
   {
      if(g_managed[i].stage >= 1)
         protectedCount++;
   }
   string text = EA_NAME;
   text += "  |  " + g_symbol + "  |  " + IntegerToString(ArraySize(g_managed)) + " of " + IntegerToString(MaxOpenTrades) +
           " trades open (" + IntegerToString(protectedCount) + " protected at break-even or better)\n";
   text += "Status: " + StatusText() + "\n";
   text += "Direction: " + trend + "   (" + TfName(TrendTimeframe) + " close " + DoubleToString(g_trendClose, g_digits) +
           " vs EMA " + IntegerToString(TrendEMAPeriod) + " " + DoubleToString(g_trendEma, g_digits) + ")\n";
   text += "ATR " + DoubleToString(g_atr, g_digits) + "  |  trades opened: " + IntegerToString(g_tradesOpened) + " (" +
           IntegerToString(g_tradesStacked) + " stacked)\n";
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
   Print(StringFormat("Test summary: %d trades opened in %.0f days (%.2f per calendar day), %d of them stacked; %d signals.",
                      g_tradesOpened, days, g_tradesOpened / days, g_tradesStacked, g_signals));
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

   g_emaHandle = iMA(g_symbol, TrendTimeframe, TrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_atrHandle = iATR(g_symbol, ATRTimeframe, ATRPeriod);
   if(g_emaHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE)
   {
      WarnMsg("Could not create the EMA / ATR indicators.");
      return INIT_FAILED;
   }

   g_gvPrefix = "GTS_" + IntegerToString(MagicNumber) + "_";
   if(g_isTester)
      GlobalVariablesDeleteAll(g_gvPrefix);  // every backtest starts from a clean slate

   LoadSafetyState();
   LoadNewsTimes();
   PrepareCsvFile();

   // Decide only on candles that finish from now on: a candle that was
   // already running when the EA started is not treated as a fresh signal.
   g_lastDecisionCandle = iTime(g_symbol, EntryTimeframe, 0);
   g_lastAtrCandle      = 0;
   ArrayResize(g_managed, 0);
   SyncPositions(false);
   RefreshManaged();
   if(!g_isTester)
      LogTradesClosedWhileOffline();

   LogMsg(StringFormat("%s started on %s | trend %s EMA %d | %s breakouts of %d candles | up to %d trades%s | "
                       "stop %.1f ATR, break-even at %.1fR, trailing %.1f ATR | risk %.2f%% per trade",
                       EA_NAME, g_symbol, TfName(TrendTimeframe), TrendEMAPeriod, TfName(EntryTimeframe),
                       BreakoutLookbackCandles, MaxOpenTrades, StackOnlyWhenProtected ? " (added only onto protected trades)" : "",
                       InitialStopATRMultiplier, BreakEvenTriggerMultiple, TrailingStopATRMultiplier, RiskPercentPerTrade));
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

   SyncPositions(false);                     // 1. trades that closed -> CSV
   RefreshManaged();
   UpdateSafetySwitches();                   // 2. daily loss limit, equity peak, kill switch
   if(g_killSwitchOn)
   {
      CloseEverythingForKillSwitch();
      ShowStatus(tick);
      return;
   }
   RefreshATR();                             // 3. ATR of the last finished candle
   datetime minute = iTime(g_symbol, PERIOD_M1, 0);
   if(minute != g_lastNewsCheck)             // 4. news check once a minute
   {
      g_lastNewsCheck = minute;
      g_newsWhat      = "";
      g_newsBlocked   = UseNewsFilter && InNewsBlackout(TimeCurrent(), g_newsWhat);
   }
   ManageOpenTrades(tick);                   // 5. break-even and trailing for every trade
   CheckFinishedEntryCandle(tick);           // 6. new 1-hour candle: breakout? -> trade
   ShowStatus(tick);
}

void OnTrade()
{
   SyncPositions(false);
   RefreshManaged();
}
//+------------------------------------------------------------------+
