//+------------------------------------------------------------------+
//| FX_G10_Basket.mq5 - cross-sectional G10 currency portfolio       |
//| Monthly, each currency (vs USD) is ranked on three factors:      |
//|   Carry    : policy rate at the previous year end (table below)  |
//|   Momentum : return vs USD over the last MomMonths months        |
//|   Value    : minus the return over the last ValMonths months     |
//| Score = weighted sum of demeaned ranks; weights scaled so that   |
//| the total notional of all legs = Gross x equity. Long the top,   |
//| short the bottom (USD leg implied). Positions rebuilt monthly.   |
//| Note: the rate table is approximate (year-end policy rates).     |
//| Note: the tester charges today's swap on all history.            |
//+------------------------------------------------------------------+
#property copyright "Strategy research"
#property version   "1.00"

#include <Trade/Trade.mqh>

input string InpPairs    = "EURUSD,GBPUSD,AUDUSD,NZDUSD,USDJPY,USDCHF,USDCAD,USDNOK,USDSEK"; // Pairs vs USD
input double InpWCarry   = 1.0;   // Weight: carry
input double InpWMom     = 1.0;   // Weight: momentum
input double InpWVal     = 1.0;   // Weight: value
input int    InpMomMonths = 12;   // Momentum lookback (months)
input int    InpValMonths = 60;   // Value lookback (months)
input double InpGross    = 2.0;   // Total notional of all legs (x equity)
input long   InpMagic    = 20261121;

CTrade   trade;
string   P[];       // pair
string   C[];       // non-USD currency of the pair
bool     Base[];    // true when the currency is the base (EURUSD), false for USDJPY
double   tgt[];     // target signed notional fraction (+ = long the currency)
bool     pend[];    // rebalance still to do for this pair
int      g_rebalMonth = -1;

int      g_curMonth = -1;
double   g_monthStart = 0;
double   g_mret[];
int      g_mkey[];

string CUR[] = {"USD","EUR","JPY","GBP","CHF","AUD","NZD","CAD","NOK","SEK"};
// year-end policy rates (%) 2004 .. 2025, approximate
double RATES[10][22] = {
 {2.25,4.25,5.25,4.25,0.25,0.25,0.25,0.25,0.25,0.25,0.25,0.50,0.75,1.50,2.50,1.75,0.25,0.25,4.50,5.50,4.50,3.75}, // USD
 {2.00,2.25,3.50,4.00,2.50,1.00,1.00,1.00,0.75,0.25,0.05,0.05,0.00,0.00,0.00,0.00,0.00,0.00,2.50,4.50,3.15,2.15}, // EUR
 {0.00,0.00,0.25,0.50,0.10,0.10,0.10,0.10,0.10,0.10,0.10,0.10,-0.10,-0.10,-0.10,-0.10,-0.10,-0.10,-0.10,-0.10,0.25,0.50}, // JPY
 {4.75,4.50,5.00,5.50,2.00,0.50,0.50,0.50,0.50,0.50,0.50,0.50,0.25,0.50,0.75,0.75,0.10,0.25,3.50,5.25,4.75,4.00}, // GBP
 {0.75,1.00,2.00,2.75,0.50,0.25,0.25,0.00,0.00,0.00,0.00,-0.75,-0.75,-0.75,-0.75,-0.75,-0.75,-0.75,1.00,1.75,0.50,0.00}, // CHF
 {5.25,5.50,6.25,6.75,4.25,3.75,4.75,4.25,3.00,2.50,2.50,2.00,1.50,1.50,1.50,0.75,0.10,0.10,3.10,4.35,4.35,3.60}, // AUD
 {6.50,7.25,7.25,8.25,5.00,2.50,3.00,2.50,2.50,2.50,3.50,2.50,1.75,1.75,1.75,1.00,0.25,0.75,4.25,5.50,4.25,2.25}, // NZD
 {2.50,3.25,4.25,4.25,1.50,0.25,1.00,1.00,1.00,1.00,1.00,0.50,0.50,1.00,1.75,1.75,0.25,0.25,4.25,5.00,3.25,2.25}, // CAD
 {1.75,2.25,3.50,5.25,3.00,1.75,2.00,1.75,1.50,1.50,1.25,0.75,0.50,0.50,0.75,1.50,0.00,0.50,2.75,4.50,4.50,4.00}, // NOK
 {2.00,1.50,3.00,4.00,2.00,0.25,1.25,1.75,1.00,0.75,0.00,-0.35,-0.50,-0.50,-0.25,0.00,0.00,0.00,2.50,4.00,2.50,1.75}  // SEK
};

