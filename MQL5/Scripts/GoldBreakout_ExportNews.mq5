//+------------------------------------------------------------------+
//|                                      GoldBreakout_ExportNews.mq5 |
//|     Helper for GoldBreakoutEA: saves high-impact USD news times  |
//|     from MetaTrader's economic calendar into a small text file.  |
//+------------------------------------------------------------------+
//
//  WHY THIS EXISTS
//  ---------------
//  MetaTrader's economic calendar does not work inside the Strategy
//  Tester. So in backtests GoldBreakoutEA reads the news times from a file
//  instead. This script creates that file from the calendar's history.
//
//  HOW TO USE (once, and again whenever you want newer events)
//  -----------------------------------------------------------
//  1. In normal MetaTrader (not the Strategy Tester) open a GOLD chart
//     (XAUUSD, or your broker's name for it) and make sure you are online.
//  2. Navigator (Ctrl+N) -> Scripts -> drag "GoldBreakout_ExportNews"
//     onto the chart. Leave the settings as they are and press OK.
//  3. A message tells you how many news times were saved. The file goes to
//     MetaTrader's COMMON Files folder, which is where the EA looks for it.
//
//  SUMMER TIME
//  -----------
//  MetaTrader may show OLD calendar events shifted by one hour if your
//  broker's clock changes for summer time. With SummerTimeFix = Auto the
//  script checks this itself (it looks at when gold's daily trading break
//  happens in winter and in summer) and corrects it. It explains what it
//  did in the final message and at the top of the file.
//+------------------------------------------------------------------+
#property script_show_inputs
#property version     "1.00"
#property description "Saves high-impact USD news times for GoldBreakoutEA backtests."
#property description "Run it on a gold chart in normal MetaTrader (not in the Strategy Tester)."

enum ENUM_SUMMER_TIME_FIX
{
   SUMMER_FIX_AUTO = 0,   // Auto-detect (recommended)
   SUMMER_FIX_NONE = 1,   // None: my broker's clock never changes
   SUMMER_FIX_US   = 2,   // My broker's clock follows US summer time
   SUMMER_FIX_EU   = 3    // My broker's clock follows European summer time
};

// First and last date to export (the EA only needs the dates you test).
input datetime FromDate = D'2019.12.01 00:00';
input datetime ToDate   = D'2026.12.31 23:59';
// News of which currency.
input string Currency = "USD";
// File name. Must match NewsTimesFile in the EA's settings.
input string OutputFileName = "GoldBreakout_news.csv";
// See "SUMMER TIME" above. Auto is right for almost everyone.
input ENUM_SUMMER_TIME_FIX SummerTimeFix = SUMMER_FIX_AUTO;

#define RULE_UNKNOWN (-1)
#define RULE_NONE    0
#define RULE_US      1
#define RULE_EU      2

//--------------------------------------------------------------------
//  Dates and summer-time rules
//--------------------------------------------------------------------

datetime MakeDate(const int year, const int month, const int day)
{
   MqlDateTime parts;
   ZeroMemory(parts);
   parts.year = year;
   parts.mon  = month;
   parts.day  = day;
   return StructToTime(parts);
}

int WeekdayOf(const datetime t)              // 0 = Sunday ... 6 = Saturday
{
   MqlDateTime parts;
   TimeToStruct(t, parts);
   return parts.day_of_week;
}

int YearOf(const datetime t)
{
   MqlDateTime parts;
   TimeToStruct(t, parts);
   return parts.year;
}

// The n-th Sunday of a month (n = 1 for the first Sunday).
datetime NthSunday(const int year, const int month, const int n)
{
   datetime first = MakeDate(year, month, 1);
   int toSunday = (7 - WeekdayOf(first)) % 7;
   return first + (toSunday + 7 * (n - 1)) * 86400;
}

// The last Sunday of a month.
datetime LastSunday(const int year, const int month)
{
   datetime nextMonth = (month == 12) ? MakeDate(year + 1, 1, 1) : MakeDate(year, month + 1, 1);
   datetime lastDay   = nextMonth - 86400;
   return lastDay - WeekdayOf(lastDay) * 86400;
}

