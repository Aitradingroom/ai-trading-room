//+------------------------------------------------------------------+
//| Asian_MeanRev.mq5                                                |
//| Asian-session mean reversion on M15.                             |
//| Entry : during [StartHour, EndHour) server time, on bar close:   |
//|         close < lower Bollinger band and RSI < RsiLow  -> buy    |
//|         close > upper Bollinger band and RSI > RsiHigh -> sell   |
//|         (skipped when the spread is above MaxSpread points)      |
//| Exit  : close back at/through the middle band (SMA), stop loss   |
//|         SL x ATR, or forced exit at ExitHour.                    |
//| Stats : R per trade; split before / from SplitYear.              |
//+------------------------------------------------------------------+
#property copyright "Strategy research"
#property version   "1.10"

#include <Trade/Trade.mqh>

input ENUM_TIMEFRAMES InpTF        = PERIOD_M15; // Timeframe
input int             InpStartHour = 1;          // Entries from this server hour
input int             InpEndHour   = 7;          // ... until this server hour
input int             InpExitHour  = 9;          // Close any open trade at this server hour
input int             InpBBLen     = 20;         // Bollinger length
input double          InpBBDev     = 2.0;        // Bollinger deviation
input int             InpRsiLen    = 14;         // RSI length
input double          InpRsiLow    = 30;         // RSI buy level
input double          InpRsiHigh   = 70;         // RSI sell level
input int             InpAtrLen    = 14;         // ATR length
input double          InpSLATR     = 2.0;        // Stop loss (x ATR)
input int             InpMaxSpread = 30;         // Max spread in points (0 = off)
input double          InpRiskPct   = 0.5;        // Base risk per trade (% of equity)
input double          InpMartMult  = 1.0;        // Martingale: risk x this after each loss (1 = off)
input int             InpMartSteps = 10;         // Martingale: reset to base after this many losses in a row
input int             InpSplitYear = 2016;       // R stats: second period from this year
input long            InpMagic     = 20261117;

CTrade   trade;
int      hBB = INVALID_HANDLE, hRSI = INVALID_HANDLE, hATR = INVALID_HANDLE;
datetime g_last = 0;
long     g_ids[];
double   g_risk[];
int      g_year[];
int      g_month[];
int      g_streak = 0;
ulong    g_lastDeal = 0;
int      g_maxStep = 0;

double B(int h, int buf, int shift) { double b[1]; if(CopyBuffer(h, buf, shift, 1, b) != 1) return 0; return b[0]; }
int HrOf(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.hour; }
int YrOf(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.year; }

bool HavePos(ulong &tk)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) { tk = t; return true; }
   }
   return false;
}

double NormVol(double lots)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < vmin) return 0;
   return MathMin(lots, vmax);
}

void Open(bool isBuy, double atr)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble(isBuy ? price - InpSLATR * atr : price + InpSLATR * atr, digits);
   double lpl = 0;
   if(!OrderCalcProfit(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, 1.0, price, sl, lpl)) return;
   lpl = MathAbs(lpl);
   if(lpl <= 0) return;
   double risk = InpRiskPct * MathPow(InpMartMult, g_streak);
   g_maxStep = MathMax(g_maxStep, g_streak);
   double lots = NormVol(AccountInfoDouble(ACCOUNT_EQUITY) * risk / 100.0 / lpl);
   if(lots <= 0) return;
   bool ok = isBuy ? trade.Buy(lots, _Symbol, price, sl, 0, "AMR") : trade.Sell(lots, _Symbol, price, sl, 0, "AMR");
   if(!ok) return;
   ulong deal = trade.ResultDeal();
   long pid = 0;
   if(deal > 0 && HistoryDealSelect(deal)) pid = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   if(pid == 0) pid = (long)trade.ResultOrder();
   int n = ArraySize(g_ids);
   ArrayResize(g_ids, n + 1); ArrayResize(g_risk, n + 1); ArrayResize(g_year, n + 1); ArrayResize(g_month, n + 1);
   g_ids[n] = pid; g_risk[n] = lots * lpl; g_year[n] = YrOf(TimeCurrent());
   MqlDateTime ms; TimeToStruct(TimeCurrent(), ms); g_month[n] = ms.year * 12 + ms.mon;
}

