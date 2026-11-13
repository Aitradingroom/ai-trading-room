//+------------------------------------------------------------------+
//| Trend_Pyramid.mq5                                                |
//| Multi-symbol trend following with pyramiding (Turtle-style).     |
//| Entry : bar close beyond the N-bar Donchian channel (+ optional  |
//|         SMA trend filter and swap filter).                       |
//| Adds  : one more unit each time price moves InpAddATR x ATR in   |
//|         the trade direction, up to InpMaxUnits. All units share  |
//|         one stop, raised to InpStopATR x ATR behind the newest   |
//|         unit.                                                    |
//| Exit  : shared stop trails the M-bar Donchian channel (opposite) |
//|         or a chandelier stop (highest close - k x ATR).          |
//| Stats : each unit is measured in R (net profit / initial risk).  |
//+------------------------------------------------------------------+
#property copyright "Trend research"
#property version   "1.00"

#include <Trade/Trade.mqh>

input string          InpSymbols     = "";        // Symbols, comma separated (empty = chart symbol)
input ENUM_TIMEFRAMES InpTF          = PERIOD_D1; // Signal timeframe
input int             InpEntryN      = 55;        // Entry: Donchian breakout length
input int             InpExitM       = 20;        // Exit: Donchian trailing length (0 = off)
input double          InpChandATR    = 0.0;       // Exit: chandelier k x ATR from best close (0 = off)
input int             InpATRLen      = 20;        // ATR length
input double          InpStopATR     = 2.0;       // Initial stop distance (x ATR)
input int             InpMaxUnits    = 4;         // Max units per symbol (1 = no pyramiding)
input double          InpAddATR      = 1.0;       // Add a unit every x ATR of favourable move
input int             InpMALen       = 200;       // Trend filter SMA length (0 = off)
input double          InpMaxSwapR    = 0.0;       // Skip a direction if daily swap costs more than x R (0 = off)
input bool            InpAllowLong   = true;      // Allow long trades
input bool            InpAllowShort  = true;      // Allow short trades
input double          InpRiskPercent = 0.5;       // Risk per unit (% of equity)
input int             InpDelayMin    = 120;       // Act X minutes after the new bar opens
input int             InpSplitYear   = 2018;      // R stats: out-of-sample from this year
input long            InpMagic       = 20261114;  // Magic number

CTrade   trade;
string   S[];
int      hA[], hM[];
datetime lastBar[];
double   lastAdd[];   // price of the newest unit
double   bestClose[]; // best close since the first unit (chandelier)

long     g_ids[];
double   g_risk[];
int      g_year[];
int      g_si[];
bool     g_retry = false;

//--- helpers -------------------------------------------------------
double Buf(int h, int shift = 1)
{
   double b[1];
   if(h == INVALID_HANDLE || CopyBuffer(h, 0, shift, 1, b) != 1) return 0.0;
   return b[0];
}

int YearOf(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.year; }

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

double MoveValue(string sym, bool isBuy, double from, double to)   // money for 1 lot
{
   double p = 0.0;
   if(!OrderCalcProfit(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, 1.0, from, to, p)) return 0.0;
   return p;
}

// daily swap for 1 lot in account money (negative = cost)
double SwapPerDay(string sym, bool isBuy, double price)
{
   double sw = SymbolInfoDouble(sym, isBuy ? SYMBOL_SWAP_LONG : SYMBOL_SWAP_SHORT);
   long mode = SymbolInfoInteger(sym, SYMBOL_SWAP_MODE);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(mode == SYMBOL_SWAP_MODE_POINTS)
      return MoveValue(sym, true, price, price + sw * pt);
   if(mode == SYMBOL_SWAP_MODE_INTEREST_CURRENT || mode == SYMBOL_SWAP_MODE_INTEREST_OPEN)
      return MoveValue(sym, true, price, price * (1.0 + sw / 100.0 / 360.0));
   if(mode == SYMBOL_SWAP_MODE_CURRENCY_DEPOSIT || mode == SYMBOL_SWAP_MODE_CURRENCY_MARGIN ||
      mode == SYMBOL_SWAP_MODE_CURRENCY_SYMBOL)
      return sw;
   return 0.0;
}

int CollectPositions(string sym, ulong &tickets[], int &dir)
{
   ArrayResize(tickets, 0);
   dir = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      tickets[n] = tk;
      dir = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   }
   return ArraySize(tickets);
}

