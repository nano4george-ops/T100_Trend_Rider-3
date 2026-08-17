//+------------------------------------------------------------------+
//| T100_Trend_Rider_v5_65_Adaptive.mq4                              |
//| T100 Trend Rider v5.65                                           |
//| Combined adaptive MTF trend + pullback + protected trade manager |
//+------------------------------------------------------------------+
#property strict
#property version   "5.65"
#property description "T100 Trend Rider v5.65 - consolidated adaptive MTF + protected trailing"

//============================== INPUTS ==============================
input int      FastEMA                  = 20;
input int      SlowEMA                  = 50;
input int      RSIPeriod                = 14;
input double   BullRSI                  = 55.0;
input double   BearRSI                  = 45.0;
input int      ATRPeriod                = 14;
input double   MinATRPoints             = 0.0;
input int      ADXPeriod                = 14;
input double   MinADX                   = 20.0;
input long     MinVolume                = 100;
input int      MaxSpread                = 50;

input bool     UseTradingHours          = true;
input int      TradingStartHour         = 10;
input int      TradingEndHour           = 2;
input int      BrokerUTCOffsetHours     = 2;
input int      SASTUTCOffsetHours       = 2;

input int      MinimumTrendScore        = 25;
input int      MinimumTriggerScore      = 40;

input double   MinEMADistancePoints     = 2.0;
input double   PullbackATRMax           = 1.75;
input int      PullbackLookbackBars     = 4;
input int      PullbackMaxBars          = 8;

input int      ReEntryCooldownBars      = 10;
input int      MaxConsecutiveLosses     = 2;

input bool     UseMaxEntryDistance      = false;
input double   MaxEntryDistanceATR      = 0.75;

input bool     UseTrendLegProtection    = false;
input int      MaxEntriesPerTrendLeg    = 2;
input double   TrendResetATR            = 0.25;

input bool     BlockDeepRSIChase        = true;
input double   DeepBullRSI              = 65.0;
input double   DeepBearRSI              = 35.0;

input bool     AllowEMA20CrossTrigger   = true;
input bool     AllowEMAReclaimTrigger   = true;
input bool     AllowMomentumTrigger     = true;
input bool     RequireTriggerCandle     = false;

input double   RiskPercent              = 1.0;
input double   MaxDailyLossPercent      = 3.0;
input int      MaxTradesPerDay          = 5;
input int      MagicNumber              = 1001;

input double   ATR_SL_Multiplier        = 2.0;
input double   ATR_TP_Multiplier        = 3.0;
input int      MinimumSLPoints          = 100;
input int      MinimumTPPoints          = 150;

// v5.65 protected management.
input bool     UseBreakEven             = true;
input double   BreakEvenATR             = 1.00;
input double   BreakEvenPlusPoints      = 3.0;
input bool     UseProtectedProfit       = true;
input double   ProtectedProfitATR       = 1.50;
input double   ProtectedProfitATRLock   = 0.25;
input bool     UseTrailingStop          = true;
input double   TrailingATR              = 1.25;
input double   TrailingStartATR         = 2.00;
input double   TrailingStepPoints      = 25.0;
input bool     TrailOnlyOnNewM1Bar      = false;

input bool     DebugMode                = true;
input bool     LogFilterBlocks          = true;
input bool     LogOnlyFilterChange      = true;

//============================== GLOBALS =============================
datetime LastBar=0;
datetime LastManagementBar=0;
datetime LastClosedTradeTime=0;
int TradeDay=-1;
int TradesToday=0;
double DayStartBalance=0.0;
int ConsecutiveLosses=0;

bool IndicatorsReady=false;
bool TradingHoursOK=true;
bool SpreadOK=false;
double CurrentSpread=0.0;

double EMA20_H4,EMA50_H4,EMA20_H1,EMA50_H1;
double EMA20_M15,EMA50_M15,EMA20_M5,EMA50_M5;
double EMA20_M1,EMA50_M1;
double EMA20_H4_Prev,EMA20_H1_Prev,EMA20_M15_Prev,EMA20_M5_Prev;
double RSI_M15,ATR_M15,ADX_M15;
long Volume_M15;
double TrendScore,EntryScore;

