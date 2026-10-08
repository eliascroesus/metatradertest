// A small MetaTrader-5-like simulator, used ONLY to exercise the EA's logic.
// Implements the subset of the MQL5 API that the EA uses, on synthetic data.
#pragma once
#include <string>
#include <vector>
#include <map>
#include <set>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <algorithm>
#include <iostream>
#include <fstream>
#include <sstream>
#include <random>
#undef SEEK_SET
#undef SEEK_CUR
#undef SEEK_END
#undef NULL

typedef unsigned char  uchar;
typedef unsigned short ushort;
typedef unsigned int   uint;
typedef unsigned long  ulong;
typedef long           datetime;
typedef unsigned int   color;

struct NullType {};
static const NullType NULL_VALUE = NullType();
#define NULL NULL_VALUE

class string {
public:
  std::string s;
  string() {}
  string(const char* c) : s(c) {}
  string(const std::string& c) : s(c) {}
  string(const NullType&) {}
  string(const string& o) : s(o.s) {}
  string& operator=(const string& o) { s = o.s; return *this; }
  string& operator=(const char* c) { s = c; return *this; }
  string& operator+=(const string& o) { s += o.s; return *this; }
  string& operator+=(const char* c) { s += c; return *this; }
  bool operator==(const string& o) const { return s == o.s; }
  bool operator!=(const string& o) const { return s != o.s; }
  bool operator==(const char* c) const { return s == c; }
  bool operator!=(const char* c) const { return s != c; }
  bool operator<(const string& o) const { return s < o.s; }
private:
  string(int); string(long); string(double); string(unsigned long); string(unsigned int); string(char); string(bool);
};
inline string operator+(const string& a, const string& b) { string r(a); r += b; return r; }
inline string operator+(const string& a, const char* b) { string r(a); r += b; return r; }
inline string operator+(const char* a, const string& b) { string r(a); r += b; return r; }

template<class T> struct MqlArray {
  std::vector<T> v;
  MqlArray() {}
  explicit MqlArray(int n) : v(n) {}
  T& operator[](int i) { if(i < 0 || i >= (int)v.size()) { fprintf(stderr, "ARRAY OUT OF RANGE %d/%d\n", i, (int)v.size()); abort(); } return v[i]; }
  const T& operator[](int i) const { if(i < 0 || i >= (int)v.size()) { fprintf(stderr, "ARRAY OUT OF RANGE %d/%d\n", i, (int)v.size()); abort(); } return v[i]; }
};
template<class T> int ArraySize(const MqlArray<T>& a) { return (int)a.v.size(); }
template<class T> int ArrayResize(MqlArray<T>& a, int n, int reserve = 0) { (void)reserve; a.v.resize(n); return n; }
template<class T> bool ArraySort(MqlArray<T>& a) { std::sort(a.v.begin(), a.v.end()); return true; }
template<class T> int ArrayMaximum(const MqlArray<T>& a, int start = 0, int count = -1) { (void)count; int best = start; for(int i = start; i < (int)a.v.size(); i++) if(a.v[i] > a.v[best]) best = i; return best; }
template<class T> int ArrayMinimum(const MqlArray<T>& a, int start = 0, int count = -1) { (void)count; int best = start; for(int i = start; i < (int)a.v.size(); i++) if(a.v[i] < a.v[best]) best = i; return best; }

#define WHOLE_ARRAY (-1)
#define INVALID_HANDLE (-1)
#define EMPTY_VALUE (1.7976931348623158e+308)
#define ULONG_MAX_MQL 18446744073709551615UL
#define CP_ACP 0

