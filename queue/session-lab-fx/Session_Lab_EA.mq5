//+------------------------------------------------------------------+
//| Session_Lab_EA.mq5 — AITR session strategy lab (research only)    |
//| Run on M5. Server time assumed GMT+2/+3 (tracks NY DST).          |
//| InpSess: 1 London 10:00-18:00 | 2 NY 15:00-23:00 | 3 NY cash      |
//|          16:30-22:55 | 4 Overlap 15:00-19:00 | 5 London AM 10-15   |
//| InpMode: 1 ORB breakout  2 ORB fade  3 pre-session range breakout |
//|          4 pre-session range fade  5 first-period momentum        |
//| One trade per day, flat at session end. Stats in R (OnTester).    |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input int    InpMode   = 1;     // Strategy mode 1..5
input int    InpSess   = 1;     // Session 1..5
input int    InpORMin  = 30;    // Opening period (minutes)
input int    InpPreH   = 6;     // Pre-session range hours (modes 3,4)
input int    InpWinMin = 120;   // Entry window after range end (minutes)
input double InpRR     = 2.0;   // Target = x risk
input double InpSF     = 0.2;   // Breakout stop: edge -/+ SF x range
input int    InpEMA    = 50;    // M15 EMA trend filter for breakouts (0=off)
input double InpMinAtr = 0.1;   // Min range = x daily ATR14
input double InpRisk   = 0.5;   // Risk % equity
input long   InpMagic  = 77001;

int hEMA, hATRd;
datetime lastBar=0; int dayKey=-1;
double rH, rL, sOpen, extH, extL; bool rangeSet, traded, brokeUp, brokeDn;
double lastRisk=0; int nT=0,nW=0,streak=0,maxStreak=0; double sumR=0;

void SessTimes(int &op,int &en){
   switch(InpSess){
      case 1: op=600; en=1080; break;
      case 2: op=900; en=1380; break;
      case 3: op=990; en=1375; break;
      case 4: op=900; en=1140; break;
      default: op=600; en=900;
   }
}
int OnInit(){
   hEMA = InpEMA>0? iMA(_Symbol,PERIOD_M15,InpEMA,0,MODE_EMA,PRICE_CLOSE) : INVALID_HANDLE;
   hATRd= iATR(_Symbol,PERIOD_D1,14);
   trade.SetExpertMagicNumber(InpMagic);
   return INIT_SUCCEEDED;
}
double Buf(int h,int shift){ double v[1]; if(h==INVALID_HANDLE||CopyBuffer(h,0,shift,1,v)!=1) return EMPTY_VALUE; return v[0]; }
bool HasPos(){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)==InpMagic) return true; } return false; }
void CloseAll(){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(PositionGetString(POSITION_SYMBOL)==_Symbol&&PositionGetInteger(POSITION_MAGIC)==InpMagic) trade.PositionClose(t); } }

void OnTradeTransaction(const MqlTradeTransaction &tr,const MqlTradeRequest &rq,const MqlTradeResult &rs){
   if(tr.type!=TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(tr.deal)) return;
   if(HistoryDealGetInteger(tr.deal,DEAL_MAGIC)!=InpMagic || HistoryDealGetInteger(tr.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   double p=HistoryDealGetDouble(tr.deal,DEAL_PROFIT)+HistoryDealGetDouble(tr.deal,DEAL_COMMISSION)+HistoryDealGetDouble(tr.deal,DEAL_SWAP);
   double r= lastRisk>0? p/lastRisk:0; nT++; sumR+=r;
   if(p>0){ nW++; streak=0; } else { streak++; if(streak>maxStreak) maxStreak=streak; }
}

bool Open(bool longSide,double sl){
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double px= longSide? ask:bid, dist= longSide? px-sl : sl-px;
   double spread=ask-bid;
   if(dist<=spread*2) return false;               // stop too tight vs spread
   double tp= longSide? px+dist*InpRR : px-dist*InpRR;
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE), ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double lossPerLot=dist/ts*tv; if(lossPerLot<=0) return false;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP), vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), vmax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double lots=MathFloor(AccountInfoDouble(ACCOUNT_EQUITY)*InpRisk/100.0/lossPerLot/step)*step;
   if(lots<vmin) return false; lots=MathMin(lots,vmax);
   bool ok= longSide? trade.Buy(lots,_Symbol,px,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),"SL")
                    : trade.Sell(lots,_Symbol,px,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),"SL");
   if(ok && trade.ResultRetcode()==TRADE_RETCODE_DONE){ lastRisk=lots*lossPerLot; return true; }
   return false;
}

