//+------------------------------------------------------------------+
//| Shadow_Grid_Test.mq5                                             |
//| Re-creation of the "Shadow" robot logic shown in the video:      |
//| 1) OCO: Buy Stop above and Sell Stop below price (trigger pts);  |
//|    whichever fills first cancels the other.                      |
//| 2) Backward grid: every GridPts against the position it opens    |
//|    another trade in the same direction (no stop loss).           |
//| 3) Per-position trailing stop; when price returns to an empty    |
//|    grid level, the position at that level is reopened.           |
//| 4) When no positions remain, the cycle restarts with a new OCO.  |
//| 5) Optional hourly profit target: close all, pause until the     |
//|    next hour.                                                    |
//| Extra (off by default): max positions, equity stop.              |
//+------------------------------------------------------------------+
#property copyright "Strategy research"
#property version   "1.00"

#include <Trade/Trade.mqh>

input double InpLot          = 0.1;   // Lot size
input int    InpTriggerPts   = 2000;  // Order trigger in points (0 = auto: 1 x ATR H1)
input int    InpGridPts      = 1000;  // Grid distance in points (0 = auto: 0.5 x ATR H1)
input int    InpTrailTrigPts = 0;     // Trailing trigger in points (0 = auto: grid / 2)
input int    InpTrailDistPts = 0;     // Trailing distance in points (0 = auto: grid / 4)
input double InpHourTarget   = 0.0;   // Hourly profit target in money (0 = off)
input int    InpMaxPos       = 100;   // Max open grid positions
input double InpEquityStop   = 0.0;   // Close all if equity < balance x (1 - x%) (0 = off)
input long   InpMagic        = 20261115;

CTrade   trade;
int      hATR = INVALID_HANDLE;
int      g_dir = 0;            // 1 long cycle, -1 short cycle, 0 waiting
double   g_anchor = 0;         // first fill price of the cycle
double   g_grid = 0, g_trig = 0, g_tTrig = 0, g_tDist = 0;   // in price units
datetime g_hourStart = 0;
double   g_hourEq = 0;
datetime g_pauseUntil = 0;
int      g_cycles = 0, g_hourHits = 0, g_eqStops = 0, g_maxPos = 0;

double Pt() { return SymbolInfoDouble(_Symbol, SYMBOL_POINT); }

double AtrH1()
{
   double b[1];
   if(hATR == INVALID_HANDLE || CopyBuffer(hATR, 0, 1, 1, b) != 1) return 0;
   return b[0];
}

bool SetDistances()
{
   double pt = Pt(), atr = AtrH1();
   g_trig = InpTriggerPts > 0 ? InpTriggerPts * pt : atr;
   g_grid = InpGridPts > 0 ? InpGridPts * pt : 0.5 * atr;
   if(g_trig <= 0 || g_grid <= 0) return false;
   g_tTrig = InpTrailTrigPts > 0 ? InpTrailTrigPts * pt : g_grid / 2.0;
   g_tDist = InpTrailDistPts > 0 ? InpTrailDistPts * pt : g_grid / 4.0;
   return true;
}

int CountPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) n++;
   }
   return n;
}

int CountPendings()
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic) n++;
   }
   return n;
}

void DeletePendings()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic) trade.OrderDelete(tk);
   }
}

void CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) trade.PositionClose(tk);
   }
   DeletePendings();
   g_dir = 0;
}

bool LevelOccupied(int k)
{
   string tag = "L" + IntegerToString(k);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         PositionGetString(POSITION_COMMENT) == tag) return true;
   }
   return false;
}

void Trail()
{
   double pt = Pt();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * pt;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      double op = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL);
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         if(bid - op < g_tTrig) continue;
         double ns = NormalizeDouble(bid - g_tDist, digits);
         if(bid - ns < stopsLvl) continue;
         if(sl == 0 || ns > sl + pt) trade.PositionModify(tk, ns, 0.0);
      }
      else
      {
         if(op - ask < g_tTrig) continue;
         double ns = NormalizeDouble(ask + g_tDist, digits);
         if(ns - ask < stopsLvl) continue;
         if(sl == 0 || ns < sl - pt) trade.PositionModify(tk, ns, 0.0);
      }
   }
}

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   hATR = iATR(_Symbol, PERIOD_H1, 14);
   PrintFormat("SG_INFO %s digits=%d point=%g contract=%g", _Symbol, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
               Pt(), SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));
   return INIT_SUCCEEDED;
}

void OnTick()
{
   datetime now = TimeCurrent();
   double eq = AccountInfoDouble(ACCOUNT_EQUITY), bal = AccountInfoDouble(ACCOUNT_BALANCE);

   // hourly target
   datetime hs = now - now % 3600;
   if(hs != g_hourStart) { g_hourStart = hs; g_hourEq = eq; }
   if(now < g_pauseUntil) return;
   if(InpHourTarget > 0 && eq - g_hourEq >= InpHourTarget)
   {
      CloseAll(); g_hourHits++; g_pauseUntil = hs + 3600; return;
   }
   // optional equity stop
   if(InpEquityStop > 0 && eq < bal * (1.0 - InpEquityStop / 100.0))
   {
      CloseAll(); g_eqStops++; g_pauseUntil = hs + 3600; return;
   }

   int n = CountPositions();
   int p = CountPendings();
   g_maxPos = MathMax(g_maxPos, n);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(n == 0)
   {
      g_dir = 0;
      if(p == 0)
      {
         if(!SetDistances()) return;
         trade.BuyStop(InpLot, NormalizeDouble(ask + g_trig, digits), _Symbol, 0, 0, ORDER_TIME_GTC, 0, "L0");
         trade.SellStop(InpLot, NormalizeDouble(bid - g_trig, digits), _Symbol, 0, 0, ORDER_TIME_GTC, 0, "L0");
      }
      return;
   }

   // a position exists: OCO -> cancel the other pending, fix the cycle
   if(g_dir == 0)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         g_dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
         g_anchor = PositionGetDouble(POSITION_PRICE_OPEN);
      }
      g_cycles++;
   }
   if(p > 0) DeletePendings();

   Trail();

   // backward grid: fill every empty level between the anchor and price
   int kNow = g_dir == 1 ? (int)MathFloor((g_anchor - bid) / g_grid + 1e-9) : (int)MathFloor((ask - g_anchor) / g_grid + 1e-9);
   if(kNow < 0) return;
   for(int k = 0; k <= kNow && n < InpMaxPos; k++)
   {
      if(LevelOccupied(k)) continue;
      string tag = "L" + IntegerToString(k);
      bool ok = g_dir == 1 ? trade.Buy(InpLot, _Symbol, ask, 0, 0, tag) : trade.Sell(InpLot, _Symbol, bid, 0, 0, tag);
      if(ok) n++;
   }
}

double OnTester()
{
   PrintFormat("SG_STATS cycles=%d hourTargets=%d equityStops=%d maxOpenPositions=%d", g_cycles, g_hourHits, g_eqStops, g_maxPos);
   return TesterStatistics(STAT_PROFIT);
}
//+------------------------------------------------------------------+