enum ENUM_TIMEFRAMES { PERIOD_CURRENT=0, PERIOD_M1=1, PERIOD_M5=5, PERIOD_M15=15, PERIOD_M30=30, PERIOD_H1=16385, PERIOD_H4=16388, PERIOD_D1=16408, PERIOD_W1=32769, PERIOD_MN1=49153 };
enum ENUM_MA_METHOD { MODE_SMA, MODE_EMA, MODE_SMMA, MODE_LWMA };
enum ENUM_APPLIED_PRICE { PRICE_CLOSE=1, PRICE_OPEN, PRICE_HIGH, PRICE_LOW, PRICE_MEDIAN, PRICE_TYPICAL, PRICE_WEIGHTED };
enum ENUM_SYMBOL_INFO_INTEGER { SYMBOL_SELECT, SYMBOL_VISIBLE, SYMBOL_CUSTOM, SYMBOL_DIGITS, SYMBOL_SPREAD, SYMBOL_SPREAD_FLOAT, SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL, SYMBOL_TRADE_MODE, SYMBOL_TRADE_EXEMODE, SYMBOL_FILLING_MODE, SYMBOL_TIME };
enum ENUM_SYMBOL_INFO_DOUBLE { SYMBOL_BID, SYMBOL_ASK, SYMBOL_LAST, SYMBOL_POINT, SYMBOL_TRADE_TICK_VALUE, SYMBOL_TRADE_TICK_VALUE_PROFIT, SYMBOL_TRADE_TICK_VALUE_LOSS, SYMBOL_TRADE_TICK_SIZE, SYMBOL_TRADE_CONTRACT_SIZE, SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX, SYMBOL_VOLUME_STEP, SYMBOL_VOLUME_LIMIT };
enum ENUM_SYMBOL_INFO_STRING { SYMBOL_BASIS, SYMBOL_CURRENCY_BASE, SYMBOL_CURRENCY_PROFIT, SYMBOL_CURRENCY_MARGIN, SYMBOL_DESCRIPTION, SYMBOL_PATH };
enum ENUM_SYMBOL_TRADE_MODE { SYMBOL_TRADE_MODE_DISABLED, SYMBOL_TRADE_MODE_LONGONLY, SYMBOL_TRADE_MODE_SHORTONLY, SYMBOL_TRADE_MODE_CLOSEONLY, SYMBOL_TRADE_MODE_FULL };
enum ENUM_ACCOUNT_INFO_DOUBLE { ACCOUNT_BALANCE, ACCOUNT_CREDIT, ACCOUNT_PROFIT, ACCOUNT_EQUITY, ACCOUNT_MARGIN, ACCOUNT_MARGIN_FREE, ACCOUNT_MARGIN_LEVEL };
enum ENUM_ACCOUNT_INFO_INTEGER { ACCOUNT_LOGIN, ACCOUNT_TRADE_MODE, ACCOUNT_LEVERAGE, ACCOUNT_MARGIN_MODE, ACCOUNT_TRADE_ALLOWED, ACCOUNT_TRADE_EXPERT };
enum ENUM_ACCOUNT_MARGIN_MODE { ACCOUNT_MARGIN_MODE_RETAIL_NETTING, ACCOUNT_MARGIN_MODE_EXCHANGE, ACCOUNT_MARGIN_MODE_RETAIL_HEDGING };
enum ENUM_ACCOUNT_INFO_STRING { ACCOUNT_NAME, ACCOUNT_SERVER, ACCOUNT_CURRENCY, ACCOUNT_COMPANY };
enum ENUM_TERMINAL_INFO_INTEGER { TERMINAL_BUILD, TERMINAL_CONNECTED, TERMINAL_TRADE_ALLOWED };
enum ENUM_TERMINAL_INFO_STRING { TERMINAL_LANGUAGE, TERMINAL_COMPANY, TERMINAL_NAME, TERMINAL_PATH, TERMINAL_DATA_PATH, TERMINAL_COMMONDATA_PATH };
enum ENUM_MQL_INFO_INTEGER { MQL_PROGRAM_TYPE, MQL_DLLS_ALLOWED, MQL_TRADE_ALLOWED, MQL_DEBUG, MQL_PROFILER, MQL_TESTER, MQL_FORWARD, MQL_OPTIMIZATION, MQL_VISUAL_MODE, MQL_FRAME_MODE };
enum ENUM_POSITION_PROPERTY_INTEGER { POSITION_TICKET, POSITION_TIME, POSITION_TIME_MSC, POSITION_TIME_UPDATE, POSITION_TYPE, POSITION_MAGIC, POSITION_IDENTIFIER, POSITION_REASON };
enum ENUM_POSITION_PROPERTY_DOUBLE { POSITION_VOLUME, POSITION_PRICE_OPEN, POSITION_SL, POSITION_TP, POSITION_PRICE_CURRENT, POSITION_SWAP, POSITION_PROFIT };
enum ENUM_POSITION_PROPERTY_STRING { POSITION_SYMBOL, POSITION_COMMENT, POSITION_EXTERNAL_ID };
enum ENUM_POSITION_TYPE { POSITION_TYPE_BUY, POSITION_TYPE_SELL };
enum ENUM_DEAL_PROPERTY_INTEGER { DEAL_TICKET, DEAL_ORDER, DEAL_TIME, DEAL_TIME_MSC, DEAL_TYPE, DEAL_ENTRY, DEAL_MAGIC, DEAL_REASON, DEAL_POSITION_ID };
enum ENUM_DEAL_PROPERTY_DOUBLE { DEAL_VOLUME, DEAL_PRICE, DEAL_COMMISSION, DEAL_SWAP, DEAL_PROFIT, DEAL_FEE, DEAL_SL, DEAL_TP };
enum ENUM_DEAL_PROPERTY_STRING { DEAL_SYMBOL, DEAL_COMMENT, DEAL_EXTERNAL_ID };
enum ENUM_DEAL_TYPE { DEAL_TYPE_BUY, DEAL_TYPE_SELL, DEAL_TYPE_BALANCE, DEAL_TYPE_CREDIT, DEAL_TYPE_CHARGE, DEAL_TYPE_CORRECTION, DEAL_TYPE_BONUS, DEAL_TYPE_COMMISSION };
enum ENUM_DEAL_ENTRY { DEAL_ENTRY_IN, DEAL_ENTRY_OUT, DEAL_ENTRY_INOUT, DEAL_ENTRY_OUT_BY };
enum ENUM_DEAL_REASON { DEAL_REASON_CLIENT, DEAL_REASON_MOBILE, DEAL_REASON_WEB, DEAL_REASON_EXPERT, DEAL_REASON_SL, DEAL_REASON_TP, DEAL_REASON_SO, DEAL_REASON_ROLLOVER, DEAL_REASON_VMARGIN, DEAL_REASON_SPLIT };
enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY, ORDER_TYPE_SELL };
enum ENUM_INIT_RETCODE { INIT_SUCCEEDED=0, INIT_FAILED=1, INIT_PARAMETERS_INCORRECT=32767 };
enum ENUM_LOG_LEVELS { LOG_LEVEL_NO, LOG_LEVEL_ERRORS, LOG_LEVEL_ALL };
enum ENUM_FILE_POSITION { SEEK_SET, SEEK_CUR, SEEK_END };
enum ENUM_CALENDAR_EVENT_IMPORTANCE { CALENDAR_IMPORTANCE_NONE, CALENDAR_IMPORTANCE_LOW, CALENDAR_IMPORTANCE_MODERATE, CALENDAR_IMPORTANCE_HIGH };
enum ENUM_CALENDAR_EVENT_TIMEMODE { CALENDAR_TIMEMODE_DATETIME, CALENDAR_TIMEMODE_DATE, CALENDAR_TIMEMODE_NOTIME, CALENDAR_TIMEMODE_TENTATIVE };

#define FILE_READ 1
#define FILE_WRITE 2
#define FILE_TXT 16
#define FILE_ANSI 32
#define FILE_SHARE_READ 128
#define FILE_SHARE_WRITE 256
#define FILE_COMMON 4096
#define TIME_DATE 1
#define TIME_MINUTES 2
#define TIME_SECONDS 4
#define TRADE_RETCODE_PLACED 10008
#define TRADE_RETCODE_DONE 10009
#define TRADE_RETCODE_DONE_PARTIAL 10010
#define TRADE_RETCODE_INVALID_STOPS 10016
#define TRADE_RETCODE_NO_CHANGES 10025

