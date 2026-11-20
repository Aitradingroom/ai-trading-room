//+------------------------------------------------------------------+
//| AITR_Portfolio_EA.mq5 — London ORB + NY ORB on one account        |
//| London (10:00 server): OR 45m, stop = opposite side, RR 6, exit 18:00 |
//| NY (16:30 server): OR 15m, stop 0.2 x OR beyond edge, RR 6, exit 22:55|
//| Both: M5 close beyond OR in M15 EMA50 direction, OR >= 0.1 x D-ATR14, |
//| one trade per symbol per day. Attach to any chart, M5. Research only. |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input double InpRisk     = 0.5;                   // Risk % of balance per trade
input string InpLonSyms  = "GER40,GBPJPY,EURJPY"; // London symbols ("" = off)
input string InpNYSyms   = "US500,NAS100";        // NY symbols ("" = off)
input double InpLonMult  = 1.0;                   // London risk multiplier
input double InpNYMult   = 1.0;                   // NY risk multiplier
input string InpWeak     = "6,7";                 // NY weak months
input double InpWeakMult = 0.5;                   // NY risk x this in weak months
input double InpMaxDD    = 0;                     // Stop trading if equity DD from peak > X% (0=off)
input long   InpMagic    = 26112001;

#define MAXS 10
string S[MAXS]; int typ[MAXS]; int n=0;               // typ 0=London 1=NY
int hE[MAXS], hA[MAXS]; datetime lb[MAXS]; int dk[MAXS];
double oh[MAXS], ol[MAXS]; bool od[MAXS], tr[MAXS];
bool wmon[13];
// stats
int monKey=-1; double monStart=0; int monUp=0, monAll=0; double worstMon=0;
int yKey=-1; double yStart=0; string ylog[]; int nyl=0;
double peak=0; bool halted=false;
int symTr[MAXS]; double symPL[MAXS];

int OpenMin(int i){ return typ[i]==0? 600 : 990; }
int ORMin(int i){ return typ[i]==0? 45 : 15; }
int WinMin(int i){ return typ[i]==0? 120 : 90; }
int ExitMin(int i){ return typ[i]==0? 1080 : 1375; }
double SF(int i){ return typ[i]==0? 1.0 : 0.2; }

