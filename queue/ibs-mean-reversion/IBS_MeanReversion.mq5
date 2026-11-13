//+------------------------------------------------------------------+
//| IBS_MeanReversion.mq5                                            |
//| IBS = (close - low) / (high - low) of the daily bar.             |
//| Entry : at the close (executed at the next bar open) when        |
//|         IBS < threshold AND (optional) close < band, where       |
//|         band = highest high(10) - 2.5 x average(high - low, 25). |
//| Exit  : when the close is above the previous day's high.         |
//| Size  : InpExposure x equity notional (1.0 = fully invested).    |
//+------------------------------------------------------------------+
#property copyright "Strategy research"
#property version   "1.20"

#include <Trade/Trade.mqh>

input ENUM_TIMEFRAMES InpTF       = PERIOD_D1; // Timeframe
input int             InpLenH     = 10;        // Pullback: highest high length
input int             InpLenR     = 25;        // Pullback: average range length
input double          InpMult     = 2.5;       // Pullback: k x average range
input bool            InpUseBand  = true;      // Require close below the pullback band
input double          InpIBS      = 0.3;       // IBS threshold
input double          InpExposure = 1.0;       // Position notional as a multiple of equity
input bool            InpAllowLong  = true;    // Allow long trades
input bool            InpAllowShort = false;   // Allow short trades (mirror rules)
input double          InpAntiMult  = 1.0;      // Reverse martingale: size x this after each win (1 = off)
input int             InpAntiSteps = 3;        // Reverse martingale: reset to base after this many wins in a row
input long            InpMagic    = 20261116;

CTrade   trade;
datetime g_last = 0;
int      g_trades = 0, g_wins = 0;
double   g_entryEq = 0;
long     g_daysIn = 0;
datetime g_entryT = 0;
int      g_win = 0, g_maxWin = 0;

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

double Lots()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double perLot = 0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, price, price * 1.01, perLot) || perLot <= 0) return 0;
   double notionalPerLot = perLot / 0.01;                    // money value of 1 lot
   double expo = InpExposure * MathPow(InpAntiMult, g_win);
   double lots = AccountInfoDouble(ACCOUNT_EQUITY) * expo / notionalPerLot;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < vmin) return 0;
   return MathMin(lots, vmax);
}

int OnInit() { trade.SetExpertMagicNumber(InpMagic); trade.SetDeviationInPoints(100); return INIT_SUCCEEDED; }

void OnTick()
{
   datetime bt = iTime(_Symbol, InpTF, 0);
   if(bt == 0 || bt == g_last) return;
   int need = MathMax(InpLenH, InpLenR) + 3;
   if(iBars(_Symbol, InpTF) < need) return;

   double h1 = iHigh(_Symbol, InpTF, 1), l1 = iLow(_Symbol, InpTF, 1), c1 = iClose(_Symbol, InpTF, 1);
   double h2 = iHigh(_Symbol, InpTF, 2), l2 = iLow(_Symbol, InpTF, 2);
   ulong tk;
   bool inPos = HavePos(tk);

   if(inPos)
   {
      bool isLong = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      if(isLong ? c1 > h2 : c1 < l2)
      {
         double eqBefore = g_entryEq;
         if(trade.PositionClose(tk))
         {
            g_trades++;
            if(AccountInfoDouble(ACCOUNT_EQUITY) > eqBefore)
            {
               g_wins++;
               g_win++;
               if(g_win >= InpAntiSteps) g_win = 0;
            }
            else g_win = 0;
            g_maxWin = MathMax(g_maxWin, g_win);
            g_daysIn += (long)((TimeCurrent() - g_entryT) / 86400);
         }
         else if(trade.ResultRetcode() == TRADE_RETCODE_MARKET_CLOSED) return;   // retry on the next tick
      }
      g_last = bt;
      return;
   }

   double sumR = 0;
   for(int k = 1; k <= InpLenR; k++) sumR += iHigh(_Symbol, InpTF, k) - iLow(_Symbol, InpTF, k);
   double avgR = sumR / InpLenR;
   int hi = iHighest(_Symbol, InpTF, MODE_HIGH, InpLenH, 1);
   int lo = iLowest(_Symbol, InpTF, MODE_LOW, InpLenH, 1);
   double band   = iHigh(_Symbol, InpTF, hi) - InpMult * avgR;
   double bandUp = iLow(_Symbol, InpTF, lo) + InpMult * avgR;
   double ibs = h1 > l1 ? (c1 - l1) / (h1 - l1) : 0.5;

   bool goLong  = InpAllowLong  && ibs < InpIBS        && (!InpUseBand || c1 < band);
   bool goShort = InpAllowShort && ibs > 1.0 - InpIBS  && (!InpUseBand || c1 > bandUp);
   if(goLong || goShort)
   {
      double lots = Lots();
      if(lots > 0)
      {
         g_entryEq = AccountInfoDouble(ACCOUNT_EQUITY);
         bool ok = goLong ? trade.Buy(lots, _Symbol, 0, 0, 0, "IBS L") : trade.Sell(lots, _Symbol, 0, 0, 0, "IBS S");
         if(ok) g_entryT = TimeCurrent();
         else if(trade.ResultRetcode() == TRADE_RETCODE_MARKET_CLOSED) return;   // retry on the next tick
      }
   }
   g_last = bt;
}

double OnTester()
{
   PrintFormat("IBS_STATS %s trades=%d wins=%d winrate=%.1f avgDaysHeld=%.1f", _Symbol, g_trades, g_wins,
               g_trades > 0 ? 100.0 * g_wins / g_trades : 0, g_trades > 0 ? (double)g_daysIn / g_trades : 0);
   return TesterStatistics(STAT_PROFIT);
}
//+------------------------------------------------------------------+