struct MqlTick { datetime time; double bid; double ask; double last; ulong volume; long time_msc; uint flags; double volume_real; };
struct MqlDateTime { int year; int mon; int day; int hour; int min; int sec; int day_of_week; int day_of_year; };
struct MqlCalendarValue { ulong id; ulong event_id; datetime time; datetime period; int revision; long actual_value; long prev_value; long revised_prev_value; long forecast_value; int impact_type; };
struct MqlCalendarEvent { ulong id; int type; int sector; int frequency; ENUM_CALENDAR_EVENT_TIMEMODE time_mode; ulong country_id; int unit; ENUM_CALENDAR_EVENT_IMPORTANCE importance; int multiplier; uint digits; string source_url; string event_code; string name; };
struct MqlRates { datetime time; double open; double high; double low; double close; long tick_volume; int spread; long real_volume; };
namespace sim { std::vector<MqlRates> m15; std::vector<MqlCalendarEvent> calEvents; std::vector<MqlCalendarValue> calValues; }

// ------------------------------------------------------------------ text helpers
inline std::string to_text(const string& v) { return v.s; }
inline std::string to_text(const char* v) { return v; }
inline std::string to_text(double v) { char b[64]; snprintf(b, sizeof b, "%.8g", v); return b; }
inline std::string to_text(int v) { return std::to_string(v); }
inline std::string to_text(long v) { return std::to_string(v); }
inline std::string to_text(unsigned long v) { return std::to_string(v); }
inline std::string to_text(unsigned int v) { return std::to_string(v); }
inline std::string to_text(bool v) { return v ? "true" : "false"; }
inline const char* fmt_arg(const string& v) { return v.s.c_str(); }
inline const char* fmt_arg(const char* v) { return v; }
inline double fmt_arg(double v) { return v; }
inline int fmt_arg(int v) { return v; }
inline long fmt_arg(long v) { return v; }

namespace sim {
  bool quiet = false;
  std::vector<std::string> log;
}
template<class... A> void Print(A... a) { std::string s; ((s += to_text(a)), ...); sim::log.push_back(s); if(!sim::quiet) std::cout << "  [EA] " << s << "\n"; }
template<class... A> void Alert(A... a) { std::string s; ((s += to_text(a)), ...); sim::log.push_back("ALERT: " + s); if(!sim::quiet) std::cout << "  [EA ALERT] " << s << "\n"; }
template<class... A> void Comment(A... a) { (void)sizeof...(a); }
template<class... A> string StringFormat(const string fmt, A... a) { char buf[8192]; snprintf(buf, sizeof buf, fmt.s.c_str(), fmt_arg(a)...); return string(buf); }

inline double MathMax(double a, double b) { return a > b ? a : b; }
inline double MathMin(double a, double b) { return a < b ? a : b; }
inline double MathAbs(double a) { return std::fabs(a); }
inline double MathRound(double a) { return std::round(a); }
inline double MathFloor(double a) { return std::floor(a); }
inline double MathCeil(double a) { return std::ceil(a); }
inline double MathPow(double a, double b) { return std::pow(a, b); }
inline bool   MathIsValidNumber(double a) { return std::isfinite(a); }
inline double NormalizeDouble(double v, int d) { double p = std::pow(10.0, d); return std::round(v * p) / p; }

inline int StringLen(const string s) { return (int)s.s.size(); }
inline int StringFind(const string s, const string m, int start = 0) { size_t p = s.s.find(m.s, start); return p == std::string::npos ? -1 : (int)p; }
inline string StringSubstr(const string s, int start, int length = -1) { if(start >= (int)s.s.size()) return string(); return string(length < 0 ? s.s.substr(start) : s.s.substr(start, length)); }
inline int StringReplace(string& s, const string f, const string r) { int n = 0; size_t p = 0; while((p = s.s.find(f.s, p)) != std::string::npos) { s.s.replace(p, f.s.size(), r.s); p += r.s.size(); n++; } return n; }
inline int StringTrimLeft(string& s) { size_t i = 0; while(i < s.s.size() && strchr(" \t\r\n", s.s[i])) i++; s.s.erase(0, i); return (int)i; }
inline int StringTrimRight(string& s) { size_t n = s.s.size(), k = n; while(k > 0 && strchr(" \t\r\n", s.s[k-1])) k--; s.s.erase(k); return (int)(n - k); }
inline bool StringToUpper(string& s) { for(auto& c : s.s) c = (char)toupper(c); return true; }
inline int StringCompare(const string a, const string b, bool cs = true) { std::string x = a.s, y = b.s; if(!cs) { for(auto& c : x) c = (char)toupper(c); for(auto& c : y) c = (char)toupper(c); } return x < y ? -1 : (x > y ? 1 : 0); }
inline ushort StringGetCharacter(const string s, int pos) { if(pos < 0 || pos >= (int)s.s.size()) return 0; return (ushort)(unsigned char)s.s[pos]; }
inline int StringSplit(const string s, const ushort sep, MqlArray<string>& r) { r.v.clear(); if(s.s.empty()) return 0; std::string cur; for(char c : s.s) { if((ushort)(unsigned char)c == sep) { r.v.push_back(string(cur)); cur.clear(); } else cur += c; } r.v.push_back(string(cur)); return (int)r.v.size(); }
inline string IntegerToString(long n, int = 0, ushort = ' ') { return string(std::to_string(n)); }
inline string DoubleToString(double v, int d = 8) { char b[64]; snprintf(b, sizeof b, "%.*f", d, v); return string(b); }
inline string TimeToString(datetime t, int mode = TIME_DATE | TIME_MINUTES) {
  time_t tt = t; struct tm g; gmtime_r(&tt, &g); char b[64]; std::string r;
  if(mode & TIME_DATE) { snprintf(b, sizeof b, "%04d.%02d.%02d", g.tm_year + 1900, g.tm_mon + 1, g.tm_mday); r += b; }
  if(mode & TIME_SECONDS) { snprintf(b, sizeof b, "%s%02d:%02d:%02d", r.empty() ? "" : " ", g.tm_hour, g.tm_min, g.tm_sec); r += b; }
  else if(mode & TIME_MINUTES) { snprintf(b, sizeof b, "%s%02d:%02d", r.empty() ? "" : " ", g.tm_hour, g.tm_min); r += b; }
  return string(r);
}
inline datetime StringToTime(const string s) { int Y = 0, M = 0, D = 0, h = 0, m = 0, sec = 0; int n = sscanf(s.s.c_str(), "%d.%d.%d %d:%d:%d", &Y, &M, &D, &h, &m, &sec); if(n < 3) return 0; struct tm g = {}; g.tm_year = Y - 1900; g.tm_mon = M - 1; g.tm_mday = D; g.tm_hour = h; g.tm_min = m; g.tm_sec = sec; return (datetime)timegm(&g); }
inline long StringToInteger(const string s) { return atol(s.s.c_str()); }
inline string EnumToString(ENUM_TIMEFRAMES tf) { switch(tf) { case PERIOD_H1: return "PERIOD_H1"; case PERIOD_H4: return "PERIOD_H4"; case PERIOD_D1: return "PERIOD_D1"; default: return "PERIOD_OTHER"; } }

