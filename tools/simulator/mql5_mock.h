// Minimal C++ stand-in for the MQL5 API, used ONLY to syntax/type-check .mq5 code.
#pragma once
#include <string>
#include <vector>
#include <cstddef>
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

// ---- string: no implicit conversion from numbers (MQL5 would warn; we want to catch it)
class string {
public:
  std::string s;
  string() {}
  string(const char* c) : s(c) {}
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
  bool operator>(const string& o) const { return s > o.s; }
private:
  string(int); string(long); string(double); string(unsigned long); string(unsigned int); string(char); string(bool);
};
inline string operator+(const string& a, const string& b) { string r(a); r += b; return r; }
inline string operator+(const string& a, const char* b) { string r(a); r += b; return r; }
inline string operator+(const char* a, const string& b) { string r(a); r += b; return r; }

// ---- dynamic arrays
template<class T> struct MqlArray {
  std::vector<T> v;
  MqlArray() {}
  explicit MqlArray(int n) : v(n) {}
  T& operator[](int i) { return v[i]; }
  const T& operator[](int i) const { return v[i]; }
};
template<class T> int ArraySize(const MqlArray<T>& a) { return (int)a.v.size(); }
template<class T> int ArrayResize(MqlArray<T>& a, int n, int reserve = 0) { a.v.resize(n); (void)reserve; return n; }
template<class T> bool ArraySort(MqlArray<T>& a) { (void)a; return true; }
template<class T> void ArrayFree(MqlArray<T>& a) { a.v.clear(); }
template<class T> bool ArraySetAsSeries(MqlArray<T>& a, bool f) { (void)a; (void)f; return true; }
template<class T> int ArrayMaximum(const MqlArray<T>& a, int start = 0, int count = -1) { (void)a; (void)start; (void)count; return 0; }
template<class T> int ArrayMinimum(const MqlArray<T>& a, int start = 0, int count = -1) { (void)a; (void)start; (void)count; return 0; }
template<class T, class V> int ArrayInitialize(MqlArray<T>& a, V value) { (void)a; (void)value; return 0; }
template<class T> int ArrayCopy(MqlArray<T>& dst, const MqlArray<T>& src, int dst_start = 0, int src_start = 0, int count = -1) { (void)dst; (void)src; (void)dst_start; (void)src_start; (void)count; return 0; }

#define WHOLE_ARRAY (-1)
#define INVALID_HANDLE (-1)
#define EMPTY_VALUE (1.7976931348623158e+308)
#define ULONG_MAX_MQL 18446744073709551615UL
#define CP_ACP 0
#define CP_UTF8 65001

// ---- enums
enum ENUM_TIMEFRAMES { PERIOD_CURRENT=0, PERIOD_M1=1, PERIOD_M5=5, PERIOD_M15=15, PERIOD_M30=30, PERIOD_H1=16385, PERIOD_H4=16388, PERIOD_D1=16408, PERIOD_W1=32769, PERIOD_MN1=49153 };
enum ENUM_MA_METHOD { MODE_SMA, MODE_EMA, MODE_SMMA, MODE_LWMA };
enum ENUM_APPLIED_PRICE { PRICE_CLOSE=1, PRICE_OPEN, PRICE_HIGH, PRICE_LOW, PRICE_MEDIAN, PRICE_TYPICAL, PRICE_WEIGHTED };
enum ENUM_SERIESMODE { MODE_OPEN, MODE_LOW, MODE_HIGH, MODE_CLOSE, MODE_VOLUME, MODE_REAL_VOLUME, MODE_SPREAD };
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
enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY, ORDER_TYPE_SELL, ORDER_TYPE_BUY_LIMIT, ORDER_TYPE_SELL_LIMIT, ORDER_TYPE_BUY_STOP, ORDER_TYPE_SELL_STOP };
enum ENUM_INIT_RETCODE { INIT_SUCCEEDED=0, INIT_FAILED=1, INIT_PARAMETERS_INCORRECT=32767, INIT_AGENT_NOT_SUITABLE=32766 };
enum ENUM_LOG_LEVELS { LOG_LEVEL_NO, LOG_LEVEL_ERRORS, LOG_LEVEL_ALL };
enum ENUM_FILE_POSITION { SEEK_SET, SEEK_CUR, SEEK_END };
enum ENUM_CALENDAR_EVENT_IMPORTANCE { CALENDAR_IMPORTANCE_NONE, CALENDAR_IMPORTANCE_LOW, CALENDAR_IMPORTANCE_MODERATE, CALENDAR_IMPORTANCE_HIGH };
enum ENUM_CALENDAR_EVENT_TIMEMODE { CALENDAR_TIMEMODE_DATETIME, CALENDAR_TIMEMODE_DATE, CALENDAR_TIMEMODE_NOTIME, CALENDAR_TIMEMODE_TENTATIVE };
enum ENUM_CALENDAR_EVENT_TYPE { CALENDAR_TYPE_EVENT, CALENDAR_TYPE_INDICATOR, CALENDAR_TYPE_HOLIDAY };
enum ENUM_CALENDAR_EVENT_IMPACT { CALENDAR_IMPACT_NA, CALENDAR_IMPACT_POSITIVE, CALENDAR_IMPACT_NEGATIVE };
enum ENUM_DAY_OF_WEEK { SUNDAY, MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY };

#define FILE_READ 1
#define FILE_WRITE 2
#define FILE_BIN 4
#define FILE_CSV 8
#define FILE_TXT 16
#define FILE_ANSI 32
#define FILE_UNICODE 64
#define FILE_SHARE_READ 128
#define FILE_SHARE_WRITE 256
#define FILE_REWRITE 512
#define FILE_COMMON 4096
#define TIME_DATE 1
#define TIME_MINUTES 2
#define TIME_SECONDS 4
#define TRADE_RETCODE_PLACED 10008
#define TRADE_RETCODE_DONE 10009
#define TRADE_RETCODE_DONE_PARTIAL 10010
#define TRADE_RETCODE_NO_CHANGES 10025
#define TICK_FLAG_BID 2
#define TICK_FLAG_ASK 4
#define TICK_FLAG_LAST 8
#define TICK_FLAG_VOLUME 16
#define TICK_FLAG_BUY 32
#define TICK_FLAG_SELL 64
#define COPY_TICKS_INFO 1
#define COPY_TICKS_TRADE 2
#define COPY_TICKS_ALL (-1)
#define ERR_HISTORY_TIMEOUT 4403

// ---- structs
struct MqlTick { datetime time; double bid; double ask; double last; ulong volume; long time_msc; uint flags; double volume_real; };
struct MqlDateTime { int year; int mon; int day; int hour; int min; int sec; int day_of_week; int day_of_year; };
struct MqlRates { datetime time; double open; double high; double low; double close; long tick_volume; int spread; long real_volume; };
struct MqlCalendarValue { ulong id; ulong event_id; datetime time; datetime period; int revision; long actual_value; long prev_value; long revised_prev_value; long forecast_value; ENUM_CALENDAR_EVENT_IMPACT impact_type; };
struct MqlCalendarEvent { ulong id; ENUM_CALENDAR_EVENT_TYPE type; int sector; int frequency; ENUM_CALENDAR_EVENT_TIMEMODE time_mode; ulong country_id; int unit; ENUM_CALENDAR_EVENT_IMPORTANCE importance; int multiplier; uint digits; string source_url; string event_code; string name; };
template<class T> void ZeroMemory(T& x) { (void)x; }

// ---- predefined variables
extern string _Symbol; extern ENUM_TIMEFRAMES _Period; extern double _Point; extern int _Digits;

// ---- output
template<class... A> void Print(A... a) { (void)sizeof...(a); }
template<class... A> void Alert(A... a) { (void)sizeof...(a); }
template<class... A> void Comment(A... a) { (void)sizeof...(a); }
template<class... A> void PrintFormat(const string fmt, A... a) { (void)fmt; (void)sizeof...(a); }
template<class... A> string StringFormat(const string fmt, A... a) { (void)sizeof...(a); return fmt; }

// ---- math
double MathMax(double a, double b); double MathMin(double a, double b); double MathAbs(double a);
double MathRound(double a); double MathFloor(double a); double MathCeil(double a); double MathPow(double a, double b);
double MathLog10(double a); double MathSqrt(double a); bool MathIsValidNumber(double a); double NormalizeDouble(double v, int digits);

// ---- strings & conversions
int StringLen(const string s); int StringFind(const string s, const string match, int start = 0);
string StringSubstr(const string s, int start, int length = -1); int StringReplace(string& s, const string find, const string repl);
int StringTrimLeft(string& s); int StringTrimRight(string& s); bool StringToUpper(string& s); bool StringToLower(string& s);
int StringCompare(const string a, const string b, bool case_sensitive = true); ushort StringGetCharacter(const string s, int pos);
int StringSplit(const string s, const ushort separator, MqlArray<string>& result);
string IntegerToString(long number, int str_len = 0, ushort fill_symbol = ' ');
string DoubleToString(double value, int digits = 8); string TimeToString(datetime value, int mode = TIME_DATE | TIME_MINUTES);
datetime StringToTime(const string s); long StringToInteger(const string s); double StringToDouble(const string s);
template<class E> string EnumToString(E e) { (void)e; return string(); }
string ShortToString(ushort c); string CharToString(uchar c);

