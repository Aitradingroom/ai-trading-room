//+------------------------------------------------------------------+
//| ORB_NY_Prop_EA.mq5 — AI Trading Room — PROP FIRM version          |
//| Same NY-open ORB as ORB_NY_Final_EA (US500 + NAS100), tiny risk.  |
//| Safety locks:                                                     |
//|  - Max loss lock: equity <= start balance x (1 - InpMaxLoss%)     |
//|    -> close everything and stop trading for good.                 |
//|  - Daily lock: equity <= day-start equity x (1 - InpDayLoss%)     |
//|    -> close everything, no new trades until next day.             |
//| Optional monthly withdrawal simulation (tester only).             |
//| Journal: worst daily loss, lock triggers, yearly & withdrawals.   |
//+------------------------------------------------------------------+
#property copyright "AI Trading Room"
#property version   "1.00"
#include <Trade/Trade.mqh>
CTrade trade;

input string InpSyms     = "US500,NAS100";
input double InpRisk     = 0.075;  // Risk % per trade (each symbol)
input double InpMaxLoss  = 5.0;    // Hard stop: max loss % from START balance
input double InpDayLoss  = 2.0;    // Daily stop: max loss % from day-start equity
input int    InpOpen     = 1630;   // Session open (server). NY=1630
input int    InpWinMin   = 90;     // Entry window after OR end (minutes)
input int    InpExit     = 2255;   // Time exit (server)
input double InpRR       = 6.0;
input double InpStopFrac = 0.2;
input double InpORminATR = 0.1;
input int    InpEMA      = 50;
input string InpWeak     = "6,7";  // weak months
input double InpWeakMult = 0.5;    // risk x this in weak months
input double InpWdPct    = 0;      // tester: withdraw % of monthly profit (0=off)
input double InpWdMin    = 0;      // tester: only if month return >= this %
input long   InpMagic    = 26111922;

#define MAXS 6
string S[MAXS]; int n=0; int hE[MAXS], hA[MAXS]; datetime lb[MAXS]; int dk[MAXS];
double oh[MAXS], ol[MAXS]; bool od[MAXS], tr[MAXS];
bool wmon[13]; double gMult=1.0;
double startBal=0; bool dead=false; int dayK=-1; double dayEq=0, dayMin=0, worstDay=0; bool dayHalt=false; int dayLocks=0;
int monKey=-1; double monStart=0; int monUp=0, monAll=0; double worstMon=0; double totWd=0; double yWd[2100];
int yKey=-1; double yStart=0; string ylog[]; int nyl=0;

int HM(datetime t){ MqlDateTime d; TimeToStruct(t,d); return d.hour*100+d.min; }
int AddMin(int hhmm,int m){ int t=(hhmm/100)*60+hhmm%100+m; return (t/60)*100+t%60; }
bool HasPos(string s){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==s&&PositionGetInteger(POSITION_MAGIC)==InpMagic) return true; } return false; }
void CloseSym(string s){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==s&&PositionGetInteger(POSITION_MAGIC)==InpMagic) trade.PositionClose(t); } }
void CloseAll(){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(PositionSelectByTicket(t)&&PositionGetInteger(POSITION_MAGIC)==InpMagic) trade.PositionClose(t); } }
double Lots(string s,double d){ double tv=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_VALUE_LOSS), ts=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_SIZE); if(tv<=0||ts<=0||d<=0) return 0; double l=AccountInfoDouble(ACCOUNT_BALANCE)*InpRisk*gMult/100.0/(d/ts*tv); double st=SymbolInfoDouble(s,SYMBOL_VOLUME_STEP), mn=SymbolInfoDouble(s,SYMBOL_VOLUME_MIN), mx=SymbolInfoDouble(s,SYMBOL_VOLUME_MAX); l=MathFloor(l/st)*st; if(l<mn) return 0; return MathMin(mx,l); }

void Guards(){
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime d; TimeToStruct(TimeCurrent(),d); int k=d.year*1000+d.day_of_year;
   if(k!=dayK){ if(dayEq>0){ double dl=(dayMin-dayEq)/dayEq*100; if(dl<worstDay) worstDay=dl; } dayK=k; dayEq=eq; dayMin=eq; dayHalt=false; }
   if(eq<dayMin) dayMin=eq;
   if(!dead && eq<=startBal*(1-InpMaxLoss/100.0)){ CloseAll(); dead=true; Print("MAX-LOSS LOCK triggered, trading stopped. Equity=",eq); }
   if(!dayHalt && eq<=dayEq*(1-InpDayLoss/100.0)){ CloseAll(); dayHalt=true; dayLocks++; Print("DAILY LOCK triggered. Equity=",eq); }
}
void MonthTick(){ MqlDateTime d; TimeToStruct(TimeCurrent(),d); int k=d.year*100+d.mon; double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(k!=monKey){
      if(monKey>0 && monStart>0){ double r=(eq-monStart)/monStart*100; monAll++; if(r>0) monUp++; if(r<worstMon) worstMon=r;
         if(InpWdPct>0 && r>=InpWdMin && eq>monStart && PositionsTotal()==0){ double wd=MathFloor((eq-monStart)*InpWdPct)/100.0; if(wd>0 && TesterWithdrawal(wd)){ totWd+=wd; yWd[monKey/100]+=wd; eq-=wd; } } }
      if(d.year!=yKey){ if(yKey>0 && yStart>0){ ArrayResize(ylog,nyl+1); ylog[nyl++]=StringFormat("YEAR %d ret=%.2f%% withdrawn=%.0f end balance=%.0f", yKey, (eq+yWd[yKey]-yStart)/yStart*100, yWd[yKey], eq); } yKey=d.year; yStart=eq; }
      monKey=k; monStart=eq; }
}

