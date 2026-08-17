//+------------------------------------------------------------------+
//| T100_Trend_Rider_v5_70_Adaptive_PROFIT.mq4                              |
//| T100 Trend Rider - Version 5.70                                 |
//| v5.69 base + hierarchical trend protection + adaptive entry distance/risk.     |
//+------------------------------------------------------------------+
#property strict
#property version "5.70"
#property description "T100 Trend Rider v5.70 - v5.68 strategy + exact entry diagnostics"

// INPUTS
input int FastEMA=20;
input int SlowEMA=50;
input int RSIPeriod=14;
input double BullRSI=55.0;
input double BearRSI=45.0;
input int ATRPeriod=14;
input double MinATRPoints=0.0;
input int ADXPeriod=14;
input double MinADX=20.0;
input long MinVolume=100;
input int MaxSpread=50;
input bool UseTradingHours=true;
input int TradingStartHour=9;
input int TradingEndHour=18;
input int BrokerUTCOffsetHours=2;
input int SASTUTCOffsetHours=2;
input int MinimumTrendScore=35;
input int MinimumTriggerScore=55;
// v5.70 hierarchical trend: H4/H1 define the primary regime; M15/M5
// describe continuation or pullback and may not flip an aligned H4/H1 trend.
input int H4TrendWeight=40;
input int H1TrendWeight=30;
input int M15TrendWeight=15;
input int M5TrendWeight=10;
input int H4SlopeBonus=4;
input int H1SlopeBonus=3;
input int M15SlopeBonus=2;
input int M5SlopeBonus=1;
input int ADXTrendBonus=4;
input bool ProtectAlignedHTFTrend=true;
input double MinEMADistancePoints=2.0;
input double PullbackATRMax=1.50;
input int PullbackLookbackBars=4;
input int PullbackMaxBars=8;
input int ReEntryCooldownBars=12;
input int MaxConsecutiveLosses=2;
input bool UseMaxEntryDistance=true;
input double MaxEntryDistanceATR=1.75;
input double HardEntryDistanceATR=2.25;
input bool UseAdaptiveEntryDistance=true;
input double StrongTrendDistanceATR=2.00;
input bool UseTrendLegProtection=true;
input int MaxEntriesPerTrendLeg=2;
input double TrendResetATR=0.25;
input bool BlockDeepRSIChase=true;
input double DeepBullRSI=68.0;
input double DeepBearRSI=32.0;
input bool AllowEMA20CrossTrigger=true;
input bool AllowEMAReclaimTrigger=true;
input bool AllowMomentumTrigger=true;
input bool RequireTriggerCandle=true;
input bool RequireM5Alignment=true;
input bool RequireM1EMA50Side=true;
input bool UseTriggerCandleQuality=true;
input double MinTriggerBodyATR=0.15;
input double BullCloseLocationMin=0.60;
input double BearCloseLocationMax=0.40;
input bool UseRSIQualityWindow=true;
input double BullRSIMax=68.0;
input double BearRSIMin=32.0;
input double RiskPercent=0.75;
input bool AdaptiveRiskByTrend=true;
input double StrongTrendRiskMultiplier=1.10;
input double WeakTrendRiskMultiplier=0.75;
input double MaxDailyLossPercent=3.0;
input int MaxTradesPerDay=5;
input int MagicNumber=1001;
input int SlippagePoints=10;
input double ATR_SL_Multiplier=1.60;
input double ATR_TP_Multiplier=3.00;
input int MinimumSLPoints=100;
input int MinimumTPPoints=150;
input bool UseBreakEven=true;
input double BreakEvenATR=0.90;
input double BreakEvenPlusPoints=3.0;
input double BreakEvenStepPoints=1.0;
input bool UseProtectedProfit=true;
input double ProtectedProfitATR=1.30;
input double ProtectedProfitATRLock=0.25;
input bool UseTrailingStop=true;
input double TrailingATR=1.10;
input double TrailingStartATR=1.80;
input double TrailingStepPoints=25.0;
input bool TrailOnlyOnNewM1Bar=false;
input bool DebugMode=true;
input bool LogFilterBlocks=true;
input bool LogOnlyFilterChange=true;
input bool LogEntryDiagnostics=true;
input bool LogAllEntryChecks=true;

// GLOBALS
datetime LastBar=0,LastManagementBar=0,LastClosedTradeTime=0;
int TradeDay=-1,TradesToday=0,ConsecutiveLosses=0;
double DayStartBalance=0.0;
bool IndicatorsReady=false,TradingHoursOK=true,SpreadOK=false;
double CurrentSpread=0.0;
double EMA20_H4=0,EMA50_H4=0,EMA20_H1=0,EMA50_H1=0;
double EMA20_M15=0,EMA50_M15=0,EMA20_M5=0,EMA50_M5=0;
double EMA20_M1=0,EMA50_M1=0;
double EMA20_H4_Prev=0,EMA20_H1_Prev=0,EMA20_M15_Prev=0,EMA20_M5_Prev=0;
double RSI_M15=0,ATR_M15=0,ADX_M15=0;
long Volume_M15=0;
double TrendScore=0,EntryScore=0;
double PrimaryTrendScore=0,SecondaryTrendScore=0;
int TradeDirection=0;
bool IsH4Bull=false,IsH4Bear=false,IsH1Bull=false,IsH1Bear=false;
bool IsM15Bull=false,IsM15Bear=false,IsM5Bull=false,IsM5Bear=false;
bool IsM1Bull=false,IsM1Bear=false;
int BullPullbackAge=0,BearPullbackAge=0;
bool RecentBullCross=false,RecentBearCross=false;
int TrendLegDirection=0,EntriesThisTrendLeg=0;
bool BullTrendReset=false,BearTrendReset=false;
string LastFilterBlock="",LastGuardBlock="";
bool HistoryInitialized=false;

// INIT
int OnInit(){
   LastBar=0; LastManagementBar=0; BullPullbackAge=0; BearPullbackAge=0;
   RecentBullCross=false; RecentBearCross=false; TrendLegDirection=0;
   EntriesThisTrendLeg=0; BullTrendReset=false; BearTrendReset=false;
   HistoryInitialized=false; ResetDailyCounters();
   Print("====================================================");
   Print("T100 Trend Rider v5.70 STARTED");
   Print("Symbol=",Symbol()," Period=",Period());
   Print("SAST session=",TradingStartHour,":00 -> ",TradingEndHour,":00");
   Print("TrendScore min=",MinimumTrendScore," TriggerScore min=",MinimumTriggerScore);
   Print("Hierarchical HTF weights H4=",H4TrendWeight," H1=",H1TrendWeight," M15=",M15TrendWeight," M5=",M5TrendWeight);
   Print("Adaptive entry distance=",UseAdaptiveEntryDistance," soft=",DoubleToString(MaxEntryDistanceATR,2)," hard=",DoubleToString(HardEntryDistanceATR,2));
   Print("Risk=",DoubleToString(RiskPercent,2),"% SL ATR=",DoubleToString(ATR_SL_Multiplier,2),
         " TP ATR=",DoubleToString(ATR_TP_Multiplier,2));
   Print("Protected exits enabled=",UseProtectedProfit," trailing=",UseTrailingStop);
   Print("Entry diagnostics enabled=",LogEntryDiagnostics," full checks=",LogAllEntryChecks);
   Print("====================================================");
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason){ Print("T100 Trend Rider v5.70 stopped."); }