// ------------------------------------------------------------------ the simulated world
namespace sim {
  struct Tick { datetime t; long msc; double bid, ask; };
  std::vector<Tick> ticks; Tick now;
  bool isTester = true; bool tradeAllowed = true;
  double commissionPerLotSide = 0.0; int stopsLevelPoints = 0; double leverage = 100.0;
  double balance = 10000.0; int lastError = 0; uint tickCounter = 0;
  const double contract = 100.0, point = 0.01;
  std::string symbolName = "XAUUSD";

  struct Bar { datetime t; double o, h, l, c; };
  struct Series { int secs; std::vector<Bar> bars; };
  std::map<int, Series> series;
  int tfSeconds(int tf) { switch(tf) { case PERIOD_M1: return 60; case PERIOD_M5: return 300; case PERIOD_M15: return 900; case PERIOD_H1: return 3600; case PERIOD_H4: return 14400; case PERIOD_D1: return 86400; default: return 3600; } }
  void initSeries() { series.clear(); int tfs[] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1}; for(int tf : tfs) { series[tf].secs = tfSeconds(tf); } }
  void updateSeries(const Tick& k) {
    for(auto& kv : series) { Series& s = kv.second; datetime bt = k.t - k.t % s.secs;
      if(s.bars.empty() || s.bars.back().t != bt) s.bars.push_back({bt, k.bid, k.bid, k.bid, k.bid});
      else { Bar& b = s.bars.back(); b.h = std::max(b.h, k.bid); b.l = std::min(b.l, k.bid); b.c = k.bid; } }
  }
  Series& S(int tf) { if(tf == PERIOD_CURRENT) tf = PERIOD_H1; return series.at(tf); }

  struct Ind { int kind; int tf; int period; };   // kind 0 = EMA, 1 = ATR
  std::vector<Ind> inds;
  std::map<std::pair<const void*, int>, std::vector<double>> emaCache;   // finished bars only
  double emaAt(const Series& s, int period, int idx) {
    double a = 2.0 / (period + 1.0); auto& v = emaCache[{(const void*)&s, period}];
    int finished = (int)s.bars.size() - 1;
    while((int)v.size() < std::min(idx + 1, finished)) { int i = (int)v.size(); v.push_back(i == 0 ? s.bars[0].c : a * s.bars[i].c + (1 - a) * v[i - 1]); }
    if(idx < (int)v.size()) return v[idx];
    return idx == 0 ? s.bars[0].c : a * s.bars[idx].c + (1 - a) * v[idx - 1]; }
  double atrAt(const Series& s, int period, int idx) { if(idx < period) return EMPTY_VALUE; double sum = 0; for(int i = idx - period + 1; i <= idx; i++) { const Bar& b = s.bars[i]; double pc = s.bars[i-1].c; sum += std::max(b.h - b.l, std::max(std::fabs(b.h - pc), std::fabs(b.l - pc))); } return sum / period; }

  struct Pos { ulong ticket; long id; int type; double volume, open, sl, tp; datetime time; long magic; std::string comment; };
  struct Deal { ulong ticket; ulong order; long posId; datetime time; int type, entry, reason; double volume, price, profit, commission, swap, fee, sl, tp; long magic; std::string comment; };
  std::vector<Pos> positions; Pos selected; bool hasSelected = false;
  std::vector<Deal> deals; std::vector<size_t> selDeals;
  ulong nextTicket = 5000;
  std::map<std::string, double> gvars;

  struct FileRec { std::string content; };
  std::map<std::string, FileRec> files;
  struct Handle { std::string key; size_t pos; bool open; };
  std::vector<Handle> handles;

  double floating(const Pos& p) { return p.type == POSITION_TYPE_BUY ? (now.bid - p.open) * p.volume * contract : (p.open - now.ask) * p.volume * contract; }
  double equity() { double e = balance; for(auto& p : positions) e += floating(p); return e; }
  double usedMargin() { double m = 0; for(auto& p : positions) m += p.volume * contract * p.open / leverage; return m; }

  struct CloseEvent { long posId; double sl, open; int type; int reason; datetime time; };
  std::vector<CloseEvent> closeEvents;
  void closePosition(size_t i, int reason, const std::string& comment) {
    Pos p = positions[i]; double price = p.type == POSITION_TYPE_BUY ? now.bid : now.ask;
    double profit = p.type == POSITION_TYPE_BUY ? (price - p.open) * p.volume * contract : (p.open - price) * p.volume * contract;
    profit = std::round(profit * 100) / 100; double comm = -commissionPerLotSide * p.volume;
    Deal d{nextTicket++, 0, p.id, now.t, p.type == POSITION_TYPE_BUY ? DEAL_TYPE_SELL : DEAL_TYPE_BUY, DEAL_ENTRY_OUT, reason, p.volume, price, profit, comm, 0, 0, p.sl, p.tp, p.magic, comment};
    deals.push_back(d); balance += profit + comm; positions.erase(positions.begin() + i);
    closeEvents.push_back({p.id, p.sl, p.open, p.type, reason, now.t});
  }
  bool checkStops() { bool any = false; for(size_t i = 0; i < positions.size();) { Pos& p = positions[i];
      bool hit = p.sl > 0 && ((p.type == POSITION_TYPE_BUY && now.bid <= p.sl) || (p.type == POSITION_TYPE_SELL && now.ask >= p.sl));
      bool tpHit = !hit && p.tp > 0 && ((p.type == POSITION_TYPE_BUY && now.bid >= p.tp) || (p.type == POSITION_TYPE_SELL && now.ask <= p.tp));
      if(hit) { char c[64]; snprintf(c, sizeof c, "[sl %.2f]", p.sl); closePosition(i, DEAL_REASON_SL, c); any = true; }
      else if(tpHit) { char c[64]; snprintf(c, sizeof c, "[tp %.2f]", p.tp); closePosition(i, DEAL_REASON_TP, c); any = true; } else i++; } return any; }
  bool tpValid(int type, double tp) { double lvl = stopsLevelPoints * point; if(tp <= 0) return true; return type == POSITION_TYPE_BUY ? (tp > now.bid + lvl + 1e-9) : (tp < now.ask - lvl - 1e-9); }
  Pos* findPos(ulong ticket) { for(auto& p : positions) if(p.ticket == ticket) return &p; return nullptr; }
  bool stopValid(int type, double sl) { double lvl = stopsLevelPoints * point; if(sl <= 0) return true; return type == POSITION_TYPE_BUY ? (sl < now.bid - lvl - 1e-9) : (sl > now.ask + lvl + 1e-9); }
}

