// Runs GoldScalperFVG (converted to C++) on synthetic gold ticks and checks
// every decision against the written rules with an independent re-implementation.
#include "mql5_sim.h"
#include "scalp_sim.inc"

namespace oracle {
  int problems = 0;
  void fail(const std::string& m) { problems++; if(problems <= 30) std::cout << "  !! CHECK FAILED: " << m << "\n"; }
  std::string ts(datetime t) { return TimeToString(t, TIME_DATE | TIME_SECONDS).s; }
}

void generateTicks(unsigned seed, datetime start, int days, double price0) {
  std::mt19937_64 rng(seed);
  std::normal_distribution<double> N(0.0, 1.0);
  std::exponential_distribution<double> E(1.0 / 3.0);         // a tick every ~3 s
  std::uniform_real_distribution<double> U(0.0, 1.0);
  double logp = std::log(price0), drift = 0.0, t = (double)start;
  datetime regimeEnd = start, end = start + (datetime)days * 86400;
  const double sigma = 0.0030 / std::sqrt(3600.0);
  bool wasClosed = false;
  sim::ticks.clear();
  while(t < end) {
    double dt = E(rng); t += dt;
    datetime ti = (datetime)t; time_t tt = ti; struct tm g; gmtime_r(&tt, &g);
    if(g.tm_wday == 0 || g.tm_wday == 6 || g.tm_hour == 0) { wasClosed = true; continue; }
    if(ti >= regimeEnd) { double r = U(rng); drift = (r < 0.4 ? 1 : (r < 0.8 ? -1 : 0)) * 0.0006 / 3600.0; regimeEnd = ti + (datetime)(3600 * (2 + 20 * U(rng))); }
    logp += drift * dt + sigma * std::sqrt(dt) * N(rng);
    if(U(rng) < 0.002) logp += 0.0004 * N(rng);                 // small jumps create gaps
    if(wasClosed) logp += 0.003 * N(rng);
    double bid = std::round(std::exp(logp) * 100.0) / 100.0;
    double spread = 0.25 + 0.04 * N(rng);
    if(wasClosed || (g.tm_hour == 1 && g.tm_min < 5)) spread = 0.90; else if(U(rng) < 0.01) spread = 0.80;
    spread = std::max(0.10, std::round(spread * 100.0) / 100.0);
    sim::ticks.push_back({ti, (long)(t * 1000.0), bid, std::round((bid + spread) * 100.0) / 100.0});
    wasClosed = false;
  }
}

// ---- independent rules
struct OGap { int dir; double low, high; datetime made; bool used; int entries; };
std::vector<OGap> ogaps;
int oTrend = 0;

// independent market-structure reading: swings with `st` candles each side, close beyond = break.
// brk = direction of a break made by the newest finished candle itself.
int structureNow(int tf, double& lo, double& hi, int st, int look, int& brk) {
  auto& b = sim::S(tf).bars; int m = (int)b.size() - 1;      // finished candles: 0..m-1
  lo = hi = 0; brk = 0; if(m < look) return 0;
  int first = m - look, dir = 0; double sh = 0, sl = 0; bool hOpen = false, lOpen = false;
  for(int i = first; i < m; i++) {
    int j = i - st;
    if(j - st >= first) {
      bool isH = true, isL = true;
      for(int k = j - st; k <= j + st; k++) { if(k == j) continue; if(b[k].h >= b[j].h) isH = false; if(b[k].l <= b[j].l) isL = false; }
      if(isH) { sh = b[j].h; hOpen = true; }
      if(isL) { sl = b[j].l; lOpen = true; }
    }
    if(hOpen && b[i].c > sh) { dir = 1; hOpen = false; if(i == m - 1) brk = 1; }
    if(lOpen && b[i].c < sl) { dir = -1; lOpen = false; if(i == m - 1) brk = -1; }
  }
  lo = sl; hi = sh; return dir;
}
int structureNow(int tf, double& lo, double& hi) { int brk; return structureNow(tf, lo, hi, SwingStrength, StructureLookback, brk); }
double oRangeLo = 0, oRangeHi = 0;
bool inHours(datetime t) { // trading hours, written independently
  if(TradingHourStart == TradingHourEnd || (TradingHourStart == 0 && TradingHourEnd == 24)) return true;
  int h = (int)((t % 86400) / 3600);
  return TradingHourStart < TradingHourEnd ? (h >= TradingHourStart && h < TradingHourEnd) : (h >= TradingHourStart || h < TradingHourEnd); }