bool IsH4Bull,IsH4Bear,IsH1Bull,IsH1Bear;
bool IsM15Bull,IsM15Bear,IsM5Bull,IsM5Bear;
bool IsM1Bull,IsM1Bear;

int BullPullbackAge=0,BearPullbackAge=0;
bool RecentBullCross=false,RecentBearCross=false;

int TrendLegDirection=0;
int EntriesThisTrendLeg=0;
bool BullTrendReset=false,BearTrendReset=false;

//============================== INIT ================================
int OnInit()
{
   ResetDailyCounters();
   LastBar=0;
   LastManagementBar=0;
   Print("====================================================");
   Print("T100 Trend Rider v5.65 STARTED");
   Print("Combined adaptive MTF trend/pullback + protected trailing");
   Print("SAST session filter + risk sizing + cooldown + loss guard");
   Print("====================================================");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Comment("");
   Print("T100 Trend Rider v5.65 stopped. reason=",reason);
}

//============================== MAIN ================================
void OnTick()
{
   ManageOpenTrades();

   if(!IsNewBar())
      return;

   UpdateDailyCounters();
   UpdateClosedTradeState();
   CheckTradingHours();
   CheckSpread();

   if(!UpdateIndicators())
      return;

   if(!MarketReady())
   {
      LogMarketFilterBlock();
      return;
   }

   CalculateTrend();
   UpdateTrendLegState();
   UpdatePullbackState();
   CalculateEntryScore();

   if(!EntryGuardsOK())
   {
      LogEntryGuardBlock();
      return;
   }

   if(DebugMode)
      PrintStatus();

   if(EntryReady())
      OpenTrade();
}

//============================== BAR =================================
bool IsNewBar()
{
   datetime t=iTime(Symbol(),PERIOD_M1,0);
   if(t<=0) return(false);
   if(t!=LastBar)
   {
      LastBar=t;
      return(true);
   }
   return(false);
}

//============================== HISTORY =============================
bool HistoryReadyTF(int tf)
{
   int required=SlowEMA+10;
   if(iBars(Symbol(),tf)<required) return(false);
   if(iTime(Symbol(),tf,SlowEMA+2)<=0) return(false);
   if(iTime(Symbol(),tf,2)<=0) return(false);
   return(true);
}

bool ValidIndicator(double v)
{
   return(v!=EMPTY_VALUE && v>0.0);
}

bool UpdateIndicators()
{
   IndicatorsReady=false;

   if(!HistoryReadyTF(PERIOD_H4) ||
      !HistoryReadyTF(PERIOD_H1) ||
      !HistoryReadyTF(PERIOD_M15) ||
      !HistoryReadyTF(PERIOD_M5) ||
      !HistoryReadyTF(PERIOD_M1))
      return(false);

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
      !ValidIndicator(RSI_M15)||!ValidIndicator(ATR_M15)||
      !ValidIndicator(ADX_M15))
      return(false);

   IndicatorsReady=true;
   return(true);
}

//============================== SAST ================================
datetime SASTNow()
{
   return(TimeCurrent()+(SASTUTCOffsetHours-BrokerUTCOffsetHours)*3600);
}

int SASTHour()
{
   return(TimeHour(SASTNow()));
}

int SASTDayOfYear()
{
   return(TimeDayOfYear(SASTNow()));
}

void CheckTradingHours()
{
   if(!UseTradingHours)
   {
      TradingHoursOK=true;
      return;
   }

   int h=SASTHour();

   if(TradingStartHour==TradingEndHour)
      TradingHoursOK=true;
   else if(TradingStartHour<TradingEndHour)
      TradingHoursOK=(h>=TradingStartHour && h<TradingEndHour);
   else
      TradingHoursOK=(h>=TradingStartHour || h<TradingEndHour);
}

void CheckSpread()
{
   CurrentSpread=MarketInfo(Symbol(),MODE_SPREAD);
   SpreadOK=(CurrentSpread>=0 && CurrentSpread<=MaxSpread);
}

