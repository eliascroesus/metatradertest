// Runs GoldTrendStacker (converted to C++) on synthetic gold ticks and checks every
// decision against the written rules with an independent re-implementation.
#include "mql5_sim.h"
#include "stack_sim.inc"

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
struct Expect { int dir; double atr; };
double atrNow() { auto& s = sim::S(ATRTimeframe); int na = (int)s.bars.size(); return na >= ATRPeriod + 2 ? sim::atrAt(s, ATRPeriod, na - 2) : 0.0; }
// 4-hour close vs EMA and a close beyond the previous BreakoutLookbackCandles candles, written independently
Expect expectedSignal() {
  Expect e{0, atrNow()};
  auto& h1 = sim::S(EntryTimeframe).bars; auto& h4 = sim::S(TrendTimeframe).bars;
  int n = (int)h1.size(), m = (int)h4.size();
  if(n < BreakoutLookbackCandles + 2 || m < 3) return e;
  double hi = -1e18, lo = 1e18;
  for(int i = n - 2 - BreakoutLookbackCandles; i <= n - 3; i++) { hi = std::max(hi, h1[i].h); lo = std::min(lo, h1[i].l); }
  double c = h1[n - 2].c, tc = h4[m - 2].c, ema = sim::emaAt(sim::S(TrendTimeframe), TrendEMAPeriod, m - 2);
  if(tc > ema && c > hi) e.dir = 1;
  if(tc < ema && c < lo) e.dir = -1;
  return e;
}
bool listedNewsNear(datetime now) {
  for(int i = 0; i < ArraySize(g_newsTimes); i++) { long t = g_newsTimes[i]; if(now >= t - NewsMinutesBefore * 60 && now <= t + NewsMinutesAfter * 60) return true; }
  return false;
}
int dirOf(const sim::Pos& p) { return p.type == POSITION_TYPE_BUY ? 1 : -1; }
double bePrice(double open) { return std::round(open / sim::point) * sim::point; }
bool isProtected(const sim::Pos& p) { return dirOf(p) * (p.sl - bePrice(p.open)) >= -sim::point * 0.5; }

struct Tracked { double open, risk, best; bool beDone; double spreadAtEntry; std::string kind; };
std::map<long, Tracked> tracked;
std::map<long, std::string> expectedReason;
std::set<long> killClosed, oppositeClosed;
double oPeak = 0, oDayBal = 0; long oDay = -1; bool oDayHit = false, oKill = false;
int opened = 0, stackedN = 0, longs = 0, shorts = 0, missed = 0, skippedLogged = 0, maxOpen = 0;

void oracleSafety() {
  double eq = sim::equity(); long day = (long)sim::now.t / 86400;
  if(day != oDay) { oDay = day; oDayBal = sim::balance; oDayHit = false; }
  if(DailyLossLimitPercent > 0 && eq <= oDayBal * (1 - DailyLossLimitPercent / 100.0)) oDayHit = true;
  if(eq > oPeak) oPeak = eq;
  if(KillSwitchDrawdownPercent > 0 && eq <= oPeak * (1 - KillSwitchDrawdownPercent / 100.0)) oKill = true;
}

// break-even and trailing, per trade
void checkManagement(const std::map<long, double>& slBefore) {
  using namespace sim;
  double atr = atrNow();
  if(!positions.empty() && std::fabs(atr - g_atr) > 1e-9) oracle::fail("EA ATR differs from the last finished candle's ATR at " + oracle::ts(now.t));
  for(auto& p : positions) {
    auto it = tracked.find(p.id); if(it == tracked.end() || !slBefore.count(p.id)) continue; Tracked& tr = it->second;
    int dir = dirOf(p); double before = slBefore.at(p.id);
    if(dir * (p.sl - before) < -1e-9) oracle::fail("stop moved BACKWARDS at " + oracle::ts(now.t));
    double px = dir > 0 ? now.bid : now.ask;
    if(dir * (px - tr.best) > 0) tr.best = px;
    double profit = dir * (tr.best - tr.open);
    if(!tr.beDone && profit >= BreakEvenTriggerMultiple * tr.risk - 1e-5) {
      if(dir * (p.sl - bePrice(tr.open)) < -point * 0.5) { char b[180]; snprintf(b, sizeof b, "break-even not applied (profit %.2f >= risk %.2f, stop %.2f) at %s", profit, tr.risk, p.sl, oracle::ts(now.t).c_str()); oracle::fail(b); }
      tr.beDone = true;
    }
    if(!tr.beDone && dir * (p.sl - before) > 1e-9) oracle::fail("stop moved before break-even was due at " + oracle::ts(now.t));
    if(tr.beDone) {
      double trail = dir > 0 ? std::floor((tr.best - TrailingStopATRMultiplier * atr) / point + 1e-8) * point
                             : std::ceil((tr.best + TrailingStopATRMultiplier * atr) / point - 1e-8) * point;
      double step = std::max(TrailingStepATR * atr, point), lvl = sim::stopsLevelPoints * point;
      bool allowed = dir > 0 ? (now.bid - trail >= lvl + point * 0.5) : (trail - now.ask >= lvl + point * 0.5);
      if(!allowed) trail = dir > 0 ? std::floor((now.bid - lvl - point) / point + 1e-8) * point : std::ceil((now.ask + lvl + point) / point - 1e-8) * point;
      if(dir * (trail - p.sl) >= step + point * 0.01) { char b[220]; snprintf(b, sizeof b, "trailing stop lags: stop %.2f, trail level %.2f, step %.2f at %s", p.sl, trail, step, oracle::ts(now.t).c_str()); oracle::fail(b); }
      bool moved = std::fabs(p.sl - before) > 1e-9, isBe = std::fabs(p.sl - bePrice(tr.open)) < point * 0.5;
      if(moved && !isBe && std::fabs(p.sl - trail) > point * 0.51) { char b[200]; snprintf(b, sizeof b, "trailing stop set to %.2f but the rule gives %.2f at %s", p.sl, trail, oracle::ts(now.t).c_str()); oracle::fail(b); }
    }
  }
}