void OnTick(){
   datetime t0=iTime(_Symbol,_Period,0); if(t0==lastBar) return; lastBar=t0;
   MqlDateTime d; TimeToStruct(t0,d);
   if(d.day_of_week==0||d.day_of_week==6) return;
   int key=d.year*1000+d.day_of_year, now=d.hour*60+d.min;   // now = close time of bar 1
   if(key!=dayKey){ dayKey=key; rangeSet=false; traded=false; brokeUp=false; brokeDn=false; rH=0; rL=0; }
   int op,en; SessTimes(op,en);
   if(HasPos() && now>=en){ CloseAll(); return; }
   if(now<op || now>=en) return;

   bool pre = (InpMode==3||InpMode==4);
   int rEnd = pre? op : op+InpORMin;
   if(!rangeSet){
      if(now<rEnd) return;
      // build range from M5 bars [rStart, rEnd)
      int rStart = pre? op-InpPreH*60 : op;
      datetime dayStart=t0-now*60;
      datetime ts=dayStart+rStart*60, te=dayStart+rEnd*60-1;
      MqlRates r[]; int n=CopyRates(_Symbol,PERIOD_M5,ts,te,r);
      if(n<3){ rangeSet=true; traded=true; return; }
      rH=r[0].high; rL=r[0].low; sOpen=r[0].open;
      for(int i=1;i<n;i++){ rH=MathMax(rH,r[i].high); rL=MathMin(rL,r[i].low); }
      rangeSet=true; extH=rH; extL=rL;
      double atrD=Buf(hATRd,1);
      if(atrD==EMPTY_VALUE || rH-rL < InpMinAtr*atrD) traded=true;   // range too small -> skip day
      if(InpMode==5 && !traded){
         double c=r[n-1].close, mv=c-sOpen;
         if(MathAbs(mv) < 0.1*atrD){ traded=true; return; }
         if(Open(mv>0, mv>0? rL : rH)) {}
         traded=true;
      }
      return;
   }
   if(traded || HasPos()) return;
   if(now > rEnd+InpWinMin) return;

   double c=iClose(_Symbol,_Period,1), h=iHigh(_Symbol,_Period,1), l=iLow(_Symbol,_Period,1);
   double rng=rH-rL;
   double ema=Buf(hEMA,1);
   if(InpMode==1 || InpMode==3){
      bool up=c>rH, dn=c<rL;
      if(InpEMA>0 && ema!=EMPTY_VALUE){ if(up && c<=ema) up=false; if(dn && c>=ema) dn=false; }
      if(up){ if(Open(true , rH-InpSF*rng)) traded=true; }
      else if(dn){ if(Open(false, rL+InpSF*rng)) traded=true; }
   } else if(InpMode==2 || InpMode==4){
      extH=MathMax(extH,h); extL=MathMin(extL,l);
      if(c>rH) brokeUp=true; if(c<rL) brokeDn=true;
      if(brokeUp && c<rH && c>rL){ if(Open(false, extH+0.1*rng)) traded=true; }
      else if(brokeDn && c>rL && c<rH){ if(Open(true, extL-0.1*rng)) traded=true; }
   }
}

double OnTester(){
   PrintFormat("SLAB mode=%d sess=%d trades=%d win=%.1f%% expR=%.3f totR=%.1f maxLS=%d",InpMode,InpSess,nT,nT>0?100.0*nW/nT:0,nT>0?sumR/nT:0,sumR,maxStreak);
   return sumR;
}
