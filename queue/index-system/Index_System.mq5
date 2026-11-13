//+------------------------------------------------------------------+
//| Index_System.mq5 - basket of stock indices, two documented edges |
//|  A) Turn of the month (McConnell & Xu 2008): long from the open  |
//|     of the last trading day of the month until the open of the   |
//|     (TomDaysAfter+1)-th trading day of the new month.            |
//|  B) IBS mean reversion: IBS < 0.3 and close below               |
//|     HH(10) - 2.5 x avg range(25); exit when close > prior high.  |
//| Size: volatility targeting - weight = RiskVol / annualised vol   |
//|       (20 days), capped per position and for the whole basket.   |
//| Report: monthly / yearly returns, per-component profit.          |
//+------------------------------------------------------------------+
#property copyright "Strategy research"
#property version   "1.00"

#include <Trade/Trade.mqh>

input string InpSymbols    = "US500,US30,UK100,JP225,NAS100,GER40,FRA40,EU50,HK50"; // Basket
input bool   InpUseTOM     = true;   // A) Turn of the month
input int    InpTomAfter   = 3;      // A) Trading days held into the new month
input bool   InpUseIBS     = true;   // B) IBS mean reversion
input double InpIBS        = 0.3;    // B) IBS threshold
input int    InpLenH       = 10;     // B) Pullback highest high length
input int    InpLenR       = 25;     // B) Pullback average range length
input double InpMult       = 2.5;    // B) Pullback k x average range
input double InpRiskVol    = 0.05;   // Annual volatility budget per position (0.05 = 5%)
input int    InpVolLen     = 20;     // Volatility lookback (days)
input double InpMaxW       = 0.5;    // Max notional per position (x equity)
input double InpMaxGross   = 1.5;    // Max total notional (x equity)
input int    InpDelayMin   = 30;     // Act X minutes after the daily bar opens
input long   InpMagic      = 20261120; // Magic (IBS = magic, TOM = magic+1)

CTrade   trade;
string   S[];
datetime lastBar[];

int      g_curMonth = -1;
double   g_monthStart = 0;
double   g_mret[];
int      g_mkey[];

int MonthKey(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.year * 12 + s.mon - 1; }
int MonOf(datetime t)    { MqlDateTime s; TimeToStruct(t, s); return s.mon; }
int DowOf(datetime t)    { MqlDateTime s; TimeToStruct(t, s); return s.day_of_week; }

bool FindPos(string sym, long magic, ulong &tk)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym && PositionGetInteger(POSITION_MAGIC) == magic) { tk = t; return true; }
   }
   return false;
}

double NotionalPerLot(string sym)
{
   double price = SymbolInfoDouble(sym, SYMBOL_BID), perLot = 0;
   if(price <= 0 || !OrderCalcProfit(ORDER_TYPE_BUY, sym, 1.0, price, price * 1.01, perLot)) return 0;
   return MathAbs(perLot) / 0.01;
}

double GrossNow()
{
   double g = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      long m = PositionGetInteger(POSITION_MAGIC);
      if(m != InpMagic && m != InpMagic + 1) continue;
      g += NotionalPerLot(PositionGetString(POSITION_SYMBOL)) * PositionGetDouble(POSITION_VOLUME);
   }
   return g;
}

double AnnVol(string sym)
{
   double s = 0, s2 = 0; int n = 0;
   for(int k = 1; k <= InpVolLen; k++)
   {
      double a = iClose(sym, PERIOD_D1, k), b = iClose(sym, PERIOD_D1, k + 1);
      if(a <= 0 || b <= 0) return 0;
      double r = MathLog(a / b); s += r; s2 += r * r; n++;
   }
   if(n < 5) return 0;
   double var = (s2 - s * s / n) / (n - 1);
   return var > 0 ? MathSqrt(var * 252.0) : 0;
}

double Lots(string sym)
{
   double vol = AnnVol(sym), npl = NotionalPerLot(sym);
   if(vol <= 0 || npl <= 0) return 0;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double w = MathMin(InpMaxW, InpRiskVol / vol);
   double want = MathMin(w * eq, InpMaxGross * eq - GrossNow());
   if(want <= 0.25 * w * eq) return 0;
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN), vmax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   double lots = MathFloor(want / npl / step + 1e-9) * step;
   if(lots < vmin) return 0;
   return MathMin(lots, vmax);
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

// returns false when the market was closed (retry later)
bool Close(ulong tk) { if(trade.PositionClose(tk)) return true; return trade.ResultRetcode() != TRADE_RETCODE_MARKET_CLOSED; }
bool Open(string sym, long magic, string cmt)
{
   double lots = Lots(sym);
   if(lots <= 0) return true;
   trade.SetExpertMagicNumber(magic);
   if(trade.Buy(lots, sym, 0, 0, 0, cmt)) return true;
   return trade.ResultRetcode() != TRADE_RETCODE_MARKET_CLOSED;
}

