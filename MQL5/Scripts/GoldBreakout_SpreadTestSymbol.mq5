//+------------------------------------------------------------------+
//|                                GoldBreakout_SpreadTestSymbol.mq5 |
//|     Helper for GoldBreakoutEA: makes a copy of gold whose spread |
//|     is doubled (or any multiple) for the spread stress test.     |
//+------------------------------------------------------------------+
//
//  WHY THIS EXISTS
//  ---------------
//  In "Every tick based on real ticks" mode the Strategy Tester always
//  uses the spreads your broker actually recorded. There is no setting to
//  make them wider. This script creates a "custom symbol": a copy of your
//  gold symbol (same contract size, tick value, trading hours...) whose
//  ticks are the real ticks, but with the Ask moved so that every spread
//  is SpreadMultiplier times wider. You then backtest the EA on that copy.
//
//  HOW TO USE
//  ----------
//  1. First run your normal backtest once over the same dates, so that
//     MetaTrader has downloaded the real tick history.
//  2. In normal MetaTrader open a gold chart. Navigator (Ctrl+N) -> Scripts
//     -> drag "GoldBreakout_SpreadTestSymbol" onto the chart, check the
//     dates, press OK.
//  3. Wait. Copying years of ticks can take a while; progress is shown in
//     the top-left corner of the chart. A message says when it is done.
//  4. In the Strategy Tester choose the new symbol (for example
//     XAUUSD_x2spread) as the Symbol and run the EA with the same settings.
//
//  Note: MetaTrader cannot copy your broker's commission to a custom
//  symbol. If your account type charges commission, this test shows the
//  wider spread but not the commission.
//+------------------------------------------------------------------+
#property script_show_inputs
#property version     "1.00"
#property description "Creates a copy of gold with a wider spread for GoldBreakoutEA stress tests."
#property description "Run it on a gold chart in normal MetaTrader (not in the Strategy Tester)."

// Symbol to copy. Leave empty to copy the symbol of the chart you drop it on.
input string SourceSymbol = "";
// How much wider the spread becomes (2.0 = double).
input double SpreadMultiplier = 2.0;
// Dates to copy. Use the dates of the backtest you want to repeat.
input datetime FromDate = D'2024.01.01 00:00';
input datetime ToDate   = D'2026.12.31 23:59';
// Extra days copied BEFORE FromDate, so the EA's 4-hour EMA has history.
input int WarmUpDays = 120;
// Name of the copy. Leave empty for the automatic name, e.g. XAUUSD_x2spread.
input string NewSymbolName = "";

// Widen the spread of a batch of ticks (Bid unchanged, Ask moved up) and
// mark which prices changed compared with the previous tick.
void WidenSpread(MqlTick &ticks[], const int count, const int digits, double &lastBid, double &lastAsk,
                 double &spreadBefore, double &spreadAfter)
{
   for(int i = 0; i < count; i++)
   {
      if(ticks[i].bid > 0.0 && ticks[i].ask > 0.0)
      {
         double spread = ticks[i].ask - ticks[i].bid;
         spreadBefore += spread;
         ticks[i].ask  = NormalizeDouble(ticks[i].bid + spread * SpreadMultiplier, digits);
         spreadAfter  += ticks[i].ask - ticks[i].bid;
      }
      uint original = ticks[i].flags;
      uint flags    = original & ~((uint)(TICK_FLAG_BID | TICK_FLAG_ASK));
      if(ticks[i].bid != lastBid)
         flags |= TICK_FLAG_BID;
      if(ticks[i].ask != lastAsk)
         flags |= TICK_FLAG_ASK;
      if(flags == 0)
         flags = original;
      ticks[i].flags = flags;
      lastBid = ticks[i].bid;
      lastAsk = ticks[i].ask;
   }
}