string _Symbol("XAUUSD"); ENUM_TIMEFRAMES _Period = PERIOD_H1; double _Point = 0.01; int _Digits = 2;

inline datetime TimeCurrent() { return sim::now.t; }
inline datetime TimeTradeServer() { return sim::now.t; }
inline uint GetTickCount() { return sim::tickCounter += 50; }
inline int GetLastError() { return sim::lastError; }
inline void ResetLastError() { sim::lastError = 0; }

inline int MQLInfoInteger(ENUM_MQL_INFO_INTEGER p) { if(p == MQL_TESTER) return sim::isTester ? 1 : 0; if(p == MQL_TRADE_ALLOWED) return sim::tradeAllowed ? 1 : 0; return 0; }
inline int TerminalInfoInteger(ENUM_TERMINAL_INFO_INTEGER p) { return p == TERMINAL_TRADE_ALLOWED ? (sim::tradeAllowed ? 1 : 0) : 0; }
inline string TerminalInfoString(ENUM_TERMINAL_INFO_STRING p) { return p == TERMINAL_COMMONDATA_PATH ? string("C:\\Common") : string("C:\\Sim"); }
inline long AccountInfoInteger(ENUM_ACCOUNT_INFO_INTEGER p) { return p == ACCOUNT_MARGIN_MODE ? (long)ACCOUNT_MARGIN_MODE_RETAIL_HEDGING : 0; }
inline double AccountInfoDouble(ENUM_ACCOUNT_INFO_DOUBLE p) { if(p == ACCOUNT_BALANCE) return sim::balance; if(p == ACCOUNT_EQUITY) return sim::equity(); if(p == ACCOUNT_MARGIN_FREE) return sim::equity() - sim::usedMargin(); return 0; }
inline string AccountInfoString(ENUM_ACCOUNT_INFO_STRING p) { return p == ACCOUNT_SERVER ? string("SimBroker-Server") : string("USD"); }
inline double SymbolInfoDouble(const string sym, ENUM_SYMBOL_INFO_DOUBLE p) { (void)sym;
  switch(p) { case SYMBOL_POINT: case SYMBOL_TRADE_TICK_SIZE: return 0.01; case SYMBOL_TRADE_TICK_VALUE: case SYMBOL_TRADE_TICK_VALUE_LOSS: case SYMBOL_TRADE_TICK_VALUE_PROFIT: return 1.0;
    case SYMBOL_VOLUME_MIN: return 0.01; case SYMBOL_VOLUME_MAX: return 100; case SYMBOL_VOLUME_STEP: return 0.01; case SYMBOL_BID: return sim::now.bid; case SYMBOL_ASK: return sim::now.ask; case SYMBOL_TRADE_CONTRACT_SIZE: return 100; default: return 0; } }
inline long SymbolInfoInteger(const string sym, ENUM_SYMBOL_INFO_INTEGER p) { (void)sym; if(p == SYMBOL_DIGITS) return 2; if(p == SYMBOL_TRADE_STOPS_LEVEL) return sim::stopsLevelPoints; if(p == SYMBOL_TRADE_MODE) return SYMBOL_TRADE_MODE_FULL; return 0; }
inline bool SymbolInfoTick(const string sym, MqlTick& t) { (void)sym; t.time = sim::now.t; t.time_msc = sim::now.msc; t.bid = sim::now.bid; t.ask = sim::now.ask; t.last = 0; t.volume = 0; t.flags = 6; t.volume_real = 0; return true; }
inline bool SymbolSelect(const string, bool) { return true; }
namespace sim { std::map<std::string, bool>& customList(); }
inline bool SymbolExist(const string s, bool& c) { c = sim::customList().count(s.s) > 0; return c || s.s == sim::symbolName; }