//============================== FILTERS =============================
bool ATR_OK()
{
   if(MinATRPoints<=0.0) return(true);
   return((ATR_M15/Point)>=MinATRPoints);
}

bool Volume_OK()
{
   if(MinVolume<=0) return(true);
   return(Volume_M15>=MinVolume);
}

bool ADX_OK()
{
   if(MinADX<=0.0) return(true);
   return(ADX_M15>=MinADX);
}

bool DailyRiskOK()
{
   if(MaxDailyLossPercent<=0.0 || DayStartBalance<=0.0)
      return(true);

   double loss=100.0*(DayStartBalance-AccountEquity())/DayStartBalance;
   return(loss<MaxDailyLossPercent);
}

bool MarketReady()
{
   return(IndicatorsReady &&
          TradingHoursOK &&
          SpreadOK &&
          ATR_OK() &&
          Volume_OK() &&
          ADX_OK());
}

bool EntryGuardsOK()
{
   if(!DailyRiskOK()) return(false);
   if(MaxTradesPerDay>0 && TradesToday>=MaxTradesPerDay) return(false);
   if(!EntryCooldownOK()) return(false);
   if(!LossLimitOK()) return(false);
   return(true);
}

void LogMarketFilterBlock()
{
   static string lastReason="";
   string reason="UNKNOWN";

   if(!IndicatorsReady) reason="INDICATORS_NOT_READY";
   else if(!TradingHoursOK) reason="TRADING_HOURS";
   else if(!SpreadOK) reason="SPREAD";
   else if(!ATR_OK()) reason="ATR";
   else if(!Volume_OK()) reason="VOLUME";
   else if(!ADX_OK()) reason="ADX";

   bool log=DebugMode && LogFilterBlocks;
   if(LogOnlyFilterChange) log=log && reason!=lastReason;

   if(log)
      Print("MARKET FILTER BLOCKED: ",reason,
            " spread=",DoubleToString(CurrentSpread,1),
            " atrPts=",DoubleToString(ATR_M15/Point,1),
            " adx=",DoubleToString(ADX_M15,1),
            " vol=",Volume_M15);

   lastReason=reason;
}

void LogEntryGuardBlock()
{
   static string lastReason="";
   string reason="UNKNOWN";

   if(!DailyRiskOK()) reason="DAILY_LOSS_LIMIT";
   else if(MaxTradesPerDay>0 && TradesToday>=MaxTradesPerDay) reason="MAX_TRADES";
   else if(!EntryCooldownOK()) reason="COOLDOWN";
   else if(!LossLimitOK()) reason="CONSECUTIVE_LOSS";

   bool log=DebugMode && LogFilterBlocks;
   if(LogOnlyFilterChange) log=log && reason!=lastReason;

   if(log) Print("ENTRY GUARD BLOCKED: ",reason);
   lastReason=reason;
}

//============================== TREND ===============================
int Direction(double f,double s)
{
   if(f>s) return(1);
   if(f<s) return(-1);
   return(0);
}

int SlopeDirection(double n,double p)
{
   double eps=Point*0.25;
   if(n>p+eps) return(1);
   if(n<p-eps) return(-1);
   return(0);
}

void CalculateTrend()
{
   IsH4Bull=EMA20_H4>EMA50_H4;
   IsH4Bear=EMA20_H4<EMA50_H4;
   IsH1Bull=EMA20_H1>EMA50_H1;
   IsH1Bear=EMA20_H1<EMA50_H1;
   IsM15Bull=EMA20_M15>EMA50_M15;
   IsM15Bear=EMA20_M15<EMA50_M15;
   IsM5Bull=EMA20_M5>EMA50_M5;
   IsM5Bear=EMA20_M5<EMA50_M5;

   TrendScore=0;
   TrendScore+=30*Direction(EMA20_H4,EMA50_H4);
   TrendScore+=25*Direction(EMA20_H1,EMA50_H1);
   TrendScore+=20*Direction(EMA20_M15,EMA50_M15);
   TrendScore+=15*Direction(EMA20_M5,EMA50_M5);

   TrendScore+=5*SlopeDirection(EMA20_H4,EMA20_H4_Prev);
   TrendScore+=4*SlopeDirection(EMA20_H1,EMA20_H1_Prev);
   TrendScore+=3*SlopeDirection(EMA20_M15,EMA20_M15_Prev);
   TrendScore+=2*SlopeDirection(EMA20_M5,EMA20_M5_Prev);

   if(ADX_M15>=30.0)
   {
      if(IsM15Bull) TrendScore+=5;
      if(IsM15Bear) TrendScore-=5;
   }
}