int OnInit(){ trade.SetExpertMagicNumber(InpMagic); startBal=AccountInfoDouble(ACCOUNT_BALANCE);
   string wm[]; int qq=StringSplit(InpWeak,',',wm); for(int j=0;j<qq;j++){ int m=(int)StringToInteger(wm[j]); if(m>=1&&m<=12) wmon[m]=true; }
   string a[]; int k=StringSplit(InpSyms,',',a);
   for(int i=0;i<k && n<MAXS;i++){ if(!SymbolSelect(a[i],true)) continue; S[n]=a[i]; hE[n]=iMA(a[i],PERIOD_M15,InpEMA,0,MODE_EMA,PRICE_CLOSE); hA[n]=iATR(a[i],PERIOD_D1,14); lb[n]=0; dk[n]=-1; n++; }
   return n>0?INIT_SUCCEEDED:INIT_FAILED; }

void Run(int i){
   string s=S[i];
   datetime t0=iTime(s,PERIOD_M5,0); if(t0==0||t0==lb[i]) return; lb[i]=t0;
   MqlRates b[1]; if(CopyRates(s,PERIOD_M5,1,1,b)!=1) return;
   MqlDateTime d; TimeToStruct(b[0].time,d); if(d.day_of_week==0||d.day_of_week==6) return;
   int key=d.year*1000+d.day_of_year, hm=d.hour*100+d.min, now=HM(t0);
   if(key!=dk[i]){ dk[i]=key; oh[i]=0; ol[i]=0; od[i]=false; tr[i]=false; }
   bool has=HasPos(s);
   if(has && now>=InpExit){ CloseSym(s); return; }
   int orEnd=AddMin(InpOpen,15), lastE=AddMin(orEnd,InpWinMin);
   if(hm>=InpOpen && hm<orEnd){ if(oh[i]==0){ oh[i]=b[0].high; ol[i]=b[0].low; } else { oh[i]=MathMax(oh[i],b[0].high); ol[i]=MathMin(ol[i],b[0].low); } }
   if(!od[i] && oh[i]>0 && now>=orEnd) od[i]=true;
   if(dead || dayHalt) return;
   if(!od[i] || tr[i] || has || now>lastE || now<orEnd) return;
   double R=oh[i]-ol[i]; if(R<=0) return;
   if(InpORminATR>0){ double a[1]; if(CopyBuffer(hA[i],0,1,1,a)!=1) return; if(R<InpORminATR*a[0]){ tr[i]=true; return; } }
   double e[1]; if(CopyBuffer(hE[i],0,1,1,e)!=1) return;
   int dir=0; if(b[0].close>oh[i] && b[0].close>e[0]) dir=1; else if(b[0].close<ol[i] && b[0].close<e[0]) dir=-1;
   if(dir==0) return;
   gMult = wmon[d.mon]? InpWeakMult : 1.0;
   int dg=(int)SymbolInfoInteger(s,SYMBOL_DIGITS);
   if(dir>0){ double ask=SymbolInfoDouble(s,SYMBOL_ASK), sl=oh[i]-InpStopFrac*R, sd=ask-sl; if(sd<=0) return; double l=Lots(s,sd);
      if(l>0 && trade.Buy(l,s,ask,NormalizeDouble(sl,dg),NormalizeDouble(ask+InpRR*sd,dg),"PROP L")) tr[i]=true; }
   else { double bid=SymbolInfoDouble(s,SYMBOL_BID), sl=ol[i]+InpStopFrac*R, sd=sl-bid; if(sd<=0) return; double l=Lots(s,sd);
      if(l>0 && trade.Sell(l,s,bid,NormalizeDouble(sl,dg),NormalizeDouble(bid-InpRR*sd,dg),"PROP S")) tr[i]=true; }
}
void OnTick(){ Guards(); MonthTick(); for(int i=0;i<n;i++) Run(i); }
double OnTester(){
   for(int j=0;j<nyl;j++) Print(ylog[j]);
   PrintFormat("YEAR %d (to date) ret=%.2f%% withdrawn=%.0f", yKey, (AccountInfoDouble(ACCOUNT_EQUITY)+yWd[yKey]-yStart)/yStart*100, yWd[yKey]);
   double pct = monAll>0? 100.0*monUp/monAll : 0;
   PrintFormat("PROP worstDay=%.2f%% dailyLocks=%d maxLossLock=%s months=%d up=%.1f%% worstMonth=%.2f%% DD=%.2f%% PF=%.2f profit=%.0f withdrawn=%.0f",
      worstDay, dayLocks, dead?"YES":"no", monAll, pct, worstMon, TesterStatistics(STAT_EQUITYDD_PERCENT), TesterStatistics(STAT_PROFIT_FACTOR), TesterStatistics(STAT_PROFIT), totWd);
   return worstDay;
}