inline datetime iTime(const string, ENUM_TIMEFRAMES tf, int shift) { auto& b = sim::S(tf).bars; int i = (int)b.size() - 1 - shift; return i < 0 ? 0 : b[i].t; }
inline double iHigh(const string, ENUM_TIMEFRAMES tf, int shift) { auto& b = sim::S(tf).bars; int i = (int)b.size() - 1 - shift; return i < 0 ? 0 : b[i].h; }
inline double iLow(const string, ENUM_TIMEFRAMES tf, int shift) { auto& b = sim::S(tf).bars; int i = (int)b.size() - 1 - shift; return i < 0 ? 0 : b[i].l; }
inline double iClose(const string, ENUM_TIMEFRAMES tf, int shift) { auto& b = sim::S(tf).bars; int i = (int)b.size() - 1 - shift; return i < 0 ? 0 : b[i].c; }
inline int CopyHigh(const string, ENUM_TIMEFRAMES tf, int start, int count, MqlArray<double>& a) { auto& b = sim::S(tf).bars; int last = (int)b.size() - 1 - start; if(last < 0) return -1; int first = std::max(0, last - count + 1); a.v.clear(); for(int i = first; i <= last; i++) a.v.push_back(b[i].h); return (int)a.v.size(); }
inline int CopyLow(const string, ENUM_TIMEFRAMES tf, int start, int count, MqlArray<double>& a) { auto& b = sim::S(tf).bars; int last = (int)b.size() - 1 - start; if(last < 0) return -1; int first = std::max(0, last - count + 1); a.v.clear(); for(int i = first; i <= last; i++) a.v.push_back(b[i].l); return (int)a.v.size(); }
inline int iMA(const string, ENUM_TIMEFRAMES tf, int period, int, ENUM_MA_METHOD, ENUM_APPLIED_PRICE) { sim::inds.push_back({0, (int)tf, period}); return (int)sim::inds.size() - 1; }
inline int iATR(const string, ENUM_TIMEFRAMES tf, int period) { sim::inds.push_back({1, (int)tf, period}); return (int)sim::inds.size() - 1; }
inline int BarsCalculated(int h) { return (int)sim::S(sim::inds[h].tf).bars.size(); }
inline bool IndicatorRelease(int) { return true; }
inline int PeriodSeconds(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) { return sim::tfSeconds(tf == PERIOD_CURRENT ? PERIOD_H1 : tf); }
inline int CopyBuffer(int h, int, datetime start, int count, MqlArray<double>& a) {
  auto& ind = sim::inds[h]; auto& s = sim::S(ind.tf); int idx = -1;
  for(int i = (int)s.bars.size() - 1; i >= 0; i--) if(s.bars[i].t <= start) { idx = i; break; }
  if(idx < 0 || count != 1) return -1;
  a.v.assign(1, ind.kind == 0 ? sim::emaAt(s, ind.period, idx) : sim::atrAt(s, ind.period, idx)); return 1; }

inline int PositionsTotal() { return (int)sim::positions.size(); }
inline ulong PositionGetTicket(int i) { if(i < 0 || i >= (int)sim::positions.size()) return 0; sim::selected = sim::positions[i]; sim::hasSelected = true; return sim::selected.ticket; }
inline bool PositionSelectByTicket(ulong t) { auto* p = sim::findPos(t); if(!p) { sim::hasSelected = false; return false; } sim::selected = *p; sim::hasSelected = true; return true; }
inline long PositionGetInteger(ENUM_POSITION_PROPERTY_INTEGER p) { auto& s = sim::selected; switch(p) { case POSITION_TICKET: return (long)s.ticket; case POSITION_TIME: return s.time; case POSITION_TYPE: return s.type; case POSITION_MAGIC: return s.magic; case POSITION_IDENTIFIER: return s.id; default: return 0; } }
inline double PositionGetDouble(ENUM_POSITION_PROPERTY_DOUBLE p) { auto& s = sim::selected; switch(p) { case POSITION_VOLUME: return s.volume; case POSITION_PRICE_OPEN: return s.open; case POSITION_SL: return s.sl; case POSITION_TP: return s.tp; case POSITION_PROFIT: { auto* q = sim::findPos(s.ticket); return q ? std::round(sim::floating(*q) * 100) / 100 : 0; } default: return 0; } }
inline string PositionGetString(ENUM_POSITION_PROPERTY_STRING p) { return p == POSITION_SYMBOL ? string(sim::symbolName) : string(sim::selected.comment); }

inline bool HistorySelect(datetime from, datetime to) { sim::selDeals.clear(); for(size_t i = 0; i < sim::deals.size(); i++) if(sim::deals[i].time >= from && sim::deals[i].time <= to) sim::selDeals.push_back(i); return true; }
inline bool HistorySelectByPosition(long id) { sim::selDeals.clear(); for(size_t i = 0; i < sim::deals.size(); i++) if(sim::deals[i].posId == id) sim::selDeals.push_back(i); return true; }
inline int HistoryDealsTotal() { return (int)sim::selDeals.size(); }
inline ulong HistoryDealGetTicket(int i) { return sim::deals[sim::selDeals[i]].ticket; }
inline sim::Deal* findDeal(ulong t) { for(auto& d : sim::deals) if(d.ticket == t) return &d; return nullptr; }
inline long HistoryDealGetInteger(ulong t, ENUM_DEAL_PROPERTY_INTEGER p) { auto* d = findDeal(t); if(!d) return 0; switch(p) { case DEAL_TIME: return d->time; case DEAL_TYPE: return d->type; case DEAL_ENTRY: return d->entry; case DEAL_REASON: return d->reason; case DEAL_MAGIC: return d->magic; case DEAL_POSITION_ID: return d->posId; default: return 0; } }
inline double HistoryDealGetDouble(ulong t, ENUM_DEAL_PROPERTY_DOUBLE p) { auto* d = findDeal(t); if(!d) return 0; switch(p) { case DEAL_VOLUME: return d->volume; case DEAL_PRICE: return d->price; case DEAL_PROFIT: return d->profit; case DEAL_COMMISSION: return d->commission; case DEAL_SWAP: return d->swap; case DEAL_FEE: return d->fee; case DEAL_SL: return d->sl; case DEAL_TP: return d->tp; default: return 0; } }
inline string HistoryDealGetString(ulong t, ENUM_DEAL_PROPERTY_STRING p) { auto* d = findDeal(t); if(!d || p != DEAL_COMMENT) return string(); return string(d->comment); }
inline bool OrderCalcMargin(ENUM_ORDER_TYPE, const string, double vol, double price, double& m) { m = vol * sim::contract * price / sim::leverage; return true; }

