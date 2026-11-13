//+------------------------------------------------------------------+
//| MAP_Trend_Rider.mq5                                              |
//| Trend following on the MAP level grid (d x 10^k, halved A,B,C..) |
//| Grid  = MAP tier whose spacing >= InpGridATR x ATR(InpATRLen).   |
//| Entry = bar closes beyond a grid level in the SMA trend          |
//|         direction -> market order at next bar open.              |
//| Stop  = one grid level beyond the broken level.                  |
//| Trail = stop follows price one level at a time (on bar close).   |
//| No fixed target. Can trade several symbols at once (portfolio).  |
//| Results are also measured in R and printed by OnTester.          |
//+------------------------------------------------------------------+
#property copyright "MAP research"
#property version   "1.03"

#include <Trade/Trade.mqh>

input string          InpSymbols     = "";        // Symbols, comma separated (empty = chart symbol)
input ENUM_TIMEFRAMES InpTF          = PERIOD_D1; // Signal timeframe
input double          InpGridATR     = 1.5;       // Grid spacing >= x * ATR
input int             InpATRLen      = 50;        // ATR length
input int             InpMALen       = 200;       // SMA length (trend filter)
input bool            InpUseTrend    = true;      // Use trend filter
input bool            InpAllowLong   = true;      // Allow long trades
input bool            InpAllowShort  = true;      // Allow short trades
input double          InpRiskPercent = 1.0;       // Risk per trade (% of equity)
input int             InpDelayMin    = 0;         // Act X minutes after the new bar opens (avoid rollover spreads)
input int             InpSplitYear   = 2018;      // R stats: out-of-sample from this year
input long            InpMagic       = 20261113;  // Magic number

CTrade   trade;
string   S[];
int      hA[], hM[];
datetime lastBar[];
double   G[];

long     g_ids[];
double   g_risk[];
int      g_year[];
int      g_si[];
bool     g_retry = false;   // set when the market was closed: retry on the next call

//--- helpers -------------------------------------------------------
double Grid(double p, double a)
{
   int k = (int)MathFloor(MathLog10(p));
   double step = MathPow(10.0, k);
   int depth = (int)MathFloor(MathLog(step / (InpGridATR * a)) / MathLog(2.0));
   depth = MathMax(0, MathMin(15, depth));
   return step / MathPow(2.0, depth);
}

bool SelectPos(string sym, ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym && PositionGetInteger(POSITION_MAGIC) == InpMagic)
      { ticket = tk; return true; }
   }
   return false;
}

double NormVol(string sym, double lots)
{
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < vmin) return 0.0;
   if(lots > vmax) lots = vmax;
   return lots;
}

double LossPerLot(string sym, bool isBuy, double entry, double sl)
{
   double p = 0.0;
   if(!OrderCalcProfit(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, 1.0, entry, sl, p)) return 0.0;
   return MathAbs(p);
}

double Buf(int h)
{
   double b[1];
   if(CopyBuffer(h, 0, 1, 1, b) != 1) return 0.0;
   return b[0];
}

int YearOf(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.year; }

void Enter(int i, bool isBuy, double sl, double g)
{
   string sym = S[i];
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   sl = NormalizeDouble(sl, digits);
   if(price <= 0 || (isBuy ? sl >= price : sl <= price)) return;
   double lpl = LossPerLot(sym, isBuy, price, sl);
   if(lpl <= 0) return;
   double lots = NormVol(sym, AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0 / lpl);
   if(lots <= 0) return;
   bool ok = isBuy ? trade.Buy(lots, sym, price, sl, 0.0, "MAP long")
                   : trade.Sell(lots, sym, price, sl, 0.0, "MAP short");
   if(!ok)
   {
      if(trade.ResultRetcode() == TRADE_RETCODE_MARKET_CLOSED) g_retry = true;
      return;
   }
   G[i] = g;
   ulong tk;
   if(SelectPos(sym, tk))
   {
      int n = ArraySize(g_ids);
      ArrayResize(g_ids, n + 1); ArrayResize(g_risk, n + 1); ArrayResize(g_year, n + 1); ArrayResize(g_si, n + 1);
      g_ids[n]  = PositionGetInteger(POSITION_IDENTIFIER);
      g_risk[n] = lots * lpl;
      g_year[n] = YearOf(TimeCurrent());
      g_si[n]   = i;
   }
}

void Process(int i)
{
   string sym = S[i];
   datetime bt = iTime(sym, InpTF, 0);
   if(bt == 0 || bt == lastBar[i]) return;
   if(TimeCurrent() < bt + InpDelayMin * 60) return;
   if(hA[i] == INVALID_HANDLE) hA[i] = iATR(sym, InpTF, InpATRLen);
   if(hM[i] == INVALID_HANDLE) hM[i] = iMA(sym, InpTF, InpMALen, 0, MODE_SMA, PRICE_CLOSE);
   if(hA[i] == INVALID_HANDLE || hM[i] == INVALID_HANDLE) return;
   double c1 = iClose(sym, InpTF, 1);
   double c2 = iClose(sym, InpTF, 2);
   double a  = Buf(hA[i]);
   double m  = Buf(hM[i]);
   if(c1 <= 0 || c2 <= 0 || a <= 0 || m <= 0) return;   // data not ready yet: retry on next call
   lastBar[i] = bt;

   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   ulong tk;

   // 1) in a trade: trail the stop one grid level at a time
   if(SelectPos(sym, tk))
   {
      double g = G[i];
      if(g <= 0) return;
      double sl = PositionGetDouble(POSITION_SL);
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         double ns = NormalizeDouble((MathFloor(c1 / g + 1e-9) - 1) * g, digits);
         if(ns > sl + pt / 2 && ns < SymbolInfoDouble(sym, SYMBOL_BID))
            if(!trade.PositionModify(tk, ns, 0.0) && trade.ResultRetcode() == TRADE_RETCODE_MARKET_CLOSED) lastBar[i] = 0;
      }
      else
      {
         double ns = NormalizeDouble((MathCeil(c1 / g - 1e-9) + 1) * g, digits);
         if((sl == 0 || ns < sl - pt / 2) && ns > SymbolInfoDouble(sym, SYMBOL_ASK))
            if(!trade.PositionModify(tk, ns, 0.0) && trade.ResultRetcode() == TRADE_RETCODE_MARKET_CLOSED) lastBar[i] = 0;
      }
      return;
   }

   // 2) flat: look for a close beyond a MAP level in the trend direction
   double g  = Grid(c1, a);
   double Lb = MathFloor(c1 / g + 1e-9) * g;
   double La = MathCeil(c1 / g - 1e-9) * g;
   bool up = !InpUseTrend || c1 > m;
   bool dn = !InpUseTrend || c1 < m;
   g_retry = false;
   if(InpAllowLong && up && c2 < Lb)        Enter(i, true,  Lb - g, g);
   else if(InpAllowShort && dn && c2 > La)  Enter(i, false, La + g, g);
   if(g_retry) lastBar[i] = 0;
}

