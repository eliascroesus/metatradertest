// Runs the EA (converted to C++) on synthetic gold ticks and independently
// checks its decisions against the written rules.
#include "mql5_sim.h"
#include "ea_sim.inc"

namespace oracle {
  int problems = 0;
  void fail(const std::string& m) { problems++; if(problems <= 40) std::cout << "  !! CHECK FAILED: " << m << "\n"; }
  std::string ts(datetime t) { return TimeToString(t, TIME_DATE | TIME_SECONDS).s; }
}

// --------------------------------------------------------------------------- synthetic market
void generateTicks(unsigned seed, datetime start, int days, double price0) {
  std::mt19937_64 rng(seed);
  std::normal_distribution<double> N(0.0, 1.0);
  std::exponential_distribution<double> E(1.0 / 12.0);        // a tick every ~12 s
  std::uniform_real_distribution<double> U(0.0, 1.0);
  double logp = std::log(price0), drift = 0.0, t = (double)start;
  datetime regimeEnd = start, end = start + (datetime)days * 86400;
  const double sigma = 0.0030 / std::sqrt(3600.0);             // ~0.30% per hour
  bool wasClosed = false;
  sim::ticks.clear();
  while(t < end) {
    t += E(rng);
    datetime ti = (datetime)t; time_t tt = ti; struct tm g; gmtime_r(&tt, &g);
    bool closed = (g.tm_wday == 0 || g.tm_wday == 6 || g.tm_hour == 0);   // weekends + daily break 00:00-01:00
    if(closed) { wasClosed = true; continue; }
    if(ti >= regimeEnd) { double r = U(rng); drift = (r < 0.4 ? 1 : (r < 0.8 ? -1 : 0)) * 0.0004 / 3600.0; regimeEnd = ti + (datetime)(86400 * (3 + 12 * U(rng))); }
    double dt = 12.0;
    logp += drift * dt + sigma * std::sqrt(dt) * N(rng);
    if(wasClosed) logp += 0.003 * N(rng);                        // opening gap
    if(U(rng) < 2e-6) logp += (U(rng) < 0.5 ? -1 : 1) * 0.012;   // rare shock (tests stop slippage)
    double bid = std::round(std::exp(logp) * 100.0) / 100.0;
    double spread = 0.25 + 0.04 * N(rng);
    if(wasClosed || (g.tm_hour == 1 && g.tm_min < 5)) spread = 0.90;       // wide at the open
    else if(U(rng) < 0.01) spread = 0.80;
    spread = std::max(0.10, std::round(spread * 100.0) / 100.0);
    sim::ticks.push_back({ti, (long)(t * 1000.0), bid, std::round((bid + spread) * 100.0) / 100.0});
    wasClosed = false;
  }
}

// --------------------------------------------------------------------------- independent rule checks
struct Expect { int dir; double close1, breakHigh, breakLow, trendClose, ema, atr; };

double atrNow() { auto& s = sim::S(ATRTimeframe); int na = (int)s.bars.size(); return na >= ATRPeriod + 2 ? sim::atrAt(s, ATRPeriod, na - 2) : 0.0; }

Expect expectedSignal() {
  Expect e{0, 0, 0, 0, 0, 0, 0};
  auto& h1 = sim::S(EntryTimeframe).bars; auto& h4 = sim::S(TrendTimeframe).bars;
  int n = (int)h1.size(), m = (int)h4.size();
  if(n < BreakoutLookbackCandles + 2 || m < 3) return e;
  e.close1 = h1[n - 2].c; e.breakHigh = -1e18; e.breakLow = 1e18;
  for(int i = n - 2 - BreakoutLookbackCandles; i <= n - 3; i++) { e.breakHigh = std::max(e.breakHigh, h1[i].h); e.breakLow = std::min(e.breakLow, h1[i].l); }
  e.trendClose = h4[m - 2].c; e.ema = sim::emaAt(sim::S(TrendTimeframe), TrendEMAPeriod, m - 2);
  e.atr = atrNow();
  if(e.trendClose > e.ema && e.close1 > e.breakHigh) e.dir = 1;
  if(e.trendClose < e.ema && e.close1 < e.breakLow) e.dir = -1;
  return e;
}