void AddSyms(string list,int t){
   string a[]; int k=StringSplit(list,',',a);
   for(int j=0;j<k && n<MAXS;j++){ string s=a[j]; StringTrimLeft(s); StringTrimRight(s); if(s=="") continue;
      if(!SymbolSelect(s,true)){ Print("symbol not found: ",s); continue; }
      S[n]=s; typ[n]=t; hE[n]=iMA(s,PERIOD_M15,50,0,MODE_EMA,PRICE_CLOSE); hA[n]=iATR(s,PERIOD_D1,14);
      lb[n]=0; dk[n]=-1; symTr[n]=0; symPL[n]=0; n++; }
}
int OnInit(){
   AddSyms(InpLonSyms,0); AddSyms(InpNYSyms,1);
   ArrayInitialize(wmon,false);
   string w[]; int q=StringSplit(InpWeak,',',w); for(int j=0;j<q;j++){ int m=(int)StringToInteger(w[j]); if(m>=1&&m<=12) wmon[m]=true; }
   trade.SetExpertMagicNumber(InpMagic); trade.SetDeviationInPoints(50);
   return n>0? INIT_SUCCEEDED : INIT_FAILED;
}
bool HasPos(string s){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==s&&PositionGetInteger(POSITION_MAGIC)==InpMagic) return true; } return false; }
void ClosePos(string s){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==s&&PositionGetInteger(POSITION_MAGIC)==InpMagic) trade.PositionClose(t); } }
double Lots(string s,double d,double mult){
   double tv=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_VALUE_LOSS), ts=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0||ts<=0||d<=0) return 0;
   double l=AccountInfoDouble(ACCOUNT_BALANCE)*InpRisk*mult/100.0/(d/ts*tv);
   double st=SymbolInfoDouble(s,SYMBOL_VOLUME_STEP), mn=SymbolInfoDouble(s,SYMBOL_VOLUME_MIN), mx=SymbolInfoDouble(s,SYMBOL_VOLUME_MAX);
   l=MathFloor(l/st)*st; if(l<mn) return 0; return MathMin(mx,l);
}
void MonthTick(datetime t){
   MqlDateTime d; TimeToStruct(t,d); int mk=d.year*100+d.mon; double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(monKey<0){ monKey=mk; monStart=eq; yKey=d.year; yStart=eq; return; }
   if(mk!=monKey){ double r=(eq-monStart)/monStart*100; monAll++; if(r>0) monUp++; if(r<worstMon) worstMon=r; monKey=mk; monStart=eq; }
   if(d.year!=yKey){ ArrayResize(ylog,nyl+1); ylog[nyl++]=StringFormat("PYEAR %d ret=%.1f%% end=%.0f",yKey,(eq-yStart)/yStart*100,eq); yKey=d.year; yStart=eq; }
}
void OnTradeTransaction(const MqlTradeTransaction &t,const MqlTradeRequest &rq,const MqlTradeResult &rs){
   if(t.type!=TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(t.deal)) return;
   if(HistoryDealGetInteger(t.deal,DEAL_MAGIC)!=InpMagic || HistoryDealGetInteger(t.deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) return;
   string s=HistoryDealGetString(t.deal,DEAL_SYMBOL);
   double p=HistoryDealGetDouble(t.deal,DEAL_PROFIT)+HistoryDealGetDouble(t.deal,DEAL_COMMISSION)+HistoryDealGetDouble(t.deal,DEAL_SWAP);
   for(int i=0;i<n;i++) if(S[i]==s){ symTr[i]++; symPL[i]+=p; }
}
void Run(int i){
   string s=S[i];
   datetime t0=iTime(s,PERIOD_M5,0); if(t0==0||t0==lb[i]) return; lb[i]=t0;
   MqlRates b[1]; if(CopyRates(s,PERIOD_M5,1,1,b)!=1) return;
   MqlDateTime d; TimeToStruct(t0,d); if(d.day_of_week==0||d.day_of_week==6) return;
   int key=d.year*1000+d.day_of_year, now=d.hour*60+d.min;  // now = close time of bar 1
   MqlDateTime db; TimeToStruct(b[0].time,db); int bm=db.hour*60+db.min;
   if(key!=dk[i]){ dk[i]=key; oh[i]=0; ol[i]=0; od[i]=false; tr[i]=false; }
   bool has=HasPos(s);
   if(has && now>=ExitMin(i)){ ClosePos(s); return; }
   int op=OpenMin(i), orEnd=op+ORMin(i), lastE=orEnd+WinMin(i);
   if(bm>=op && bm<orEnd && db.day_of_year==d.day_of_year){ if(oh[i]==0){ oh[i]=b[0].high; ol[i]=b[0].low; } else { oh[i]=MathMax(oh[i],b[0].high); ol[i]=MathMin(ol[i],b[0].low); } }
   if(!od[i] && oh[i]>0 && now>=orEnd) od[i]=true;
   if(!od[i] || tr[i] || has || now>lastE || now<orEnd || halted) return;
   double R=oh[i]-ol[i]; if(R<=0) return;
   double a[1]; if(CopyBuffer(hA[i],0,1,1,a)!=1) return; if(R<0.1*a[0]){ tr[i]=true; return; }
   double e[1]; if(CopyBuffer(hE[i],0,1,1,e)!=1) return;
   int dir=0; if(b[0].close>oh[i] && b[0].close>e[0]) dir=1; else if(b[0].close<ol[i] && b[0].close<e[0]) dir=-1;
   if(dir==0) return;
   double mult = typ[i]==0? InpLonMult : InpNYMult*(wmon[d.mon]? InpWeakMult:1.0);
   if(mult<=0){ tr[i]=true; return; }
   int dg=(int)SymbolInfoInteger(s,SYMBOL_DIGITS); double sf=SF(i);
   if(dir>0){ double ask=SymbolInfoDouble(s,SYMBOL_ASK), sl=oh[i]-sf*R, sd=ask-sl; if(sd<=0) return; double l=Lots(s,sd,mult);
      if(l>0 && trade.Buy(l,s,ask,NormalizeDouble(sl,dg),NormalizeDouble(ask+6.0*sd,dg),"PF L")) tr[i]=true; }
   else { double bid=SymbolInfoDouble(s,SYMBOL_BID), sl=ol[i]+sf*R, sd=sl-bid; if(sd<=0) return; double l=Lots(s,sd,mult);
      if(l>0 && trade.Sell(l,s,bid,NormalizeDouble(sl,dg),NormalizeDouble(bid-6.0*sd,dg),"PF S")) tr[i]=true; }
}
void OnTick(){
   MonthTick(TimeCurrent());
   double eq=AccountInfoDouble(ACCOUNT_EQUITY); if(eq>peak) peak=eq;
   if(InpMaxDD>0 && !halted && peak>0 && (peak-eq)/peak*100>=InpMaxDD){ halted=true; for(int i=0;i<n;i++) ClosePos(S[i]); }
   for(int i=0;i<n;i++) Run(i);
}
double OnTester(){
   MonthTick(TimeCurrent()+40*86400);
   for(int j=0;j<nyl;j++) Print(ylog[j]);
   if(yStart>0) PrintFormat("PYEAR %d (to date) ret=%.1f%% end=%.0f",yKey,(AccountInfoDouble(ACCOUNT_EQUITY)-yStart)/yStart*100,AccountInfoDouble(ACCOUNT_EQUITY));
   for(int i=0;i<n;i++) PrintFormat("PSYM %s trades=%d PL=%.0f",S[i],symTr[i],symPL[i]);
   PrintFormat("PORT risk=%.2f months=%d up=%d (%.1f%%) worstMonth=%.2f%% PF=%.2f net=%.0f DD%%=%.2f trades=%.0f",InpRisk,monAll,monUp,monAll>0?100.0*monUp/monAll:0,worstMon,TesterStatistics(STAT_PROFIT_FACTOR),TesterStatistics(STAT_PROFIT),TesterStatistics(STAT_EQUITYDD_PERCENT),TesterStatistics(STAT_TRADES));
   return TesterStatistics(STAT_PROFIT);
}
