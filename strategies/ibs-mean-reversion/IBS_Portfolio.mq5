//+------------------------------------------------------------------+
//| IBS_Portfolio.mq5 - IBS mean reversion on a basket of indices    |
//| Per symbol, on the daily bar:                                    |
//|   IBS = (close - low) / (high - low)                             |
//|   Buy when IBS < InpIBS and close < highest high(10)             |
//|            - 2.5 x average range(25)  (pullback band)            |
//|   Exit when close > previous day's high.                         |
//| Size: notional = InpExpo x equity per position.                  |
//| Report: monthly returns (positive %, average, worst, best),      |
//|         yearly returns and per-symbol results.                   |
//+------------------------------------------------------------------+
#property copyright "Strategy research"
#property version   "1.10"

#include <Trade/Trade.mqh>

input string InpSymbols = "US500,US30,UK100,JP225,NAS100,USTEC,US100,GER40,DE40,FRA40,EU50,STOXX50,AUS200,HK50,ESP35"; // Basket (missing names are skipped)
input int    InpLenH    = 10;    // Pullback: highest high length
input int    InpLenR    = 25;    // Pullback: average range length
input double InpMult    = 2.5;   // Pullback: k x average range
input bool   InpUseBand = true;  // Require close below the pullback band
input double InpIBS     = 0.3;   // IBS threshold
input double InpExpo    = 0.25;  // Notional per position (x equity)
input double InpMaxGross = 1.0;  // Max total notional of all open positions (x equity)
input int    InpDelayMin = 30;   // Act X minutes after the daily bar opens
input long   InpMagic   = 20261119;

CTrade   trade;
string   S[];
datetime lastBar[];
double   entryEq[];
int      symN[], symW[];
double   symPnL[];

// monthly equity marks
int      g_curMonth = -1;
double   g_monthStart = 0;
double   g_mret[];
int      g_mkey[];

int MonthKey(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.year * 12 + s.mon - 1; }

bool SelectPos(string sym, ulong &tk)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym && PositionGetInteger(POSITION_MAGIC) == InpMagic) { tk = t; return true; }
   }
   return false;
}

double Notional(string sym, double vol)
{
   double price = SymbolInfoDouble(sym, SYMBOL_BID), perLot = 0;
   if(price <= 0 || !OrderCalcProfit(ORDER_TYPE_BUY, sym, 1.0, price, price * 1.01, perLot)) return 0;
   return MathAbs(perLot) / 0.01 * vol;
}

double GrossNow()
{
   double g = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      g += Notional(PositionGetString(POSITION_SYMBOL), PositionGetDouble(POSITION_VOLUME));
   }
   return g;
}

double Lots(string sym)
{
   double price = SymbolInfoDouble(sym, SYMBOL_ASK), perLot = 0;
   if(price <= 0 || !OrderCalcProfit(ORDER_TYPE_BUY, sym, 1.0, price, price * 1.01, perLot) || perLot <= 0) return 0;
   double eqv = AccountInfoDouble(ACCOUNT_EQUITY);
   double room = InpMaxGross * eqv - GrossNow();
   double want = MathMin(InpExpo * eqv, room);
   if(want <= 0.5 * InpExpo * eqv) return 0;          // basket is full
   double lots = want / (perLot / 0.01);
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN), vmax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
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
      g_mret[n] = g_monthStart > 0 ? eq / g_monthStart - 1.0 : 0;
      g_mkey[n] = g_curMonth;
      g_curMonth = mk; g_monthStart = eq;
   }
}