bool BullRegime(){return(TrendScore>=MinimumTrendScore);}
bool BearRegime(){return(TrendScore<=-MinimumTrendScore);}

//============================== M1 TRIGGERS =========================
bool BullCross()
{
   double f2=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double s2=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double f1=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double s1=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   return(f2<=s2 && f1>s1);
}

bool BearCross()
{
   double f2=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double s2=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double f1=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double s1=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   return(f2>=s2 && f1<s1);
}

bool BullReclaim()
{
   double o=iOpen(Symbol(),PERIOD_M1,1),c=iClose(Symbol(),PERIOD_M1,1);
   double h=iHigh(Symbol(),PERIOD_M1,1),l=iLow(Symbol(),PERIOD_M1,1);
   double e=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   return(l<=e && c>e && c>o && h>l);
}

bool BearReclaim()
{
   double o=iOpen(Symbol(),PERIOD_M1,1),c=iClose(Symbol(),PERIOD_M1,1);
   double h=iHigh(Symbol(),PERIOD_M1,1),l=iLow(Symbol(),PERIOD_M1,1);
   double e=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   return(h>=e && c<e && c<o && h>l);
}

bool BullMomentum()
{
   double c1=iClose(Symbol(),PERIOD_M1,1);
   double c2=iClose(Symbol(),PERIOD_M1,2);
   double e=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   return(c1>c2 && c1>e);
}

bool BearMomentum()
{
   double c1=iClose(Symbol(),PERIOD_M1,1);
   double c2=iClose(Symbol(),PERIOD_M1,2);
   double e=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   return(c1<c2 && c1<e);
}

bool BullCandleOK()
{
   return(iClose(Symbol(),PERIOD_M1,1)>iOpen(Symbol(),PERIOD_M1,1) ||
          iClose(Symbol(),PERIOD_M1,1)>iClose(Symbol(),PERIOD_M1,2));
}

bool BearCandleOK()
{
   return(iClose(Symbol(),PERIOD_M1,1)<iOpen(Symbol(),PERIOD_M1,1) ||
          iClose(Symbol(),PERIOD_M1,1)<iClose(Symbol(),PERIOD_M1,2));
}

//============================== PULLBACK ===========================
bool BullPullback()
{
   if(!BullRegime()) return(false);

   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);
   if(atr<=0) return(false);

   int look=MathMax(1,PullbackLookbackBars);
   double maxDist=atr*PullbackATRMax;
   bool touch=false,above=false;

   for(int sh=1;sh<=look;sh++)
   {
      double e20=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,sh);
      double e50=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,sh);
      double c=iClose(Symbol(),PERIOD_M1,sh);
      double l=iLow(Symbol(),PERIOD_M1,sh);

      if(MathAbs(c-e20)<=maxDist || MathAbs(l-e20)<=maxDist) touch=true;
      if(c>e20 || c>e50) above=true;
   }

   double e=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double c=iClose(Symbol(),PERIOD_M1,1);
   double o=iOpen(Symbol(),PERIOD_M1,1);
   double l=iLow(Symbol(),PERIOD_M1,1);

   return((l<=e && c>e && c>=o) || (touch && c>e && above));
}

bool BearPullback()
{
   if(!BearRegime()) return(false);

   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);
   if(atr<=0) return(false);

   int look=MathMax(1,PullbackLookbackBars);
   double maxDist=atr*PullbackATRMax;
   bool touch=false,below=false;

   for(int sh=1;sh<=look;sh++)
   {
      double e20=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,sh);
      double e50=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,sh);
      double c=iClose(Symbol(),PERIOD_M1,sh);
      double h=iHigh(Symbol(),PERIOD_M1,sh);

      if(MathAbs(c-e20)<=maxDist || MathAbs(h-e20)<=maxDist) touch=true;
      if(c<e20 || c<e50) below=true;
   }

   double e=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double c=iClose(Symbol(),PERIOD_M1,1);
   double o=iOpen(Symbol(),PERIOD_M1,1);
   double h=iHigh(Symbol(),PERIOD_M1,1);

   return((h>=e && c<e && c<=o) || (touch && c<e && below));
}