// MAIN
void OnTick(){
   ManageOpenTrades();
   if(!IsNewBar()) return;
   UpdateDailyCounters(); UpdateClosedTradeState(); CheckTradingHours(); CheckSpread();
   if(!UpdateIndicators()){ LogBlock("INDICATORS","indicator history/data not ready"); return; }
   if(!MarketReady()) return;
   CalculateTrend(); UpdateTrendLegState(); UpdatePullbackState(); CalculateEntryScore();
   if(!EntryGuardsOK()) return;
   if(DebugMode) PrintStatus();
   if(EntryReady()) OpenTrade();
   else if(DebugMode)
      Print("ENTRY NOT READY: direction=",CurrentEntryDirectionName(),
            " TrendScore=",DoubleToString(TrendScore,2),
            " EntryScore=",DoubleToString(EntryScore,2),
            " | exact first failure is shown by ENTRY CHECK.");
}
bool IsNewBar(){
   datetime t=iTime(Symbol(),PERIOD_M1,0);
   if(t<=0) return(false);
   if(t!=LastBar){ LastBar=t; return(true); }
   return(false);
}

// HISTORY / INDICATORS
bool HistoryReadyTF(int tf){
   int requiredBars=SlowEMA+15;
   if(iBars(Symbol(),tf)<requiredBars) return(false);
   if(iTime(Symbol(),tf,SlowEMA+2)<=0) return(false);
   if(iTime(Symbol(),tf,2)<=0) return(false);
   return(true);
}
bool ValidIndicator(double value){ return(value!=EMPTY_VALUE && value>0.0); }
bool UpdateIndicators(){
   IndicatorsReady=false;
   if(!HistoryReadyTF(PERIOD_H4)||!HistoryReadyTF(PERIOD_H1)||
      !HistoryReadyTF(PERIOD_M15)||!HistoryReadyTF(PERIOD_M5)||!HistoryReadyTF(PERIOD_M1)) return(false);
   EMA20_H4=iMA(Symbol(),PERIOD_H4,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_H4=iMA(Symbol(),PERIOD_H4,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA20_H1=iMA(Symbol(),PERIOD_H1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_H1=iMA(Symbol(),PERIOD_H1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA20_M15=iMA(Symbol(),PERIOD_M15,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_M15=iMA(Symbol(),PERIOD_M15,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA20_M5=iMA(Symbol(),PERIOD_M5,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_M5=iMA(Symbol(),PERIOD_M5,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA20_M1=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_M1=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA20_H4_Prev=iMA(Symbol(),PERIOD_H4,FastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   EMA20_H1_Prev=iMA(Symbol(),PERIOD_H1,FastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   EMA20_M15_Prev=iMA(Symbol(),PERIOD_M15,FastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   EMA20_M5_Prev=iMA(Symbol(),PERIOD_M5,FastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   RSI_M15=iRSI(Symbol(),PERIOD_M15,RSIPeriod,PRICE_CLOSE,1);
   ATR_M15=iATR(Symbol(),PERIOD_M15,ATRPeriod,1);
   ADX_M15=iADX(Symbol(),PERIOD_M15,ADXPeriod,PRICE_CLOSE,MODE_MAIN,1);
   Volume_M15=iVolume(Symbol(),PERIOD_M15,1);
   CurrentSpread=MarketInfo(Symbol(),MODE_SPREAD);
   if(!ValidIndicator(EMA20_H4)||!ValidIndicator(EMA50_H4)||
      !ValidIndicator(EMA20_H1)||!ValidIndicator(EMA50_H1)||
      !ValidIndicator(EMA20_M15)||!ValidIndicator(EMA50_M15)||
      !ValidIndicator(EMA20_M5)||!ValidIndicator(EMA50_M5)||
      !ValidIndicator(EMA20_M1)||!ValidIndicator(EMA50_M1)||
      !ValidIndicator(RSI_M15)||!ValidIndicator(ATR_M15)||!ValidIndicator(ADX_M15)) return(false);
   IndicatorsReady=true; return(true);
}

// SESSION / MARKET
datetime SASTNow(){ return(TimeCurrent()+(SASTUTCOffsetHours-BrokerUTCOffsetHours)*3600); }
int SASTHour(){ return(TimeHour(SASTNow())); }
void CheckTradingHours(){
   if(!UseTradingHours){TradingHoursOK=true;return;}
   int h=SASTHour();
   if(TradingStartHour==TradingEndHour){TradingHoursOK=true;return;}
   if(TradingStartHour<TradingEndHour) TradingHoursOK=(h>=TradingStartHour&&h<TradingEndHour);
   else TradingHoursOK=(h>=TradingStartHour||h<TradingEndHour);
}
void CheckSpread(){
   CurrentSpread=MarketInfo(Symbol(),MODE_SPREAD);
   SpreadOK=(CurrentSpread>=0&&CurrentSpread<=MaxSpread);
}
bool ATR_OK(){if(MinATRPoints<=0.0)return(true);return((ATR_M15/Point)>=MinATRPoints);}
bool Volume_OK(){if(MinVolume<=0)return(true);return(Volume_M15>=MinVolume);}
bool ADX_OK(){if(MinADX<=0.0)return(true);return(ADX_M15>=MinADX);}
bool DailyRiskOK(){
   if(MaxDailyLossPercent<=0.0||DayStartBalance<=0.0)return(true);
   double lossPct=100.0*(DayStartBalance-AccountEquity())/DayStartBalance;
   return(lossPct<MaxDailyLossPercent);
}
bool MarketReady(){
   if(!IndicatorsReady){LogBlock("MARKET","indicators not ready");return(false);}
   if(!TradingHoursOK){LogBlock("SESSION","outside SAST trading window");return(false);}
   if(!SpreadOK){LogBlock("SPREAD","spread="+DoubleToString(CurrentSpread,0));return(false);}
   if(!ATR_OK()){LogBlock("ATR","ATR below minimum");return(false);}
   if(!Volume_OK()){LogBlock("VOLUME","M15 volume below minimum");return(false);}
   if(!ADX_OK()){LogBlock("ADX","M15 ADX below minimum");return(false);}
   return(true);
}

// TREND
// v5.70: hierarchical regime scoring. When H4 and H1 agree, their
// direction is protected from M15/M5 pullback noise. When H4/H1 disagree,
// all four timeframes participate in a balanced composite.
void CalculateTrend(){
   IsH4Bull=(EMA20_H4>EMA50_H4); IsH4Bear=(EMA20_H4<EMA50_H4);
   IsH1Bull=(EMA20_H1>EMA50_H1); IsH1Bear=(EMA20_H1<EMA50_H1);
   IsM15Bull=(EMA20_M15>EMA50_M15); IsM15Bear=(EMA20_M15<EMA50_M15);
   IsM5Bull=(EMA20_M5>EMA50_M5); IsM5Bear=(EMA20_M5<EMA50_M5);
   IsM1Bull=(EMA20_M1>EMA50_M1); IsM1Bear=(EMA20_M1<EMA50_M1);

   double h4Slope=EMA20_H4-EMA20_H4_Prev;
   double h1Slope=EMA20_H1-EMA20_H1_Prev;
   double m15Slope=EMA20_M15-EMA20_M15_Prev;
   double m5Slope=EMA20_M5-EMA20_M5_Prev;

   PrimaryTrendScore=0;
   if(IsH4Bull) PrimaryTrendScore+=H4TrendWeight;
   if(IsH4Bear) PrimaryTrendScore-=H4TrendWeight;
   if(IsH1Bull) PrimaryTrendScore+=H1TrendWeight;
   if(IsH1Bear) PrimaryTrendScore-=H1TrendWeight;

   SecondaryTrendScore=0;
   if(IsM15Bull) SecondaryTrendScore+=M15TrendWeight;
   if(IsM15Bear) SecondaryTrendScore-=M15TrendWeight;
   if(IsM5Bull) SecondaryTrendScore+=M5TrendWeight;
   if(IsM5Bear) SecondaryTrendScore-=M5TrendWeight;
   if(IsH4Bull&&h4Slope>0) SecondaryTrendScore+=H4SlopeBonus;
   if(IsH4Bear&&h4Slope<0) SecondaryTrendScore-=H4SlopeBonus;
   if(IsH1Bull&&h1Slope>0) SecondaryTrendScore+=H1SlopeBonus;
   if(IsH1Bear&&h1Slope<0) SecondaryTrendScore-=H1SlopeBonus;
   if(IsM15Bull&&m15Slope>0) SecondaryTrendScore+=M15SlopeBonus;
   if(IsM15Bear&&m15Slope<0) SecondaryTrendScore-=M15SlopeBonus;
   if(IsM5Bull&&m5Slope>0) SecondaryTrendScore+=M5SlopeBonus;
   if(IsM5Bear&&m5Slope<0) SecondaryTrendScore-=M5SlopeBonus;
   if(ADX_M15>=25.0){
      if(PrimaryTrendScore+SecondaryTrendScore>0) SecondaryTrendScore+=ADXTrendBonus;
      else if(PrimaryTrendScore+SecondaryTrendScore<0) SecondaryTrendScore-=ADXTrendBonus;
   }

   bool htfAlignedBull=(IsH4Bull&&IsH1Bull);
   bool htfAlignedBear=(IsH4Bear&&IsH1Bear);

   if(ProtectAlignedHTFTrend && htfAlignedBull){
      TradeDirection=1;
      TrendScore=PrimaryTrendScore + 0.25*SecondaryTrendScore;
   }
   else if(ProtectAlignedHTFTrend && htfAlignedBear){
      TradeDirection=-1;
      TrendScore=PrimaryTrendScore + 0.25*SecondaryTrendScore;
   }
   else{
      TradeDirection=(PrimaryTrendScore+SecondaryTrendScore>=0?1:-1);
      TrendScore=PrimaryTrendScore+SecondaryTrendScore;
   }
}
bool BullTrend(){return(TradeDirection>0 && TrendScore>=MinimumTrendScore);}
bool BearTrend(){return(TradeDirection<0 && TrendScore<=-MinimumTrendScore);}

// TREND LEG
void UpdateTrendLegState(){
   int direction=0;if(BullTrend())direction=1;else if(BearTrend())direction=-1;
   if(direction==0)return;
   if(TrendLegDirection==0){TrendLegDirection=direction;EntriesThisTrendLeg=0;BullTrendReset=false;BearTrendReset=false;return;}
   if(direction!=TrendLegDirection){TrendLegDirection=direction;EntriesThisTrendLeg=0;BullTrendReset=false;BearTrendReset=false;return;}
   double resetDistance=TrendResetATR*EntryATR_M1();
   if(direction>0){
      double close1=iClose(Symbol(),PERIOD_M1,1);
      if(close1<EMA20_M1-resetDistance)BullTrendReset=true;
      if(BullTrendReset&&close1>EMA20_M1){EntriesThisTrendLeg=0;BullTrendReset=false;}
   }else{
      double close1=iClose(Symbol(),PERIOD_M1,1);
      if(close1>EMA20_M1+resetDistance)BearTrendReset=true;
      if(BearTrendReset&&close1<EMA20_M1){EntriesThisTrendLeg=0;BearTrendReset=false;}
   }
}

// PULLBACK
double EntryATR_M1(){double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);if(atr>0.0)return(atr);return(ATR_M15);}
bool BullPullbackDetected(){
   double maxDistance=PullbackATRMax*EntryATR_M1();if(maxDistance<=0.0)return(false);
   bool recentTouch=false,recentAbove=false;int lookback=MathMax(1,PullbackLookbackBars);
   for(int shift=1;shift<=lookback;shift++){
      double ema20=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,shift);
      double ema50=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,shift);
      double close=iClose(Symbol(),PERIOD_M1,shift),low=iLow(Symbol(),PERIOD_M1,shift);
      if(MathAbs(close-ema20)<=maxDistance||MathAbs(low-ema20)<=maxDistance)recentTouch=true;
      if(close>ema20||close>ema50)recentAbove=true;
   }
   double ema=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double close1=iClose(Symbol(),PERIOD_M1,1),open1=iOpen(Symbol(),PERIOD_M1,1),low1=iLow(Symbol(),PERIOD_M1,1);
   bool immediate=(low1<=ema&&close1>ema&&close1>=open1);
   bool shallow=(recentTouch&&close1>ema&&recentAbove);
   return(immediate||shallow);
}
bool BearPullbackDetected(){
   double maxDistance=PullbackATRMax*EntryATR_M1();if(maxDistance<=0.0)return(false);
   bool recentTouch=false,recentBelow=false;int lookback=MathMax(1,PullbackLookbackBars);
   for(int shift=1;shift<=lookback;shift++){
      double ema20=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,shift);
      double ema50=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,shift);
      double close=iClose(Symbol(),PERIOD_M1,shift),high=iHigh(Symbol(),PERIOD_M1,shift);
      if(MathAbs(close-ema20)<=maxDistance||MathAbs(high-ema20)<=maxDistance)recentTouch=true;
      if(close<ema20||close<ema50)recentBelow=true;
   }
   double ema=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double close1=iClose(Symbol(),PERIOD_M1,1),open1=iOpen(Symbol(),PERIOD_M1,1),high1=iHigh(Symbol(),PERIOD_M1,1);
   bool immediate=(high1>=ema&&close1<ema&&close1<=open1);
   bool shallow=(recentTouch&&close1<ema&&recentBelow);
   return(immediate||shallow);
}
void UpdatePullbackState(){
   RecentBullCross=false;RecentBearCross=false;
   if(BullPullbackDetected())BullPullbackAge=1;else if(BullPullbackAge>0)BullPullbackAge++;
   if(BearPullbackDetected())BearPullbackAge=1;else if(BearPullbackAge>0)BearPullbackAge++;
   if(BullPullbackAge>PullbackMaxBars)BullPullbackAge=0;
   if(BearPullbackAge>PullbackMaxBars)BearPullbackAge=0;
   double f1=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double s1=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double f2=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double s2=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,2);
   RecentBullCross=(f2<=s2&&f1>s1);RecentBearCross=(f2>=s2&&f1<s1);
}

// CANDLE
bool BullTriggerCandleOK(){
   if(!UseTriggerCandleQuality)return(true);
   double o=iOpen(Symbol(),PERIOD_M1,1),c=iClose(Symbol(),PERIOD_M1,1),h=iHigh(Symbol(),PERIOD_M1,1),l=iLow(Symbol(),PERIOD_M1,1);
   double range=h-l;if(range<=0.0)return(false);double body=MathAbs(c-o);
   if(body<(MinTriggerBodyATR*EntryATR_M1()))return(false);
   double location=(c-l)/range;return(c>o&&location>=BullCloseLocationMin);
}
bool BearTriggerCandleOK(){
   if(!UseTriggerCandleQuality)return(true);
   double o=iOpen(Symbol(),PERIOD_M1,1),c=iClose(Symbol(),PERIOD_M1,1),h=iHigh(Symbol(),PERIOD_M1,1),l=iLow(Symbol(),PERIOD_M1,1);
   double range=h-l;if(range<=0.0)return(false);double body=MathAbs(c-o);
   if(body<(MinTriggerBodyATR*EntryATR_M1()))return(false);
   double location=(c-l)/range;return(c<o&&location<=BearCloseLocationMax);
}
bool EMADistanceOK(){if(MinEMADistancePoints<=0.0)return(true);return(MathAbs(EMA20_M15-EMA50_M15)/Point>=MinEMADistancePoints);}

// SCORE
// v5.70: score trigger quality rather than treating any one-bar momentum
// as equivalent to a fresh EMA cross.
void CalculateEntryScore(){
   EntryScore=0;
   double close1=iClose(Symbol(),PERIOD_M1,1);
   double close2=iClose(Symbol(),PERIOD_M1,2);
   bool crossBull=false,crossBear=false,reclaimBull=false,reclaimBear=false;
   bool momentumBull=false,momentumBear=false;

   if(AllowEMA20CrossTrigger){crossBull=RecentBullCross;crossBear=RecentBearCross;}
   if(AllowEMAReclaimTrigger){
      reclaimBull=(close2<=EMA20_M1&&close1>EMA20_M1);
      reclaimBear=(close2>=EMA20_M1&&close1<EMA20_M1);
   }
   if(AllowMomentumTrigger){
      double move=close1-close2;
      momentumBull=(move>0&&close1>EMA20_M1);
      momentumBear=(move<0&&close1<EMA20_M1);
   }

   IsM1Bull=(crossBull||reclaimBull||momentumBull);
   IsM1Bear=(crossBear||reclaimBear||momentumBear);

   if(BullTrend()&&IsM1Bull){
      EntryScore+=25;
      if(crossBull) EntryScore+=25;
      else if(reclaimBull) EntryScore+=18;
      else if(momentumBull) EntryScore+=10;
      if(close1>EMA20_M1) EntryScore+=10;
      if(EMA20_M1>EMA50_M1) EntryScore+=10;
      if(IsM5Bull) EntryScore+=8;
      if(BullPullbackAge>0) EntryScore+=7;
      if(BullTriggerCandleOK()) EntryScore+=10;
      if(ADX_M15>=30.0) EntryScore+=5;
   }
   if(BearTrend()&&IsM1Bear){
      EntryScore+=25;
      if(crossBear) EntryScore+=25;
      else if(reclaimBear) EntryScore+=18;
      else if(momentumBear) EntryScore+=10;
      if(close1<EMA20_M1) EntryScore+=10;
      if(EMA20_M1<EMA50_M1) EntryScore+=10;
      if(IsM5Bear) EntryScore+=8;
      if(BearPullbackAge>0) EntryScore+=7;
      if(BearTriggerCandleOK()) EntryScore+=10;
      if(ADX_M15>=30.0) EntryScore+=5;
   }
}

// ENTRY FILTERS
bool M1SideOK(int type){
   double close1=iClose(Symbol(),PERIOD_M1,1);
   if(type==OP_BUY){if(RequireM1EMA50Side&&close1<=EMA50_M1)return(false);return(true);}
   if(type==OP_SELL){if(RequireM1EMA50Side&&close1>=EMA50_M1)return(false);return(true);}
   return(false);
}
bool RSIQualityOK(int type){
   if(!UseRSIQualityWindow)return(true);
   if(type==OP_BUY)return(RSI_M15>=BullRSI&&RSI_M15<=BullRSIMax);
   if(type==OP_SELL)return(RSI_M15<=BearRSI&&RSI_M15>=BearRSIMin);
   return(false);
}
bool DeepRSIChaseOK(int type){
   if(!BlockDeepRSIChase)return(true);
   if(type==OP_BUY)return(RSI_M15<DeepBullRSI);
   if(type==OP_SELL)return(RSI_M15>DeepBearRSI);
   return(false);
}
bool EntryDistanceOK(int type){
   if(!UseMaxEntryDistance)return(true);
   double atr=EntryATR_M1();
   if(atr<=0.0)return(false);
   double price=(type==OP_BUY?Ask:Bid);
   double distance=MathAbs(price-EMA20_M1);
   double ratio=distance/atr;
   if(ratio<=MaxEntryDistanceATR)return(true);
   if(ratio>HardEntryDistanceATR)return(false);
   if(!UseAdaptiveEntryDistance)return(false);

   // Allow a controlled momentum extension only when the trend is strong,
   // the trigger is genuine, and the market is not deeply stretched.
   bool strong=(MathAbs(TrendScore)>=70.0 || MathAbs(PrimaryTrendScore)>=65.0);
   bool trigger=(RecentBullCross||RecentBearCross);
   bool adxStrong=(ADX_M15>=25.0);
   bool notChasing=(type==OP_BUY ? RSI_M15<DeepBullRSI : RSI_M15>DeepBearRSI);
   if(strong && trigger && adxStrong && notChasing && ratio<=StrongTrendDistanceATR) return(true);
   return(false);
}
bool EntryCooldownOK(){
   if(ReEntryCooldownBars<=0||LastClosedTradeTime<=0)return(true);
   int shift=iBarShift(Symbol(),PERIOD_M1,LastClosedTradeTime,false);
   if(shift<0)return(true);return(shift>=ReEntryCooldownBars);
}
bool LossLimitOK(){if(MaxConsecutiveLosses<=0)return(true);return(ConsecutiveLosses<MaxConsecutiveLosses);}
bool PositionExists(){
   for(int i=OrdersTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber)continue;
      if(OrderType()==OP_BUY||OrderType()==OP_SELL)return(true);
   }
   return(false);
}

// GUARDS
void LogGuardBlock(string group,string detail){
   if(LogEntryDiagnostics&&DebugMode)Print("ENTRY GUARD BLOCKED ",group,": ",detail);
}
bool EntryGuardsOK(){
   if(!DailyRiskOK()){LogBlock("DAILY_RISK","daily loss limit");LogGuardBlock("DAILY_RISK","equity daily loss limit");return(false);}
   if(MaxTradesPerDay>0&&TradesToday>=MaxTradesPerDay){
      LogBlock("DAILY_TRADES","max trades reached");LogGuardBlock("DAILY_TRADES","TradesToday="+IntegerToString(TradesToday)+"/"+IntegerToString(MaxTradesPerDay));return(false);}
   if(!EntryCooldownOK()){
      LogBlock("COOLDOWN","re-entry cooldown");LogGuardBlock("COOLDOWN","LastClosedTradeTime="+TimeToString(LastClosedTradeTime,TIME_DATE|TIME_MINUTES));return(false);}
   if(!LossLimitOK()){
      LogBlock("LOSS_STREAK","consecutive loss limit");LogGuardBlock("LOSS_STREAK","ConsecutiveLosses="+IntegerToString(ConsecutiveLosses)+"/"+IntegerToString(MaxConsecutiveLosses));return(false);}
   if(PositionExists()){LogBlock("POSITION","existing position");LogGuardBlock("POSITION","managed position already exists");return(false);}
   if(UseTrendLegProtection&&MaxEntriesPerTrendLeg>0&&EntriesThisTrendLeg>=MaxEntriesPerTrendLeg){
      LogBlock("TREND_LEG","max entries in current trend leg");LogGuardBlock("TREND_LEG","EntriesThisTrendLeg="+IntegerToString(EntriesThisTrendLeg)+"/"+IntegerToString(MaxEntriesPerTrendLeg));return(false);}
   return(true);
}

// DIAGNOSTICS
string CurrentEntryDirectionName(){if(BullTrend())return("BUY");if(BearTrend())return("SELL");return("NONE");}
void PrintEntryCheck(string direction,string name,bool passed,string detail){
   if(!LogEntryDiagnostics||!DebugMode)return;
   if(!LogAllEntryChecks&&passed)return;
   Print("ENTRY CHECK [",direction,"] ",name,"=",passed?"PASS":"FAIL"," | ",detail);
}
bool EntryReadyBuy(){
   string d="BUY";
   if(TrendScore<MinimumTrendScore){PrintEntryCheck(d,"TREND_SCORE",false,"TrendScore="+DoubleToString(TrendScore,2)+" < "+IntegerToString(MinimumTrendScore));return(false);}
   PrintEntryCheck(d,"TREND_SCORE",true,"TrendScore="+DoubleToString(TrendScore,2));
   if(!IsM1Bull){PrintEntryCheck(d,"M1_TRIGGER",false,"IsM1Bull=false cross="+(RecentBullCross?"true":"false")+" pullbackAge="+IntegerToString(BullPullbackAge));return(false);}
   PrintEntryCheck(d,"M1_TRIGGER",true,"IsM1Bull=true cross="+(RecentBullCross?"true":"false")+" pullbackAge="+IntegerToString(BullPullbackAge));
   if(EntryScore<MinimumTriggerScore){PrintEntryCheck(d,"ENTRY_SCORE",false,"EntryScore="+DoubleToString(EntryScore,2)+" < "+IntegerToString(MinimumTriggerScore));return(false);}
   PrintEntryCheck(d,"ENTRY_SCORE",true,"EntryScore="+DoubleToString(EntryScore,2));
   if(BullPullbackAge<=0&&!RecentBullCross){PrintEntryCheck(d,"PULLBACK_RECLAIM",false,"BullPullbackAge="+IntegerToString(BullPullbackAge)+" RecentBullCross="+(RecentBullCross?"true":"false"));return(false);}
   PrintEntryCheck(d,"PULLBACK_RECLAIM",true,"BullPullbackAge="+IntegerToString(BullPullbackAge)+" RecentBullCross="+(RecentBullCross?"true":"false"));
   if(RequireTriggerCandle&&!BullTriggerCandleOK()){
      double o=iOpen(Symbol(),PERIOD_M1,1),c=iClose(Symbol(),PERIOD_M1,1),h=iHigh(Symbol(),PERIOD_M1,1),l=iLow(Symbol(),PERIOD_M1,1),r=h-l,b=MathAbs(c-o);
      PrintEntryCheck(d,"TRIGGER_CANDLE",false,"body="+DoubleToString(b,Digits)+" minBody="+DoubleToString(MinTriggerBodyATR*EntryATR_M1(),Digits)+" closeLocation="+DoubleToString(r>0?(c-l)/r:0,2));return(false);}
   PrintEntryCheck(d,"TRIGGER_CANDLE",true,RequireTriggerCandle?"quality passed":"requirement disabled");
   if(!M1SideOK(OP_BUY)){PrintEntryCheck(d,"M1_EMA50_SIDE",false,"close="+DoubleToString(iClose(Symbol(),PERIOD_M1,1),Digits)+" EMA50="+DoubleToString(EMA50_M1,Digits));return(false);}
   PrintEntryCheck(d,"M1_EMA50_SIDE",true,"close="+DoubleToString(iClose(Symbol(),PERIOD_M1,1),Digits)+" > EMA50="+DoubleToString(EMA50_M1,Digits));
   if(!RSIQualityOK(OP_BUY)){PrintEntryCheck(d,"RSI_WINDOW",false,"RSI="+DoubleToString(RSI_M15,2)+" required "+DoubleToString(BullRSI,2)+".."+DoubleToString(BullRSIMax,2));return(false);}
   PrintEntryCheck(d,"RSI_WINDOW",true,"RSI="+DoubleToString(RSI_M15,2));
   if(!DeepRSIChaseOK(OP_BUY)){PrintEntryCheck(d,"DEEP_RSI_CHASE",false,"RSI="+DoubleToString(RSI_M15,2)+" must be < "+DoubleToString(DeepBullRSI,2));return(false);}
   PrintEntryCheck(d,"DEEP_RSI_CHASE",true,"RSI="+DoubleToString(RSI_M15,2));
   if(!EntryDistanceOK(OP_BUY)){double dist=MathAbs(Ask-EMA20_M1),atr=EntryATR_M1();PrintEntryCheck(d,"ENTRY_DISTANCE",false,"distance="+DoubleToString(dist,Digits)+" max="+DoubleToString(MaxEntryDistanceATR*atr,Digits));return(false);}
   PrintEntryCheck(d,"ENTRY_DISTANCE",true,"within "+DoubleToString(MaxEntryDistanceATR,2)+" ATR");
   PrintEntryCheck(d,"RESULT",true,"ALL BUY ENTRY CONDITIONS PASSED");return(true);
}
bool EntryReadySell(){
   string d="SELL";
   if(TrendScore>-MinimumTrendScore){PrintEntryCheck(d,"TREND_SCORE",false,"TrendScore="+DoubleToString(TrendScore,2)+" > -"+IntegerToString(MinimumTrendScore));return(false);}
   PrintEntryCheck(d,"TREND_SCORE",true,"TrendScore="+DoubleToString(TrendScore,2));
   if(!IsM1Bear){PrintEntryCheck(d,"M1_TRIGGER",false,"IsM1Bear=false cross="+(RecentBearCross?"true":"false")+" pullbackAge="+IntegerToString(BearPullbackAge));return(false);}
   PrintEntryCheck(d,"M1_TRIGGER",true,"IsM1Bear=true cross="+(RecentBearCross?"true":"false")+" pullbackAge="+IntegerToString(BearPullbackAge));
   if(EntryScore<MinimumTriggerScore){PrintEntryCheck(d,"ENTRY_SCORE",false,"EntryScore="+DoubleToString(EntryScore,2)+" < "+IntegerToString(MinimumTriggerScore));return(false);}
   PrintEntryCheck(d,"ENTRY_SCORE",true,"EntryScore="+DoubleToString(EntryScore,2));
   if(BearPullbackAge<=0&&!RecentBearCross){PrintEntryCheck(d,"PULLBACK_RECLAIM",false,"BearPullbackAge="+IntegerToString(BearPullbackAge)+" RecentBearCross="+(RecentBearCross?"true":"false"));return(false);}
   PrintEntryCheck(d,"PULLBACK_RECLAIM",true,"BearPullbackAge="+IntegerToString(BearPullbackAge)+" RecentBearCross="+(RecentBearCross?"true":"false"));
   if(RequireTriggerCandle&&!BearTriggerCandleOK()){
      double o=iOpen(Symbol(),PERIOD_M1,1),c=iClose(Symbol(),PERIOD_M1,1),h=iHigh(Symbol(),PERIOD_M1,1),l=iLow(Symbol(),PERIOD_M1,1),r=h-l,b=MathAbs(c-o);
      PrintEntryCheck(d,"TRIGGER_CANDLE",false,"body="+DoubleToString(b,Digits)+" minBody="+DoubleToString(MinTriggerBodyATR*EntryATR_M1(),Digits)+" closeLocation="+DoubleToString(r>0?(c-l)/r:0,2));return(false);}
   PrintEntryCheck(d,"TRIGGER_CANDLE",true,RequireTriggerCandle?"quality passed":"requirement disabled");
   if(!M1SideOK(OP_SELL)){PrintEntryCheck(d,"M1_EMA50_SIDE",false,"close="+DoubleToString(iClose(Symbol(),PERIOD_M1,1),Digits)+" EMA50="+DoubleToString(EMA50_M1,Digits));return(false);}
   PrintEntryCheck(d,"M1_EMA50_SIDE",true,"close="+DoubleToString(iClose(Symbol(),PERIOD_M1,1),Digits)+" < EMA50="+DoubleToString(EMA50_M1,Digits));
   if(!RSIQualityOK(OP_SELL)){PrintEntryCheck(d,"RSI_WINDOW",false,"RSI="+DoubleToString(RSI_M15,2)+" required "+DoubleToString(BearRSIMin,2)+".."+DoubleToString(BearRSI,2));return(false);}
   PrintEntryCheck(d,"RSI_WINDOW",true,"RSI="+DoubleToString(RSI_M15,2));
   if(!DeepRSIChaseOK(OP_SELL)){PrintEntryCheck(d,"DEEP_RSI_CHASE",false,"RSI="+DoubleToString(RSI_M15,2)+" must be > "+DoubleToString(DeepBearRSI,2));return(false);}
   PrintEntryCheck(d,"DEEP_RSI_CHASE",true,"RSI="+DoubleToString(RSI_M15,2));
   if(!EntryDistanceOK(OP_SELL)){double dist=MathAbs(Bid-EMA20_M1),atr=EntryATR_M1();PrintEntryCheck(d,"ENTRY_DISTANCE",false,"distance="+DoubleToString(dist,Digits)+" max="+DoubleToString(MaxEntryDistanceATR*atr,Digits));return(false);}
   PrintEntryCheck(d,"ENTRY_DISTANCE",true,"within "+DoubleToString(MaxEntryDistanceATR,2)+" ATR");
   PrintEntryCheck(d,"RESULT",true,"ALL SELL ENTRY CONDITIONS PASSED");return(true);
}
bool EntryReady(){
   if(TrendScore>=MinimumTrendScore)return(EntryReadyBuy());
   if(TrendScore<=-MinimumTrendScore)return(EntryReadySell());
   if(LogEntryDiagnostics&&DebugMode)Print("ENTRY CHECK [NONE] FAIL | TrendScore=",DoubleToString(TrendScore,2)," inside neutral range +/-",IntegerToString(MinimumTrendScore));
   return(false);
}

// LOTS
double LotStep(){double step=MarketInfo(Symbol(),MODE_LOTSTEP);if(step<=0.0)step=0.01;return(step);}
double NormalizeLot(double lot){
   double minLot=MarketInfo(Symbol(),MODE_MINLOT),maxLot=MarketInfo(Symbol(),MODE_MAXLOT),step=LotStep();
   if(lot<minLot)lot=minLot;if(lot>maxLot)lot=maxLot;
   lot=MathFloor(lot/step+0.0000001)*step;if(lot<minLot)lot=minLot;
   int digitsLot=2;if(step>=1.0)digitsLot=0;else if(step>=0.1)digitsLot=1;
   return(NormalizeDouble(lot,digitsLot));
}
double CalculateLot(double stopDistancePrice){
   if(RiskPercent<=0.0)return(NormalizeLot(MarketInfo(Symbol(),MODE_MINLOT)));
   double riskPct=RiskPercent;
   if(AdaptiveRiskByTrend){
      if(MathAbs(TrendScore)>=85.0) riskPct*=StrongTrendRiskMultiplier;
      else if(MathAbs(TrendScore)<50.0) riskPct*=WeakTrendRiskMultiplier;
   }
   double riskMoney=AccountBalance()*riskPct/100.0,tickValue=MarketInfo(Symbol(),MODE_TICKVALUE),tickSize=MarketInfo(Symbol(),MODE_TICKSIZE);
   if(tickValue<=0.0||tickSize<=0.0||stopDistancePrice<=0.0)return(NormalizeLot(MarketInfo(Symbol(),MODE_MINLOT)));
   double moneyPerLot=stopDistancePrice/tickSize*tickValue;if(moneyPerLot<=0.0)return(NormalizeLot(MarketInfo(Symbol(),MODE_MINLOT)));
   return(NormalizeLot(riskMoney/moneyPerLot));
}

// STOPS
double StopLevelPrice(){return(MarketInfo(Symbol(),MODE_STOPLEVEL)*Point);}
double FreezeLevelPrice(){return(MarketInfo(Symbol(),MODE_FREEZELEVEL)*Point);}
double MinStopDistancePrice(){return(MathMax(StopLevelPrice()+2.0*Point,MinimumSLPoints*Point));}
double MinTPDistancePrice(){return(MathMax(StopLevelPrice()+2.0*Point,MinimumTPPoints*Point));}
void BuildStops(int type,double entry,double &sl,double &tp){
   double slDistance=MathMax(ATR_M15*ATR_SL_Multiplier,MinStopDistancePrice());
   double tpDistance=MathMax(ATR_M15*ATR_TP_Multiplier,MinTPDistancePrice());
   if(type==OP_BUY){sl=entry-slDistance;tp=entry+tpDistance;}
   else{sl=entry+slDistance;tp=entry-tpDistance;}
   sl=NormalizeDouble(sl,Digits);tp=NormalizeDouble(tp,Digits);
}

// OPEN
void OpenTrade(){
   RefreshRates();int type=-1;double price=0.0;
   if(TrendScore>=MinimumTrendScore&&IsM1Bull){type=OP_BUY;price=Ask;}
   else if(TrendScore<=-MinimumTrendScore&&IsM1Bear){type=OP_SELL;price=Bid;}
   else return;
   double sl=0.0,tp=0.0;BuildStops(type,price,sl,tp);
   double lots=CalculateLot(MathAbs(price-sl));
   if(lots<=0.0){Print("ORDER BLOCKED: calculated lot <= 0");return;}
   string comment="T100 Trend Rider v5.70";ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,NormalizeDouble(price,Digits),SlippagePoints,sl,tp,comment,MagicNumber,0,clrNONE);
   if(ticket<0){int err=GetLastError();Print("OrderSend FAILED. error=",err," type=",type," lots=",DoubleToString(lots,2)," price=",DoubleToString(price,Digits)," SL=",DoubleToString(sl,Digits)," TP=",DoubleToString(tp,Digits));return;}
   TradesToday++;if(UseTrendLegProtection)EntriesThisTrendLeg++;
   if(type==OP_BUY)BullPullbackAge=0;else BearPullbackAge=0;
   Print("ORDER OPENED ticket=",ticket," type=",type==OP_BUY?"BUY":"SELL"," lots=",DoubleToString(lots,2),
         " price=",DoubleToString(price,Digits)," SL=",DoubleToString(sl,Digits)," TP=",DoubleToString(tp,Digits),
         " TrendScore=",DoubleToString(TrendScore,2)," EntryScore=",DoubleToString(EntryScore,2));
}

// MANAGEMENT
bool BetterStop(int type,double proposed,double currentSL,double minimumStep){
   double step=MathMax(minimumStep,0.1)*Point;
   if(type==OP_BUY){if(currentSL<=0.0)return(true);return(proposed>currentSL+step);}
   if(type==OP_SELL){if(currentSL<=0.0)return(true);return(proposed<currentSL-step);}
   return(false);
}
bool ValidStopForBroker(int type,double stop){
   RefreshRates();double minDist=MathMax(StopLevelPrice(),FreezeLevelPrice())+2.0*Point;
   if(type==OP_BUY)return((Bid-stop)>=minDist);if(type==OP_SELL)return((stop-Ask)>=minDist);return(false);
}
bool ModifyStop(int ticket,double newSL,double currentTP,double minimumStep){
   if(!OrderSelect(ticket,SELECT_BY_TICKET))return(false);
   double oldSL=OrderStopLoss();int type=OrderType();newSL=NormalizeDouble(newSL,Digits);
   if(!BetterStop(type,newSL,oldSL,minimumStep))return(false);if(!ValidStopForBroker(type,newSL))return(false);
   ResetLastError();
   bool ok=OrderModify(ticket,OrderOpenPrice(),newSL,currentTP,0,clrNONE);
   if(!ok){int err=GetLastError();if(DebugMode)Print("OrderModify FAILED ticket=",ticket," error=",err," newSL=",DoubleToString(newSL,Digits));return(false);}
   return(true);
}
void ManageBuy(){
   int ticket=OrderTicket();double open=OrderOpenPrice(),tp=OrderTakeProfit();RefreshRates();
   double profitDistance=Bid-open;if(profitDistance<=0.0)return;
   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);if(atr<=0.0)atr=ATR_M15;if(atr<=0.0)atr=iATR(Symbol(),PERIOD_M15,ATRPeriod,1);if(atr<=0.0)return;
   if(UseBreakEven&&profitDistance>=BreakEvenATR*atr)ModifyStop(ticket,open+BreakEvenPlusPoints*Point,tp,BreakEvenStepPoints);
   if(UseProtectedProfit&&profitDistance>=ProtectedProfitATR*atr)ModifyStop(ticket,open+ProtectedProfitATRLock*atr,tp,BreakEvenStepPoints);
   if(UseTrailingStop&&profitDistance>=TrailingStartATR*atr)ModifyStop(ticket,Bid-TrailingATR*atr,tp,TrailingStepPoints);
}
void ManageSell(){
   int ticket=OrderTicket();double open=OrderOpenPrice(),tp=OrderTakeProfit();RefreshRates();
   double profitDistance=open-Ask;if(profitDistance<=0.0)return;
   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);if(atr<=0.0)atr=ATR_M15;if(atr<=0.0)atr=iATR(Symbol(),PERIOD_M15,ATRPeriod,1);if(atr<=0.0)return;
   if(UseBreakEven&&profitDistance>=BreakEvenATR*atr)ModifyStop(ticket,open-BreakEvenPlusPoints*Point,tp,BreakEvenStepPoints);
   if(UseProtectedProfit&&profitDistance>=ProtectedProfitATR*atr)ModifyStop(ticket,open-ProtectedProfitATRLock*atr,tp,BreakEvenStepPoints);
   if(UseTrailingStop&&profitDistance>=TrailingStartATR*atr)ModifyStop(ticket,Ask+TrailingATR*atr,tp,TrailingStepPoints);
}
void ManageOpenTrades(){
   if(TrailOnlyOnNewM1Bar){datetime t=iTime(Symbol(),PERIOD_M1,0);if(t==LastManagementBar)return;LastManagementBar=t;}
   for(int i=OrdersTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber)continue;
      if(OrderType()==OP_BUY)ManageBuy();else if(OrderType()==OP_SELL)ManageSell();
   }
}

// DAILY / HISTORY
int CurrentDayKey(){datetime now=SASTNow();return(TimeYear(now)*10000+TimeMonth(now)*100+TimeDay(now));}
void ResetDailyCounters(){TradeDay=CurrentDayKey();TradesToday=0;DayStartBalance=AccountBalance();}
void UpdateDailyCounters(){
   int d=CurrentDayKey();if(d!=TradeDay){TradeDay=d;TradesToday=0;DayStartBalance=AccountBalance();ConsecutiveLosses=0;
      if(DebugMode)Print("NEW SAST TRADING DAY. StartBalance=",DoubleToString(DayStartBalance,2));}
}
void UpdateClosedTradeState(){
   static int lastHistoryTotal=-1;int total=OrdersHistoryTotal();if(total==lastHistoryTotal)return;lastHistoryTotal=total;
   datetime newest=0;double newestNet=0.0;
   for(int i=total-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))continue;
      if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber)continue;
      if(OrderType()!=OP_BUY&&OrderType()!=OP_SELL)continue;if(OrderCloseTime()<=0)continue;
      if(OrderCloseTime()>newest){newest=OrderCloseTime();newestNet=OrderProfit()+OrderSwap()+OrderCommission();}
   }
   if(!HistoryInitialized){if(newest>0)LastClosedTradeTime=newest;ConsecutiveLosses=0;HistoryInitialized=true;return;}
   if(newest>LastClosedTradeTime){LastClosedTradeTime=newest;if(newestNet<0.0)ConsecutiveLosses++;else if(newestNet>0.0)ConsecutiveLosses=0;}
}

