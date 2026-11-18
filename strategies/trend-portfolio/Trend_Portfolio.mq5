//+------------------------------------------------------------------+
//| Trend_Portfolio.mq5 - diversified time-series momentum           |
//| (Moskowitz, Ooi & Pedersen 2012; Hurst, Ooi & Pedersen 2017)     |
//| Monthly, for every market:                                       |
//|   signal = average of sign(return) over 1, 3 and 12 months       |
//|            -> -1, -1/3, +1/3 or +1                               |
//|   weight = signal x AssetVol / annualised vol (60 days)          |
//| Total notional capped at MaxGross x equity. Positions are only   |
//| changed when the direction flips or the size moves > 25%.        |
//| Missing symbols are skipped; a market joins when it has data.    |
//+------------------------------------------------------------------+
#property copyright "Strategy research"
#property version   "1.00"

#include <Trade/Trade.mqh>

input string InpSymbols  = "US500,NAS100,US30,GER40,UK100,JP225,FRA40,EU50,HK50,XAUUSD,XAGUSD,XTIUSD,USOIL,WTI,XBRUSD,UKOIL,BRENT,XNGUSD,NGAS,EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,USDCHF,NZDUSD"; // Markets
input double InpAssetVol = 0.04;  // Annual volatility budget per market (0.04 = 4%)
input int    InpVolDays  = 60;    // Volatility lookback (days)
input double InpMaxW     = 1.0;   // Max notional per market (x equity)
input double InpMaxGross = 4.0;   // Max total notional (x equity)
input double InpBand     = 0.25;  // Resize only when the size changes more than this
input long   InpMagic    = 20261122;

CTrade   trade;
string   S[];
double   tgt[];      // target signed notional fraction
bool     pend[];
double   pnlS[];     // realised P&L per market
int      g_rebalMonth = -1;

int      g_curMonth = -1;
double   g_monthStart = 0;
double   g_mret[];
int      g_mkey[];

int MonthKey(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.year * 12 + s.mon - 1; }

double NotionalPerLot(string sym)
{
   double price = SymbolInfoDouble(sym, SYMBOL_BID), perLot = 0;
   if(price <= 0 || !OrderCalcProfit(ORDER_TYPE_BUY, sym, 1.0, price, price * 1.01, perLot)) return 0;
   return MathAbs(perLot) / 0.01;
}

double AnnVol(string sym)
{
   double s = 0, s2 = 0; int n = 0;
   for(int k = 1; k <= InpVolDays; k++)
   {
      double a = iClose(sym, PERIOD_D1, k), b = iClose(sym, PERIOD_D1, k + 1);
      if(a <= 0 || b <= 0) return 0;
      double r = MathLog(a / b); s += r; s2 += r * r; n++;
   }
   if(n < 20) return 0;
   double var = (s2 - s * s / n) / (n - 1);
   return var > 0 ? MathSqrt(var * 252.0) : 0;
}

double Signal(string sym)
{
   int L[3] = {21, 63, 252};
   if(iBars(sym, PERIOD_D1) < 260) return 0;
   double c1 = iClose(sym, PERIOD_D1, 1), sum = 0;
   for(int k = 0; k < 3; k++)
   {
      double b = iClose(sym, PERIOD_D1, 1 + L[k]);
      if(b <= 0 || c1 <= 0) return 0;
      sum += c1 > b ? 1.0 : -1.0;
   }
   return sum / 3.0;
}

void ComputeTargets()
{
   int n = ArraySize(S);
   double gross = 0;
   for(int i = 0; i < n; i++)
   {
      double v = AnnVol(S[i]), sg = Signal(S[i]);
      tgt[i] = (v > 0) ? sg * MathMin(InpMaxW, InpAssetVol / v) : 0;
      gross += MathAbs(tgt[i]);
   }
   if(gross > InpMaxGross) for(int i = 0; i < n; i++) tgt[i] *= InpMaxGross / gross;
}