// ---- time
datetime TimeCurrent(); datetime TimeTradeServer(); datetime TimeGMT(); datetime TimeLocal();
bool TimeToStruct(datetime t, MqlDateTime& s); datetime StructToTime(MqlDateTime& s);
uint GetTickCount(); void Sleep(int ms); bool IsStopped(); int GetLastError(); void ResetLastError(); void ExpertRemove();

// ---- info
int MQLInfoInteger(ENUM_MQL_INFO_INTEGER p); int TerminalInfoInteger(ENUM_TERMINAL_INFO_INTEGER p); string TerminalInfoString(ENUM_TERMINAL_INFO_STRING p);
double AccountInfoDouble(ENUM_ACCOUNT_INFO_DOUBLE p); long AccountInfoInteger(ENUM_ACCOUNT_INFO_INTEGER p); string AccountInfoString(ENUM_ACCOUNT_INFO_STRING p);
double SymbolInfoDouble(const string sym, ENUM_SYMBOL_INFO_DOUBLE p); long SymbolInfoInteger(const string sym, ENUM_SYMBOL_INFO_INTEGER p);
string SymbolInfoString(const string sym, ENUM_SYMBOL_INFO_STRING p); bool SymbolInfoTick(const string sym, MqlTick& tick);
bool SymbolSelect(const string sym, bool select); bool SymbolExist(const string sym, bool& is_custom);
int SymbolsTotal(bool selected); string SymbolName(int pos, bool selected);

// ---- series & indicators
datetime iTime(const string sym, ENUM_TIMEFRAMES tf, int shift); double iClose(const string sym, ENUM_TIMEFRAMES tf, int shift);
double iHigh(const string sym, ENUM_TIMEFRAMES tf, int shift); double iLow(const string sym, ENUM_TIMEFRAMES tf, int shift);
double iOpen(const string sym, ENUM_TIMEFRAMES tf, int shift); int iBars(const string sym, ENUM_TIMEFRAMES tf);
int Bars(const string sym, ENUM_TIMEFRAMES tf); int Bars(const string sym, ENUM_TIMEFRAMES tf, datetime start, datetime stop);
int iBarShift(const string sym, ENUM_TIMEFRAMES tf, datetime t, bool exact = false);
int CopyHigh(const string sym, ENUM_TIMEFRAMES tf, int start_pos, int count, MqlArray<double>& a);
int CopyLow(const string sym, ENUM_TIMEFRAMES tf, int start_pos, int count, MqlArray<double>& a);
int CopyClose(const string sym, ENUM_TIMEFRAMES tf, int start_pos, int count, MqlArray<double>& a);
int CopyTime(const string sym, ENUM_TIMEFRAMES tf, int start_pos, int count, MqlArray<datetime>& a);
int CopyRates(const string sym, ENUM_TIMEFRAMES tf, int start_pos, int count, MqlArray<MqlRates>& a);
int CopyRates(const string sym, ENUM_TIMEFRAMES tf, datetime start, datetime stop, MqlArray<MqlRates>& a);
int CopyTicksRange(const string sym, MqlArray<MqlTick>& ticks, uint flags = COPY_TICKS_ALL, ulong from_msc = 0, ulong to_msc = 0);
int CopyBuffer(int handle, int buffer, int start_pos, int count, MqlArray<double>& a);
int CopyBuffer(int handle, int buffer, datetime start_time, int count, MqlArray<double>& a);
int CopyBuffer(int handle, int buffer, datetime start_time, datetime stop_time, MqlArray<double>& a);
int iMA(const string sym, ENUM_TIMEFRAMES tf, int ma_period, int ma_shift, ENUM_MA_METHOD method, ENUM_APPLIED_PRICE price);
int iATR(const string sym, ENUM_TIMEFRAMES tf, int ma_period);
int BarsCalculated(int handle); bool IndicatorRelease(int handle); int PeriodSeconds(ENUM_TIMEFRAMES tf = PERIOD_CURRENT);