bool OpenUnit(int i, bool isBuy, double sl)
{
   string sym = S[i];
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   sl = NormalizeDouble(sl, digits);
   if(price <= 0 || (isBuy ? sl >= price : sl <= price)) return false;
   double lpl = MathAbs(MoveValue(sym, isBuy, price, sl));
   if(lpl <= 0) return false;
   double lots = NormVol(sym, AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0 / lpl);
   if(lots <= 0) return false;
   bool ok = isBuy ? trade.Buy(lots, sym, price, sl, 0.0, "TP unit")
                   : trade.Sell(lots, sym, price, sl, 0.0, "TP unit");
   if(!ok)
   {
      if(trade.ResultRetcode() == TRADE_RETCODE_MARKET_CLOSED) g_retry = true;
      return false;
   }
   ulong deal = trade.ResultDeal();
   long pid = 0;
   if(deal > 0 && HistoryDealSelect(deal)) pid = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   if(pid == 0) pid = (long)trade.ResultOrder();
   int n = ArraySize(g_ids);
   ArrayResize(g_ids, n + 1); ArrayResize(g_risk, n + 1); ArrayResize(g_year, n + 1); ArrayResize(g_si, n + 1);
   g_ids[n] = pid; g_risk[n] = lots * lpl; g_year[n] = YearOf(TimeCurrent()); g_si[n] = i;
   lastAdd[i] = price;
   return true;
}

void SetStops(string sym, ulong &tickets[], double sl, bool isBuy)
{
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   sl = NormalizeDouble(sl, digits);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID), ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(isBuy ? sl >= bid : sl <= ask) return;
   for(int k = 0; k < ArraySize(tickets); k++)
   {
      if(!PositionSelectByTicket(tickets[k])) continue;
      double cur = PositionGetDouble(POSITION_SL);
      bool better = isBuy ? (sl > cur + pt / 2) : (cur == 0 || sl < cur - pt / 2);
      if(!better) continue;
      if(!trade.PositionModify(tickets[k], sl, 0.0) && trade.ResultRetcode() == TRADE_RETCODE_MARKET_CLOSED) g_retry = true;
   }
}

double CommonSL(ulong &tickets[], bool isBuy)
{
   double best = 0;
   for(int k = 0; k < ArraySize(tickets); k++)
   {
      if(!PositionSelectByTicket(tickets[k])) continue;
      double sl = PositionGetDouble(POSITION_SL);
      if(sl == 0) continue;
      if(best == 0 || (isBuy ? sl > best : sl < best)) best = sl;
   }
   return best;
}

bool SwapOK(string sym, bool isBuy, double price, double atr)
{
   if(InpMaxSwapR <= 0) return true;
   double riskPerLot = MathAbs(MoveValue(sym, isBuy, price, isBuy ? price - InpStopATR * atr : price + InpStopATR * atr));
   if(riskPerLot <= 0) return true;
   double swR = SwapPerDay(sym, isBuy, price) / riskPerLot;
   return swR >= -InpMaxSwapR;
}