void checkEntries(bool newCandle, const Expect& ex, const std::set<long>& openBefore, size_t logBefore, double balanceAtTick, double spreadNow) {
  using namespace sim;
  if(oKill) return;
  // trades that were open before this tick and still are, after the EA's stop management
  int same = 0, unprotectedSame = 0, against = 0, survivors = 0;
  for(auto& p : positions) if(openBefore.count(p.id)) { survivors++; if(dirOf(p) == ex.dir) { same++; if(!isProtected(p)) unprotectedSame++; } else against++; }
  if(newCandle && ex.dir != 0 && CloseOnOppositeBreakout && against > 0) oracle::fail("trade against the new breakout left open at " + oracle::ts(now.t));
  int newOnes = 0;
  for(auto& p : positions) {
    if(tracked.count(p.id)) continue;
    newOnes++; opened++; int dir = dirOf(p); (dir > 0 ? longs : shorts)++;
    std::string kind = same > 0 ? "stacked" : "breakout"; if(same > 0) stackedN++;
    if(p.comment != "GTS " + kind) oracle::fail("order comment '" + p.comment + "' but the rules say " + kind + " at " + oracle::ts(now.t));
    tracked[p.id] = Tracked{p.open, std::fabs(p.open - p.sl), p.open, false, spreadNow, kind};
    if(!newCandle) oracle::fail("entry not on the first tick of a new candle at " + oracle::ts(now.t));
    if(dir != ex.dir) oracle::fail("entry direction does not match the rule at " + oracle::ts(now.t));
    if(survivors >= MaxOpenTrades) oracle::fail("entry although MaxOpenTrades were open at " + oracle::ts(now.t));
    if(same > 0 && StackOnlyWhenProtected && unprotectedSame > 0) oracle::fail("stacked onto a trade that is not protected yet at " + oracle::ts(now.t));
    if(oDayHit) oracle::fail("entry after the daily loss limit at " + oracle::ts(now.t));
    if(MaxSpreadUSD > 0 && spreadNow > MaxSpreadUSD + 1e-9) oracle::fail("entry with spread above max at " + oracle::ts(now.t));
    if(UseNewsFilter && listedNewsNear(now.t)) oracle::fail("entry inside a news blackout at " + oracle::ts(now.t));
    double wantDist = InitialStopATRMultiplier * ex.atr;
    double wantSl = dir > 0 ? std::floor((p.open - wantDist) / point + 1e-8) * point : std::ceil((p.open + wantDist) / point - 1e-8) * point;
    if(std::fabs(p.sl - wantSl) > point * 0.51) { char b[220]; snprintf(b, sizeof b, "initial stop %.2f, rule says %.2f (entry %.2f, ATR %.4f) at %s", p.sl, wantSl, p.open, ex.atr, oracle::ts(now.t).c_str()); oracle::fail(b); }
    if(p.tp != 0) oracle::fail("trade has a take-profit at " + oracle::ts(now.t));
    double lossPerLot = std::fabs(p.open - p.sl) / 0.01 * 1.0;
    double lots = std::floor(balanceAtTick * RiskPercentPerTrade / 100.0 / lossPerLot / 0.01 + 1e-8) * 0.01;
    if(lots < 0.01) lots = 0.01;
    if(std::fabs(lots - p.volume) > 1e-9) { char b[200]; snprintf(b, sizeof b, "lot size %.2f, rule says %.2f at %s", p.volume, lots, oracle::ts(now.t).c_str()); oracle::fail(b); }
    if(p.volume * lossPerLot / balanceAtTick * 100.0 > MaxRiskPercentAtMinLot + 1e-9) oracle::fail("trade risks more than MaxRiskPercentAtMinLot at " + oracle::ts(now.t));
  }
  if(newOnes > 1) oracle::fail("more than one trade opened in one tick at " + oracle::ts(now.t));
  if(newCandle && ex.dir != 0 && newOnes == 0 && survivors < MaxOpenTrades && !(same > 0 && StackOnlyWhenProtected && unprotectedSame > 0)) {
    bool blocked = oDayHit || ResetKillSwitch || (MaxSpreadUSD > 0 && spreadNow > MaxSpreadUSD + 1e-9) || (UseNewsFilter && listedNewsNear(now.t));
    bool explained = false;
    for(size_t i = logBefore; i < sim::log.size(); i++) if(sim::log[i].find("skipped") != std::string::npos) explained = true;
    if(explained) skippedLogged++;
    if(!blocked && !explained) { missed++; oracle::fail("signal missed at " + oracle::ts(now.t)); }
  }
}