// ---- trading / history
int PositionsTotal(); ulong PositionGetTicket(int index); bool PositionSelectByTicket(ulong ticket); bool PositionSelect(const string sym);
long PositionGetInteger(ENUM_POSITION_PROPERTY_INTEGER p); double PositionGetDouble(ENUM_POSITION_PROPERTY_DOUBLE p); string PositionGetString(ENUM_POSITION_PROPERTY_STRING p);
bool HistorySelect(datetime from, datetime to); bool HistorySelectByPosition(long position_id); int HistoryDealsTotal(); ulong HistoryDealGetTicket(int index);
long HistoryDealGetInteger(ulong ticket, ENUM_DEAL_PROPERTY_INTEGER p); double HistoryDealGetDouble(ulong ticket, ENUM_DEAL_PROPERTY_DOUBLE p); string HistoryDealGetString(ulong ticket, ENUM_DEAL_PROPERTY_STRING p);
bool OrderCalcMargin(ENUM_ORDER_TYPE action, const string sym, double volume, double price, double& margin);
bool OrderCalcProfit(ENUM_ORDER_TYPE action, const string sym, double volume, double price_open, double price_close, double& profit);

// ---- global variables of the terminal
bool GlobalVariableCheck(const string name); double GlobalVariableGet(const string name); bool GlobalVariableGet(const string name, double& value);
datetime GlobalVariableSet(const string name, double value); bool GlobalVariableDel(const string name);
int GlobalVariablesDeleteAll(const string prefix = NULL, datetime limit = 0); void GlobalVariablesFlush(); int GlobalVariablesTotal(); string GlobalVariableName(int index);

// ---- files
int FileOpen(const string name, int flags, short delimiter = '\t', uint codepage = CP_ACP); void FileClose(int h);
uint FileWriteString(int h, const string text, int length = -1); string FileReadString(int h, int length = -1);
bool FileIsEnding(int h); bool FileSeek(int h, long offset, ENUM_FILE_POSITION origin); ulong FileSize(int h);
bool FileIsExist(const string name, int common_flag = 0); void FileFlush(int h); bool FileDelete(const string name, int common_flag = 0);

// ---- economic calendar
bool CalendarValueHistory(MqlArray<MqlCalendarValue>& values, datetime from, datetime to = 0, const string country = NULL, const string currency = NULL);
bool CalendarEventById(ulong event_id, MqlCalendarEvent& ev);
int CalendarEventByCurrency(const string currency, MqlArray<MqlCalendarEvent>& events);
bool CalendarValueHistoryByEvent(ulong event_id, MqlArray<MqlCalendarValue>& values, datetime from, datetime to = 0);

// ---- custom symbols
bool CustomSymbolCreate(const string name, const string path = "", const string origin = NULL);
bool CustomSymbolDelete(const string name);
int CustomTicksReplace(const string sym, long from_msc, long to_msc, const MqlArray<MqlTick>& ticks, uint count = WHOLE_ARRAY);
int CustomTicksDelete(const string sym, long from_msc, long to_msc);
int CustomRatesReplace(const string sym, datetime from, datetime to, const MqlArray<MqlRates>& rates, uint count = WHOLE_ARRAY);
int CustomRatesDelete(const string sym, datetime from, datetime to);
bool CustomSymbolSetString(const string sym, ENUM_SYMBOL_INFO_STRING p, const string value);
bool CustomSymbolSetInteger(const string sym, ENUM_SYMBOL_INFO_INTEGER p, long value);

// ---- CTrade (Trade\Trade.mqh)
class CTrade {
public:
  void SetExpertMagicNumber(const ulong magic);
  void SetDeviationInPoints(const ulong deviation);
  bool SetTypeFillingBySymbol(const string symbol);
  void SetMarginMode();
  void LogLevel(const ENUM_LOG_LEVELS level);
  bool Buy(const double volume, const string symbol = NULL, double price = 0.0, const double sl = 0.0, const double tp = 0.0, const string comment = "");
  bool Sell(const double volume, const string symbol = NULL, double price = 0.0, const double sl = 0.0, const double tp = 0.0, const string comment = "");
  bool PositionModify(const ulong ticket, const double sl, const double tp);
  bool PositionModify(const string symbol, const double sl, const double tp);
  bool PositionClose(const ulong ticket, const ulong deviation = ULONG_MAX_MQL);
  bool PositionClose(const string symbol, const ulong deviation = ULONG_MAX_MQL);
  uint ResultRetcode() const; string ResultRetcodeDescription() const; ulong ResultOrder() const; ulong ResultDeal() const; double ResultPrice() const;
};
