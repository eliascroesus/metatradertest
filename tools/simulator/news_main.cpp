// Tests GoldBreakout_ExportNews on synthetic broker clocks and calendars.
#include "mql5_sim.h"
#include "news_sim.inc"

// independent summer-time rules (written separately from the script)
static long ymd(int y, int m, int d) { struct tm g = {}; g.tm_year = y - 1900; g.tm_mon = m - 1; g.tm_mday = d; return (long)timegm(&g); }
static int wday(long t) { time_t tt = t; struct tm g; gmtime_r(&tt, &g); return g.tm_wday; }
static int yearOf(long t) { time_t tt = t; struct tm g; gmtime_r(&tt, &g); return g.tm_year + 1900; }
static long nthSunday(int y, int m, int n) { long t = ymd(y, m, 1); while(wday(t) != 0) t += 86400; return t + (n - 1) * 7 * 86400L; }
static long lastSunday(int y, int m) { long t = (m == 12 ? ymd(y + 1, 1, 1) : ymd(y, m + 1, 1)) - 86400; while(wday(t) != 0) t -= 86400; return t; }
// US summer time starts 2:00 local on the 2nd Sunday of March (= 7:00 UTC), ends 2:00 local 1st Sunday Nov (= 6:00 UTC)
static bool usSummerUtc(long utc) { int y = yearOf(utc); return utc >= nthSunday(y, 3, 2) + 7 * 3600 && utc < nthSunday(y, 11, 1) + 6 * 3600; }
static bool euSummerUtc(long utc) { int y = yearOf(utc); return utc >= lastSunday(y, 3) + 3600 && utc < lastSunday(y, 10) + 3600; }
static int nyOffset(long utc) { return usSummerUtc(utc) ? -4 : -5; }
std::string model = "ny7";
static int serverOffset(long utc) { if(model == "ny7") return nyOffset(utc) + 7; if(model == "gmt0") return 0; return 2 + (euSummerUtc(utc) ? 1 : 0); }
static long nyToUtc(int y, int m, int d, int hh, int mm) { long local = ymd(y, m, d) + hh * 3600 + mm * 60; long utc = local + 5 * 3600; if(usSummerUtc(utc - 3600)) utc -= 3600; return utc; }

int main(int argc, char** argv) {
  model = argv[1]; std::string calMode = argv[2];     // calMode: "uniform" (today's offset for all dates) or "seasonal"
  sim::isTester = false; sim::quiet = true;
  long startUtc = ymd(2022, 12, 20), endUtc = (argc > 3 ? ymd(2024, atoi(argv[3]), 20) : ymd(2024, 6, 28)) + 12 * 3600;
  // 15-minute bars: market open from Sunday 18:00 to Friday 17:00 New York time, daily break 17:00-18:00 NY
  for(long utc = startUtc; utc < endUtc; utc += 900) {
    long ny = utc + nyOffset(utc) * 3600; time_t tt = ny; struct tm g; gmtime_r(&tt, &g);
    int w = g.tm_wday, h = g.tm_hour;
    bool open = !(w == 6 || (w == 0 && h < 18) || (w == 5 && h >= 17) || h == 17);
    if(!open) continue;
    MqlRates r{}; r.time = utc + serverOffset(utc) * 3600; r.open = r.high = r.low = r.close = 2000; sim::m15.push_back(r);
  }
  long nowUtc = endUtc; sim::now.t = nowUtc + serverOffset(nowUtc) * 3600;
  int nowOffset = serverOffset(nowUtc);
  auto calTime = [&](long utc) { return calMode == "uniform" ? utc + nowOffset * 3600L : utc + serverOffset(utc) * 3600L; };
  // events: NFP (first Friday 8:30 NY), CPI (13th or next weekday 8:30 NY), FOMC (3rd Wednesday of odd months 14:00 NY), a low-impact one
  MqlCalendarEvent e{}; e.importance = CALENDAR_IMPORTANCE_HIGH;
  e.id = 1; e.event_code = "nonfarm-payrolls"; e.name = "Nonfarm Payrolls"; sim::calEvents.push_back(e);
  e.id = 2; e.event_code = "cpi"; e.name = "CPI m/m"; sim::calEvents.push_back(e);
  e.id = 3; e.event_code = "fomc"; e.name = "Fed Interest Rate Decision, statement"; sim::calEvents.push_back(e);
  e.id = 4; e.event_code = "low"; e.name = "Low thing"; e.importance = CALENDAR_IMPORTANCE_LOW; sim::calEvents.push_back(e);
  std::map<long, std::string> truth;   // true SERVER time -> name
  for(int y = 2019; y <= 2024; y++) for(int m = 1; m <= 12; m++) {
    auto add = [&](ulong id, long utc, const char* nm) { MqlCalendarValue v{}; v.event_id = id; v.time = calTime(utc); sim::calValues.push_back(v); if(id != 4) truth[utc + serverOffset(utc) * 3600L] = nm; };
    long d = ymd(y, m, 1); while(wday(d) != 5) d += 86400; time_t tt = d; struct tm g; gmtime_r(&tt, &g);
    add(1, nyToUtc(y, m, g.tm_mday, 8, 30), "Nonfarm Payrolls");
    long c = ymd(y, m, 13); while(wday(c) == 0 || wday(c) == 6) c += 86400; tt = c; gmtime_r(&tt, &g);
    add(2, nyToUtc(y, m, g.tm_mday, 8, 30), "CPI m/m");
    if(m % 2 == 1) { long f = ymd(y, m, 1); int k = 0; while(true) { if(wday(f) == 3 && ++k == 3) break; f += 86400; } tt = f; gmtime_r(&tt, &g); add(3, nyToUtc(y, m, g.tm_mday, 14, 0), "Fed"); }
    add(4, nyToUtc(y, m, 20, 10, 0), "Low thing");
  }
  std::sort(sim::calValues.begin(), sim::calValues.end(), [](const MqlCalendarValue& a, const MqlCalendarValue& b) { return a.time < b.time; });
  OnStart();
  // compare the file with the truth
  std::istringstream f(sim::files["common/GoldBreakout_news.csv"].content); std::string line; int ok = 0, bad = 0, lines = 0; std::string header;
  while(std::getline(f, line)) { if(!line.empty() && line.back() == '\r') line.pop_back(); if(line.empty()) continue; if(line[0] == '#') { header += line + "\n"; continue; }
    lines++; long t = StringToTime(string(line.substr(0, 16))); if(truth.count(t)) ok++; else { bad++; if(bad <= 3) std::cout << "   wrong time: " << line << "\n"; } }
  long inRange = 0; for(auto& kv : truth) if(kv.first >= StringToTime(string("2019.12.01")) ) inRange++;
  std::cout << model << "/" << calMode << ": " << lines << " lines, " << ok << " at the correct server time, " << bad << " wrong (expected " << inRange << ")\n" << header;
  for(auto& s : sim::log) if(s.find("ALERT") == 0) std::cout << "   " << s.substr(0, 400) << "\n";
  return bad == 0 && ok == inRange ? 0 : 1;
}