std::string reasonFor(const sim::CloseEvent& c) {
  if(c.reason == DEAL_REASON_EXPERT) return killClosed.count(c.posId) ? "kill switch" : (oppositeClosed.count(c.posId) ? "opposite breakout" : "closed by EA");
  int dir = c.type == POSITION_TYPE_BUY ? 1 : -1;
  double d = dir * (c.sl - bePrice(c.open));
  if(d < -0.005) return "first stop";
  if(d <= 0.005) return "break-even stop";
  return "trailing stop";
}
std::vector<std::string> splitCsv(const std::string& line) { std::vector<std::string> r; std::string cur; for(char c : line) { if(c == ',') { r.push_back(cur); cur.clear(); } else if(c != '\r') cur += c; } r.push_back(cur); return r; }

// A full terminal restart: the EA's memory is wiped, only saved values survive.
void wipeEaMemory() {
  ArrayResize(g_managed, 0); ArrayResize(g_openIds, 0); ArrayResize(g_goneSince, 0); ArrayResize(g_trendClosedIds, 0);
  g_lastDecisionCandle = 0; g_lastAtrCandle = 0; g_atr = 0; g_trendDir = 0; g_breakoutDir = 0;
  g_peakEquity = 0; g_killSwitchOn = false; g_dayNumber = -1; g_dayStartBalance = 0; g_dailyLimitHit = false;
  g_closeRetryAfter = 0; ArrayResize(g_newsTimes, 0); g_csvFile = ""; g_lastNewsCheck = 0;
}

