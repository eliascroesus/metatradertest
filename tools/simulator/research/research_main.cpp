// Runs the REAL GoldScalperFVG code (converted to C++) on real gold ticks made by
// convert_ticks, and prints the results. For research only: no rule checks here
// (scalp_main.cpp does those).
// Usage: research <from YYYY-MM-DD> <to YYYY-MM-DD> <price scale> <extra spread> file1.bin [file2.bin ...]
//   price scale: multiplies every price (keeps % moves, spreads stay in dollars). 3 = gold of
//   2012-2018 lifted to about today's $3,500-4,500, so spread vs. take-profit is like today.
#include "mql5_sim.h"
#include "research_ea.inc"
#include <cstdint>
struct Rec { int64_t msc; float bid, ask; };
static datetime parseDate(const char* s) { int Y, M, D; sscanf(s, "%d-%d-%d", &Y, &M, &D); struct tm g = {}; g.tm_year = Y - 1900; g.tm_mon = M - 1; g.tm_mday = D; return (datetime)timegm(&g); }
int main(int argc, char** argv) {
  if(argc < 6) { fprintf(stderr, "usage: research from to scale extraSpread files...\n"); return 1; }
  datetime from = parseDate(argv[1]), to = parseDate(argv[2]);
  double scale = atof(argv[3]), extraSpread = atof(argv[4]);
  sim::quiet = true; sim::initSeries();
  bool started = false; double peak = 0, maxDD = 0, maxDDpct = 0; long ticks = 0;
  datetime firstT = 0, lastT = 0;
  std::vector<Rec> buf(1 << 16);
  for(int fi = 5; fi < argc; fi++) {
    FILE* f = fopen(argv[fi], "rb"); if(!f) { fprintf(stderr, "cannot open %s\n", argv[fi]); return 1; }
    size_t n;
    while((n = fread(buf.data(), sizeof(Rec), buf.size(), f)) > 0) {
      for(size_t i = 0; i < n; i++) {
        const Rec& r = buf[i];
        datetime t = (datetime)(r.msc / 1000);
        if(t >= to) break;
        double bid = std::round(r.bid * scale * 100.0) / 100.0;
        double spread = std::max(0.01, std::round(((double)r.ask - (double)r.bid + extraSpread) * 100.0) / 100.0);
        sim::now = {t, (long)r.msc, bid, std::round((bid + spread) * 100.0) / 100.0};
        sim::updateSeries(sim::now);
        if(!started) {
          if(t < from) continue;
          if(OnInit() != 0) { printf("OnInit failed\n"); return 2; }
          started = true; firstT = t; peak = sim::balance;
        }
        ticks++; lastT = t;
        sim::checkStops();
        OnTick();
        if(!sim::closeEvents.empty()) { OnTrade(); sim::closeEvents.clear(); }
        if(sim::log.size() > 20000) sim::log.clear();
        double eq = sim::equity();
        if(eq > peak) peak = eq;
        if(peak - eq > maxDD) maxDD = peak - eq;
        if(peak > 0 && (peak - eq) / peak > maxDDpct) maxDDpct = (peak - eq) / peak;
      }
    }
    fclose(f);
  }
  if(!started) { printf("no ticks in range\n"); return 2; }
  OnDeinit(0);
  // ---- results per trade from the deal history
  struct T { int dir = 0; std::string kind; datetime open = 0, close = 0; double net = 0; bool closed = false; };
  std::map<long, T> tr;
  for(auto& d : sim::deals) {
    T& x = tr[d.posId]; x.net += d.profit + d.commission + d.swap + d.fee;
    if(d.entry == DEAL_ENTRY_IN) { x.dir = d.type == DEAL_TYPE_BUY ? 1 : -1; x.kind = d.comment.size() > 4 ? d.comment.substr(4) : d.comment; x.open = d.time; }
    else { x.close = d.time; x.closed = true; }
  }
  auto stats = [](const std::vector<double>& v, const char* label) {
    double gp = 0, gl = 0; int w = 0; for(double x : v) { if(x > 0) { gp += x; w++; } else gl -= x; }
    printf("%s n=%zu win=%.1f%% pf=%.2f net=%.0f", label, v.size(), v.empty() ? 0 : 100.0 * w / v.size(), gl > 0 ? gp / gl : 0, gp - gl);
  };
  std::vector<double> all, lng, sht; std::map<std::string, std::vector<double>> byKind; std::map<int, std::vector<double>> byYear;
  for(auto& kv : tr) { const T& x = kv.second; if(!x.closed) continue; all.push_back(x.net); (x.dir > 0 ? lng : sht).push_back(x.net); byKind[x.kind].push_back(x.net);
    time_t tt = x.close; struct tm g; gmtime_r(&tt, &g); byYear[g.tm_year + 1900].push_back(x.net); }
  double days = (lastT - firstT) / 86400.0;
  stats(all, "ALL"); printf(" perday=%.1f maxDD=%.0f (%.1f%%) end=%.0f ticks=%ld\n", all.size() / std::max(1.0, days * 5.0 / 7.0), maxDD, maxDDpct * 100, sim::equity(), ticks);
  stats(lng, "  long "); printf("\n"); stats(sht, "  short"); printf("\n");
  for(auto& k : byKind) { stats(k.second, ("  kind " + k.first).c_str()); printf("\n"); }
  for(auto& y : byYear) { stats(y.second, ("  year " + std::to_string(y.first)).c_str()); printf("\n"); }
  return 0;
}
