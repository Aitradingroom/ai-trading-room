//+------------------------------------------------------------------+
//| QM_Strategy.mq5 - Quasimodo (over and under) pattern             |
//| Swings: fractal pivots (N bars each side) on InpTF.              |
//| Bearish: pivots H -> L -> HH (HH > H), then a close below L      |
//|          -> sell limit at H (QM level), SL above HH, TP = RR x R |
//| Bullish: pivots L -> H -> LL (LL < L), then a close above H      |
//|          -> buy limit at L (QM level), SL below LL, TP = RR x R  |
//| Pending order cancelled when price breaks HH/LL before fill or   |
//| after InpExpiry bars. Results measured in R (OnTester).          |
//+------------------------------------------------------------------+
#property copyright "Strategy research"
#property version   "1.00"

#include <Trade/Trade.mqh>

input ENUM_TIMEFRAMES InpTF        = PERIOD_H1; // Pattern timeframe
input int             InpPivot     = 3;         // Pivot strength (bars each side)
input double          InpMinSwing  = 0.5;       // Min swing size (x ATR) between H and L
input double          InpRR        = 2.0;       // Take profit (x risk)
input double          InpSLBuf     = 0.1;       // Stop buffer beyond HH/LL (x ATR)
input int             InpExpiry    = 30;        // Pending order lifetime (bars)
input double          InpRiskPct   = 1.0;       // Risk per trade (% of equity)
input int             InpSplitYear = 2021;      // R stats: second period from this year
input long            InpMagic     = 20261118;

CTrade   trade;
int      hATR = INVALID_HANDLE;
datetime g_last = 0;

// pivot list (most recent last)
double   pvP[];  int pvT[];  datetime pvTime[];

// pending order state
ulong    g_ord = 0;  int g_ordDir = 0;  double g_inval = 0;  int g_ordBars = 0;
datetime g_usedPivot = 0;

long     g_ids[];  double g_risk[];  int g_year[];

double Atr() { double b[1]; if(CopyBuffer(hATR, 0, 1, 1, b) != 1) return 0; return b[0]; }
int YrOf(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.year; }

void AddPivot(int type, double price, datetime t)
{
   int n = ArraySize(pvP);
   if(n > 0 && pvT[n - 1] == type)   // keep alternation: replace with the more extreme pivot
   {
      if((type == 1 && price > pvP[n - 1]) || (type == -1 && price < pvP[n - 1])) { pvP[n - 1] = price; pvTime[n - 1] = t; }
      return;
   }
   ArrayResize(pvP, n + 1); ArrayResize(pvT, n + 1); ArrayResize(pvTime, n + 1);
   pvP[n] = price; pvT[n] = type; pvTime[n] = t;
   if(n + 1 > 50)   // keep the list short
   {
      ArrayRemove(pvP, 0, 1); ArrayRemove(pvT, 0, 1); ArrayRemove(pvTime, 0, 1);
   }
}

bool HavePos()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) return true;
   }
   return false;
}

bool OrderAlive(ulong tk) { return tk != 0 && OrderSelect(tk); }

double NormVol(double lots)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < vmin) return 0;
   return MathMin(lots, vmax);
}

void PlaceLimit(int dir, double entry, double sl, double inval)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   entry = NormalizeDouble(entry, digits); sl = NormalizeDouble(sl, digits);
   double risk = MathAbs(entry - sl);
   if(risk <= 0) return;
   double tp = NormalizeDouble(dir == 1 ? entry + InpRR * risk : entry - InpRR * risk, digits);
   double lpl = 0;
   if(!OrderCalcProfit(dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, 1.0, entry, sl, lpl)) return;
   lpl = MathAbs(lpl);
   if(lpl <= 0) return;
   double lots = NormVol(AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0 / lpl);
   if(lots <= 0) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool ok = false;
   if(dir == -1 && entry > bid) ok = trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "QM sell");
   if(dir == 1 && entry < ask)  ok = trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "QM buy");
   if(!ok) return;
   if(OrderAlive(g_ord)) trade.OrderDelete(g_ord);
   g_ord = trade.ResultOrder(); g_ordDir = dir; g_inval = inval; g_ordBars = 0;
   int n = ArraySize(g_ids);
   ArrayResize(g_ids, n + 1); ArrayResize(g_risk, n + 1); ArrayResize(g_year, n + 1);
   g_ids[n] = (long)g_ord; g_risk[n] = lots * lpl; g_year[n] = YrOf(TimeCurrent());
}

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   hATR = iATR(_Symbol, InpTF, 14);
   return hATR == INVALID_HANDLE ? INIT_FAILED : INIT_SUCCEEDED;
}

