//+------------------------------------------------------------------+
//| ORB_NY_Final_EA.mq5 — AI Trading Room — FINAL DEFAULTS (weak-month risk + BB range) |
//| ORB trend breakout on US500+NAS100 (stop 0.2xOR, RR, OR filter).  |
//| v4 adds (all optional):                                           |
//|  - InpOpen: session open (server HHMM) -> test other times of day |
//|  - InpRev: after a STOP-LOSS, open the reverse trade (stop at the |
//|    original entry, target InpRevRR x risk)                        |
//|  - InpMonthStop: stop trading for the month after -X% in month    |
//|  - InpStreak/InpCool: after N losses in a row pause K days        |
//|  - Journal: one line per month (return, trades, wins, TP hits)    |
//+------------------------------------------------------------------+
#property copyright "AI Trading Room"
#property version   "4.00"
#include <Trade/Trade.mqh>
CTrade trade;

input string InpSyms     = "US500,NAS100";
input double InpRisk     = 0.5;    // Risk % per trade (each symbol)
input int    InpOpen     = 1630;   // Session open (server). NY=1630, London=1000
input int    InpWinMin   = 90;     // Entry window after OR end (minutes)
input int    InpExit     = 2255;   // Time exit (server)
input double InpRR       = 6.0;
input double InpStopFrac = 0.2;
input double InpORminATR = 0.1;
input int    InpEMA      = 50;
input int    InpRev      = 0;      // 1 = reverse after stop-loss
input double InpRevRR    = 2.0;    // Reverse target in R
input double InpMonthStop= 0;      // Halt month after -X% (0=off)
input int    InpStreak   = 0;      // Pause after N losses in a row (0=off)
input int    InpCool     = 5;      // Pause length (trading days)
input bool   InpMonthLog = true;
input string InpSummer   = "5,6,7,8"; // months treated as "summer"
input int    InpSumMode  = 0;      // summer: 0=normal ORB, 1=no trading, 2=range fade, 3=ORB+fade
input int    InpFadeAll  = 0;      // 1 = run the fade strategy all year (research)
input double InpFadeTP   = 1.0;    // fade target: 1=opposite OR edge, 0.5=OR middle
input double InpFadeBuf  = 0.1;    // fade stop beyond breakout extreme (x OR)
input string InpWeak     = "6,7";  // weak months (risk multiplier applies)
input double InpWeakMult = 0.5;    // ORB risk x this in weak months (1=same, 0.5=half, 0=off)
input int    InpBB       = 0;      // Bollinger range strategy: 0=off, 1=weak months only, 2=all year
input int    InpBBStart  = 1730;   // BB trading window start (server)
input int    InpBBEnd    = 2230;   // BB window end (server)
input double InpBBDev    = 2.0;
input double InpMgMult   = 1.0;    // Martingale: risk x this after each loss (1=off)
input int    InpMgCap    = 6;      // Max martingale steps (then stays at cap)
input long   InpMagic    = 26111920;

#define MAXS 6
string S[MAXS]; int n=0; int hE[MAXS], hA[MAXS]; datetime lb[MAXS]; int dk[MAXS];
double oh[MAXS], ol[MAXS]; bool od[MAXS], tr[MAXS], revd[MAXS]; int pdir[MAXS]; double pent[MAXS], prd[MAXS], plots[MAXS]; bool isRev[MAXS];
int monKey=-1; double monStart=0; int monUp=0, monAll=0; double worstMon=0; int mTr=0,mW=0,mTP=0;
string mlog[]; int nml=0;
double moySum[13]; int moyPos[13], moyCnt[13]; double sumYr[2100]; bool smon[13];
int yKey=-1; double yStart=0; string ylog[]; int nyl=0;
bool wmon[13]; double gMult=1.0; int hBB[MAXS], hA15[MAXS]; datetime lb15[MAXS]; bool bbd[MAXS];
bool bUp[MAXS], bDn[MAXS]; double xHi[MAXS], xLo[MAXS]; bool fd[MAXS];
int mgStep=0;
int streak=0, coolLeft=0, lastDayKey=-1; bool monthHalt=false;