bool DoSym(int i)
{
   string sym = S[i];
   double npl = NotionalPerLot(sym);
   if(npl <= 0) return false;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN), vmax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   double want = MathFloor(MathAbs(tgt[i]) * eq / npl / step + 1e-9) * step;
   if(want < vmin) want = 0;
   want = MathMin(want, vmax);
   int wdir = tgt[i] > 0 ? 1 : (tgt[i] < 0 ? -1 : 0);
   if(want == 0) wdir = 0;

   // current position
   ulong tk = 0; double cur = 0; int cdir = 0;
   for(int k = PositionsTotal() - 1; k >= 0; k--)
   {
      ulong t = PositionGetTicket(k);
      if(t == 0 || PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != sym) continue;
      tk = t; cur = PositionGetDouble(POSITION_VOLUME);
      cdir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   }
   if(cdir == wdir && (wdir == 0 || MathAbs(want - cur) <= InpBand * cur)) return true;   // keep
   if(tk != 0)
   {
      if(!PositionSelectByTicket(tk)) return false;
      double pr =PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(!trade.PositionClose(tk)) return trade.ResultRetcode() != TRADE_RETCODE_MARKET_CLOSED ? true : false;
      pnlS[i] += pr;
   }
   if(wdir == 0) return true;
   bool ok = wdir > 0 ? trade.Buy(want, sym, 0, 0, 0, "TREND") : trade.Sell(want, sym, 0, 0, 0, "TREND");
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
   trade.SetDeviationInPoints(200);
   string parts[];
   int n = StringSplit(InpSymbols, ',', parts);
   for(int k = 0; k < n; k++)
   {
      string s = parts[k]; StringTrimLeft(s); StringTrimRight(s);
      if(s == "" || !SymbolSelect(s, true)) { if(s != "") PrintFormat("TREND skip %s", s); continue; }
      int j = ArraySize(S); ArrayResize(S, j + 1); S[j] = s;
   }
   int c = ArraySize(S);
   if(c == 0) return INIT_FAILED;
   ArrayResize(tgt, c); ArrayResize(pend, c); ArrayResize(pnlS, c);
   ArrayInitialize(tgt, 0); ArrayInitialize(pend, false); ArrayInitialize(pnlS, 0);
   string list = ""; for(int i = 0; i < c; i++) list += S[i] + " ";
   PrintFormat("TREND markets (%d): %s", c, list);
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
   if(mk != g_rebalMonth && s.day_of_week >= 1 && s.day_of_week <= 5 && s.hour >= 3)
   {
      g_rebalMonth = mk;
      ComputeTargets();
      ArrayInitialize(pend, true);
   }
   for(int i = 0; i < ArraySize(S); i++) if(pend[i] && DoSym(i)) pend[i] = false;
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
   PrintFormat("TREND_M pos=%d neg=%d of %d", pos, neg, m);
   PrintFormat("TREND_W worst=%.2f%% best=%.2f%%", 100 * worst, 100 * best);
   PrintFormat("TREND_S to2015=%+.1f%% from2016=%+.1f%%", 100 * (a1 - 1), 100 * (a2 - 1));
   int curY = -1; double acc = 1;
   for(int k = 0; k < m; k++)
   {
      int y = g_mkey[k] / 12;
      if(y != curY) { if(curY >= 0) PrintFormat("TREND_YEAR %d %+.1f%%", curY, 100 * (acc - 1)); curY = y; acc = 1; }
      acc *= 1 + g_mret[k];
   }
   if(curY >= 0) PrintFormat("TREND_YEAR %d %+.1f%%", curY, 100 * (acc - 1));
   HistorySelect(0, TimeCurrent() + 86400);
   double sw = 0, pr = 0;
   for(int d = 0; d < HistoryDealsTotal(); d++)
   {
      ulong t = HistoryDealGetTicket(d);
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic) continue;
      sw += HistoryDealGetDouble(t, DEAL_SWAP); pr += HistoryDealGetDouble(t, DEAL_PROFIT);
   }
   PrintFormat("TREND_SWAP price_pnl=%.0f swap=%.0f", pr, sw);
   for(int i = 0; i < ArraySize(S); i++) PrintFormat("TREND_SYM %s pnl=%.0f", S[i], pnlS[i]);
   return TesterStatistics(STAT_PROFIT);
}
//+------------------------------------------------------------------+