bool listedNewsNear(datetime now) {
  for(int i = 0; i < ArraySize(g_newsTimes); i++) { long t = g_newsTimes[i]; if(now >= t - NewsMinutesBefore * 60 && now <= t + NewsMinutesAfter * 60) return true; }
  return false;
}

struct Tracked { long id; int type; double open, risk, best, lastSl; bool beDone; double spreadAtEntry; };
std::map<long, Tracked> tracked;
std::map<long, std::string> expectedReason;
std::set<long> killClosed;

double oPeak = 0, oDayBal = 0; long oDay = -1; bool oDayHit = false, oKill = false;
int opened = 0, longs = 0, shorts = 0, missed = 0, skippedLogged = 0, entriesAfterKill = 0;

// Safety switches, judged on what the EA sees at the start of its tick.
void oracleSafety() {
  double eq = sim::equity();
  long day = (long)sim::now.t / 86400;
  if(day != oDay) { bool first = oDay < 0; oDay = day; if(first || true) oDayBal = sim::balance; oDayHit = false; }
  if(DailyLossLimitPercent > 0 && eq <= oDayBal * (1 - DailyLossLimitPercent / 100.0)) oDayHit = true;
  if(eq > oPeak) oPeak = eq;
  if(KillSwitchDrawdownPercent > 0 && eq <= oPeak * (1 - KillSwitchDrawdownPercent / 100.0)) oKill = true;
}

void checkManagement(const std::map<long, double>& slBefore) {
  using namespace sim;
  for(auto& p : positions) {
    auto it = tracked.find(p.id); if(it == tracked.end()) continue; Tracked& tr = it->second;
    int dir = p.type == POSITION_TYPE_BUY ? 1 : -1;
    double before = slBefore.count(p.id) ? slBefore.at(p.id) : p.sl;
    if(dir * (p.sl - before) < -1e-9) oracle::fail("stop moved BACKWARDS at " + oracle::ts(now.t));
    double px = dir > 0 ? now.bid : now.ask;
    if(dir * (px - tr.best) > 0) tr.best = px;
    double profit = dir * (tr.best - tr.open), atr = atrNow();
    if(std::fabs(atr - g_atr) > 1e-9) oracle::fail("EA ATR differs from the last finished candle's ATR at " + oracle::ts(now.t));
    if(!tr.beDone && profit >= BreakEvenTriggerMultiple * tr.risk - 1e-5) {
      double be = std::round((tr.open + dir * BreakEvenExtraUSD) / point) * point;
      if(dir * (p.sl - be) < -point * 0.5) { char b[180]; snprintf(b, sizeof b, "break-even not applied (profit %.2f >= risk %.2f, stop %.2f) at %s", profit, tr.risk, p.sl, oracle::ts(now.t).c_str()); oracle::fail(b); }
      tr.beDone = true;
    }
    if(!tr.beDone && dir * (p.sl - before) > 1e-9) oracle::fail("stop moved before break-even was due at " + oracle::ts(now.t));
    if(tr.beDone) {
      double trail = dir > 0 ? std::floor((tr.best - TrailingStopATRMultiplier * atr) / point + 1e-8) * point
                             : std::ceil((tr.best + TrailingStopATRMultiplier * atr) / point - 1e-8) * point;
      double step = std::max(TrailingStepATR * atr, point);
      double lvl = sim::stopsLevelPoints * point;
      bool allowed = dir > 0 ? (now.bid - trail >= lvl + point * 0.5) : (trail - now.ask >= lvl + point * 0.5);
      if(!allowed) trail = dir > 0 ? std::floor((now.bid - lvl - point) / point + 1e-8) * point : std::ceil((now.ask + lvl + point) / point - 1e-8) * point;
      if(dir * (trail - p.sl) >= step + point * 0.01) { char b[400]; snprintf(b, sizeof b, "trailing stop lags: stop %.2f, trail level %.2f, step %.2f at %s | EA: stage %d best %.2f atr %.4f retryAfter %s | oracle best %.2f bid %.2f ask %.2f dir %d", p.sl, trail, step, oracle::ts(now.t).c_str(), g_tradeStage, g_tradeBest, g_atr, oracle::ts(g_modifyRetryAfter).c_str(), tr.best, now.bid, now.ask, dir); oracle::fail(b); }
      bool moved = std::fabs(p.sl - before) > 1e-9;
      bool isBe = std::fabs(p.sl - std::round((tr.open + dir * BreakEvenExtraUSD) / point) * point) < point * 0.5;
      if(moved && !isBe && std::fabs(p.sl - trail) > point * 0.51) { char b[200]; snprintf(b, sizeof b, "trailing stop set to %.2f but the rule gives %.2f at %s", p.sl, trail, oracle::ts(now.t).c_str()); oracle::fail(b); }
    }
  }
}