void UpdateStreak()
{
   if(InpMartMult == 1.0) return;
   HistorySelect(0, TimeCurrent() + 60);
   for(int d = HistoryDealsTotal() - 1; d >= 0; d--)
   {
      ulong t = HistoryDealGetTicket(d);
      if(t <= g_lastDeal) break;
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic || HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double v = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) + HistoryDealGetDouble(t, DEAL_COMMISSION);
      g_lastDeal = t;
      if(v < 0) { g_streak++; if(g_streak >= InpMartSteps) g_streak = 0; }
      else g_streak = 0;
      break;
   }
}

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   hBB  = iBands(_Symbol, InpTF, InpBBLen, 0, InpBBDev, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, InpTF, InpRsiLen, PRICE_CLOSE);
   hATR = iATR(_Symbol, InpTF, InpAtrLen);
   if(hBB == INVALID_HANDLE || hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnTick()
{
   datetime bt = iTime(_Symbol, InpTF, 0);
   if(bt == 0 || bt == g_last) return;
   g_last = bt;
   int hr = HrOf(bt);

   double c1  = iClose(_Symbol, InpTF, 1);
   double mid = B(hBB, 0, 1), up = B(hBB, 1, 1), lo = B(hBB, 2, 1);
   double rsi = B(hRSI, 0, 1), atr = B(hATR, 0, 1);
   if(mid <= 0 || atr <= 0) return;

   ulong tk;
   if(HavePos(tk))
   {
      bool isBuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      bool target = isBuy ? c1 >= mid : c1 <= mid;
      bool timeUp = hr >= InpExitHour || hr < InpStartHour;
      if(target || timeUp) trade.PositionClose(tk);
      return;
   }

   UpdateStreak();
   if(hr < InpStartHour || hr >= InpEndHour) return;
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(InpMaxSpread > 0 && spread > InpMaxSpread) return;

   if(c1 < lo && rsi < InpRsiLow)       Open(true, atr);
   else if(c1 > up && rsi > InpRsiHigh) Open(false, atr);
}

double OnTester()
{
   HistorySelect(0, TimeCurrent() + 86400);
   int n = ArraySize(g_ids);
   double pnl[];
   ArrayResize(pnl, n); ArrayInitialize(pnl, 0.0);
   for(int d = 0; d < HistoryDealsTotal(); d++)
   {
      ulong t = HistoryDealGetTicket(d);
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic) continue;
      long pid = HistoryDealGetInteger(t, DEAL_POSITION_ID);
      double v = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) +
                 HistoryDealGetDouble(t, DEAL_COMMISSION) + HistoryDealGetDouble(t, DEAL_FEE);
      for(int k = 0; k < n; k++) if(g_ids[k] == pid) { pnl[k] += v; break; }
   }
   double sum = 0, r1 = 0, r2 = 0; int w = 0, n1 = 0, n2 = 0;
   for(int k = 0; k < n; k++)
   {
      if(g_risk[k] <= 0) continue;
      double r = pnl[k] / g_risk[k];
      sum += r; if(r > 0) w++;
      if(g_year[k] < InpSplitYear) { r1 += r; n1++; } else { r2 += r; n2++; }
   }
   // losing streaks: overall and the longest streak inside each month
   int cur = 0, maxAll = 0, mCur = 0, mMax = 0, lastM = -1, months = 0, m5 = 0, m7 = 0, m10 = 0;
   for(int k = 0; k < n; k++)
   {
      if(g_risk[k] <= 0) continue;
      if(g_month[k] != lastM)
      {
         if(lastM >= 0) { months++; if(mMax >= 5) m5++; if(mMax >= 7) m7++; if(mMax >= 10) m10++; }
         lastM = g_month[k]; mCur = 0; mMax = 0;
      }
      if(pnl[k] < 0) { cur++; mCur++; } else { cur = 0; mCur = 0; }
      maxAll = MathMax(maxAll, cur); mMax = MathMax(mMax, mCur);
   }
   if(lastM >= 0) { months++; if(mMax >= 5) m5++; if(mMax >= 7) m7++; if(mMax >= 10) m10++; }
   PrintFormat("AMR_STREAK maxLosingStreak=%d | months=%d with streak>=5: %d  >=7: %d  >=10: %d | maxMartStep=%d",
               maxAll, months, m5, m7, m10, g_maxStep);
   PrintFormat("AMR_STATS %s trades=%d win=%.1f avgR=%.4f totalR=%.1f | before %d: n=%d avgR=%.4f | from %d: n=%d avgR=%.4f",
               _Symbol, n, n > 0 ? 100.0 * w / n : 0, n > 0 ? sum / n : 0, sum,
               InpSplitYear, n1, n1 > 0 ? r1 / n1 : 0, InpSplitYear, n2, n2 > 0 ? r2 / n2 : 0);
   return sum;
}
//+------------------------------------------------------------------+