bool EntryDistanceOK(bool bullish)
{
   if(!UseMaxEntryDistance || MaxEntryDistanceATR<=0) return(true);

   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);
   if(atr<=0) return(false);

   double e=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double price=bullish?Ask:Bid;
   return(MathAbs(price-e)<=atr*MaxEntryDistanceATR);
}

void UpdatePullbackState()
{
   bool bp=BullPullback();
   bool sp=BearPullback();

   if(!BullRegime()) BullPullbackAge=0;
   if(!BearRegime()) BearPullbackAge=0;

   if(bp)
   {
      BullPullbackAge=1;
      BearPullbackAge=0;
   }
   else if(BullPullbackAge>0)
   {
      BullPullbackAge++;
      if(PullbackMaxBars>0 && BullPullbackAge>PullbackMaxBars)
         BullPullbackAge=0;
   }

   if(sp)
   {
      BearPullbackAge=1;
      BullPullbackAge=0;
   }
   else if(BearPullbackAge>0)
   {
      BearPullbackAge++;
      if(PullbackMaxBars>0 && BearPullbackAge>PullbackMaxBars)
         BearPullbackAge=0;
   }

   RecentBullCross=BullCross();
   RecentBearCross=BearCross();
}

bool BullPullbackArmed()
{
   return(BullRegime() && BullPullbackAge>0 &&
          (PullbackMaxBars<=0 || BullPullbackAge<=PullbackMaxBars));
}

bool BearPullbackArmed()
{
   return(BearRegime() && BearPullbackAge>0 &&
          (PullbackMaxBars<=0 || BearPullbackAge<=PullbackMaxBars));
}

//============================== TREND LEG ===========================
void UpdateTrendLegState()
{
   if(!UseTrendLegProtection) return;

   int dir=0;
   if(BullRegime()) dir=1;
   else if(BearRegime()) dir=-1;

   if(dir!=TrendLegDirection)
   {
      TrendLegDirection=dir;
      EntriesThisTrendLeg=0;
      BullTrendReset=(dir!=1);
      BearTrendReset=(dir!=-1);
   }

   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);
   if(atr<=0) return;

   double e=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double c=iClose(Symbol(),PERIOD_M1,1);

   if(dir==1 && c<e-atr*TrendResetATR) BullTrendReset=true;
   if(dir==-1 && c>e+atr*TrendResetATR) BearTrendReset=true;
}

bool TrendLegEntryOK(bool bullish)
{
   if(!UseTrendLegProtection || MaxEntriesPerTrendLeg<=0) return(true);
   if(EntriesThisTrendLeg<MaxEntriesPerTrendLeg) return(true);
   return(bullish?BullTrendReset:BearTrendReset);
}

//============================== SCORE ===============================
bool EMADistanceOK()
{
   return(MathAbs(EMA20_M15-EMA50_M15)/Point>=MinEMADistancePoints);
}

bool DeepRSIChaseBlocked(bool bull,bool bear)
{
   if(!BlockDeepRSIChase) return(false);
   if(bull && RSI_M15>=DeepBullRSI) return(true);
   if(bear && RSI_M15<=DeepBearRSI) return(true);
   return(false);
}