int HM(datetime t){ MqlDateTime d; TimeToStruct(t,d); return d.hour*100+d.min; }
int AddMin(int hhmm,int m){ int t=(hhmm/100)*60+hhmm%100+m; return (t/60)*100+t%60; }
bool HasPos(string s){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==s&&PositionGetInteger(POSITION_MAGIC)==InpMagic) return true; } return false; }
void ClosePos(string s){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==s&&PositionGetInteger(POSITION_MAGIC)==InpMagic) trade.PositionClose(t); } }
double Lots(string s,double d){ double tv=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_VALUE_LOSS), ts=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_SIZE); if(tv<=0||ts<=0||d<=0) return 0; double l=AccountInfoDouble(ACCOUNT_BALANCE)*InpRisk*gMult*MathPow(InpMgMult,mgStep)/100.0/(d/ts*tv); double st=SymbolInfoDouble(s,SYMBOL_VOLUME_STEP), mn=SymbolInfoDouble(s,SYMBOL_VOLUME_MIN), mx=SymbolInfoDouble(s,SYMBOL_VOLUME_MAX); l=MathFloor(l/st)*st; if(l<mn) return 0; return MathMin(mx,l); }

void MonthTick(datetime t){ MqlDateTime d; TimeToStruct(t,d); int k=d.year*100+d.mon; double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(d.year!=yKey){ if(yKey>0 && yStart>0){ ArrayResize(ylog,nyl+1); ylog[nyl++]=StringFormat("YEAR %d ret=%.2f%% end=%.0f", yKey, (eq-yStart)/yStart*100, eq); } yKey=d.year; yStart=eq; }
   if(k!=monKey){ if(monKey>0 && monStart>0){ double r=(eq-monStart)/monStart*100; monAll++; if(r>0) monUp++; if(r<worstMon) worstMon=r;
         { int mo=monKey%100, yr=monKey/100; moySum[mo]+=r; moyCnt[mo]++; if(r>0) moyPos[mo]++; if(smon[mo]) sumYr[yr]=(sumYr[yr]==0?1.0:sumYr[yr])*(1+r/100.0); }
         if(InpMonthLog && monKey>=202501){ ArrayResize(mlog,nml+1); mlog[nml++]=StringFormat("MON %d ret=%.2f%% trades=%d wins=%d tp=%d", monKey, r, mTr, mW, mTP); } }
      monKey=k; monStart=eq; mTr=0; mW=0; mTP=0; monthHalt=false; }
   if(InpMonthStop>0 && monStart>0 && (eq-monStart)/monStart*100 <= -InpMonthStop) monthHalt=true; }

int OnInit(){ trade.SetExpertMagicNumber(InpMagic);
   string sm[]; int q=StringSplit(InpSummer,',',sm); for(int j=0;j<q;j++){ int m=(int)StringToInteger(sm[j]); if(m>=1&&m<=12) smon[m]=true; }
   string wm[]; int qq=StringSplit(InpWeak,',',wm); for(int j=0;j<qq;j++){ int m=(int)StringToInteger(wm[j]); if(m>=1&&m<=12) wmon[m]=true; }
   string a[]; int k=StringSplit(InpSyms,',',a);
   for(int i=0;i<k && n<MAXS;i++){ if(!SymbolSelect(a[i],true)) continue; S[n]=a[i]; hE[n]=iMA(a[i],PERIOD_M15,InpEMA,0,MODE_EMA,PRICE_CLOSE); hA[n]=iATR(a[i],PERIOD_D1,14); hBB[n]=iBands(a[i],PERIOD_M15,20,0,InpBBDev,PRICE_CLOSE); hA15[n]=iATR(a[i],PERIOD_M15,14); lb15[n]=0; lb[n]=0; dk[n]=-1; pdir[n]=0; n++; }
   return n>0?INIT_SUCCEEDED:INIT_FAILED; }

