//+------------------------------------------------------------------+
//| ORB_London.mq5 - Opening Range Breakout, multi-session           |
//| Range = first N minutes after the session open (local time,      |
//| DST-aware, converted to server time).                            |
//| First bar CLOSE beyond the range -> enter at next bar open.      |
//| Stop = opposite side of range. Exit = session open + X minutes.  |
//| One trade per session. Results are also measured in R            |
//| (net profit / initial risk), printed and returned by OnTester.   |
//+------------------------------------------------------------------+
#property copyright "ORB research"
#property version   "3.00"

#include <Trade/Trade.mqh>

enum ENUM_SESSION { SES_SYDNEY = 0, SES_TOKYO = 1, SES_LONDON = 2, SES_NEWYORK = 3 };

input ENUM_SESSION    InpSession        = SES_LONDON;  // Session
input int             InpRangeMinutes   = 15;          // Opening range length (minutes)
input int             InpEntryWindowMin = 240;         // Entries allowed until open + X minutes
input int             InpSessionMinutes = 360;         // Close any trade at open + X minutes
input double          InpRiskPercent    = 1.0;         // Risk per trade (% of equity)
input bool            InpAllowLong      = true;        // Allow long trades
input bool            InpAllowShort     = true;        // Allow short trades
input ENUM_TIMEFRAMES InpTF             = PERIOD_M15;  // Signal timeframe (bar closes)
input int             InpServerGMT      = 2;           // Broker server GMT offset (winter)
input bool            InpServerUSDST    = true;        // Server shifts +1h during US DST
input long            InpMagic          = 20261112;    // Magic number
input int             InpTrendFilter    = 0;           // Trend filter: 0 off, 1 trade with daily SMA50
input int             InpORFilter       = 0;           // Range filter: 0 off, 1 OR<=0.20 ATR, 2 OR<=0.35 ATR, 3 OR>=0.10 ATR, 4 OR>=0.20 ATR
input int             InpVolFilter      = 0;           // Volatility filter: 0 off, 1 ATR14/ATR100>=1.0, 2 >=1.15, 3 <=1.0

CTrade   trade;
datetime g_lastBar   = 0;
datetime g_open      = 0;     // current session open (server time)
datetime g_posOpen   = 0;     // session open of the open position
double   g_orHigh    = 0.0;
double   g_orLow     = 0.0;
bool     g_hasRange  = false;
bool     g_rangeDone = false;
bool     g_traded    = false;

int      hMA = INVALID_HANDLE, hATR14 = INVALID_HANDLE, hATR100 = INVALID_HANDLE;
long     g_ids[];
double   g_risk[];

//--- calendar helpers ----------------------------------------------
datetime MakeDate(int y, int m, int d)
{
   MqlDateTime s; ZeroMemory(s);
   s.year = y; s.mon = m; s.day = d;
   return StructToTime(s);
}

int DOW(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.day_of_week; }

datetime NthSunday(int y, int m, int n)
{
   datetime d = MakeDate(y, m, 1);
   int add = (7 - DOW(d)) % 7;
   return d + (add + 7 * (n - 1)) * 86400;
}

datetime LastSunday(int y, int m)
{
   int nm = (m == 12) ? 1 : m + 1;
   int ny = (m == 12) ? y + 1 : y;
   datetime d = MakeDate(ny, nm, 1) - 86400;
   return d - DOW(d) * 86400;
}

bool IsUSDST(datetime t)
{
   MqlDateTime s; TimeToStruct(t, s);
   return t >= NthSunday(s.year, 3, 2) && t < NthSunday(s.year, 11, 1);
}

bool IsEUDST(datetime t)
{
   MqlDateTime s; TimeToStruct(t, s);
   return t >= LastSunday(s.year, 3) && t < LastSunday(s.year, 10);
}

bool IsAUDST(datetime t)
{
   MqlDateTime s; TimeToStruct(t, s);
   return t >= NthSunday(s.year, 10, 1) || t < NthSunday(s.year, 4, 1);
}

