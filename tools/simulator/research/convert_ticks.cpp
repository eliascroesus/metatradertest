// Converts Dukascopy hourly tick CSV files (FX-Data-XAUUSD-DS layout: time,bid,ask,... with
// prices divided by 100) into one compact binary file for research_main.cpp.
//   - times shifted from UTC to a typical gold broker clock: GMT+2, GMT+3 while the US is on
//     summer time (so the trading day ends at 17:00 New York, like most MT5 brokers);
//   - each second keeps only its first, highest-bid, lowest-bid and last tick (TP/SL hits and
//     candle highs/lows stay exact; the file gets several times smaller).
// Usage: ls hourly csv files sorted | ./convert_ticks out.bin
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <iostream>
#include <algorithm>
struct Rec { int64_t msc; float bid, ask; };
static int64_t daysFromCivil(int y, unsigned m, unsigned d) {   // Howard Hinnant
  y -= m <= 2; const int64_t era = (y >= 0 ? y : y - 399) / 400; const unsigned yoe = (unsigned)(y - era * 400);
  const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1; const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + (int64_t)doe - 719468; }
static int weekday(int64_t days) { return (int)((days % 7 + 11) % 7); }   // 0 = Sunday
static int64_t nthSunday(int y, int m, int n) { int64_t d = daysFromCivil(y, m, 1); while(weekday(d) != 0) d++; return d + 7 * (n - 1); }
static bool usSummer(int64_t utcSec) {   // 2nd Sunday of March 07:00 UTC .. 1st Sunday of November 06:00 UTC
  int64_t days = utcSec / 86400; int64_t z = days + 719468; int64_t era = (z >= 0 ? z : z - 146096) / 146097; unsigned doe = (unsigned)(z - era * 146097);
  unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; int y = (int)yoe + (int)era * 400; unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  unsigned mp = (5 * doy + 2) / 153; unsigned m = mp + (mp < 10 ? 3 : -9); y += (m <= 2);
  int64_t start = nthSunday(y, 3, 2) * 86400 + 7 * 3600, end = nthSunday(y, 11, 1) * 86400 + 6 * 3600;
  return utcSec >= start && utcSec < end; }
int main(int argc, char** argv) {
  if(argc < 2) { fprintf(stderr, "usage: convert_ticks out.bin < filelist\n"); return 1; }
  FILE* out = fopen(argv[1], "wb"); if(!out) return 1;
  std::string path; std::vector<Rec> sec; int64_t curSec = -1, lastMsc = -1; long in = 0, kept = 0;
  auto flush = [&]() {
    if(sec.empty()) return;
    size_t hi = 0, lo = 0; for(size_t i = 1; i < sec.size(); i++) { if(sec[i].bid > sec[hi].bid) hi = i; if(sec[i].bid < sec[lo].bid) lo = i; }
    std::vector<size_t> idx = {0, hi, lo, sec.size() - 1}; std::sort(idx.begin(), idx.end()); idx.erase(std::unique(idx.begin(), idx.end()), idx.end());
    for(size_t i : idx) { fwrite(&sec[i], sizeof(Rec), 1, out); kept++; }
    sec.clear(); };
  char line[256];
  while(std::getline(std::cin, path)) {
    FILE* f = fopen(path.c_str(), "r"); if(!f) { fprintf(stderr, "cannot open %s\n", path.c_str()); continue; }
    while(fgets(line, sizeof line, f)) {
      int Y, M, D, h, mi, s, ms; double a, b;
      if(sscanf(line, "%d.%d.%d %d:%d:%d.%d,%lf,%lf", &Y, &M, &D, &h, &mi, &s, &ms, &a, &b) != 9) continue;
      in++;
      int64_t utc = daysFromCivil(Y, M, D) * 86400 + h * 3600 + mi * 60 + s;
      int64_t server = utc + (usSummer(utc) ? 3 : 2) * 3600;
      int64_t msc = server * 1000 + ms;
      if(msc <= lastMsc) msc = lastMsc + 1;                   // keep time strictly increasing
      lastMsc = msc;
      double bid = std::min(a, b) * 100.0, ask = std::max(a, b) * 100.0;
      if(bid <= 0) continue;
      if(msc / 1000 != curSec) { flush(); curSec = msc / 1000; }
      sec.push_back({msc, (float)bid, (float)ask});
    }
    fclose(f);
  }
  flush(); fclose(out);
  fprintf(stderr, "ticks read %ld, kept %ld\n", in, kept);
  return 0;
}
