//+------------------------------------------------------------------+
//| VWAP_Intraday.mq5 - session VWAP strategies (intraday, flat at   |
//| session end, so no swap). VWAP built from tick volume of the     |
//| bars since the session start; bands = VWAP +/- k x volume-       |
//| weighted standard deviation.                                     |
//| Mode 1: cross / flip (Zarattini & Aziz 2023) - long while close  |
//|         > VWAP, short while close < VWAP.                        |
//| Mode 2: band reversion - fade a close beyond VWAP +/- K sd,      |
//|         exit at VWAP, stop beyond StopK sd.                      |
//| Mode 3: trend pullback - VWAP rising and price above it: buy a   |
//|         bar that dips to VWAP and closes back above (mirror for  |
//|         shorts); exit at session end or close beyond 1 sd on     |
//|         the wrong side.                                          |
//+------------------------------------------------------------------+
#property copyright "Strategy research"
#property version   "1.00"

#include <Trade/Trade.mqh>

input int    InpMode      = 1;      // Mode: 1 cross, 2 band reversion, 3 trend pullback
input ENUM_TIMEFRAMES InpTF = PERIOD_M5; // Signal timeframe
input int    InpStartHM   = 1630;   // Session start (server time HHMM)
input int    InpEndHM     = 2255;   // Flat at (server time HHMM)
input int    InpWaitMin   = 15;     // No entries in the first X minutes
input bool   InpAllowShort = true;  // Allow short trades
input double InpBandK     = 2.0;    // Mode 2: entry band (sd)
input double InpStopK     = 3.5;    // Mode 2: stop band (sd)
input int    InpSlopeBars = 6;      // Mode 3: VWAP slope lookback (bars)
input double InpExpo      = 1.0;    // Position notional (x equity)
input long   InpMagic     = 20261123;

CTrade   trade;
datetime g_last = 0;
int      g_day = -1;
double   g_pv = 0, g_v = 0, g_p2v = 0;
datetime g_sessStart = 0;
double   g_vw[];           // VWAP history inside the session (per bar)
int      g_trades = 0, g_wins = 0;
double   g_sumPts = 0;

int      g_curMonth = -1;
double   g_monthStart = 0;
double   g_mret[];
int      g_mkey[];

int HM(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.hour * 100 + s.min; }
int DayKey(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.year * 400 + s.day_of_year; }
int MonthKey(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.year * 12 + s.mon - 1; }

int PosDir(ulong &tk)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
      { tk = t; return PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1; }
   }
   tk = 0; return 0;
}

double Lots()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK), perLot = 0;
   if(price <= 0 || !OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, price, price * 1.01, perLot) || perLot <= 0) return 0;
   double lots = AccountInfoDouble(ACCOUNT_EQUITY) * InpExpo / (perLot / 0.01);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < vmin) return 0;
   return MathMin(lots, vmax);
}

void CloseTk(ulong tk)
{
   if(!PositionSelectByTicket(tk)) return;
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   int dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   double px = dir == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double prof = PositionGetDouble(POSITION_PROFIT);
   if(trade.PositionClose(tk))
   {
      g_trades++; if(prof > 0) g_wins++;
      g_sumPts += dir * (px - open) / _Point;
   }
}