int main(int argc, char** argv) {
  unsigned seed = argc > 1 ? (unsigned)atoi(argv[1]) : 1;
  int days = argc > 2 ? atoi(argv[2]) : 365;
  sim::quiet = true;
  if(getenv("SIM_COMMISSION")) sim::commissionPerLotSide = atof(getenv("SIM_COMMISSION"));
  if(getenv("SIM_STOPSLEVEL")) sim::stopsLevelPoints = atoi(getenv("SIM_STOPSLEVEL"));
  if(getenv("SIM_LIVE")) sim::isTester = false;
  if(getenv("SIM_NEWSFILE")) { std::ifstream f(getenv("SIM_NEWSFILE")); std::stringstream b; b << f.rdbuf(); sim::files["common/" + std::string(NewsTimesFile.s)].content = b.str(); }
  int restartEvery = getenv("SIM_RESTART_EVERY") ? atoi(getenv("SIM_RESTART_EVERY")) : 0;
  datetime warmStart = 1672617600, testStart = warmStart + 60 * 86400;
  generateTicks(seed, warmStart, 60 + days, 1850.0);
  sim::initSeries();
  size_t k = 0;
  for(; k < sim::ticks.size() && sim::ticks[k].t < testStart; k++) { sim::now = sim::ticks[k]; sim::updateSeries(sim::now); }
  if(k < sim::ticks.size()) sim::now = sim::ticks[k];
  if(OnInit() != 0) { std::cout << "OnInit failed\n"; return 2; }
  datetime lastCandle = iTime(_Symbol, EntryTimeframe, 0);
  long tickNo = 0;
  for(; k < sim::ticks.size(); k++) {
    sim::now = sim::ticks[k]; sim::updateSeries(sim::now);
    sim::checkStops();
    for(auto& c : sim::closeEvents) expectedReason[c.posId] = reasonFor(c);   // broker stops before the EA's tick
    sim::closeEvents.clear();
    datetime candle = iTime(_Symbol, EntryTimeframe, 0);
    bool newCandle = candle != lastCandle; lastCandle = candle;
    oracleSafety();
    std::map<long, double> slBefore; std::set<long> openBefore;
    for(auto& p : sim::positions) { slBefore[p.id] = p.sl; openBefore.insert(p.id); }
    Expect ex = newCandle ? expectedSignal() : Expect{0, 0};
    if(newCandle && ex.dir != 0 && CloseOnOppositeBreakout && !oKill) for(auto& p : sim::positions) if(dirOf(p) == -ex.dir) oppositeClosed.insert(p.id);
    double balanceAtTick = sim::balance, spreadNow = sim::now.ask - sim::now.bid;
    size_t logBefore = sim::log.size();
    OnTick();
    if(!sim::closeEvents.empty()) OnTrade();
    if(oKill) for(auto& c : sim::closeEvents) if(c.reason == DEAL_REASON_EXPERT) killClosed.insert(c.posId);
    if(oKill != g_killSwitchOn) oracle::fail(std::string("kill switch ") + (g_killSwitchOn ? "ON" : "off") + " but the rule says " + (oKill ? "ON" : "off") + " at " + oracle::ts(sim::now.t));
    if(g_dailyLimitHit != oDayHit) oracle::fail("daily limit flag differs from the rule at " + oracle::ts(sim::now.t));
    if(oKill && !sim::positions.empty()) oracle::fail("kill switch active but a trade is still open at " + oracle::ts(sim::now.t));
    checkManagement(slBefore);
    checkEntries(newCandle, ex, openBefore, logBefore, balanceAtTick, spreadNow);
    if((int)sim::positions.size() > MaxOpenTrades) oracle::fail("more than MaxOpenTrades open at " + oracle::ts(sim::now.t));
    maxOpen = std::max(maxOpen, (int)sim::positions.size());
    for(auto& c : sim::closeEvents) expectedReason[c.posId] = reasonFor(c);
    sim::closeEvents.clear();
    if(restartEvery > 0 && ++tickNo % restartEvery == 0) {
      OnDeinit(1); sim::inds.clear(); wipeEaMemory();
      if(OnInit() != 0) { std::cout << "re-init failed\n"; return 3; }
      lastCandle = iTime(_Symbol, EntryTimeframe, 0);
    }
  }
  OnDeinit(0);
  std::string csvKey; for(auto& f : sim::files) if(f.first.find("files/GoldTrendStacker_") == 0) csvKey = f.first;
  std::istringstream csv(csvKey.empty() ? std::string() : sim::files[csvKey].content);
  std::string line; int rows = 0; std::getline(csv, line);
  if(line.rfind("OpenTime,CloseTime,Direction", 0) != 0) oracle::fail("CSV header missing: " + line);
  std::map<std::string, int> reasonCount; std::set<long> seen;
  while(std::getline(csv, line)) {
    if(line.empty() || line == "\r") continue; rows++;
    auto c = splitCsv(line);
    if(c.size() != 14) { oracle::fail("CSV row has " + std::to_string(c.size()) + " columns: " + line); continue; }
    long id = atol(c[10].c_str()); reasonCount[c[8]]++;
    if(seen.count(id)) oracle::fail("trade logged twice: " + line);
    seen.insert(id);
    auto tr = tracked.find(id);
    if(tr != tracked.end() && c[13] != tr->second.kind) oracle::fail("CSV entry kind '" + c[13] + "' but the trade was " + tr->second.kind);
    if(!expectedReason.count(id)) { if(c[8].find("end of test") == std::string::npos) oracle::fail("CSV row for a trade that did not close: " + line); continue; }
    if(c[8] != expectedReason[id]) oracle::fail("exit reason '" + c[8] + "' but the rule says '" + expectedReason[id] + "': " + line);
    double net = 0; for(auto& d : sim::deals) if(d.posId == id) net += d.profit + d.commission + d.swap + d.fee;
    if(std::fabs(net - atof(c[7].c_str())) > 0.011) oracle::fail("CSV profit differs from the account: " + line);
    if(tr != tracked.end() && c[6] != "n/a" && std::fabs(atof(c[6].c_str()) - tr->second.spreadAtEntry) > 0.0051) oracle::fail("CSV spread differs: " + line);
  }
  for(auto& e : expectedReason) if(!seen.count(e.first)) oracle::fail("closed trade missing from the CSV: position " + std::to_string(e.first));
  printf("balance %.2f | trades %d (long %d / short %d, %d stacked) | most open at once %d | CSV rows %d | missed %d | skipped-with-reason %d |",
         sim::balance, opened, longs, shorts, stackedN, maxOpen, rows, missed, skippedLogged);
  for(auto& r : reasonCount) printf(" [%s]=%d", r.first.c_str(), r.second);
  printf(" | kill switch %s | checks failed %d\n", g_killSwitchOn ? "ON" : "off", oracle::problems);
  return oracle::problems == 0 ? 0 : 1;
}