void OnStart()
{
   if(MQLInfoInteger(MQL_TESTER) != 0)
   {
      Print("This script only works in normal MetaTrader, not in the Strategy Tester.");
      return;
   }
   if(SpreadMultiplier <= 0.0)
   {
      Alert("GoldBreakout_SpreadTestSymbol: SpreadMultiplier must be above 0.");
      return;
   }

   // ---- Which symbol to copy, and the name of the copy
   string source = SourceSymbol;
   StringTrimLeft(source);
   StringTrimRight(source);
   if(source == "")
      source = _Symbol;
   bool sourceIsCustom = false;
   if(!SymbolExist(source, sourceIsCustom))
   {
      Alert("GoldBreakout_SpreadTestSymbol: the symbol '", source, "' does not exist.");
      return;
   }
   SymbolSelect(source, true);
   string multiplierText = DoubleToString(SpreadMultiplier, (SpreadMultiplier == MathRound(SpreadMultiplier)) ? 0 : 1);
   string target = NewSymbolName;
   StringTrimLeft(target);
   StringTrimRight(target);
   if(target == "")
      target = source + "_x" + multiplierText + "spread";
   if(StringLen(target) > 31)
   {
      Alert("GoldBreakout_SpreadTestSymbol: the name '", target, "' is too long (31 characters at most). Type a shorter NewSymbolName.");
      return;
   }

   // ---- Create the copy (or reuse it if this script made it before)
   bool targetIsCustom = false;
   if(SymbolExist(target, targetIsCustom))
   {
      if(!targetIsCustom)
      {
         Alert("GoldBreakout_SpreadTestSymbol: your broker already has a symbol called '", target, "'. Type another NewSymbolName.");
         return;
      }
      Print("Custom symbol ", target, " already exists: its ticks in the chosen dates will be replaced.");
   }
   else if(!CustomSymbolCreate(target, "GoldBreakout", source))
   {
      Alert("GoldBreakout_SpreadTestSymbol: could not create the custom symbol ", target, " (error ", GetLastError(), ").");
      return;
   }
   CustomSymbolSetString(target, SYMBOL_DESCRIPTION, source + " with spread x" + multiplierText + " (GoldBreakoutEA stress test)");
   SymbolSelect(target, true);

   // ---- Copy the ticks day by day, widening the spread
   int      digits = (int)SymbolInfoInteger(source, SYMBOL_DIGITS);
   datetime start  = FromDate - WarmUpDays * 86400;
   start = (datetime)((long)start - (long)start % 86400);        // midnight
   datetime finish = ToDate;
   if(finish > TimeTradeServer())
      finish = TimeTradeServer();
   if(finish <= start)
   {
      Alert("GoldBreakout_SpreadTestSymbol: check FromDate and ToDate.");
      return;
   }

   long   totalTicks = 0;
   int    daysWithTicks = 0, failedDays = 0;
   double lastBid = 0.0, lastAsk = 0.0, spreadBefore = 0.0, spreadAfter = 0.0;
   long   allDays = (long)(finish - start) / 86400 + 1;
   long   dayIndex = 0;
   for(datetime day = start; day <= finish && !IsStopped(); day += 86400, dayIndex++)
   {
      long fromMsc = (long)day * 1000;
      long toMsc   = (long)(day + 86400) * 1000 - 1;
      MqlTick ticks[];
      int count = -1;
      for(int attempt = 0; attempt < 5 && count < 0; attempt++)
      {
         count = CopyTicksRange(source, ticks, COPY_TICKS_ALL, (ulong)fromMsc, (ulong)toMsc);
         if(count < 0)
            Sleep(1000);                     // history still downloading: wait and try again
      }
      if(count < 0)
      {
         failedDays++;
         continue;
      }
      if(count == 0)
         continue;                           // weekend or holiday
      WidenSpread(ticks, count, digits, lastBid, lastAsk, spreadBefore, spreadAfter);
      if(CustomTicksReplace(target, fromMsc, toMsc, ticks) < 0)
      {
         failedDays++;
         continue;
      }
      // 1-minute candles too (same prices; the spread field is widened).
      MqlRates rates[];
      int bars = CopyRates(source, PERIOD_M1, day, day + 86399, rates);
      if(bars > 0)
      {
         for(int i = 0; i < bars; i++)
            rates[i].spread = (int)MathRound(rates[i].spread * SpreadMultiplier);
         CustomRatesReplace(target, day, day + 86399, rates);
      }
      totalTicks += count;
      daysWithTicks++;
      if(dayIndex % 5 == 0)
         Comment(StringFormat("GoldBreakout_SpreadTestSymbol: copying %s -> %s   %s   (%d%%)", source, target,
                              TimeToString(day, TIME_DATE), (int)(100 * dayIndex / allDays)));
   }
   Comment("");

   if(IsStopped())
   {
      Alert("GoldBreakout_SpreadTestSymbol: stopped before the end. Run it again to finish.");
      return;
   }
   if(totalTicks == 0)
   {
      Alert("GoldBreakout_SpreadTestSymbol: no ticks could be copied. Run a normal backtest over these dates first "
            "(so MetaTrader downloads the tick history), then run this script again.");
      return;
   }
   double avgBefore = spreadBefore / (double)totalTicks;
   double avgAfter  = spreadAfter / (double)totalTicks;
   string note = "";
   if(failedDays > 0)
      note = " WARNING: " + IntegerToString(failedDays) + " days could not be copied; run the script again later.";
   Alert("GoldBreakout_SpreadTestSymbol: done. ", target, " has ", IntegerToString(totalTicks), " ticks on ",
         IntegerToString(daysWithTicks), " days (", TimeToString(start, TIME_DATE), " to ", TimeToString(finish, TIME_DATE),
         "). Average spread ", DoubleToString(avgBefore, digits), " -> ", DoubleToString(avgAfter, digits),
         ". In the Strategy Tester choose ", target, " as the Symbol.", note);
}
//+------------------------------------------------------------------+