// Is this date in summer time? US: 2nd Sunday of March to 1st Sunday of
// November. Europe: last Sunday of March to last Sunday of October.
bool IsSummerTime(const int rule, const datetime t)
{
   int year = YearOf(t);
   if(rule == RULE_US)
      return (t >= NthSunday(year, 3, 2) && t < NthSunday(year, 11, 1));
   if(rule == RULE_EU)
      return (t >= LastSunday(year, 3) && t < LastSunday(year, 10));
   return false;
}

// Difference between two times of day in minutes, from -720 to +719
// (so that 23:30 and 00:30 are one hour apart, not 23 hours).
int MinutesApart(const int a, const int b)
{
   int d = (a - b) % 1440;
   if(d < -720)
      d += 1440;
   if(d >= 720)
      d -= 1440;
   return d;
}

int MinuteOfDay(const datetime t)
{
   return (int)(((long)t % 86400) / 60);
}

int BusiestSlot(const int &counts[])
{
   int best = 0;
   for(int i = 1; i < ArraySize(counts); i++)
   {
      if(counts[i] > counts[best])
         best = i;
   }
   return best;
}

//--------------------------------------------------------------------
//  Detecting whether a summer-time correction is needed
//--------------------------------------------------------------------

// Nonfarm Payrolls are always released at 8:30 New York time. This looks at
// how the calendar reports past releases:
//   1 = same distance from UTC all year (the calendar uses ONE clock offset
//       for every date, so a broker with summer time needs a correction),
//   2 = the distance changes with US summer time (the calendar already
//       matches a summer-time clock: no correction needed),
//   0 = not enough information.
int CalendarPattern(const datetime &nfpTimes[])
{
   int summer[48];
   int winter[48];
   ArrayInitialize(summer, 0);
   ArrayInitialize(winter, 0);
   int summerTotal = 0, winterTotal = 0;
   for(int i = 0; i < ArraySize(nfpTimes); i++)
   {
      bool isSummer  = IsSummerTime(RULE_US, nfpTimes[i]);
      int  utcMinute = isSummer ? 12 * 60 + 30 : 13 * 60 + 30;          // 8:30 New York, in UTC
      int  slot      = (MinutesApart(MinuteOfDay(nfpTimes[i]), utcMinute) + 720) / 30;
      if(isSummer)
      {
         summer[slot]++;
         summerTotal++;
      }
      else
      {
         winter[slot]++;
         winterTotal++;
      }
   }
   if(summerTotal < 3 || winterTotal < 3)
      return 0;
   int difference = (BusiestSlot(summer) - BusiestSlot(winter)) * 30;
   if(difference == 0)
      return 1;
   if(difference == 60)
      return 2;
   return 0;
}

// Middle of gold's daily trading break, in minutes after midnight (server
// time), found from the 15-minute price history between two dates.
// Returns -1 if no clear daily break is found.
int DailyBreakMiddle(const datetime from, const datetime to, const int minimumBreaks)
{
   MqlRates rates[];
   int count = -1;
   for(int attempt = 0; attempt < 10 && count <= 0; attempt++)
   {
      count = CopyRates(_Symbol, PERIOD_M15, from, to, rates);
      if(count <= 0)
         Sleep(500);                         // history is still downloading
   }
   if(count < 100)
      return -1;

   int slots[48];
   ArrayInitialize(slots, 0);
   int breaks = 0;
   for(int i = 1; i < count; i++)
   {
      long gap = (long)rates[i].time - (long)rates[i - 1].time;
      if(gap < 45 * 60 || gap > 4 * 3600)
         continue;                           // not a daily break (normal candle, or a weekend/holiday)
      long breakStart = (long)rates[i - 1].time + 15 * 60;
      long middle     = breakStart + ((long)rates[i].time - breakStart) / 2;
      slots[(int)((middle % 86400) / 1800)]++;
      breaks++;
   }
   int best = BusiestSlot(slots);
   if(breaks < minimumBreaks || slots[best] * 2 < breaks)
      return -1;
   return best * 30 + 15;
}

