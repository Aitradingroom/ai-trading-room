//+------------------------------------------------------------------+
//| RangeBreakout_v1_EA.mq5 — AITR Forex Range Breakout v1 (direct)   |
//| MQL5 port of AITR_RangeBreakout_v1.pine. Backtest/demo only.     |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input int    InpRangeLen = 12;     // Range candles (closed, before signal)
input int    InpATR      = 14;     // ATR length
input double InpComp     = 1.5;    // Compression: width < x ATR
input double InpSL       = 1.5;    // Stop = x ATR
input double InpRR       = 3.0;    // Target = x stop
input int    InpMaxBars  = 12;     // Time exit bars (0=off)
input double InpRisk     = 0.5;    // Risk % equity
input int    InpMaxDay   = 0;      // Max trades/day (0=unlimited)
input bool   InpUseEMA   = false;  // EMA trend filter
input int    InpEMA      = 200;
input int    InpADXMode  = 0;      // ADX filter: 0 off, 1 above, 2 below
input double InpADXLvl   = 20;
input bool   InpUseSess  = false;  // Session filter (server hours)
input int    InpSessFrom = 9;      // session start hour (server)
input int    InpSessTo   = 19;     // session end hour (server, exclusive)
input double InpAtrMinP  = 0;      // ATR min pips (0=off)
input double InpAtrMaxP  = 0;      // ATR max pips (0=off)
input double InpBrk      = 0;      // min breakout beyond range (x ATR)
input bool   InpUseH4    = false;  // H4 trend filter (confirmed bar)
input int    InpH4EMA    = 50;
input long   InpMagic    = 51001;

int hATR, hEMA, hADX, hH4;
datetime lastBar = 0;
int dayCount = 0, lastDay = -1;
double lastRisk = 0;
datetime entryTime = 0;
// stats
int nT=0, nW=0, nL=0, nS=0, streak=0, maxStreak=0;
double sumR=0, sumWR=0, sumLR=0;
double yR[100]; int yN[100]; double mR[100][12];

double Pip(){ int d=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS); return (d==3||d==5)? _Point*10 : _Point; }

int OnInit(){
   hATR=iATR(_Symbol,_Period,InpATR);
   hEMA=iMA(_Symbol,_Period,InpEMA,0,MODE_EMA,PRICE_CLOSE);
   hADX=iADX(_Symbol,_Period,14);
   hH4 =iMA(_Symbol,PERIOD_H4,InpH4EMA,0,MODE_EMA,PRICE_CLOSE);
   trade.SetExpertMagicNumber(InpMagic);
   ArrayInitialize(yR,0); ArrayInitialize(yN,0); ArrayInitialize(mR,0);
   return INIT_SUCCEEDED;
}

double Buf(int h,int buf,int shift){ double v[1]; if(CopyBuffer(h,buf,shift,1,v)!=1) return EMPTY_VALUE; return v[0]; }

bool HasPos(){
   for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagic) return true; }
   return false;
}

void OnTradeTransaction(const MqlTradeTransaction &tr,const MqlTradeRequest &rq,const MqlTradeResult &rs){
   if(tr.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(tr.deal)) return;
   if(HistoryDealGetInteger(tr.deal,DEAL_MAGIC)!=InpMagic) return;
   long entry=HistoryDealGetInteger(tr.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT) return;
   double p=HistoryDealGetDouble(tr.deal,DEAL_PROFIT)+HistoryDealGetDouble(tr.deal,DEAL_COMMISSION)+HistoryDealGetDouble(tr.deal,DEAL_SWAP);
   double r= lastRisk>0? p/lastRisk : 0;
   long typ=HistoryDealGetInteger(tr.deal,DEAL_TYPE); // closing a long = SELL deal
   if(typ==DEAL_TYPE_SELL) nL++; else nS++;
   nT++; sumR+=r;
   if(p>0){ nW++; sumWR+=r; streak=0; } else { sumLR+=r; streak++; if(streak>maxStreak) maxStreak=streak; }
   MqlDateTime dt; TimeToStruct((datetime)HistoryDealGetInteger(tr.deal,DEAL_TIME),dt);
   int yi=dt.year-2000; if(yi>=0&&yi<100){ yR[yi]+=r; yN[yi]++; mR[yi][dt.mon-1]+=r; }
}