void CalculateEntryScore()
{
   EntryScore=0;
   IsM1Bull=false;
   IsM1Bear=false;

   bool bull=BullRegime();
   bool bear=BearRegime();
   bool bp=BullPullbackArmed();
   bool sp=BearPullbackArmed();

   bool bc=AllowEMA20CrossTrigger && RecentBullCross;
   bool sc=AllowEMA20CrossTrigger && RecentBearCross;
   bool br=AllowEMAReclaimTrigger && BullReclaim();
   bool sr=AllowEMAReclaimTrigger && BearReclaim();
   bool bm=AllowMomentumTrigger && BullMomentum();
   bool sm=AllowMomentumTrigger && BearMomentum();

   if(bull) EntryScore+=30;
   if(bear) EntryScore-=30;

   if(bull && RSI_M15>=BullRSI) EntryScore+=10;
   if(bear && RSI_M15<=BearRSI) EntryScore-=10;

   if(ADX_M15>=30.0)
   {
      if(bull) EntryScore+=8;
      if(bear) EntryScore-=8;
   }

   if(EMADistanceOK())
   {
      if(bull) EntryScore+=7;
      if(bear) EntryScore-=7;
   }

   if(bp) EntryScore+=20;
   if(sp) EntryScore-=20;

   int bullTrigger=bc?20:(br?16:(bm?12:0));
   int bearTrigger=sc?20:(sr?16:(sm?12:0));

   if(bull) EntryScore+=bullTrigger;
   if(bear) EntryScore-=bearTrigger;

   // v5.65: deep RSI chase is a HARD directional entry block.
   bool deepBull=DeepRSIChaseBlocked(bull,false);
   bool deepBear=DeepRSIChaseBlocked(false,bear);

   bool bullCandle=!RequireTriggerCandle || BullCandleOK();
   bool bearCandle=!RequireTriggerCandle || BearCandleOK();

   IsM1Bull=bull && bp && bullTrigger>0 && bullCandle &&
            !deepBull &&
            EntryScore>=MinimumTriggerScore &&
            EntryDistanceOK(true) &&
            TrendLegEntryOK(true);

   IsM1Bear=bear && sp && bearTrigger>0 && bearCandle &&
            !deepBear &&
            EntryScore<=-MinimumTriggerScore &&
            EntryDistanceOK(false) &&
            TrendLegEntryOK(false);
}

//============================== GUARDS ==============================
bool EntryCooldownOK()
{
   if(ReEntryCooldownBars<=0 || LastClosedTradeTime<=0) return(true);

   int bars=iBarShift(Symbol(),PERIOD_M1,LastClosedTradeTime,false);
   if(bars<0) return(true);
   return(bars>=ReEntryCooldownBars);
}

bool LossLimitOK()
{
   if(MaxConsecutiveLosses<=0) return(true);
   return(ConsecutiveLosses<MaxConsecutiveLosses);
}

bool EntryReady()
{
   if(PositionExists()) return(false);
   if(!DailyRiskOK()) return(false);
   if(MaxTradesPerDay>0 && TradesToday>=MaxTradesPerDay) return(false);
   if(!EntryCooldownOK() || !LossLimitOK()) return(false);
   return(IsM1Bull || IsM1Bear);
}

bool PositionExists()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      if(OrderType()==OP_BUY || OrderType()==OP_SELL) return(true);
   }
   return(false);
}

//============================== LOT SIZE ============================
double CalculateLot(double stopDistancePrice)
{
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
   double tickSize=MarketInfo(Symbol(),MODE_TICKSIZE);

   if(step<=0) step=0.01;
   if(RiskPercent<=0 || tickValue<=0 || tickSize<=0 || stopDistancePrice<=0)
      return(minLot);

   double riskMoney=AccountBalance()*RiskPercent/100.0;
   double lossPerLot=(stopDistancePrice/tickSize)*tickValue;
   if(lossPerLot<=0) return(minLot);

   double lots=riskMoney/lossPerLot;
   lots=MathFloor(lots/step)*step;
   lots=MathMax(minLot,lots);
   lots=MathMin(maxLot,lots);

   int digits=2;
   if(step>=1.0) digits=0;
   else if(step>=0.1) digits=1;

   return(NormalizeDouble(lots,digits));
}

