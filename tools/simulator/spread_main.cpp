#include "mql5_sim.h"
void generateTicks(unsigned seed, datetime start, int days, double price0);
#include "spread_sim.inc"
#include <random>
void generateTicks(unsigned seed, datetime start, int days, double price0) {
  std::mt19937_64 rng(seed); std::normal_distribution<double> N(0, 1); std::exponential_distribution<double> E(1.0 / 12.0);
  double lp = std::log(price0), t = (double)start; datetime end = start + (datetime)days * 86400;
  while(t < end) { t += E(rng); datetime ti = (datetime)t; time_t tt = ti; struct tm g; gmtime_r(&tt, &g); if(g.tm_wday == 0 || g.tm_wday == 6 || g.tm_hour == 0) continue;
    lp += 0.00005 * N(rng); double bid = std::round(std::exp(lp) * 100) / 100, sp = std::max(0.10, std::round((0.25 + 0.05 * N(rng)) * 100) / 100);
    sim::ticks.push_back({ti, (long)(t * 1000), bid, std::round((bid + sp) * 100) / 100}); }
}
int main() {
  sim::isTester = false; sim::quiet = true;
  generateTicks(7, 1703980800 /*2023-12-31*/ - 130 * 86400L, 180, 2050.0);       // covers warm-up + Jan..Apr 2024
  sim::now = {1703980800 + 120 * 86400L, 0, 2000, 2000.3};                         // "today" = 2024-04-29
  OnStart();
  for(auto& s : sim::log) std::cout << s.substr(0, 400) << "\n";
  // every source tick in the copied range must be present once, bid unchanged, spread doubled
  datetime from = 1704067200 - 120 * 86400L; from -= from % 86400; long expected = 0, bad = 0;
  double lastB = 0, lastA = 0; size_t ci = 0;
  for(auto& k : sim::ticks) { if(k.t < from || k.t > sim::now.t) continue; expected++;
    if(ci >= sim::customTicks.size()) { bad++; continue; } const MqlTick& c = sim::customTicks[ci++];
    if(c.time_msc != k.msc) { bad++; if(bad < 5) printf("order/time mismatch\n"); continue; }
    double want = std::round((k.bid + 2 * (k.ask - k.bid)) * 100) / 100;
    if(c.bid != k.bid || std::fabs(c.ask - want) > 1e-9) { bad++; if(bad < 8) printf("price: bid %.5f/%.5f ask %.5f want %.5f\n", c.bid, k.bid, c.ask, want); }
    uint wf = (c.bid != lastB ? 2u : 0u) | (c.ask != lastA ? 4u : 0u); if(wf == 0) wf = 6; if(c.flags != wf) { bad++; if(bad < 8) printf("flags %u want %u\n", c.flags, wf); } lastB = c.bid; lastA = c.ask; }
  long extra = 0; for(auto& c : sim::customTicks) if(c.time > sim::now.t) extra++; printf("copied ticks after 'now': %ld\n", extra);
  printf("source ticks in range %ld, copied %zu, bad %ld, M1 bars %ld, description '%s'\n", expected, sim::customTicks.size(), bad, sim::customRates, sim::lastDescription.c_str());
  return (bad == 0 && (long)sim::customTicks.size() == expected) ? 0 : 1;
}