void checkEntries(bool newCandle, bool flatBefore, const Expect& ex, size_t logBefore, double balanceAtTick, double spreadNow) {
  using namespace sim;
  for(auto& p : positions) {
    if(tracked.count(p.id)) continue;
    opened++; (p.type == POSITION_TYPE_BUY ? longs : shorts)++;
    tracked[p.id] = Tracked{p.id, p.type, p.open, std::fabs(p.open - p.sl), p.open, p.sl, false, spreadNow};
    int dir = p.type == POSITION_TYPE_BUY ? 1 : -1;
    if(oKill) entriesAfterKill++;
    if(!newCandle) oracle::fail("entry not on the first tick of a new candle at " + oracle::ts(now.t));
    if(!flatBefore) oracle::fail("entry while another trade was open at " + oracle::ts(now.t));
    if(oDayHit) oracle::fail("entry after the daily loss limit at " + oracle::ts(now.t));
    if(oKill) oracle::fail("entry after the kill switch at " + oracle::ts(now.t));
    if(MaxSpreadUSD > 0 && spreadNow > MaxSpreadUSD + 1e-9) oracle::fail("entry with spread above max at " + oracle::ts(now.t));
    if(UseNewsFilter && listedNewsNear(now.t)) oracle::fail("entry inside a news blackout at " + oracle::ts(now.t));
    if(!RandomEntryMode && dir != ex.dir) oracle::fail("entry direction does not match the rule at " + oracle::ts(now.t));
    double wantDist = InitialStopATRMultiplier * ex.atr;
    double wantSl = dir > 0 ? std::floor((p.open - wantDist) / point + 1e-8) * point : std::ceil((p.open + wantDist) / point - 1e-8) * point;
    if(std::fabs(p.sl - wantSl) > point * 0.51) { char b[220]; snprintf(b, sizeof b, "initial stop %.2f, rule says %.2f (entry %.2f, ATR %.4f) at %s", p.sl, wantSl, p.open, ex.atr, oracle::ts(now.t).c_str()); oracle::fail(b); }
    double lossPerLot = std::fabs(p.open - p.sl) / 0.01 * 1.0;
    double lots = std::floor(balanceAtTick * RiskPercentPerTrade / 100.0 / lossPerLot / 0.01 + 1e-8) * 0.01;
    if(lots < 0.01) lots = 0.01;
    if(std::fabs(lots - p.volume) > 1e-9) { char b[200]; snprintf(b, sizeof b, "lot size %.2f, rule says %.2f at %s", p.volume, lots, oracle::ts(now.t).c_str()); oracle::fail(b); }
    if(p.volume * lossPerLot / balanceAtTick * 100.0 > MaxRiskPercentAtMinLot + 1e-9) oracle::fail("trade risks more than MaxRiskPercentAtMinLot at " + oracle::ts(now.t));
  }
  if(!RandomEntryMode && newCandle && flatBefore && ex.dir != 0 && positions.empty()) {
    bool blocked = oDayHit || oKill || ResetKillSwitch || (MaxSpreadUSD > 0 && spreadNow > MaxSpreadUSD + 1e-9) || (UseNewsFilter && listedNewsNear(now.t));
    bool explained = false;
    for(size_t i = logBefore; i < sim::log.size(); i++) if(sim::log[i].find("skipped") != std::string::npos) explained = true;
    if(explained) skippedLogged++;
    if(!blocked && !explained) { missed++; oracle::fail("signal missed at " + oracle::ts(now.t)); }
  }
}

std::string reasonFor(const sim::CloseEvent& c) {
  if(c.reason == DEAL_REASON_EXPERT) return killClosed.count(c.posId) ? "kill switch" : "closed by EA";
  int dir = c.type == POSITION_TYPE_BUY ? 1 : -1;
  double be = std::round((c.open + dir * BreakEvenExtraUSD) / sim::point) * sim::point;
  double d = dir * (c.sl - be);
  if(d < -0.005) return "stop";
  if(d <= 0.005) return "break-even";
  return "trailing";
}