void OnTick(){
   datetime bt=iTime(_Symbol,_Period,0);
   if(bt==lastBar) return;
   lastBar=bt;
   MqlDateTime dt; TimeToStruct(bt,dt);
   if(dt.day_of_year!=lastDay){ lastDay=dt.day_of_year; dayCount=0; }

   // time exit at the open of the bar after InpMaxBars bars in trade
   if(HasPos() && InpMaxBars>0){
      int sh=iBarShift(_Symbol,_Period,entryTime,false);
      if(sh>=InpMaxBars){ trade.PositionClose(_Symbol); }
   }
   if(HasPos()) return;
   if(InpMaxDay>0 && dayCount>=InpMaxDay) return;

   // signal bar = 1 (just closed); range = bars 2..RangeLen+1
   int hi=iHighest(_Symbol,_Period,MODE_HIGH,InpRangeLen,2);
   int lo=iLowest (_Symbol,_Period,MODE_LOW ,InpRangeLen,2);
   double rH=iHigh(_Symbol,_Period,hi), rL=iLow(_Symbol,_Period,lo);
   double atrPrev=Buf(hATR,0,2), atr=Buf(hATR,0,1);
   if(atrPrev==EMPTY_VALUE||atr==EMPTY_VALUE||atr<=0) return;
   if(rH-rL >= InpComp*atrPrev) return;
   double c=iClose(_Symbol,_Period,1);
   double brk=InpBrk*atr;
   bool L = c>rH && c-rH>=brk;
   bool S = c<rL && rL-c>=brk;
   if(!L && !S) return;

   // filters
   if(InpUseEMA){ double e=Buf(hEMA,0,1); if(L && c<=e) return; if(S && c>=e) return; }
   if(InpADXMode>0){ double a=Buf(hADX,0,1); if(InpADXMode==1 && a<=InpADXLvl) return; if(InpADXMode==2 && a>=InpADXLvl) return; }
   if(InpUseSess){ MqlDateTime d1; TimeToStruct(iTime(_Symbol,_Period,1),d1); if(d1.hour<InpSessFrom||d1.hour>=InpSessTo) return; }
   double ap=atr/Pip();
   if(InpAtrMinP>0 && ap<InpAtrMinP) return;
   if(InpAtrMaxP>0 && ap>InpAtrMaxP) return;
   if(InpUseH4){
      int s4=iBarShift(_Symbol,PERIOD_H4,iTime(_Symbol,_Period,0),false)+1; // last CLOSED H4 bar
      double e4=Buf(hH4,0,s4), c4=iClose(_Symbol,PERIOD_H4,s4);
      if(L && c4<=e4) return; if(S && c4>=e4) return;
   }

   // sizing
   double dist=InpSL*atr;
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE), ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double riskCash=AccountInfoDouble(ACCOUNT_EQUITY)*InpRisk/100.0;
   double lossPerLot=dist/ts*tv;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP), vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), vmax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double lots=MathFloor(riskCash/lossPerLot/step)*step;
   if(lots<vmin) return; if(lots>vmax) lots=vmax;

   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   bool ok=false;
   if(L) ok=trade.Buy (lots,_Symbol,ask,NormalizeDouble(ask-dist,_Digits),NormalizeDouble(ask+dist*InpRR,_Digits),"RB L");
   else  ok=trade.Sell(lots,_Symbol,bid,NormalizeDouble(bid+dist,_Digits),NormalizeDouble(bid-dist*InpRR,_Digits),"RB S");
   if(ok && trade.ResultRetcode()==TRADE_RETCODE_DONE){
      // re-anchor SL/TP to the actual fill price
      double fill=trade.ResultPrice();
      if(fill>0 && PositionSelect(_Symbol)){
         double sl= L? fill-dist : fill+dist, tp= L? fill+dist*InpRR : fill-dist*InpRR;
         if(MathAbs(fill-(L?ask:bid))>_Point/2) trade.PositionModify(_Symbol,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits));
      }
      lastRisk=lots*lossPerLot; entryTime=bt; dayCount++;
   }
}

double OnTester(){
   double wr= nT>0? 100.0*nW/nT:0, ex= nT>0? sumR/nT:0;
   double aw= nW>0? sumWR/nW:0, al= (nT-nW)>0? sumLR/(nT-nW):0;
   double pf= sumLR!=0? sumWR/MathAbs(sumLR):0;
   PrintFormat("RBSTAT trades=%d win=%.1f%% expR=%.3f avgW=%.2f avgL=%.2f pfR=%.2f maxLossStreak=%d long=%d short=%d totR=%.1f",
               nT,wr,ex,aw,al,pf,maxStreak,nL,nS,sumR);
   for(int y=0;y<100;y++) if(yN[y]>0){
      string s=""; for(int m=0;m<12;m++) s+=StringFormat("%.1f ",mR[y][m]);
      PrintFormat("RBYEAR %d n=%d R=%.1f | %s",2000+y,yN[y],yR[y],s);
   }
   return sumR;
}