int MonthKey(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.year * 12 + s.mon - 1; }

double Rate(string cur, int year)
{
   int y = year - 1 - 2004;              // previous year end
   if(y < 0) y = 0; if(y > 21) y = 21;
   for(int i = 0; i < 10; i++) if(CUR[i] == cur) return RATES[i][y];
   return -999;
}

// return of the currency vs USD over k completed months (from month-end closes)
bool CurRet(int i, int k, double &r)
{
   double a = iClose(P[i], PERIOD_MN1, 1), b = iClose(P[i], PERIOD_MN1, 1 + k);
   if(a <= 0 || b <= 0) return false;
   double pr = a / b - 1.0;
   r = Base[i] ? pr : 1.0 / (1.0 + pr) - 1.0;
   return true;
}

// demeaned ranks, scaled so that sum |score| = 1
void RankScore(const double &v[], double &out[])
{
   int n = ArraySize(v);
   ArrayResize(out, n);
   double mean = (n - 1) / 2.0, tot = 0;
   for(int i = 0; i < n; i++)
   {
      int rk = 0;
      for(int j = 0; j < n; j++) if(v[j] < v[i] || (v[j] == v[i] && j < i)) rk++;
      out[i] = rk - mean; tot += MathAbs(out[i]);
   }
   for(int i = 0; i < n; i++) out[i] = tot > 0 ? out[i] / tot : 0;
}

void ComputeTargets()
{
   int n = ArraySize(P), m = n + 1;            // + USD at index n
   double car[], mom[], val[], sc[], sm[], sv[];
   ArrayResize(car, m); ArrayResize(mom, m); ArrayResize(val, m);
   int year = (int)(MonthKey(TimeCurrent()) / 12);
   bool okM = true, okV = true;
   for(int i = 0; i < n; i++)
   {
      car[i] = Rate(C[i], year);
      double r;
      if(CurRet(i, InpMomMonths, r)) mom[i] = r; else okM = false;
      if(CurRet(i, InpValMonths, r)) val[i] = -r; else okV = false;
   }
   car[n] = Rate("USD", year); mom[n] = 0; val[n] = 0;
   RankScore(car, sc); RankScore(mom, sm); RankScore(val, sv);
   double wc = InpWCarry, wm = okM ? InpWMom : 0, wv = okV ? InpWVal : 0;
   double comb[]; ArrayResize(comb, m);
   double tot = 0;
   for(int i = 0; i < m; i++) { comb[i] = wc * sc[i] + wm * sm[i] + wv * sv[i]; tot += MathAbs(comb[i]); }
   // total notional of all legs (incl. the implied USD leg) = Gross
   for(int i = 0; i < n; i++) tgt[i] = tot > 0 ? InpGross * comb[i] / tot : 0;
}

double NotionalPerLot(string sym)
{
   double price = SymbolInfoDouble(sym, SYMBOL_BID), perLot = 0;
   if(price <= 0 || !OrderCalcProfit(ORDER_TYPE_BUY, sym, 1.0, price, price * 1.01, perLot)) return 0;
   return MathAbs(perLot) / 0.01;
}