// session open (server time) for a given local calendar day
datetime SessionOpenServer(datetime day)
{
   int localMin = 0, offMin = 0;
   switch(InpSession)
   {
      case SES_SYDNEY:  localMin = 420; offMin = IsAUDST(day) ? 660 : 600; break;   // 07:00 Sydney
      case SES_TOKYO:   localMin = 540; offMin = 540;                       break;   // 09:00 Tokyo
      case SES_LONDON:  localMin = 480; offMin = IsEUDST(day) ? 60 : 0;     break;   // 08:00 London
      case SES_NEWYORK: localMin = 570; offMin = IsUSDST(day) ? -240 : -300; break;  // 09:30 New York
   }
   datetime utc = day + (localMin - offMin) * 60;
   int srv = InpServerGMT * 60 + ((InpServerUSDST && IsUSDST(utc)) ? 60 : 0);
   return utc + srv * 60;
}

// latest session open at or before t
datetime LatestOpen(datetime t)
{
   datetime day = t - (t % 86400);
   datetime best = 0;
   for(int k = -1; k <= 1; k++)
   {
      datetime o = SessionOpenServer(day + k * 86400);
      if(o <= t && o > best) best = o;
   }
   return best;
}

//--- trading helpers -----------------------------------------------
bool SelectOurPosition(ulong &ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
      { ticket = tk; return true; }
   }
   return false;
}

double NormalizeVolume(double lots)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < vmin) return 0.0;
   if(lots > vmax) lots = vmax;
   return lots;
}

double LossPerLot(bool isBuy, double entry, double sl)
{
   double p = 0.0;
   if(!OrderCalcProfit(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, 1.0, entry, sl, p)) return 0.0;
   return MathAbs(p);
}

void RememberRisk(double riskMoney)
{
   ulong t;
   if(!SelectOurPosition(t)) return;
   long id = PositionGetInteger(POSITION_IDENTIFIER);
   int n = ArraySize(g_ids);
   ArrayResize(g_ids, n + 1);
   ArrayResize(g_risk, n + 1);
   g_ids[n] = id;
   g_risk[n] = riskMoney;
}

void Enter(bool isBuy)
{
   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl    = NormalizeDouble(isBuy ? g_orLow : g_orHigh, _Digits);
   if(isBuy ? (sl >= price) : (sl <= price)) return;
   double lpl = LossPerLot(isBuy, price, sl);
   if(lpl <= 0) return;
   double lots = NormalizeVolume(AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0 / lpl);
   if(lots <= 0) return;
   bool ok = isBuy ? trade.Buy(lots, _Symbol, price, sl, 0.0, "ORB long")
                   : trade.Sell(lots, _Symbol, price, sl, 0.0, "ORB short");
   if(ok)
   {
      g_posOpen = g_open;
      RememberRisk(lots * lpl);
   }
}

//--- events --------------------------------------------------------
double Buf(int h)
{
   double b[1];
   if(CopyBuffer(h, 0, 1, 1, b) != 1) return 0.0;
   return b[0];
}