int oTop = 0;
int momentumNow() {
  auto& b = sim::S(MomentumTimeframe).bars; int f = (int)b.size() - 2, L = std::max(MomentumShortCandles, MomentumLongCandles);
  if(f - L < 0) return 0;
  double now = b[f].c, s1 = b[f - MomentumShortCandles].c, s2 = b[f - MomentumLongCandles].c;
  return (now > s1 && now > s2) ? 1 : ((now < s1 && now < s2) ? -1 : 0);
}
int trendNow() {
  double lo, hi;
  oTop = structureNow(TopTimeframe, lo, hi);
  int h = structureNow(HigherTimeframe, lo, hi), m = structureNow(MiddleTimeframe, oRangeLo, oRangeHi);
  int e = 0; auto& s = sim::S(TrendTimeframe); int n = (int)s.bars.size();
  if(n >= 3) { double f = sim::emaAt(s, TrendFastEMA, n - 2), sl = sim::emaAt(s, TrendSlowEMA, n - 2); e = f > sl ? 1 : (f < sl ? -1 : 0); }
  int mo = momentumNow();
  std::vector<std::pair<bool, int>> checks = {{UseTopStructure, oTop}, {UseHigherStructure, h}, {UseMiddleStructure, m}, {UseEMAFilter, e}, {UseMomentum, mo}};
  int on = 0, up = 0, down = 0;
  for(auto& c : checks) if(c.first) { on++; up += c.second > 0; down += c.second < 0; }
  bool buy = on - up <= ChecksAllowedToDisagree && (!TopTimeframeMustAgree || oTop > 0);
  bool sell = on - down <= ChecksAllowedToDisagree && (!TopTimeframeMustAgree || oTop < 0);
  return buy == sell ? 0 : (buy ? 1 : -1);
}
int oBreak = 0; datetime oBreakCandle = 0; double oEma = 0, oPrevClose = 0;
void oracleNewCandle() {
  oTrend = trendNow();
  auto& b = sim::S(SignalTimeframe).bars; int n = (int)b.size();
  if(n < 5) return;
  const auto& c1 = b[n - 2]; const auto& c3 = b[n - 4];
  for(size_t i = ogaps.size(); i-- > 0;) {
    const OGap& g = ogaps[i];
    bool broken = (g.dir > 0 && c1.c < g.low) || (g.dir < 0 && c1.c > g.high);
    bool old = (c1.t - g.made) >= (long)GapExpiryCandles * PeriodSeconds(SignalTimeframe);
    if(g.used || broken || old || g.dir != oTrend) ogaps.erase(ogaps.begin() + i);
  }
  if(UseGapEntries && oTrend > 0 && c1.l > c3.h && c1.l - c3.h >= MinGapUSD) ogaps.push_back({1, c3.h, c1.l, c1.t, false, 0});
  if(UseGapEntries && oTrend < 0 && c3.l > c1.h && c3.l - c1.h >= MinGapUSD) ogaps.push_back({-1, c1.h, c3.l, c1.t, false, 0});
  if(ogaps.size() > MAX_GAPS) ogaps.erase(ogaps.begin());
  // entry kind 2 (break of a small 1-minute swing) and kind 3 (EMA pullback)
  oBreak = 0;
  if(UseBreakEntries && oTrend != 0) {
    double lo, hi; int brk; structureNow(SignalTimeframe, lo, hi, EntrySwingStrength, EntryStructureLookback, brk);
    if(brk == oTrend) { oBreak = brk; oBreakCandle = b[n - 1].t; }
  }
  oEma = UsePullbackEntries ? sim::emaAt(sim::S(SignalTimeframe), PullbackEMA, n - 2) : 0; oPrevClose = c1.c;
}
// which entry kind the rules allow on this tick (0 none, 1 gap, 2 break, 3 pullback)
int kindNow(int pick, double bid, datetime candle) {
  if(oTrend == 0) return 0;
  if(pick >= 0) return 1;
  if(UseBreakEntries && oBreak == oTrend && oBreakCandle == candle) return 2;
  if(UsePullbackEntries && oEma > 0 && ((oTrend > 0 && oPrevClose > oEma && bid <= oEma) || (oTrend < 0 && oPrevClose < oEma && bid >= oEma))) return 3;
  return 0;
}
int pickGap(double bid) {
  for(int i = (int)ogaps.size() - 1; i >= 0; i--)
    if(UseGapEntries && !ogaps[i].used && ogaps[i].dir == oTrend && bid >= ogaps[i].low && bid <= ogaps[i].high) return i;
  return -1;
}