inline bool GlobalVariableCheck(const string n) { return sim::gvars.count(n.s) > 0; }
inline double GlobalVariableGet(const string n) { auto it = sim::gvars.find(n.s); return it == sim::gvars.end() ? 0 : it->second; }
inline datetime GlobalVariableSet(const string n, double v) { sim::gvars[n.s] = v; return sim::now.t; }
inline bool GlobalVariableDel(const string n) { return sim::gvars.erase(n.s) > 0; }
inline int GlobalVariablesDeleteAll(const string prefix = NULL, datetime = 0) { int k = 0; for(auto it = sim::gvars.begin(); it != sim::gvars.end();) { if(it->first.rfind(prefix.s, 0) == 0) { it = sim::gvars.erase(it); k++; } else ++it; } return k; }
inline void GlobalVariablesFlush() {}
inline int GlobalVariablesTotal() { return (int)sim::gvars.size(); }
inline string GlobalVariableName(int i) { auto it = sim::gvars.begin(); std::advance(it, i); return string(it->first); }

inline std::string fileKey(const string name, int flags) { return std::string((flags & FILE_COMMON) ? "common/" : "files/") + name.s; }
inline int FileOpen(const string name, int flags, short = '\t', uint = CP_ACP) {
  std::string key = fileKey(name, flags); bool exists = sim::files.count(key) > 0;
  if((flags & FILE_READ) && !(flags & FILE_WRITE) && !exists) { sim::lastError = 5004; return INVALID_HANDLE; }
  if((flags & FILE_WRITE) && !(flags & FILE_READ)) sim::files[key].content.clear();
  if(!exists) sim::files[key];
  sim::handles.push_back({key, 0, true}); return (int)sim::handles.size() - 1; }
inline void FileClose(int h) { auto& hd = sim::handles[h]; hd.open = false; std::string path = "simout_" + hd.key; for(auto& c : path) if(c == '/') c = '_'; std::ofstream(path, std::ios::binary) << sim::files[hd.key].content; }
inline uint FileWriteString(int h, const string text, int = -1) { auto& hd = sim::handles[h]; auto& c = sim::files[hd.key].content; if(hd.pos > c.size()) c.resize(hd.pos); c.replace(hd.pos, std::min(text.s.size(), c.size() - hd.pos), text.s); hd.pos += text.s.size(); return (uint)text.s.size(); }
inline string FileReadString(int h, int = -1) { auto& hd = sim::handles[h]; auto& c = sim::files[hd.key].content; size_t e = c.find('\n', hd.pos); std::string line = c.substr(hd.pos, e == std::string::npos ? std::string::npos : e - hd.pos); hd.pos = e == std::string::npos ? c.size() : e + 1; if(!line.empty() && line.back() == '\r') line.pop_back(); return string(line); }
inline bool FileIsEnding(int h) { auto& hd = sim::handles[h]; return hd.pos >= sim::files[hd.key].content.size(); }
inline bool FileSeek(int h, long off, ENUM_FILE_POSITION o) { auto& hd = sim::handles[h]; size_t sz = sim::files[hd.key].content.size(); hd.pos = o == SEEK_END ? sz + off : (o == SEEK_SET ? off : hd.pos + off); return true; }
inline ulong FileSize(int h) { return sim::files[sim::handles[h].key].content.size(); }
inline bool FileIsExist(const string name, int common = 0) { return sim::files.count(fileKey(name, common)) > 0; }

inline bool CalendarValueHistory(MqlArray<MqlCalendarValue>& v, datetime from, datetime to = 0, const string = NULL, const string = NULL) { v.v.clear(); for(auto& x : sim::calValues) if(x.time >= from && (to == 0 || x.time <= to)) v.v.push_back(x); return true; }
inline bool CalendarValueHistoryByEvent(ulong id, MqlArray<MqlCalendarValue>& v, datetime from, datetime to = 0) { v.v.clear(); for(auto& x : sim::calValues) if(x.event_id == id && x.time >= from && (to == 0 || x.time <= to)) v.v.push_back(x); return true; }
inline bool CalendarEventById(ulong id, MqlCalendarEvent& e) { for(auto& x : sim::calEvents) if(x.id == id) { e = x; return true; } return false; }


// ---- extra pieces used by the helper scripts
template<class T> void ZeroMemory(T& x) { x = T(); }
template<class T, class V> int ArrayInitialize(MqlArray<T>& a, V value) { for(auto& e : a.v) e = (T)value; return (int)a.v.size(); }
inline void Sleep(int) {}
inline bool IsStopped() { return false; }
inline bool TimeToStruct(datetime t, MqlDateTime& s) { time_t tt = t; struct tm g; gmtime_r(&tt, &g); s.year = g.tm_year + 1900; s.mon = g.tm_mon + 1; s.day = g.tm_mday; s.hour = g.tm_hour; s.min = g.tm_min; s.sec = g.tm_sec; s.day_of_week = g.tm_wday; s.day_of_year = g.tm_yday; return true; }
inline datetime StructToTime(MqlDateTime& s) { struct tm g = {}; g.tm_year = s.year - 1900; g.tm_mon = s.mon - 1; g.tm_mday = s.day; g.tm_hour = s.hour; g.tm_min = s.min; g.tm_sec = s.sec; return (datetime)timegm(&g); }
inline int CopyRatesM1(datetime from, datetime to, MqlArray<MqlRates>& r);
inline int CopyRates(const string, ENUM_TIMEFRAMES tf, datetime from, datetime to, MqlArray<MqlRates>& r) { if(tf == PERIOD_M1) return CopyRatesM1(from, to, r); if(tf != PERIOD_M15) return -1; r.v.clear(); for(auto& b : sim::m15) if(b.time >= from && b.time <= to) r.v.push_back(b); return (int)r.v.size(); }
inline int CalendarEventByCurrency(const string, MqlArray<MqlCalendarEvent>& e) { e.v = sim::calEvents; return (int)e.v.size(); }


