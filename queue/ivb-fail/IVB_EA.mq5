//+------------------------------------------------------------------+
//| IVB_EA.mq5 — Initial Volatility Breakout (rebuild from a reel)    |
//| AI Trading Room — research/backtest only.                         |
//| IB = high/low of 09:30-10:00 NY (16:30-17:00 server, GMT+2/+3).   |
//| Filters (on the breakout bar):                                    |
//|  - today's IB range / avg IB range of last N days in [min,max]    |
//|  - bar volume >= Surge x average of previous K RTH bars           |
//| Close > IB high -> long, close < IB low -> short (5m chart).      |
//| SL = StopATR x ATR(14), TP = TpATR x ATR(14). Risk % of equity.   |
//| Max trades per day, entry window until 16:00 NY, optional flatten.|
//+------------------------------------------------------------------+
#property copyright "AI Trading Room"
#property version   "1.00"
#include <Trade/Trade.mqh>
CTrade trade;

input int    InpSess    = 1630;  // Session start (server HHMM) = 09:30 NY
input int    InpIBEnd   = 1700;  // IB close (server HHMM) = 10:00 NY
input int    InpWinEnd  = 2300;  // Entry window end (server) = 16:00 NY
input int    InpDir     = 0;     // 0=both 1=long 2=short
input double InpMaxCR   = 1.1;   // Max contraction ratio
input double InpMinCR   = 0.3;   // Min contraction ratio
input int    InpIBLook  = 10;    // Trailing IB lookback (days)
input double InpSurge   = 1.2;   // Volume surge multiplier
input int    InpVolLook = 10;    // RTH volume lookback (bars)
input int    InpATR     = 14;
input double InpRiskPct = 2.0;   // Risk % of equity per trade
input double InpSLATR   = 3.5;
input double InpTPATR   = 5.0;
input bool   InpFlatten = false; // Flatten at EOD
input int    InpFlatT   = 2300;  // Flatten time (server)
input int    InpMaxDay  = 2;     // Max trades per day
input long   InpMagic   = 26111905;

int hATR; datetime lastBar=0; int dayKey=-1;
double ibH=0, ibL=0; bool ibDone=false, ibOK=false; int tradesToday=0;
double ibHist[]; int ibN=0;
double volBuf[]; int volN=0;

int HM(datetime t){ MqlDateTime d; TimeToStruct(t,d); return d.hour*100+d.min; }
int Pos(){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)==InpMagic) return PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1; } return 0; }
void CloseAll(){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)==InpMagic) trade.PositionClose(t); } }
double Lots(double d){ double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS), ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); if(tv<=0||ts<=0||d<=0) return 0; double l=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPct/100.0/(d/ts*tv); double st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP), mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX); l=MathFloor(l/st)*st; if(l<mn) return 0; return MathMin(mx,l); }

int OnInit(){ hATR=iATR(_Symbol,_Period,InpATR); trade.SetExpertMagicNumber(InpMagic); ArrayResize(ibHist,InpIBLook); ArrayResize(volBuf,InpVolLook); return hATR==INVALID_HANDLE?INIT_FAILED:INIT_SUCCEEDED; }

void OnTick()
{
   datetime t0=iTime(_Symbol,_Period,0); if(t0==lastBar) return; lastBar=t0;
   MqlRates b[1]; if(CopyRates(_Symbol,_Period,1,1,b)!=1) return;
   MqlDateTime d; TimeToStruct(b[0].time,d);
   if(d.day_of_week==0||d.day_of_week==6) return;
   int key=d.year*1000+d.day_of_year, hm=d.hour*100+d.min;
   int barEnd=HM(t0); // time when the closed bar ended
   if(key!=dayKey){ dayKey=key; ibH=0; ibL=0; ibDone=false; ibOK=false; tradesToday=0; volN=0; }

   if(InpFlatten && Pos()!=0 && barEnd>=InpFlatT) CloseAll();

   bool rth = hm>=InpSess && hm<InpWinEnd;
   // build IB
   if(hm>=InpSess && hm<InpIBEnd){ if(ibH==0){ ibH=b[0].high; ibL=b[0].low; } else { ibH=MathMax(ibH,b[0].high); ibL=MathMin(ibL,b[0].low); } }
   double v=(double)b[0].tick_volume;
   // freeze IB at IB close
   if(!ibDone && ibH>0 && barEnd>=InpIBEnd){
      ibDone=true; double r=ibH-ibL;
      if(ibN>=InpIBLook){ double s=0; for(int i=0;i<InpIBLook;i++) s+=ibHist[i]; double avg=s/InpIBLook; double cr=avg>0? r/avg:0; ibOK=(cr>=InpMinCR && cr<=InpMaxCR); }
      for(int i=InpIBLook-1;i>0;i--) ibHist[i]=ibHist[i-1]; ibHist[0]=r; if(ibN<InpIBLook) ibN++;
   }
   // signal (on bars after the IB, inside the entry window)
   if(ibDone && ibOK && rth && hm>=InpIBEnd && tradesToday<InpMaxDay && Pos()==0 && volN>=InpVolLook){
      double s=0; for(int i=0;i<InpVolLook;i++) s+=volBuf[i]; double avgV=s/InpVolLook;
      if(v>=InpSurge*avgV){
         double a[1]; if(CopyBuffer(hATR,0,1,1,a)==1){
            double sd=InpSLATR*a[0], td=InpTPATR*a[0];
            if(b[0].close>ibH && InpDir!=2){ double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), l=Lots(sd); if(l>0 && trade.Buy(l,_Symbol,ask,NormalizeDouble(ask-sd,_Digits),NormalizeDouble(ask+td,_Digits),"IVB L")) tradesToday++; }
            else if(b[0].close<ibL && InpDir!=1){ double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID), l=Lots(sd); if(l>0 && trade.Sell(l,_Symbol,bid,NormalizeDouble(bid+sd,_Digits),NormalizeDouble(bid-td,_Digits),"IVB S")) tradesToday++; }
         }
      }
   }
   // update RTH volume buffer (previous K RTH bars, excluding current at signal time)
   if(rth){ for(int i=InpVolLook-1;i>0;i--) volBuf[i]=volBuf[i-1]; volBuf[0]=v; if(volN<InpVolLook) volN++; }
}

double OnTester()
{
   double tr=TesterStatistics(STAT_TRADES);
   PrintFormat("IVB %s trades=%.0f PF=%.2f net=%.2f maxDD%%=%.2f", _Symbol, tr, TesterStatistics(STAT_PROFIT_FACTOR), TesterStatistics(STAT_PROFIT), TesterStatistics(STAT_EQUITYDD_PERCENT));
   return TesterStatistics(STAT_PROFIT_FACTOR);
}