//============================== OPEN ================================
void OpenTrade()
{
   if(PositionExists()) return;

   RefreshRates();

   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);
   if(atr<=0) atr=ATR_M15;
   if(atr<=0) return;

   double slDistance=MathMax(atr*ATR_SL_Multiplier,MinimumSLPoints*Point);
   double tpDistance=MathMax(atr*ATR_TP_Multiplier,MinimumTPPoints*Point);
   double stopLevel=(MarketInfo(Symbol(),MODE_STOPLEVEL)+2)*Point;

   slDistance=MathMax(slDistance,stopLevel);
   tpDistance=MathMax(tpDistance,stopLevel);

   double lots=CalculateLot(slDistance);
   if(lots<=0) return;

   int type=-1;
   double price,sl,tp;

   if(IsM1Bull)
   {
      type=OP_BUY;
      price=Ask;
      sl=NormalizeDouble(price-slDistance,Digits);
      tp=NormalizeDouble(price+tpDistance,Digits);
   }
   else if(IsM1Bear)
   {
      type=OP_SELL;
      price=Bid;
      sl=NormalizeDouble(price+slDistance,Digits);
      tp=NormalizeDouble(price-tpDistance,Digits);
   }
   else return;

   ResetLastError();

   int ticket=OrderSend(Symbol(),type,lots,price,10,sl,tp,
                        "T100 Trend Rider v5.65",
                        MagicNumber,0,type==OP_BUY?clrBlue:clrRed);

   if(ticket<0)
   {
      Print("ORDER SEND FAILED error=",GetLastError(),
            " type=",type," lots=",DoubleToString(lots,2),
            " price=",DoubleToString(price,Digits),
            " SL=",DoubleToString(sl,Digits),
            " TP=",DoubleToString(tp,Digits));
      return;
   }

   TradesToday++;

   if(UseTrendLegProtection)
   {
      EntriesThisTrendLeg++;
      if(IsM1Bull) BullTrendReset=false;
      if(IsM1Bear) BearTrendReset=false;
   }

   Print("TRADE OPENED v5.65 ticket=",ticket,
         " direction=",type==OP_BUY?"BUY":"SELL",
         " lots=",DoubleToString(lots,2),
         " TrendScore=",DoubleToString(TrendScore,0),
         " EntryScore=",DoubleToString(EntryScore,0));
}

//============================== MANAGEMENT =========================
bool ModifySL(int ticket,double open,double newSL,double tp)
{
   ResetLastError();

   if(!OrderModify(ticket,open,newSL,tp,0,clrNONE))
   {
      Print("OrderModify failed ticket=",ticket,
            " error=",GetLastError(),
            " requestedSL=",DoubleToString(newSL,Digits));
      return(false);
   }
   return(true);
}