// Work out from the price history whether the broker's clock changes for
// summer time, and if so whether it follows the US or the European dates.
int DetectBrokerRule(string &explanation)
{
   int year   = YearOf(TimeTradeServer()) - 1;           // last full year
   int winter = DailyBreakMiddle(MakeDate(year, 1, 8), MakeDate(year, 3, 1), 10);
   int summer = DailyBreakMiddle(MakeDate(year, 6, 1), MakeDate(year, 9, 1), 10);
   if(winter < 0 || summer < 0)
   {
      explanation = "the script could not find gold's daily trading break in the price history (run it on a gold chart)";
      return RULE_UNKNOWN;
   }
   // Gold's daily break is at 5 pm New York time. If the broker's clock does
   // not change, the break is one hour earlier on the clock in summer.
   int shift = MinutesApart(summer, winter);
   if(MathAbs(shift + 60) <= 15)
   {
      explanation = "your broker's clock stays the same all year";
      return RULE_NONE;
   }
   if(MathAbs(shift) > 15)
   {
      explanation = "gold's daily trading break did not follow a clear pattern";
      return RULE_UNKNOWN;
   }
   // The clock follows summer time. US or European dates? Look at the weeks
   // in March when the US has already switched and Europe has not yet.
   int march = DailyBreakMiddle(NthSunday(year, 3, 2) + 86400, LastSunday(year, 3) - 86400, 5);
   if(march >= 0 && MathAbs(MinutesApart(march, winter) + 60) <= 15)
   {
      explanation = "your broker's clock follows European summer time";
      return RULE_EU;
   }
   explanation = "your broker's clock follows US summer time";
   return RULE_US;
}

// Decide which correction to apply (RULE_NONE, RULE_US or RULE_EU) and
// explain the decision in plain words.
int ChooseCorrection(const datetime &nfpTimes[], string &explanation)
{
   if(SummerTimeFix == SUMMER_FIX_NONE)
   {
      explanation = "no summer-time correction (as selected in the settings)";
      return RULE_NONE;
   }
   int pattern = CalendarPattern(nfpTimes);
   if(pattern == 2)
   {
      explanation = "no correction needed: the calendar already gives past events in your broker's summer/winter clock";
      return RULE_NONE;
   }

   int    rule = RULE_NONE;
   string why  = "";
   if(SummerTimeFix == SUMMER_FIX_US)
   {
      rule = RULE_US;
      why  = "your broker's clock follows US summer time (as selected in the settings)";
   }
   else if(SummerTimeFix == SUMMER_FIX_EU)
   {
      rule = RULE_EU;
      why  = "your broker's clock follows European summer time (as selected in the settings)";
   }
   else
   {
      rule = DetectBrokerRule(why);
      if(rule == RULE_UNKNOWN)
      {
         explanation = "no correction: " + why + ". If your broker's clock changes for summer time, run the "
                       "script again and choose SummerTimeFix = US or European";
         return RULE_NONE;
      }
      if(rule == RULE_NONE)
      {
         explanation = "no correction needed: " + why;
         return RULE_NONE;
      }
   }
   explanation = "events were moved by one hour where needed, because " + why +
                 " while the calendar uses today's clock for all dates";
   if(pattern == 0)
      explanation += " (the calendar's own pattern could not be double-checked)";
   return rule;
}

//--------------------------------------------------------------------
//  Main part
//--------------------------------------------------------------------

string CleanName(const string text)
{
   string result = text;
   StringReplace(result, ",", " ");
   StringReplace(result, "\r", " ");
   StringReplace(result, "\n", " ");
   return result;
}