// ---- custom symbols (for the spread script test)
#define TICK_FLAG_BID 2
#define TICK_FLAG_ASK 4
#define COPY_TICKS_ALL (-1)
namespace sim { std::map<std::string, bool> customSymbols; std::vector<MqlTick> customTicks; long customRates = 0; std::string lastDescription; }
inline int CopyTicksRange(const string, MqlArray<MqlTick>& out, uint = COPY_TICKS_ALL, ulong from = 0, ulong to = 0) {
  out.v.clear(); for(auto& k : sim::ticks) if((ulong)k.msc >= from && (ulong)k.msc <= to) { MqlTick t{}; t.time = k.t; t.time_msc = k.msc; t.bid = k.bid; t.ask = k.ask; t.flags = 6; out.v.push_back(t); } return (int)out.v.size(); }
inline bool CustomSymbolCreate(const string name, const string = "", const string = NULL) { sim::customSymbols[name.s] = true; return true; }
inline bool CustomSymbolSetString(const string, ENUM_SYMBOL_INFO_STRING, const string v) { sim::lastDescription = v.s; return true; }
inline int CustomTicksReplace(const string name, long from, long to, const MqlArray<MqlTick>& t, uint = WHOLE_ARRAY) {
  if(!sim::customSymbols.count(name.s)) return -1;
  std::vector<MqlTick> keep; for(auto& k : sim::customTicks) if(k.time_msc < from || k.time_msc > to) keep.push_back(k);
  for(auto& k : t.v) { if(k.time_msc < from || k.time_msc > to) { fprintf(stderr, "tick outside range\n"); abort(); } keep.push_back(k); }
  std::stable_sort(keep.begin(), keep.end(), [](const MqlTick& a, const MqlTick& b) { return a.time_msc < b.time_msc; }); sim::customTicks.swap(keep); return (int)t.v.size(); }
inline int CopyRatesM1(datetime from, datetime to, MqlArray<MqlRates>& r) { r.v.clear(); for(auto& k : sim::ticks) if(k.t >= from && k.t <= to && (r.v.empty() || r.v.back().time != k.t - k.t % 60)) { MqlRates b{}; b.time = k.t - k.t % 60; b.open = b.high = b.low = b.close = k.bid; b.spread = 25; r.v.push_back(b); } return (int)r.v.size(); }
inline int CustomRatesReplace(const string, datetime, datetime, const MqlArray<MqlRates>& r, uint = WHOLE_ARRAY) { sim::customRates += (long)r.v.size(); for(auto& b : r.v) if(b.spread != 50) { fprintf(stderr, "bad bar spread %d\n", b.spread); abort(); } return (int)r.v.size(); }

class CTrade {
  ulong m_magic = 0; uint m_ret = 0; ulong m_order = 0;
  bool open(int type, double vol, double sl, double tp, const string& comment) {
    if(vol < 0.01 - 1e-9 || std::fabs(vol / 0.01 - std::round(vol / 0.01)) > 1e-6) { m_ret = 10014; return false; }
    if(!sim::stopValid(type, sl) || !sim::tpValid(type, tp)) { m_ret = TRADE_RETCODE_INVALID_STOPS; return false; }
    double price = type == POSITION_TYPE_BUY ? sim::now.ask : sim::now.bid;
    sim::Pos p{sim::nextTicket++, 0, type, vol, price, sl, tp, sim::now.t, (long)m_magic, comment.s}; p.id = (long)p.ticket;
    double comm = -sim::commissionPerLotSide * vol;
    sim::deals.push_back({sim::nextTicket++, p.ticket, p.id, sim::now.t, type == POSITION_TYPE_BUY ? DEAL_TYPE_BUY : DEAL_TYPE_SELL, DEAL_ENTRY_IN, DEAL_REASON_EXPERT, vol, price, 0, comm, 0, 0, sl, tp, (long)m_magic, comment.s});
    sim::balance += comm; sim::positions.push_back(p); m_order = p.ticket; m_ret = TRADE_RETCODE_DONE; return true; }
public:
  void SetExpertMagicNumber(const ulong m) { m_magic = m; }
  void SetDeviationInPoints(const ulong) {}
  bool SetTypeFillingBySymbol(const string) { return true; }
  void SetMarginMode() {}
  void LogLevel(const ENUM_LOG_LEVELS) {}
  bool Buy(const double vol, const string = NULL, double = 0.0, const double sl = 0.0, const double tp = 0.0, const string comment = "") { return open(POSITION_TYPE_BUY, vol, sl, tp, comment); }
  bool Sell(const double vol, const string = NULL, double = 0.0, const double sl = 0.0, const double tp = 0.0, const string comment = "") { return open(POSITION_TYPE_SELL, vol, sl, tp, comment); }
  bool PositionModify(const ulong ticket, const double sl, const double tp) { auto* p = sim::findPos(ticket); if(!p) { m_ret = 10036; return false; }
    if(std::fabs(p->sl - sl) < 1e-9 && std::fabs(p->tp - tp) < 1e-9) { m_ret = TRADE_RETCODE_NO_CHANGES; return false; }
    if(!sim::stopValid(p->type, sl)) { m_ret = TRADE_RETCODE_INVALID_STOPS; return false; }
    p->sl = sl; p->tp = tp; m_ret = TRADE_RETCODE_DONE; return true; }
  bool PositionClose(const ulong ticket, const ulong = ULONG_MAX_MQL) { for(size_t i = 0; i < sim::positions.size(); i++) if(sim::positions[i].ticket == ticket) { sim::closePosition(i, DEAL_REASON_EXPERT, ""); m_ret = TRADE_RETCODE_DONE; return true; } m_ret = 10036; return false; }
  uint ResultRetcode() const { return m_ret; }
  string ResultRetcodeDescription() const { return string(std::string("retcode ") + std::to_string(m_ret)); }
  ulong ResultOrder() const { return m_order; }
};

namespace sim { std::map<std::string, bool>& customList() { return customSymbols; } }