//--- events --------------------------------------------------------
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(100);
   string list = InpSymbols;
   StringTrimLeft(list); StringTrimRight(list);
   string parts[];
   int n = 0;
   if(list == "") { ArrayResize(parts, 1); parts[0] = _Symbol; n = 1; }
   else n = StringSplit(list, ',', parts);
   ArrayResize(S, 0);
   for(int k = 0; k < n; k++)
   {
      string s = parts[k];
      StringTrimLeft(s); StringTrimRight(s);
      if(s == "") continue;
      if(!SymbolSelect(s, true)) { PrintFormat("Symbol %s not found", s); return INIT_FAILED; }
      int j = ArraySize(S);
      ArrayResize(S, j + 1); S[j] = s;
   }
   int cnt = ArraySize(S);
   ArrayResize(hA, cnt); ArrayResize(hM, cnt); ArrayResize(lastBar, cnt); ArrayResize(G, cnt);
   for(int i = 0; i < cnt; i++)
   {
      hA[i] = INVALID_HANDLE;   // created lazily: some symbols start their history later
      hM[i] = INVALID_HANDLE;
      lastBar[i] = 0;
      G[i] = 0;
   }
   EventSetTimer(60);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTick()  { for(int i = 0; i < ArraySize(S); i++) Process(i); }
void OnTimer() { for(int i = 0; i < ArraySize(S); i++) Process(i); }

double OnTester()
{
   HistorySelect(0, TimeCurrent() + 86400);
   int n = ArraySize(g_ids);
   double pnl[], swp[];
   ArrayResize(pnl, n); ArrayResize(swp, n);
   ArrayInitialize(pnl, 0.0); ArrayInitialize(swp, 0.0);
   int deals = HistoryDealsTotal();
   for(int d = 0; d < deals; d++)
   {
      ulong t = HistoryDealGetTicket(d);
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic) continue;
      long pid = HistoryDealGetInteger(t, DEAL_POSITION_ID);
      double v = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) +
                 HistoryDealGetDouble(t, DEAL_COMMISSION) + HistoryDealGetDouble(t, DEAL_FEE);
      for(int k = 0; k < n; k++) if(g_ids[k] == pid) { pnl[k] += v; swp[k] += HistoryDealGetDouble(t, DEAL_SWAP); break; }
   }
   int cnt = ArraySize(S);
   double symR[]; int symN[];
   ArrayResize(symR, cnt); ArrayResize(symN, cnt);
   ArrayInitialize(symR, 0.0); ArrayInitialize(symN, 0);
   double sumR = 0, peak = 0, maxDD = 0, rIS = 0, rOOS = 0, rSwap = 0;
   int wins = 0, nIS = 0, nOOS = 0;
   for(int k = 0; k < n; k++)
   {
      if(g_risk[k] <= 0) continue;
      double r = pnl[k] / g_risk[k];
      sumR += r;
      rSwap += swp[k] / g_risk[k];
      if(r > 0) wins++;
      peak = MathMax(peak, sumR);
      maxDD = MathMax(maxDD, peak - sumR);
      if(g_year[k] >= InpSplitYear) { rOOS += r; nOOS++; } else { rIS += r; nIS++; }
      symR[g_si[k]] += r; symN[g_si[k]]++;
   }
   PrintFormat("MAP_R_STATS trades=%d winrate=%.1f totalR=%.2f avgR=%.4f maxDD_R=%.2f | IS n=%d avgR=%.4f | OOS n=%d avgR=%.4f",
               n, n > 0 ? 100.0 * wins / n : 0, sumR, n > 0 ? sumR / n : 0, maxDD,
               nIS, nIS > 0 ? rIS / nIS : 0, nOOS, nOOS > 0 ? rOOS / nOOS : 0);
   PrintFormat("MAP_R_SWAP swapR=%.2f (avg %.4f per trade) | result without swap: totalR=%.2f avgR=%.4f",
               rSwap, n > 0 ? rSwap / n : 0, sumR - rSwap, n > 0 ? (sumR - rSwap) / n : 0);
   for(int i = 0; i < cnt; i++)
      PrintFormat("MAP_R_SYM %s trades=%d totalR=%.2f avgR=%.4f", S[i], symN[i], symR[i], symN[i] > 0 ? symR[i] / symN[i] : 0);
   return sumR;
}
//+------------------------------------------------------------------+