double oPeak = 0, oDayBal = 0; long oDay = -1; bool oDayHit = false, oKill = false;
void oracleSafety() {
  double eq = sim::equity(); long day = (long)sim::now.t / 86400;
  if(day != oDay) { oDay = day; oDayBal = sim::balance; oDayHit = false; }
  if(DailyLossLimitPercent > 0 && eq <= oDayBal * (1 - DailyLossLimitPercent / 100.0)) oDayHit = true;
  if(eq > oPeak) oPeak = eq;
  if(KillSwitchDrawdownPercent > 0 && eq <= oPeak * (1 - KillSwitchDrawdownPercent / 100.0)) oKill = true;
}

std::vector<std::string> splitCsv(const std::string& line) { std::vector<std::string> r; std::string cur; for(char c : line) { if(c == ',') { r.push_back(cur); cur.clear(); } else if(c != '\r') cur += c; } r.push_back(cur); return r; }

int main(int argc, char** argv) {
  unsigned seed = argc > 1 ? (unsigned)atoi(argv[1]) : 1;
  int days = argc > 2 ? atoi(argv[2]) : 60;
  sim::quiet = true;
  if(getenv("SIM_LIVE")) sim::isTester = false;
  datetime warmStart = 1672617600, testStart = warmStart + 90 * 86400;     // 90 days of history for the 4-hour structure
  generateTicks(seed, warmStart, 90 + days, 4000.0);
  sim::initSeries();
  size_t k = 0;
  for(; k < sim::ticks.size() && sim::ticks[k].t < testStart; k++) { sim::now = sim::ticks[k]; sim::updateSeries(sim::now); }
  sim::now = sim::ticks[k];
  int rc = OnInit();
  if(rc != 0) { std::cout << "OnInit returned " << rc << "\n"; return 2; }
  datetime lastCandle = iTime(_Symbol, SignalTimeframe, 0);
  std::set<long> known; std::set<datetime> enteredCandles;
  std::map<long, std::string> expected, kindOf; std::set<long> killIds; int kindCount[4] = {0, 0, 0, 0};
  int opened = 0, maxOpenSeen = 0, missed = 0, buys = 0, sells = 0;
  for(; k < sim::ticks.size(); k++) {
    sim::now = sim::ticks[k]; sim::updateSeries(sim::now);
    sim::checkStops();
    datetime candle = iTime(_Symbol, SignalTimeframe, 0);
    bool newCandle = candle != lastCandle;
    if(newCandle) { lastCandle = candle; oracleNewCandle(); }
    oracleSafety();
    int openBefore = (int)sim::positions.size();
    double spread = sim::now.ask - sim::now.bid;
    int pick = pickGap(sim::now.bid);
    int kind = kindNow(pick, sim::now.bid, candle);
    if(kind > 0 && UsePremiumDiscount && oRangeHi > oRangeLo) { double mid = (oRangeHi + oRangeLo) / 2; if((oTrend > 0 && sim::now.bid > mid) || (oTrend < 0 && sim::now.bid < mid)) kind = 0; }
    int againstBefore = 0; if(newCandle && CloseOnTrendChange && oTrend != 0) for(auto& p : sim::positions) if((p.type == POSITION_TYPE_BUY ? 1 : -1) == -oTrend) againstBefore++;
    int openAfterFlip = (int)sim::positions.size() - againstBefore;
    (void)openBefore;
    bool shouldEnter = kind > 0 && openAfterFlip < MaxOpenTrades && !enteredCandles.count(candle) && !oDayHit && !oKill &&
                       !(MaxSpreadUSD > 0 && spread > MaxSpreadUSD + 1e-9) && inHours(sim::now.t);
    OnTick();
    if(!sim::closeEvents.empty()) OnTrade();
    if(oKill != g_killSwitchOn) oracle::fail("kill switch state differs from the rule at " + oracle::ts(sim::now.t));
    if(oKill && !sim::positions.empty()) oracle::fail("kill switch on but trades still open at " + oracle::ts(sim::now.t));
    if(newCandle && CloseOnTrendChange && oTrend != 0) for(auto& p : sim::positions) if((p.type == POSITION_TYPE_BUY ? 1 : -1) == -oTrend) oracle::fail("trade against the new direction left open at " + oracle::ts(sim::now.t));
    if(!g_killSwitchOn && g_trendDir != oTrend) oracle::fail("trend differs from the rule at " + oracle::ts(sim::now.t));
    int newOnes = 0;
    for(auto& p : sim::positions) {
      if(known.count(p.id)) continue;
      known.insert(p.id); newOnes++; opened++;
      int dir = p.type == POSITION_TYPE_BUY ? 1 : -1; (dir > 0 ? buys : sells)++;
      if(!shouldEnter) oracle::fail("trade opened although the rules say no entry at " + oracle::ts(sim::now.t));
      if(dir != oTrend) oracle::fail("trade against the trend at " + oracle::ts(sim::now.t));
      if(kind == 1 && ++ogaps[pick].entries >= EntriesPerGap) ogaps[pick].used = true;
      const char* kn[] = {"?", "gap", "break", "pullback"};
      if(p.comment != std::string("GSF ") + kn[kind]) oracle::fail("entry kind '" + p.comment + "' but the rules say " + kn[kind] + " at " + oracle::ts(sim::now.t));
      kindOf[p.id] = kn[kind]; kindCount[kind]++;
      enteredCandles.insert(candle);
      double margin = p.volume * sim::contract * p.open / sim::leverage, perPrice = p.volume * sim::contract;
      double wantTp = TakeProfitPercentOfMargin / 100.0 * margin / perPrice, wantSl = StopLossPercentOfMargin / 100.0 * margin / perPrice;
      if(std::fabs(dir * (p.tp - p.open) - wantTp) > 0.011) { char b[160]; snprintf(b, sizeof b, "take-profit distance %.2f, rule %.2f at %s", dir * (p.tp - p.open), wantTp, oracle::ts(sim::now.t).c_str()); oracle::fail(b); }
      if(std::fabs(dir * (p.open - p.sl) - wantSl) > 0.011) { char b[160]; snprintf(b, sizeof b, "stop-loss distance %.2f, rule %.2f at %s", dir * (p.open - p.sl), wantSl, oracle::ts(sim::now.t).c_str()); oracle::fail(b); }
      if(std::fabs(p.volume - LotSize) > 1e-9) oracle::fail("lot size differs at " + oracle::ts(sim::now.t));
    }
    if(newOnes > 1) oracle::fail("more than one trade in one tick at " + oracle::ts(sim::now.t));
    if(shouldEnter && newOnes == 0) { missed++; oracle::fail("entry missed at " + oracle::ts(sim::now.t)); }
    if((int)sim::positions.size() > MaxOpenTrades) oracle::fail("more than MaxOpenTrades open at " + oracle::ts(sim::now.t));
    maxOpenSeen = std::max(maxOpenSeen, (int)sim::positions.size());
    for(auto& c : sim::closeEvents) {
      std::string r = c.reason == DEAL_REASON_TP ? "take-profit" : (c.reason == DEAL_REASON_SL ? "stop-loss" : (oKill ? "kill switch" : "trend changed"));
      expected[c.posId] = r;
    }
    sim::closeEvents.clear();
  }
  OnDeinit(0);
  std::string csvKey; for(auto& f : sim::files) if(f.first.find("files/GoldScalper_") == 0) csvKey = f.first;
  std::istringstream csv(csvKey.empty() ? std::string() : sim::files[csvKey].content);
  std::string line; int rows = 0; std::getline(csv, line);
  if(line.rfind("OpenTime,CloseTime,Direction", 0) != 0) oracle::fail("CSV header missing");
  std::map<std::string, int> reasons; std::set<long> seen;
  while(std::getline(csv, line)) {
    if(line.empty() || line == "\r") continue; rows++;
    auto c = splitCsv(line); if(c.size() != 14) { oracle::fail("CSV row with " + std::to_string(c.size()) + " columns"); continue; }
    long id = atol(c[10].c_str()); reasons[c[8]]++;
    if(seen.count(id)) oracle::fail("trade logged twice"); seen.insert(id);
    if(c[13] != kindOf[id]) oracle::fail("CSV entry kind '" + c[13] + "' but the trade was opened as " + kindOf[id]);
    if(!expected.count(id)) { if(c[8].find("end of test") == std::string::npos) oracle::fail("CSV row for a trade that did not close: " + line); continue; }
    if(c[8] != expected[id]) oracle::fail("exit reason '" + c[8] + "' but should be '" + expected[id] + "'");
    double net = 0; for(auto& d : sim::deals) if(d.posId == id) net += d.profit + d.commission + d.swap + d.fee;
    if(std::fabs(net - atof(c[7].c_str())) > 0.011) oracle::fail("CSV profit differs: " + line);
  }
  for(auto& e : expected) if(!seen.count(e.first)) oracle::fail("closed trade missing from CSV");
  printf("trades %d (buy %d / sell %d; gap %d, break %d, pullback %d) = %.1f per day | most open at once %d | balance %.2f | CSV rows %d | missed %d |",
         opened, buys, sells, kindCount[1], kindCount[2], kindCount[3], opened / (double)days, maxOpenSeen, sim::balance, rows, missed);
  for(auto& r : reasons) printf(" [%s]=%d", r.first.c_str(), r.second);
  printf(" | kill switch %s | checks failed %d\n", g_killSwitchOn ? "ON" : "off", oracle::problems);
  return oracle::problems == 0 ? 0 : 1;
}