bool FilterOK(bool isBuy)
{
   if(InpTrendFilter == 1)
   {
      double ma = Buf(hMA), cl = iClose(_Symbol, PERIOD_D1, 1);
      if(ma <= 0) return false;
      if(isBuy && cl <= ma) return false;
      if(!isBuy && cl >= ma) return false;
   }
   double a14 = Buf(hATR14);
   if(InpORFilter > 0)
   {
      if(a14 <= 0) return false;
      double w = (g_orHigh - g_orLow) / a14;
      if(InpORFilter == 1 && w > 0.20) return false;
      if(InpORFilter == 2 && w > 0.35) return false;
      if(InpORFilter == 3 && w < 0.10) return false;
      if(InpORFilter == 4 && w < 0.20) return false;
   }
   if(InpVolFilter > 0)
   {
      double a100 = Buf(hATR100);
      if(a14 <= 0 || a100 <= 0) return false;
      double r = a14 / a100;
      if(InpVolFilter == 1 && r < 1.0) return false;
      if(InpVolFilter == 2 && r < 1.15) return false;
      if(InpVolFilter == 3 && r > 1.0) return false;
   }
   return true;
}

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   hMA     = iMA(_Symbol, PERIOD_D1, 50, 0, MODE_SMA, PRICE_CLOSE);
   hATR14  = iATR(_Symbol, PERIOD_D1, 14);
   hATR100 = iATR(_Symbol, PERIOD_D1, 100);
   if(hMA == INVALID_HANDLE || hATR14 == INVALID_HANDLE || hATR100 == INVALID_HANDLE) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnTick()
{
   datetime barTime = iTime(_Symbol, InpTF, 0);
   if(barTime == 0 || barTime == g_lastBar) return;
   g_lastBar = barTime;

   int tfMin = PeriodSeconds(InpTF) / 60;
   ulong ticket;

   // 1) time exit
   if(SelectOurPosition(ticket) && (barTime - g_posOpen) / 60 >= InpSessionMinutes)
      trade.PositionClose(ticket);

   // 2) last closed bar
   datetime t1 = iTime(_Symbol, InpTF, 1);
   if(t1 == 0) return;
   datetime o = LatestOpen(t1);
   if(o != g_open)
   {
      g_open = o; g_hasRange = false; g_rangeDone = false; g_traded = false;
   }
   long elapsed = (t1 - g_open) / 60;

   // 3) build range
   if(elapsed >= 0 && elapsed < InpRangeMinutes)
   {
      double h = iHigh(_Symbol, InpTF, 1), l = iLow(_Symbol, InpTF, 1);
      if(!g_hasRange) { g_orHigh = h; g_orLow = l; g_hasRange = true; }
      else            { g_orHigh = MathMax(g_orHigh, h); g_orLow = MathMin(g_orLow, l); }
      if(elapsed + tfMin >= InpRangeMinutes) g_rangeDone = true;
      return;
   }

   // 4) breakout
   if(!g_rangeDone || g_traded || elapsed >= InpEntryWindowMin) return;
   if(SelectOurPosition(ticket)) return;
   double c = iClose(_Symbol, InpTF, 1);
   if(c > g_orHigh)      { if(InpAllowLong && FilterOK(true))   Enter(true);  g_traded = true; }
   else if(c < g_orLow)  { if(InpAllowShort && FilterOK(false)) Enter(false); g_traded = true; }
}

double OnTester()
{
   HistorySelect(0, TimeCurrent() + 86400);
   int n = ArraySize(g_ids);
   double pnl[];
   ArrayResize(pnl, n);
   ArrayInitialize(pnl, 0.0);
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      long pid = HistoryDealGetInteger(d, DEAL_POSITION_ID);
      double v = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
                 HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
      for(int k = 0; k < n; k++) if(g_ids[k] == pid) { pnl[k] += v; break; }
   }
   double sumR = 0, peak = 0, maxDD = 0;
   int wins = 0;
   for(int k = 0; k < n; k++)
   {
      if(g_risk[k] <= 0) continue;
      double r = pnl[k] / g_risk[k];
      sumR += r;
      if(r > 0) wins++;
      peak = MathMax(peak, sumR);
      maxDD = MathMax(maxDD, peak - sumR);
   }
   PrintFormat("ORB_R_STATS session=%d range=%d trades=%d wins=%d winrate=%.1f totalR=%.2f avgR=%.4f maxDD_R=%.2f",
               (int)InpSession, InpRangeMinutes, n, wins, n > 0 ? 100.0 * wins / n : 0, sumR, n > 0 ? sumR / n : 0, maxDD);
   return sumR;
}
//+------------------------------------------------------------------+