// called when a symbol's position disappears: evaluate the last closing deal
void OnClosed(int i){
   if(!HistorySelect(TimeCurrent()-86400*3,TimeCurrent())) return;
   for(int k=HistoryDealsTotal()-1;k>=0;k--){ ulong dl=HistoryDealGetTicket(k);
      if(HistoryDealGetInteger(dl,DEAL_MAGIC)!=InpMagic || HistoryDealGetString(dl,DEAL_SYMBOL)!=S[i] || HistoryDealGetInteger(dl,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double p=HistoryDealGetDouble(dl,DEAL_PROFIT)+HistoryDealGetDouble(dl,DEAL_SWAP)+HistoryDealGetDouble(dl,DEAL_COMMISSION);
      long reason=HistoryDealGetInteger(dl,DEAL_REASON);
      mTr++; if(p>0){ mW++; streak=0; mgStep=0; } else { mgStep=MathMin(mgStep+1,InpMgCap); streak++; if(InpStreak>0 && streak>=InpStreak){ coolLeft=InpCool; streak=0; } }
      if(reason==DEAL_REASON_TP) mTP++;
      // reverse after stop-loss (only for an original trade, once per day)
      if(InpRev==1 && reason==DEAL_REASON_SL && !isRev[i] && !revd[i] && HM(TimeCurrent())<InpExit){
         int d=-pdir[i]; double sd=prd[i]; int dg=(int)SymbolInfoInteger(S[i],SYMBOL_DIGITS); double l=Lots(S[i],sd);
         if(l>0){ if(d>0){ double ask=SymbolInfoDouble(S[i],SYMBOL_ASK); if(trade.Buy(l,S[i],ask,NormalizeDouble(ask-sd,dg),NormalizeDouble(ask+InpRevRR*sd,dg),"REV L")){ pdir[i]=1; isRev[i]=true; revd[i]=true; return; } }
                  else    { double bid=SymbolInfoDouble(S[i],SYMBOL_BID); if(trade.Sell(l,S[i],bid,NormalizeDouble(bid+sd,dg),NormalizeDouble(bid-InpRevRR*sd,dg),"REV S")){ pdir[i]=-1; isRev[i]=true; revd[i]=true; return; } } }
      }
      break;
   }
   pdir[i]=0;
}

void Fade(int i, MqlRates &bar){
   gMult=1.0; string s=S[i]; double R=oh[i]-ol[i]; if(R<=0) return;
   if(bar.close>oh[i]){ bUp[i]=true; xHi[i]=MathMax(xHi[i],bar.high); }
   if(bar.close<ol[i]){ bDn[i]=true; xLo[i]=(xLo[i]==0?bar.low:MathMin(xLo[i],bar.low)); }
   if(bUp[i]) xHi[i]=MathMax(xHi[i],bar.high);
   if(bDn[i]) xLo[i]=(xLo[i]==0?bar.low:MathMin(xLo[i],bar.low));
   int dg=(int)SymbolInfoInteger(s,SYMBOL_DIGITS);
   if(bUp[i] && bar.close<oh[i] && bar.close>ol[i]){ // failed upside breakout -> SELL
      double bid=SymbolInfoDouble(s,SYMBOL_BID), sl=xHi[i]+InpFadeBuf*R, tp=oh[i]-InpFadeTP*R, sd=sl-bid; if(sd<=0||tp>=bid) return;
      double l=Lots(s,sd); if(l>0 && trade.Sell(l,s,bid,NormalizeDouble(sl,dg),NormalizeDouble(tp,dg),"FADE S")){ fd[i]=true; tr[i]=true; pdir[i]=-1; prd[i]=sd; isRev[i]=true; } }
   else if(bDn[i] && bar.close>ol[i] && bar.close<oh[i]){ // failed downside breakout -> BUY
      double ask=SymbolInfoDouble(s,SYMBOL_ASK), sl=xLo[i]-InpFadeBuf*R, tp=ol[i]+InpFadeTP*R, sd=ask-sl; if(sd<=0||tp<=ask) return;
      double l=Lots(s,sd); if(l>0 && trade.Buy(l,s,ask,NormalizeDouble(sl,dg),NormalizeDouble(tp,dg),"FADE L")){ fd[i]=true; tr[i]=true; pdir[i]=1; prd[i]=sd; isRev[i]=true; } }
}
void BBRun(int i){
   string s=S[i]; datetime t=iTime(s,PERIOD_M15,0); if(t==0||t==lb15[i]) return; lb15[i]=t;
   int now=HM(t); if(now<InpBBStart || now>InpBBEnd || bbd[i] || HasPos(s)) return;
   MqlDateTime d; TimeToStruct(t,d); if(d.day_of_week==0||d.day_of_week==6) return;
   if(InpBB==1 && !wmon[d.mon]) return;
   double up[2], mid[2], lo[2], a[1];
   if(CopyBuffer(hBB[i],1,1,2,up)!=2||CopyBuffer(hBB[i],0,1,2,mid)!=2||CopyBuffer(hBB[i],2,1,2,lo)!=2||CopyBuffer(hA15[i],0,1,1,a)!=1) return;
   double c1=iClose(s,PERIOD_M15,1), c2=iClose(s,PERIOD_M15,2); // up[0]=bar2, up[1]=bar1
   int dg=(int)SymbolInfoInteger(s,SYMBOL_DIGITS); gMult=1.0;
   if(c2>up[0] && c1<up[1]){ double bid=SymbolInfoDouble(s,SYMBOL_BID), sl=bid+a[0], tp=mid[1]; if(tp>=bid) return; double l=Lots(s,sl-bid);
      if(l>0 && trade.Sell(l,s,bid,NormalizeDouble(sl,dg),NormalizeDouble(tp,dg),"BB S")){ bbd[i]=true; pdir[i]=-1; prd[i]=sl-bid; isRev[i]=true; } }
   else if(c2<lo[0] && c1>lo[1]){ double ask=SymbolInfoDouble(s,SYMBOL_ASK), sl=ask-a[0], tp=mid[1]; if(tp<=ask) return; double l=Lots(s,ask-sl);
      if(l>0 && trade.Buy(l,s,ask,NormalizeDouble(sl,dg),NormalizeDouble(tp,dg),"BB L")){ bbd[i]=true; pdir[i]=1; prd[i]=ask-sl; isRev[i]=true; } }
}
void Run(int i){
   string s=S[i];
   if(pdir[i]!=0 && !HasPos(s)) OnClosed(i);
   datetime t0=iTime(s,PERIOD_M5,0); if(t0==0||t0==lb[i]) return; lb[i]=t0;
   MqlRates b[1]; if(CopyRates(s,PERIOD_M5,1,1,b)!=1) return;
   MqlDateTime d; TimeToStruct(b[0].time,d); if(d.day_of_week==0||d.day_of_week==6) return;
   int key=d.year*1000+d.day_of_year, hm=d.hour*100+d.min, now=HM(t0);
   if(key!=dk[i]){ dk[i]=key; oh[i]=0; ol[i]=0; od[i]=false; tr[i]=false; revd[i]=false; bUp[i]=false; bDn[i]=false; xHi[i]=0; xLo[i]=0; fd[i]=false; bbd[i]=false; }
   if(i==0 && key!=lastDayKey){ lastDayKey=key; if(coolLeft>0) coolLeft--; }
   bool has=HasPos(s);
   if(has && now>=InpExit){ ClosePos(s); pdir[i]=0; return; }
   int orEnd=AddMin(InpOpen,15), lastE=AddMin(orEnd,InpWinMin);
   if(hm>=InpOpen && hm<orEnd){ if(oh[i]==0){ oh[i]=b[0].high; ol[i]=b[0].low; } else { oh[i]=MathMax(oh[i],b[0].high); ol[i]=MathMin(ol[i],b[0].low); } }
   if(!od[i] && oh[i]>0 && now>=orEnd) od[i]=true;
   bool summer=smon[d.mon];
   bool doORB = !(summer && (InpSumMode==1 || InpSumMode==2));
   bool doFade = InpFadeAll==1 || (summer && (InpSumMode==2 || InpSumMode==3));
   if(od[i] && now>=orEnd && now<=lastE && !has && doFade && !fd[i]) Fade(i,b[0]);
   if(!doORB) return;
   if(!od[i] || tr[i] || has || now>lastE || now<orEnd) return;
   if(monthHalt || coolLeft>0) return;
   double R=oh[i]-ol[i]; if(R<=0) return;
   if(InpORminATR>0){ double a[1]; if(CopyBuffer(hA[i],0,1,1,a)!=1) return; if(R<InpORminATR*a[0]){ tr[i]=true; return; } }
   double e[1]; if(CopyBuffer(hE[i],0,1,1,e)!=1) return;
   int dir=0; if(b[0].close>oh[i] && b[0].close>e[0]) dir=1; else if(b[0].close<ol[i] && b[0].close<e[0]) dir=-1;
   if(dir==0) return;
   gMult = wmon[d.mon]? InpWeakMult : 1.0; if(gMult<=0){ tr[i]=true; return; }
   int dg=(int)SymbolInfoInteger(s,SYMBOL_DIGITS);
   if(dir>0){ double ask=SymbolInfoDouble(s,SYMBOL_ASK), sl=oh[i]-InpStopFrac*R, sd=ask-sl; if(sd<=0) return; double l=Lots(s,sd);
      if(l>0 && trade.Buy(l,s,ask,NormalizeDouble(sl,dg),NormalizeDouble(ask+InpRR*sd,dg),"PF L")){ tr[i]=true; pdir[i]=1; pent[i]=ask; prd[i]=sd; plots[i]=l; isRev[i]=false; } }
   else { double bid=SymbolInfoDouble(s,SYMBOL_BID), sl=ol[i]+InpStopFrac*R, sd=sl-bid; if(sd<=0) return; double l=Lots(s,sd);
      if(l>0 && trade.Sell(l,s,bid,NormalizeDouble(sl,dg),NormalizeDouble(bid-InpRR*sd,dg),"PF S")){ tr[i]=true; pdir[i]=-1; pent[i]=bid; prd[i]=sd; plots[i]=l; isRev[i]=false; } }
}
void OnTick(){ MonthTick(TimeCurrent()); for(int i=0;i<n;i++){ Run(i); if(InpBB>0) BBRun(i); } }
double OnTester(){
   MonthTick(TimeCurrent()+40*86400);
   double pct = monAll>0? 100.0*monUp/monAll : 0;
   for(int j=0;j<nml;j++) Print(mlog[j]);
   for(int m=1;m<=12;m++) if(moyCnt[m]>0) PrintFormat("MOY %02d avg=%.2f%% pos=%d/%d", m, moySum[m]/moyCnt[m], moyPos[m], moyCnt[m]);
   for(int y=2021;y<=2026;y++) if(sumYr[y]>0) PrintFormat("SUMMER %d ret=%.2f%%", y, (sumYr[y]-1)*100);
   for(int j=0;j<nyl;j++) Print(ylog[j]);
   if(yStart>0) PrintFormat("YEAR %d (to date) ret=%.2f%% end=%.0f", yKey, (AccountInfoDouble(ACCOUNT_EQUITY)-yStart)/yStart*100, AccountInfoDouble(ACCOUNT_EQUITY));
   PrintFormat("V7 months=%d up=%d (%.1f%%) worstMonth=%.2f%% PF=%.2f net=%.2f DD%%=%.2f trades=%.0f", monAll, monUp, pct, worstMon, TesterStatistics(STAT_PROFIT_FACTOR), TesterStatistics(STAT_PROFIT), TesterStatistics(STAT_EQUITYDD_PERCENT), TesterStatistics(STAT_TRADES));
   return MathRound(pct)*100.0 + MathAbs(worstMon);
}