void OnStart()
{
   if(MQLInfoInteger(MQL_TESTER) != 0)
   {
      Print("This script only works in normal MetaTrader, not in the Strategy Tester.");
      return;
   }

   // 1. Which events of this currency are "high impact"?
   MqlCalendarEvent events[];
   int eventCount = CalendarEventByCurrency(Currency, events);
   if(eventCount <= 0)
   {
      Alert("GoldBreakout_ExportNews: no calendar events found for ", Currency, ". Make sure you are connected, and ",
            "open the Calendar tab (View > Toolbox > Calendar) once so MetaTrader downloads it. Then run the script again.");
      return;
   }
   ulong  highIds[];
   string highNames[];
   ulong  nfpId = 0;
   for(int i = 0; i < eventCount; i++)
   {
      if(events[i].importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      int n = ArraySize(highIds);
      ArrayResize(highIds, n + 1);
      ArrayResize(highNames, n + 1);
      highIds[n]   = events[i].id;
      highNames[n] = events[i].name;
      if(events[i].event_code == "nonfarm-payrolls" || StringCompare(events[i].name, "Nonfarm Payrolls", false) == 0)
         nfpId = events[i].id;
   }

   // 2. Every release of those events between FromDate and ToDate.
   MqlCalendarValue values[];
   ResetLastError();
   if(!CalendarValueHistory(values, FromDate, ToDate, NULL, Currency) && GetLastError() != 0)
   {
      Alert("GoldBreakout_ExportNews: could not read the calendar history (error ", GetLastError(), ").");
      return;
   }
   datetime times[];
   string   names[];
   datetime nfpTimes[];
   datetime now = TimeTradeServer();
   for(int i = 0; i < ArraySize(values); i++)
   {
      int k = -1;
      for(int j = 0; j < ArraySize(highIds); j++)
      {
         if(highIds[j] == values[i].event_id)
         {
            k = j;
            break;
         }
      }
      if(k < 0)
         continue;
      int n = ArraySize(times);
      ArrayResize(times, n + 1, 1024);
      ArrayResize(names, n + 1, 1024);
      times[n] = values[i].time;
      names[n] = CleanName(highNames[k]);
      if(values[i].event_id == nfpId && values[i].time < now)
      {
         int m = ArraySize(nfpTimes);
         ArrayResize(nfpTimes, m + 1, 128);
         nfpTimes[m] = values[i].time;
      }
   }
   int total = ArraySize(times);
   if(total == 0)
   {
      Alert("GoldBreakout_ExportNews: no high-impact ", Currency, " events found between ", TimeToString(FromDate, TIME_DATE),
            " and ", TimeToString(ToDate, TIME_DATE), ".");
      return;
   }

   // 3. Summer-time correction.
   string explanation = "";
   int    rule        = ChooseCorrection(nfpTimes, explanation);
   int    moved       = 0;
   if(rule != RULE_NONE)
   {
      int summerNow = IsSummerTime(rule, now) ? 1 : 0;
      for(int i = 0; i < total; i++)
      {
         int shift = (IsSummerTime(rule, times[i]) ? 1 : 0) - summerNow;
         if(shift != 0)
         {
            times[i] += shift * 3600;
            moved++;
         }
      }
   }

   // 4. Sort by time (the calendar is almost sorted already, so this is quick).
   for(int i = 1; i < total; i++)
   {
      datetime t    = times[i];
      string   name = names[i];
      int      j    = i - 1;
      while(j >= 0 && times[j] > t)
      {
         times[j + 1] = times[j];
         names[j + 1] = names[j];
         j--;
      }
      times[j + 1] = t;
      names[j + 1] = name;
   }

   // 5. Write the file (events at the same minute share one line).
   int handle = FileOpen(OutputFileName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      Alert("GoldBreakout_ExportNews: could not create the file ", OutputFileName, " (error ", GetLastError(), ").");
      return;
   }
   FileWriteString(handle, "# High-impact " + Currency + " news times for GoldBreakoutEA, in your broker's SERVER time.\r\n");
   FileWriteString(handle, "# Made on " + TimeToString(now, TIME_DATE | TIME_MINUTES) + " by GoldBreakout_ExportNews from "
                   "MetaTrader's economic calendar (" + AccountInfoString(ACCOUNT_SERVER) + ").\r\n");
   FileWriteString(handle, "# Summer time: " + explanation + ".\r\n");
   FileWriteString(handle, "# Format: YYYY.MM.DD HH:MM,event name. You may add or delete lines by hand.\r\n");
   int      lines = 0;
   datetime lastTime = 0;
   string   lineNames = "";
   for(int i = 0; i <= total; i++)
   {
      if(i < total && times[i] == lastTime)
      {
         if(StringFind(lineNames, names[i]) < 0)
            lineNames += " / " + names[i];
         continue;
      }
      if(lastTime != 0)
      {
         FileWriteString(handle, TimeToString(lastTime, TIME_DATE | TIME_MINUTES) + "," + lineNames + "\r\n");
         lines++;
      }
      if(i < total)
      {
         lastTime  = times[i];
         lineNames = names[i];
      }
   }
   FileClose(handle);

   string path = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + OutputFileName;
   Print("Summer time: ", explanation, ". Events moved by one hour: ", moved, ".");
   Alert("GoldBreakout_ExportNews: saved ", lines, " high-impact ", Currency, " news times (",
         TimeToString(FromDate, TIME_DATE), " to ", TimeToString(ToDate, TIME_DATE), ") to ", path,
         ". Summer time: ", explanation, ".");
}
//+------------------------------------------------------------------+