void Open(int dir)
{
   double lots = Lots();
   if(lots <= 0) return;
   if(dir == 1) trade.Buy(lots, _Symbol, 0, 0, 0, "VWAP");
   else if(InpAllowShort) trade.Sell(lots, _Symbol, 0, 0, 0, "VWAP");
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

int OnInit() { trade.SetExpertMagicNumber(InpMagic); trade.SetDeviationInPoints(50); return INIT_SUCCEEDED; }

void OnTick()
{
   datetime bt = iTime(_Symbol, InpTF, 0);
   if(bt == 0 || bt == g_last) return;
   g_last = bt;
   MarkMonth();

   int hm = HM(bt);
   ulong tk; int dir = PosDir(tk);

   // flat outside the session
   if(hm >= InpEndHM || hm < InpStartHM)
   {
      if(dir != 0) CloseTk(tk);
      return;
   }

   // new session: reset VWAP sums
   int dk = DayKey(bt);
   if(dk != g_day) { g_day = dk; g_pv = 0; g_v = 0; g_p2v = 0; g_sessStart = bt; ArrayResize(g_vw, 0); }

   // add the last closed bar (only bars that belong to this session)
   datetime t1 = iTime(_Symbol, InpTF, 1);
   if(t1 < g_sessStart) return;                  // first bar of the session: nothing closed yet
   double h1 = iHigh(_Symbol, InpTF, 1), l1 = iLow(_Symbol, InpTF, 1), c1 = iClose(_Symbol, InpTF, 1);
   double v1 = (double)iVolume(_Symbol, InpTF, 1);
   if(v1 <= 0) v1 = 1;
   double tp = (h1 + l1 + c1) / 3.0;
   g_pv += tp * v1; g_v += v1; g_p2v += tp * tp * v1;
   double vwap = g_pv / g_v;
   double var = g_p2v / g_v - vwap * vwap;
   double sd = var > 0 ? MathSqrt(var) : 0;
   int n = ArraySize(g_vw); ArrayResize(g_vw, n + 1); g_vw[n] = vwap;

   bool canEnter = (bt - g_sessStart) >= InpWaitMin * 60;

   if(InpMode == 1)
   {
      int want = c1 > vwap ? 1 : (c1 < vwap ? -1 : dir);
      if(!InpAllowShort && want == -1) want = 0;
      if(dir != 0 && dir != want) { CloseTk(tk); dir = 0; }
      if(dir == 0 && want != 0 && canEnter) Open(want);
      return;
   }

   if(InpMode == 2)
   {
      if(sd <= 0) return;
      if(dir == 1 && (c1 >= vwap || c1 < vwap - InpStopK * sd)) { CloseTk(tk); return; }
      if(dir == -1 && (c1 <= vwap || c1 > vwap + InpStopK * sd)) { CloseTk(tk); return; }
      if(dir == 0 && canEnter)
      {
         if(c1 < vwap - InpBandK * sd && c1 > vwap - InpStopK * sd) Open(1);
         else if(c1 > vwap + InpBandK * sd && c1 < vwap + InpStopK * sd) Open(-1);
      }
      return;
   }

   if(InpMode == 3)
   {
      if(dir == 1 && c1 < vwap - sd) { CloseTk(tk); return; }
      if(dir == -1 && c1 > vwap + sd) { CloseTk(tk); return; }
      if(dir != 0 || !canEnter || n < InpSlopeBars) return;
      double slope = vwap - g_vw[n - InpSlopeBars];
      if(slope > 0 && l1 <= vwap && c1 > vwap) Open(1);
      else if(slope < 0 && h1 >= vwap && c1 < vwap) Open(-1);
   }
}

double OnTester()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_curMonth >= 0) { int n = ArraySize(g_mret); ArrayResize(g_mret, n + 1); ArrayResize(g_mkey, n + 1); g_mret[n] = g_monthStart > 0 ? eq / g_monthStart - 1 : 0; g_mkey[n] = g_curMonth; }
   int m = ArraySize(g_mret), pos = 0, neg = 0;
   double worst = 0, best = 0;
   for(int k = 0; k < m; k++)
   {
      double r = g_mret[k];
      if(r > 0.0005) pos++; else if(r < -0.0005) neg++;
      worst = MathMin(worst, r); best = MathMax(best, r);
   }
   PrintFormat("VW_T mode=%d trades=%d win=%.0f%%", InpMode, g_trades, g_trades > 0 ? 100.0 * g_wins / g_trades : 0);
   PrintFormat("VW_P avgpts=%.1f spread=%d", g_trades > 0 ? g_sumPts / g_trades : 0, (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
   PrintFormat("VW_M pos=%d neg=%d of %d", pos, neg, m);
   PrintFormat("VW_W worst=%.2f%% best=%.2f%%", 100 * worst, 100 * best);
   int curY = -1; double acc = 1;
   for(int k = 0; k < m; k++)
   {
      int y = g_mkey[k] / 12;
      if(y != curY) { if(curY >= 0) PrintFormat("VW_Y %d %+.1f%%", curY, 100 * (acc - 1)); curY = y; acc = 1; }
      acc *= 1 + g_mret[k];
   }
   if(curY >= 0) PrintFormat("VW_Y %d %+.1f%%", curY, 100 * (acc - 1));
   return TesterStatistics(STAT_PROFIT);
}
//+------------------------------------------------------------------+