std::vector<std::string> splitCsv(const std::string& line) { std::vector<std::string> r; std::string cur; for(char c : line) { if(c == ',') { r.push_back(cur); cur.clear(); } else if(c != '\r') cur += c; } r.push_back(cur); return r; }

// A full terminal restart: the EA's memory is wiped, only saved values survive.
void wipeEaMemory() {
  ForgetTrade(); g_lastDecisionCandle = 0; g_lastAtrCandle = 0; g_atr = 0; g_trendDir = 0; g_breakoutDir = 0;
  g_peakEquity = 0; g_killSwitchOn = false; g_dayNumber = -1; g_dayStartBalance = 0; g_dailyLimitHit = false;
  g_modifyRetryAfter = 0; g_closeRetryAfter = 0; ArrayResize(g_newsTimes, 0); g_csvFile = "";
}

int main(int argc, char** argv) {
  unsigned seed = argc > 1 ? (unsigned)atoi(argv[1]) : 1;
  int days = argc > 2 ? atoi(argv[2]) : 365;
  sim::quiet = argc > 3 && std::string(argv[3]) == "quiet";
  if(getenv("SIM_COMMISSION")) sim::commissionPerLotSide = atof(getenv("SIM_COMMISSION"));
  if(getenv("SIM_STOPSLEVEL")) sim::stopsLevelPoints = atoi(getenv("SIM_STOPSLEVEL"));
  if(getenv("SIM_LIVE")) sim::isTester = false;
  if(getenv("SIM_NEWSFILE")) { std::ifstream f(getenv("SIM_NEWSFILE")); std::stringstream b; b << f.rdbuf(); sim::files["common/" + std::string(NewsTimesFile.s)].content = b.str(); }
  int restartEvery = getenv("SIM_RESTART_EVERY") ? atoi(getenv("SIM_RESTART_EVERY")) : 0;
  int offlineTicks = getenv("SIM_OFFLINE_TICKS") ? atoi(getenv("SIM_OFFLINE_TICKS")) : 0;

  datetime warmStart = 1672617600;                       // 2023-01-02 00:00 (Monday)
  datetime testStart = warmStart + 60 * 86400;
  generateTicks(seed, warmStart, 60 + days, 1850.0);
  sim::initSeries();
  size_t k = 0;
  for(; k < sim::ticks.size() && sim::ticks[k].t < testStart; k++) { sim::now = sim::ticks[k]; sim::updateSeries(sim::now); }
  if(k < sim::ticks.size()) sim::now = sim::ticks[k];
  int rc = OnInit();
  std::cout << "OnInit returned " << rc << "\n";
  if(rc != 0) return 2;
  datetime lastCandle = iTime(_Symbol, EntryTimeframe, 0);
  long tickNo = 0; int offline = 0;
  for(; k < sim::ticks.size(); k++) {
    sim::now = sim::ticks[k]; sim::updateSeries(sim::now);
    sim::checkStops();
    datetime candle = iTime(_Symbol, EntryTimeframe, 0);
    bool newCandle = candle != lastCandle; lastCandle = candle;
    if(offline > 0) {                                      // EA switched off: the broker still triggers stops
      for(auto& c : sim::closeEvents) expectedReason[c.posId] = reasonFor(c);
      sim::closeEvents.clear();
      if(--offline == 0) { wipeEaMemory(); if(OnInit() != 0) { std::cout << "re-init failed\n"; return 3; } lastCandle = iTime(_Symbol, EntryTimeframe, 0); }
      continue;
    }
    oracleSafety();
    std::map<long, double> slBefore; for(auto& p : sim::positions) slBefore[p.id] = p.sl;
    std::set<long> openBefore; for(auto& p : sim::positions) openBefore.insert(p.id);
    bool flatBefore = sim::positions.empty();
    double balanceAtTick = sim::balance, spreadNow = sim::now.ask - sim::now.bid;
    Expect ex = newCandle ? expectedSignal() : Expect{0, 0, 0, 0, 0, 0, 0};
    size_t logBefore = sim::log.size();
    OnTick();
    if(!sim::closeEvents.empty()) OnTrade();
    if(oKill) for(auto& c : sim::closeEvents) if(c.reason == DEAL_REASON_EXPERT) killClosed.insert(c.posId);
    if(oKill != g_killSwitchOn) oracle::fail(std::string("kill switch ") + (g_killSwitchOn ? "ON" : "off") + " but the rule says " + (oKill ? "ON" : "off") + " at " + oracle::ts(sim::now.t));
    if(g_dailyLimitHit != oDayHit) oracle::fail(std::string("daily limit flag ") + (g_dailyLimitHit ? "ON" : "off") + " but the rule says " + (oDayHit ? "ON" : "off") + " at " + oracle::ts(sim::now.t));
    if(oKill && !sim::positions.empty()) oracle::fail("kill switch active but a trade is still open at " + oracle::ts(sim::now.t));
    checkManagement(slBefore);
    checkEntries(newCandle, flatBefore, ex, logBefore, balanceAtTick, spreadNow);
    for(auto& c : sim::closeEvents) expectedReason[c.posId] = reasonFor(c);
    sim::closeEvents.clear();
    if(restartEvery > 0 && ++tickNo % restartEvery == 0) {
      OnDeinit(1);
      sim::inds.clear();
      if(offlineTicks > 0) offline = offlineTicks;
      else { wipeEaMemory(); if(OnInit() != 0) { std::cout << "re-init failed\n"; return 3; } lastCandle = iTime(_Symbol, EntryTimeframe, 0); }
    }
  }
  OnDeinit(0);

  // ----- compare the CSV with what really happened
  std::string csvKey;
  for(auto& f : sim::files) if(f.first.find("files/GoldBreakout_") == 0) csvKey = f.first;
  std::istringstream csv(csvKey.empty() ? std::string() : sim::files[csvKey].content);
  std::string line; int rows = 0; std::getline(csv, line);
  if(line.rfind("OpenTime,CloseTime,Direction", 0) != 0) oracle::fail("CSV header missing: " + line);
  std::map<std::string, int> reasonCount; std::set<long> seen;
  while(std::getline(csv, line)) {
    if(line.empty() || line == "\r") continue; rows++;
    auto c = splitCsv(line);
    if(c.size() != 13) { oracle::fail("CSV row has " + std::to_string(c.size()) + " columns: " + line); continue; }
    long id = atol(c[11].c_str()); reasonCount[c[8]]++;
    if(seen.count(id)) oracle::fail("trade logged twice: " + line);
    seen.insert(id);
    if(!expectedReason.count(id)) { if(c[8].find("end of test") == std::string::npos) oracle::fail("CSV row for a trade that did not close: " + line); continue; }
    if(c[8] != expectedReason[id]) oracle::fail("exit reason '" + c[8] + "' but the rule says '" + expectedReason[id] + "': " + line);
    double net = 0; for(auto& d : sim::deals) if(d.posId == id) net += d.profit + d.commission + d.swap + d.fee;
    if(std::fabs(net - atof(c[7].c_str())) > 0.011) oracle::fail("CSV profit differs from the account: " + line);
    auto tr = tracked.find(id);
    if(tr != tracked.end() && c[6] != "n/a" && std::fabs(atof(c[6].c_str()) - tr->second.spreadAtEntry) > 0.0051) oracle::fail("CSV spread differs: " + line);
  }
  for(auto& e : expectedReason) if(!seen.count(e.first)) oracle::fail("closed trade missing from the CSV: position " + std::to_string(e.first));
  double years = (double)(sim::ticks.back().t - testStart) / 31557600.0;
  std::cout << "\n==== RESULT (seed " << seed << ", " << days << " days, " << sim::ticks.size() << " ticks) ====\n";
  printf("balance %.2f | trades %d (long %d / short %d) = %.1f per year | closed %d | CSV rows %d | missed %d | skipped-with-reason %d\n",
         sim::balance, opened, longs, shorts, opened / years, (int)expectedReason.size(), rows, missed, skippedLogged);
  std::cout << "exit reasons in CSV:"; for(auto& r : reasonCount) std::cout << "  [" << r.first << "]=" << r.second; std::cout << "\n";
  std::cout << "kill switch " << (g_killSwitchOn ? "ON" : "off") << " | checks failed: " << oracle::problems << "\n";
  return oracle::problems == 0 ? 0 : 1;
}