void Process(int i)
{
   string sym = S[i];
   datetime bt = iTime(sym, PERIOD_D1, 0);
   if(bt == 0 || bt == lastBar[i]) return;
   if(TimeCurrent() < bt + InpDelayMin * 60) return;
   int need = MathMax(InpLenH, InpLenR) + 3;
   if(iBars(sym, PERIOD_D1) < need) return;

   double h1 = iHigh(sym, PERIOD_D1, 1), l1 = iLow(sym, PERIOD_D1, 1), c1 = iClose(sym, PERIOD_D1, 1);
   double h2 = iHigh(sym, PERIOD_D1, 2);
   if(h1 <= 0 || c1 <= 0 || h2 <= 0) return;
   ulong tk;

   if(SelectPos(sym, tk))
   {
      if(c1 > h2)
      {
         double prof = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(trade.PositionClose(tk))
         {
            symN[i]++; symPnL[i] += prof; if(prof > 0) symW[i]++;
         }
         else if(trade.ResultRetcode() == TRADE_RETCODE_MARKET_CLOSED) return;   // retry later
      }
      lastBar[i] = bt;
      return;
   }

   double sumR = 0;
   for(int k = 1; k <= InpLenR; k++) sumR += iHigh(sym, PERIOD_D1, k) - iLow(sym, PERIOD_D1, k);
   int hi = iHighest(sym, PERIOD_D1, MODE_HIGH, InpLenH, 1);
   double band = iHigh(sym, PERIOD_D1, hi) - InpMult * sumR / InpLenR;
   double ibs = h1 > l1 ? (c1 - l1) / (h1 - l1) : 0.5;

   if(ibs < InpIBS && (!InpUseBand || c1 < band))
   {
      double lots = Lots(sym);
      if(lots > 0 && !trade.Buy(lots, sym, 0, 0, 0, "IBS basket") && trade.ResultRetcode() == TRADE_RETCODE_MARKET_CLOSED) return;
   }
   lastBar[i] = bt;
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
      if(s == "" || !SymbolSelect(s, true)) { if(s != "") PrintFormat("BASKET skip %s (not available)", s); continue; }
      int j = ArraySize(S);
      ArrayResize(S, j + 1); S[j] = s;
   }
   int c = ArraySize(S);
   if(c == 0) return INIT_FAILED;
   ArrayResize(lastBar, c); ArrayResize(entryEq, c); ArrayResize(symN, c); ArrayResize(symW, c); ArrayResize(symPnL, c);
   ArrayInitialize(lastBar, 0); ArrayInitialize(symN, 0); ArrayInitialize(symW, 0); ArrayInitialize(symPnL, 0.0);
   string list = "";
   for(int i = 0; i < c; i++) list += S[i] + " ";
   PrintFormat("BASKET symbols (%d): %s", c, list);
   EventSetTimer(600);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void Run() { MarkMonth(); for(int i = 0; i < ArraySize(S); i++) Process(i); }
void OnTick()  { static long lastMin = 0; long m = (long)(TimeCurrent() / 60); if(m == lastMin) return; lastMin = m; Run(); }
void OnTimer() { Run(); }

double OnTester()
{
   // close the last (partial) month
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_curMonth >= 0)
   {
      int n = ArraySize(g_mret);
      ArrayResize(g_mret, n + 1); ArrayResize(g_mkey, n + 1);
      g_mret[n] = g_monthStart > 0 ? eq / g_monthStart - 1.0 : 0; g_mkey[n] = g_curMonth;
   }
   int m = ArraySize(g_mret), pos = 0, flat = 0;
   double sum = 0, worst = 0, best = 0;
   for(int k = 0; k < m; k++)
   {
      double r = g_mret[k];
      sum += r; if(r > 0.0005) pos++; else if(r > -0.0005) flat++;
      worst = MathMin(worst, r); best = MathMax(best, r);
   }
   PrintFormat("BASKET_MONTHS months=%d positive=%d (%.0f%%) flat=%d negative=%d avg=%.2f%% worst=%.2f%% best=%.2f%%",
               m, pos, m > 0 ? 100.0 * pos / m : 0, flat, m - pos - flat, m > 0 ? 100 * sum / m : 0, 100 * worst, 100 * best);
   // yearly returns from the monthly chain
   int curY = -1; double acc = 1.0;
   for(int k = 0; k < m; k++)
   {
      int y = g_mkey[k] / 12;
      if(y != curY) { if(curY >= 0) PrintFormat("BASKET_YEAR %d %+.1f%%", curY, 100 * (acc - 1)); curY = y; acc = 1.0; }
      acc *= 1.0 + g_mret[k];
   }
   if(curY >= 0) PrintFormat("BASKET_YEAR %d %+.1f%%", curY, 100 * (acc - 1));
   for(int i = 0; i < ArraySize(S); i++)
      PrintFormat("BASKET_SYM %s trades=%d win=%.0f%% pnl=%.0f", S[i], symN[i], symN[i] > 0 ? 100.0 * symW[i] / symN[i] : 0, symPnL[i]);
   return TesterStatistics(STAT_PROFIT);
}
//+------------------------------------------------------------------+