void Process(int i)
{
   string sym = S[i];
   datetime bt = iTime(sym, PERIOD_D1, 0);
   if(bt == 0 || bt == lastBar[i]) return;
   if(TimeCurrent() < bt + InpDelayMin * 60) return;
   if(iBars(sym, PERIOD_D1) < MathMax(InpLenR, InpVolLen) + 5) return;
   bool ok = true;
   ulong tk;

   // ---- A) turn of the month
   if(InpUseTOM)
   {
      int mon = MonOf(bt), dayIdx = 1;
      for(int k = 1; k < 30; k++) { datetime t = iTime(sym, PERIOD_D1, k); if(t == 0 || MonOf(t) != mon) break; dayIdx++; }
      datetime nx = bt + 86400;
      while(DowOf(nx) == 0 || DowOf(nx) == 6) nx += 86400;
      bool lastDay = MonOf(nx) != mon;
      if(FindPos(sym, InpMagic + 1, tk))
      {
         long held = (long)(TimeCurrent() - (datetime)PositionGetInteger(POSITION_TIME)) / 86400;
         if((!lastDay && dayIdx >= InpTomAfter + 1 && dayIdx < 15) || held > 12) ok = Close(tk) && ok;
      }
      else if(lastDay) ok = Open(sym, InpMagic + 1, "TOM") && ok;
   }

   // ---- B) IBS
   if(InpUseIBS)
   {
      double h1 = iHigh(sym, PERIOD_D1, 1), l1 = iLow(sym, PERIOD_D1, 1), c1 = iClose(sym, PERIOD_D1, 1), h2 = iHigh(sym, PERIOD_D1, 2);
      if(FindPos(sym, InpMagic, tk))
      {
         if(c1 > h2) ok = Close(tk) && ok;
      }
      else if(h1 > l1)
      {
         double sumR = 0;
         for(int k = 1; k <= InpLenR; k++) sumR += iHigh(sym, PERIOD_D1, k) - iLow(sym, PERIOD_D1, k);
         int hi = iHighest(sym, PERIOD_D1, MODE_HIGH, InpLenH, 1);
         double band = iHigh(sym, PERIOD_D1, hi) - InpMult * sumR / InpLenR;
         double ibs = (c1 - l1) / (h1 - l1);
         if(ibs < InpIBS && c1 < band) ok = Open(sym, InpMagic, "IBS") && ok;
      }
   }
   if(ok) lastBar[i] = bt;   // market closed -> try again on the next tick
}

int OnInit()
{
   trade.SetDeviationInPoints(200);
   string parts[];
   int n = StringSplit(InpSymbols, ',', parts);
   for(int k = 0; k < n; k++)
   {
      string s = parts[k]; StringTrimLeft(s); StringTrimRight(s);
      if(s == "" || !SymbolSelect(s, true)) { if(s != "") PrintFormat("SYS skip %s", s); continue; }
      int j = ArraySize(S); ArrayResize(S, j + 1); S[j] = s;
   }
   int c = ArraySize(S);
   if(c == 0) return INIT_FAILED;
   ArrayResize(lastBar, c); ArrayInitialize(lastBar, 0);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   static long lastMin = 0;
   long m = (long)(TimeCurrent() / 60);
   if(m == lastMin) return;
   lastMin = m;
   MarkMonth();
   for(int i = 0; i < ArraySize(S); i++) Process(i);
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
   PrintFormat("SYS_M pos=%d neg=%d of %d", pos, neg, m);
   PrintFormat("SYS_W worst=%.2f%% best=%.2f%%", 100 * worst, 100 * best);
   PrintFormat("SYS_S to2015=%+.1f%% from2016=%+.1f%%", 100 * (a1 - 1), 100 * (a2 - 1));
   int curY = -1; double acc = 1;
   for(int k = 0; k < m; k++)
   {
      int y = g_mkey[k] / 12;
      if(y != curY) { if(curY >= 0) PrintFormat("SYS_YEAR %d %+.1f%%", curY, 100 * (acc - 1)); curY = y; acc = 1; }
      acc *= 1 + g_mret[k];
   }
   if(curY >= 0) PrintFormat("SYS_YEAR %d %+.1f%%", curY, 100 * (acc - 1));
   // profit per component
   HistorySelect(0, TimeCurrent() + 86400);
   double pI = 0, pT = 0; int nI = 0, nT = 0;
   for(int d = 0; d < HistoryDealsTotal(); d++)
   {
      ulong t = HistoryDealGetTicket(d);
      long mg = HistoryDealGetInteger(t, DEAL_MAGIC);
      double v = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) + HistoryDealGetDouble(t, DEAL_COMMISSION);
      bool out = HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_OUT;
      if(mg == InpMagic)     { pI += v; if(out) nI++; }
      if(mg == InpMagic + 1) { pT += v; if(out) nT++; }
   }
   PrintFormat("SYS_PARTS IBS trades=%d pnl=%.0f | TOM trades=%d pnl=%.0f", nI, pI, nT, pT);
   return TesterStatistics(STAT_PROFIT);
}
//+------------------------------------------------------------------+