void OnTick()
{
   datetime bt = iTime(_Symbol, InpTF, 0);
   if(bt == 0 || bt == g_last) return;
   g_last = bt;
   int N = InpPivot;
   if(iBars(_Symbol, InpTF) < 2 * N + 20) return;
   double atr = Atr();
   if(atr <= 0) return;

   // 1) manage the pending order: invalidation and expiry
   if(OrderAlive(g_ord))
   {
      g_ordBars++;
      double h1 = iHigh(_Symbol, InpTF, 1), l1 = iLow(_Symbol, InpTF, 1);
      bool broken = (g_ordDir == -1 && h1 > g_inval) || (g_ordDir == 1 && l1 < g_inval);
      if(broken || g_ordBars > InpExpiry) { trade.OrderDelete(g_ord); g_ord = 0; }
   }

   // 2) confirm a new pivot at shift N+1 (needs N bars on each side, all closed)
   int c = N + 1;
   int hi = iHighest(_Symbol, InpTF, MODE_HIGH, 2 * N + 1, 1);
   int lo = iLowest(_Symbol, InpTF, MODE_LOW, 2 * N + 1, 1);
   if(hi == c) AddPivot(1, iHigh(_Symbol, InpTF, c), iTime(_Symbol, InpTF, c));
   if(lo == c) AddPivot(-1, iLow(_Symbol, InpTF, c), iTime(_Symbol, InpTF, c));

   // 3) pattern check on the last three pivots + the last closed bar
   int n = ArraySize(pvP);
   if(n < 3 || HavePos() || OrderAlive(g_ord)) return;
   double c1 = iClose(_Symbol, InpTF, 1);
   int a = n - 3, b = n - 2, d = n - 1;
   if(pvTime[d] == g_usedPivot) return;

   // bearish QM: H (a) -> L (b) -> HH (d), close below L
   if(pvT[a] == 1 && pvT[b] == -1 && pvT[d] == 1 && pvP[d] > pvP[a] && pvP[a] - pvP[b] >= InpMinSwing * atr && c1 < pvP[b])
   {
      g_usedPivot = pvTime[d];
      PlaceLimit(-1, pvP[a], pvP[d] + InpSLBuf * atr, pvP[d]);
      return;
   }
   // bullish QM: L (a) -> H (b) -> LL (d), close above H
   if(pvT[a] == -1 && pvT[b] == 1 && pvT[d] == -1 && pvP[d] < pvP[a] && pvP[b] - pvP[a] >= InpMinSwing * atr && c1 > pvP[b])
   {
      g_usedPivot = pvTime[d];
      PlaceLimit(1, pvP[a], pvP[d] - InpSLBuf * atr, pvP[d]);
   }
}

double OnTester()
{
   HistorySelect(0, TimeCurrent() + 86400);
   int n = ArraySize(g_ids);
   double pnl[]; bool filled[];
   ArrayResize(pnl, n); ArrayResize(filled, n);
   ArrayInitialize(pnl, 0.0); ArrayInitialize(filled, false);
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic) continue;
      long pid = HistoryDealGetInteger(t, DEAL_POSITION_ID);
      double v = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) +
                 HistoryDealGetDouble(t, DEAL_COMMISSION) + HistoryDealGetDouble(t, DEAL_FEE);
      for(int k = 0; k < n; k++) if(g_ids[k] == pid) { pnl[k] += v; filled[k] = true; break; }
   }
   double sum = 0, r1 = 0, r2 = 0; int tr = 0, w = 0, n1 = 0, n2 = 0;
   for(int k = 0; k < n; k++)
   {
      if(!filled[k] || g_risk[k] <= 0) continue;
      double r = pnl[k] / g_risk[k];
      tr++; sum += r; if(r > 0) w++;
      if(g_year[k] < InpSplitYear) { r1 += r; n1++; } else { r2 += r; n2++; }
   }
   PrintFormat("QM_STATS %s %s setups=%d trades=%d win=%.1f avgR=%.4f totalR=%.1f | before %d n=%d avgR=%.4f | from %d n=%d avgR=%.4f",
               _Symbol, EnumToString(InpTF), n, tr, tr > 0 ? 100.0 * w / tr : 0, tr > 0 ? sum / tr : 0, sum,
               InpSplitYear, n1, n1 > 0 ? r1 / n1 : 0, InpSplitYear, n2, n2 > 0 ? r2 / n2 : 0);
   return sum;
}
//+------------------------------------------------------------------+