// LOGGING
void LogBlock(string group,string detail){
   if(!LogFilterBlocks)return;string msg=group+": "+detail;if(LogOnlyFilterChange&&msg==LastFilterBlock)return;
   LastFilterBlock=msg;if(DebugMode)Print("BLOCKED ",msg);
}
void PrintStatus()
{
   string status="";

   status="T100 Trend Rider v5.70\n";
   status=status+"SAST Hour: "+IntegerToString(SASTHour())+"\n";
   status=status+"Session OK: "+(TradingHoursOK ? "true" : "false");
   status=status+" Spread: "+DoubleToString(CurrentSpread,0)+"/"+IntegerToString(MaxSpread)+"\n";
   status=status+"TrendScore: "+DoubleToString(TrendScore,2);
   status=status+" Primary: "+DoubleToString(PrimaryTrendScore,2)+" Secondary: "+DoubleToString(SecondaryTrendScore,2);
   status=status+" EntryScore: "+DoubleToString(EntryScore,2)+"\n";
   status=status+"H4 "+(IsH4Bull ? "BULL" : (IsH4Bear ? "BEAR" : "FLAT"));
   status=status+" | H1 "+(IsH1Bull ? "BULL" : (IsH1Bear ? "BEAR" : "FLAT"))+"\n";
   status=status+"M15 "+(IsM15Bull ? "BULL" : (IsM15Bear ? "BEAR" : "FLAT"));
   status=status+" | M5 "+(IsM5Bull ? "BULL" : (IsM5Bear ? "BEAR" : "FLAT"))+"\n";
   status=status+"M1 "+(IsM1Bull ? "BULL" : (IsM1Bear ? "BEAR" : "FLAT"));
   status=status+" RSI15 "+DoubleToString(RSI_M15,2);
   status=status+" ADX "+DoubleToString(ADX_M15,2)+"\n";
   status=status+"Pullback B/Age "+IntegerToString(BullPullbackAge);
   status=status+" BCross "+(RecentBullCross ? "true" : "false");
   status=status+" | S/Age "+IntegerToString(BearPullbackAge);
   status=status+" SCross "+(RecentBearCross ? "true" : "false")+"\n";
   status=status+"M1 EMA20 "+DoubleToString(EMA20_M1,Digits);
   status=status+" EMA50 "+DoubleToString(EMA50_M1,Digits)+"\n";
   status=status+"BE ATR "+DoubleToString(BreakEvenATR,2);
   status=status+" Lock ATR "+DoubleToString(ProtectedProfitATR,2);
   status=status+" Trail ATR "+DoubleToString(TrailingStartATR,2)+"\n";
   status=status+"Trades today: "+IntegerToString(TradesToday)+"/"+IntegerToString(MaxTradesPerDay);
   status=status+" Loss streak: "+IntegerToString(ConsecutiveLosses)+"\n";
   status=status+"Trend leg entries: "+IntegerToString(EntriesThisTrendLeg)+"/"+IntegerToString(MaxEntriesPerTrendLeg);

   if(DebugMode) Print(status);
}
//+------------------------------------------------------------------+
//| END OF T100 TREND RIDER v5.70                                    |
//+------------------------------------------------------------------+