void Process(int i)
{
   string sym = S[i];
   datetime bt = iTime(sym, InpTF, 0);
   if(bt == 0 || bt == lastBar[i]) return;
   if(TimeCurrent() < bt + InpDelayMin * 60) return;
   if(hA[i] == INVALID_HANDLE) hA[i] = iATR(sym, InpTF, InpATRLen);
   if(InpMALen > 0 && hM[i] == INVALID_HANDLE) hM[i] = iMA(sym, InpTF, InpMALen, 0, MODE_SMA, PRICE_CLOSE);
   double atr = Buf(hA[i]);
   double ma  = InpMALen > 0 ? Buf(hM[i]) : 0;
   double c1  = iClose(sym, InpTF, 1);
   int need = MathMax(InpEntryN, InpExitM) + 2;
   if(atr <= 0 || c1 <= 0 || (InpMALen > 0 && ma <= 0) || iBars(sym, InpTF) < need) return;
   lastBar[i] = bt;
   g_retry = false;

   ulong tickets[];
   int dir = 0;
   int units = CollectPositions(sym, tickets, dir);

   if(units > 0)
   {
      bool isBuy = dir == 1;
      if(isBuy) bestClose[i] = MathMax(bestClose[i], c1); else bestClose[i] = (bestClose[i] == 0 ? c1 : MathMin(bestClose[i], c1));
      double sl = CommonSL(tickets, isBuy);
      // trailing exits
      if(InpExitM > 0)
      {
         int idx = isBuy ? iLowest(sym, InpTF, MODE_LOW, InpExitM, 1) : iHighest(sym, InpTF, MODE_HIGH, InpExitM, 1);
         double ch = isBuy ? iLow(sym, InpTF, idx) : iHigh(sym, InpTF, idx);
         if(ch > 0) sl = isBuy ? MathMax(sl, ch) : (sl == 0 ? ch : MathMin(sl, ch));
      }
      if(InpChandATR > 0)
      {
         double cs = isBuy ? bestClose[i] - InpChandATR * atr : bestClose[i] + InpChandATR * atr;
         sl = isBuy ? MathMax(sl, cs) : (sl == 0 ? cs : MathMin(sl, cs));
      }
      // pyramiding
      if(units < InpMaxUnits)
      {
         bool addSig = isBuy ? c1 >= lastAdd[i] + InpAddATR * atr : c1 <= lastAdd[i] - InpAddATR * atr;
         if(addSig)
         {
            double price = isBuy ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
            double unitSL = isBuy ? price - InpStopATR * atr : price + InpStopATR * atr;
            sl = isBuy ? MathMax(sl, unitSL) : MathMin(sl, unitSL);
            SetStops(sym, tickets, sl, isBuy);
            if(OpenUnit(i, isBuy, sl))
            {
               CollectPositions(sym, tickets, dir);
            }
         }
      }
      SetStops(sym, tickets, sl, isBuy);
      if(g_retry) lastBar[i] = 0;
      return;
   }

   // flat: Donchian breakout of the previous N bars (bars 2..N+1)
   int hi = iHighest(sym, InpTF, MODE_HIGH, InpEntryN, 2);
   int lo = iLowest(sym, InpTF, MODE_LOW, InpEntryN, 2);
   double HH = iHigh(sym, InpTF, hi), LL = iLow(sym, InpTF, lo);
   if(HH <= 0 || LL <= 0) return;
   bool upOK = InpMALen <= 0 || c1 > ma;
   bool dnOK = InpMALen <= 0 || c1 < ma;
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK), bid = SymbolInfoDouble(sym, SYMBOL_BID);
   if(InpAllowLong && upOK && c1 > HH && SwapOK(sym, true, ask, atr))
   {
      bestClose[i] = c1;
      OpenUnit(i, true, ask - InpStopATR * atr);
   }
   else if(InpAllowShort && dnOK && c1 < LL && SwapOK(sym, false, bid, atr))
   {
      bestClose[i] = c1;
      OpenUnit(i, false, bid + InpStopATR * atr);
   }
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
      if(!SymbolSelect(s, true)) { PrintFormat("TP_WARN symbol %s not found - skipped", s); continue; }
      int j = ArraySize(S);
      ArrayResize(S, j + 1); S[j] = s;
   }
   int cnt = ArraySize(S);
   if(cnt == 0) return INIT_FAILED;
   ArrayResize(hA, cnt); ArrayResize(hM, cnt); ArrayResize(lastBar, cnt);
   ArrayResize(lastAdd, cnt); ArrayResize(bestClose, cnt);
   for(int i = 0; i < cnt; i++)
   {
      hA[i] = INVALID_HANDLE; hM[i] = INVALID_HANDLE;
      lastBar[i] = 0; lastAdd[i] = 0; bestClose[i] = 0;
   }
   EventSetTimer(3600);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { EventKillTimer(); }
void OnTick()  { static long lastMin = 0; long m = (long)(TimeCurrent() / 60); if(m == lastMin) return; lastMin = m; for(int i = 0; i < ArraySize(S); i++) Process(i); }
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
   double sumR = 0, rIS = 0, rOOS = 0, rSwap = 0;
   int wins = 0, nIS = 0, nOOS = 0;
   for(int k = 0; k < n; k++)
   {
      if(g_risk[k] <= 0) continue;
      double r = pnl[k] / g_risk[k];
      sumR += r; rSwap += swp[k] / g_risk[k];
      if(r > 0) wins++;
      if(g_year[k] >= InpSplitYear) { rOOS += r; nOOS++; } else { rIS += r; nIS++; }
      symR[g_si[k]] += r; symN[g_si[k]]++;
   }
   PrintFormat("TP_STATS units=%d win=%.1f totalR=%.2f avgR=%.4f swapR=%.2f",
               n, n > 0 ? 100.0 * wins / n : 0, sumR, n > 0 ? sumR / n : 0, rSwap);
   PrintFormat("TP_SPLIT IS n=%d avgR=%.4f totR=%.1f", nIS, nIS > 0 ? rIS / nIS : 0, rIS);
   PrintFormat("TP_SPLIT OOS n=%d avgR=%.4f totR=%.1f", nOOS, nOOS > 0 ? rOOS / nOOS : 0, rOOS);
   for(int i = 0; i < cnt; i++)
      PrintFormat("TP_SYM %s n=%d totR=%.1f avgR=%.3f", S[i], symN[i], symR[i], symN[i] > 0 ? symR[i] / symN[i] : 0);
   return sumR;
}
//+------------------------------------------------------------------+