bool DoPair(int i)
{
   // close existing
   for(int k = PositionsTotal() - 1; k >= 0; k--)
   {
      ulong t = PositionGetTicket(k);
      if(t == 0 || PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != P[i]) continue;
      if(!trade.PositionClose(t)) return false;
   }
   double npl = NotionalPerLot(P[i]);
   if(npl <= 0) return false;
   double w = tgt[i];
   bool buyPair = Base[i] ? (w > 0) : (w < 0);      // long EUR = buy EURUSD; long JPY = sell USDJPY
   double step = SymbolInfoDouble(P[i], SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(P[i], SYMBOL_VOLUME_MIN);
   if(step <= 0) step = 0.01;
   double lots = MathFloor(MathAbs(w) * AccountInfoDouble(ACCOUNT_EQUITY) / npl / step + 1e-9) * step;
   if(lots < vmin) return true;
   bool ok = buyPair ? trade.Buy(lots, P[i], 0, 0, 0, "G10") : trade.Sell(lots, P[i], 0, 0, 0, "G10");
   return ok || trade.ResultRetcode() != TRADE_RETCODE_MARKET_CLOSED;
}

void MarkMonth()
{
   int mk = MonthKey(TimeCurrent());
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_curMonth < 0) { g_curMonth = mk; g_monthStart = eq; return; }
   if(mk != g_curMonth)
   {
      int n = ArraySize(g_mret);
      ArrayResize(g_mret, n + 1); ArrayResize(g_mkey, n + 1);
      g_mret[n] = g_monthStart > 0 ? eq / g_monthStart - 1.0 : 0; g_mkey[n] = g_curMonth;
      g_curMonth = mk; g_monthStart = eq;
   }
}

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   string parts[];
   int n = StringSplit(InpPairs, ',', parts);
   for(int k = 0; k < n; k++)
   {
      string s = parts[k]; StringTrimLeft(s); StringTrimRight(s);
      if(s == "" || !SymbolSelect(s, true)) { if(s != "") PrintFormat("G10 skip %s", s); continue; }
      string b = StringSubstr(s, 0, 3), q = StringSubstr(s, 3, 3);
      if(b != "USD" && q != "USD") continue;
      int j = ArraySize(P);
      ArrayResize(P, j + 1); ArrayResize(C, j + 1); ArrayResize(Base, j + 1);
      P[j] = s; Base[j] = (q == "USD"); C[j] = Base[j] ? b : q;
   }
   int c = ArraySize(P);
   if(c < 3) return INIT_FAILED;
   ArrayResize(tgt, c); ArrayResize(pend, c); ArrayInitialize(tgt, 0); ArrayInitialize(pend, false);
   string list = ""; for(int i = 0; i < c; i++) list += P[i] + " ";
   PrintFormat("G10 pairs (%d): %s", c, list);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   static long lastHour = 0;
   long h = (long)(TimeCurrent() / 3600);
   if(h == lastHour) return;
   lastHour = h;
   MarkMonth();
   MqlDateTime s; TimeToStruct(TimeCurrent(), s);
   int mk = MonthKey(TimeCurrent());
   if(mk != g_rebalMonth && s.day_of_week >= 1 && s.day_of_week <= 5 && s.hour >= 2)
   {
      g_rebalMonth = mk;
      ComputeTargets();
      ArrayInitialize(pend, true);
   }
   for(int i = 0; i < ArraySize(P); i++) if(pend[i] && DoPair(i)) pend[i] = false;
}

double OnTester()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_curMonth >= 0) { int n = ArraySize(g_mret); ArrayResize(g_mret, n + 1); ArrayResize(g_mkey, n + 1); g_mret[n] = g_monthStart > 0 ? eq / g_monthStart - 1 : 0; g_mkey[n] = g_curMonth; }
   int m = ArraySize(g_mret), pos = 0, neg = 0;
   double worst = 0, best = 0, a1 = 1, a2 = 1;
   for(int k = 0; k < m; k++)
   {
      double r = g_mret[k];
      if(r > 0.0005) pos++; else if(r < -0.0005) neg++;
      worst = MathMin(worst, r); best = MathMax(best, r);
      if(g_mkey[k] / 12 < 2016) a1 *= 1 + r; else a2 *= 1 + r;
   }
   PrintFormat("G10_M pos=%d neg=%d of %d", pos, neg, m);
   PrintFormat("G10_W worst=%.2f%% best=%.2f%%", 100 * worst, 100 * best);
   PrintFormat("G10_S to2015=%+.1f%% from2016=%+.1f%%", 100 * (a1 - 1), 100 * (a2 - 1));
   int curY = -1; double acc = 1;
   for(int k = 0; k < m; k++)
   {
      int y = g_mkey[k] / 12;
      if(y != curY) { if(curY >= 0) PrintFormat("G10_YEAR %d %+.1f%%", curY, 100 * (acc - 1)); curY = y; acc = 1; }
      acc *= 1 + g_mret[k];
   }
   if(curY >= 0) PrintFormat("G10_YEAR %d %+.1f%%", curY, 100 * (acc - 1));
   HistorySelect(0, TimeCurrent() + 86400);
   double sw = 0, pr = 0;
   for(int d = 0; d < HistoryDealsTotal(); d++)
   {
      ulong t = HistoryDealGetTicket(d);
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic) continue;
      sw += HistoryDealGetDouble(t, DEAL_SWAP); pr += HistoryDealGetDouble(t, DEAL_PROFIT);
   }
   PrintFormat("G10_SWAP price_pnl=%.0f swap=%.0f", pr, sw);
   return TesterStatistics(STAT_PROFIT);
}
//+------------------------------------------------------------------+