void ManageOpenTrades()
{
   RefreshRates();

   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);
   if(atr<=0) atr=iATR(Symbol(),PERIOD_M15,ATRPeriod,1);
   if(atr<=0) return;

   datetime bar=iTime(Symbol(),PERIOD_M1,0);
   bool allowTrail=true;

   if(TrailOnlyOnNewM1Bar)
   {
      allowTrail=(bar!=LastManagementBar);
      if(allowTrail) LastManagementBar=bar;
   }

   double pointStep=MathMax(TrailingStepPoints,1.0)*Point;
   double stopLevel=(MarketInfo(Symbol(),MODE_STOPLEVEL)+2)*Point;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;

      int ticket=OrderTicket();
      double open=OrderOpenPrice();
      double currentSL=OrderStopLoss();
      double newSL=currentSL;
      bool candidate=false;

      if(OrderType()==OP_BUY)
      {
         double profit=Bid-open;

         // Stage 1: ordinary break-even.
         if(UseBreakEven && profit>=atr*BreakEvenATR)
         {
            double be=NormalizeDouble(open+BreakEvenPlusPoints*Point,Digits);
            if(currentSL==0 || be>newSL)
            {
               newSL=be;
               candidate=true;
            }
         }

         // Stage 2: protected profit, but not so early that M1 noise
         // immediately creates a near-zero exit.
         if(UseProtectedProfit && profit>=atr*ProtectedProfitATR)
         {
            double lock=NormalizeDouble(open+atr*ProtectedProfitATRLock,Digits);
            if(lock>newSL)
            {
               newSL=lock;
               candidate=true;
            }
         }

         // Stage 3: ATR trailing.
         if(UseTrailingStop && allowTrail && profit>=atr*TrailingStartATR)
         {
            double trail=NormalizeDouble(Bid-atr*TrailingATR,Digits);
            if(trail>newSL && trail>open)
            {
               newSL=trail;
               candidate=true;
            }
         }

         double maxSL=NormalizeDouble(Bid-stopLevel,Digits);
         if(newSL>maxSL) newSL=maxSL;
         newSL=NormalizeDouble(newSL,Digits);

         if(candidate && newSL>currentSL && newSL<Bid &&
            (currentSL==0 || newSL-currentSL>=pointStep))
            ModifySL(ticket,open,newSL,OrderTakeProfit());
      }
      else
      {
         double profit=open-Ask;

         if(UseBreakEven && profit>=atr*BreakEvenATR)
         {
            double be=NormalizeDouble(open-BreakEvenPlusPoints*Point,Digits);
            if(currentSL==0 || be<newSL)
            {
               newSL=be;
               candidate=true;
            }
         }

         if(UseProtectedProfit && profit>=atr*ProtectedProfitATR)
         {
            double lock=NormalizeDouble(open-atr*ProtectedProfitATRLock,Digits);
            if(newSL==0 || lock<newSL)
            {
               newSL=lock;
               candidate=true;
            }
         }

         if(UseTrailingStop && allowTrail && profit>=atr*TrailingStartATR)
         {
            double trail=NormalizeDouble(Ask+atr*TrailingATR,Digits);
            if((newSL==0 || trail<newSL) && trail<open)
            {
               newSL=trail;
               candidate=true;
            }
         }

         double minSL=NormalizeDouble(Ask+stopLevel,Digits);
         if(newSL>0 && newSL<minSL) newSL=minSL;
         newSL=NormalizeDouble(newSL,Digits);

         if(candidate && (currentSL==0 || newSL<currentSL) &&
            newSL>Ask &&
            (currentSL==0 || currentSL-newSL>=pointStep))
            ModifySL(ticket,open,newSL,OrderTakeProfit());
      }
   }
}

//============================== DAILY ===============================
void ResetDailyCounters()
{
   TradeDay=SASTDayOfYear();
   DayStartBalance=AccountBalance();
   TradesToday=0;
   ConsecutiveLosses=0;
   LastManagementBar=0;
}

void UpdateDailyCounters()
{
   int d=SASTDayOfYear();
   if(d!=TradeDay)
      ResetDailyCounters();
}

//============================== CLOSED HISTORY =====================
void UpdateClosedTradeState()
{
   static int lastHistoryTotal=-1;
   static bool historyInitialized=false;

   int total=OrdersHistoryTotal();
   if(total==lastHistoryTotal) return;
   lastHistoryTotal=total;

   datetime newest=0;
   double newestNet=0.0;

   for(int i=total-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;

      if(OrderCloseTime()>newest)
      {
         newest=OrderCloseTime();
         newestNet=OrderProfit()+OrderSwap()+OrderCommission();
      }
   }

   if(!historyInitialized)
   {
      if(newest>0) LastClosedTradeTime=newest;
      ConsecutiveLosses=0;
      historyInitialized=true;
      return;
   }

   if(newest>LastClosedTradeTime)
   {
      LastClosedTradeTime=newest;

      if(newestNet<0.0)
         ConsecutiveLosses++;
      else if(newestNet>0.0)
         ConsecutiveLosses=0;
   }
}

//============================== DEBUG ===============================
void PrintStatus()
{
   Print("T100 v5.65 | SASTHour=",SASTHour(),
         " HoursOK=",TradingHoursOK,
         " Spread=",DoubleToString(CurrentSpread,1),
         " Trend=",DoubleToString(TrendScore,0),
         " Entry=",DoubleToString(EntryScore,0),
         " BullPB=",BullPullbackAge,
         " BearPB=",BearPullbackAge,
         " Bull=",IsM1Bull,
         " Bear=",IsM1Bear,
         " Trades=",TradesToday,
         " LossStreak=",ConsecutiveLosses);
}
//+------------------------------------------------------------------+
//| END                                                              |
//+------------------------------------------------------------------+
