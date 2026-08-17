//+------------------------------------------------------------------+
//|                 T100_Trend_Rider_v5_67_Adaptive.mq4              |
//|                 T100 Trend Rider - Version 5.67                  |
//|  MTF trend score + pullback/reclaim entry + SAST session filter |
//|  Adaptive ATR exits + protected profit + loss containment        |
//|  MT4 / MQL4 - #property strict                                   |
//+------------------------------------------------------------------+
#property strict
#property version   "5.67"
#property description "T100 Trend Rider v5.67 - Adaptive MTF + SAST + asymmetric protected exits"

//==================================================================
// INPUTS
//==================================================================
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

// SAST session. 09:00-18:00 is the default daytime window.
// Set start=end to allow 24 hours.
input bool     UseTradingHours          = true;
input int      TradingStartHour         = 9;
input int      TradingEndHour           = 18;
input int      BrokerUTCOffsetHours     = 2;
input int      SASTUTCOffsetHours       = 2;

// Trend / trigger scoring.
input int      MinimumTrendScore        = 30;
input int      MinimumTriggerScore      = 50;
input double   MinEMADistancePoints     = 2.0;

input double   PullbackATRMax           = 1.50;
input int      PullbackLookbackBars     = 4;
input int      PullbackMaxBars          = 8;

// Entry protection.
input int      ReEntryCooldownBars      = 12;
input int      MaxConsecutiveLosses     = 2;

input bool     UseMaxEntryDistance      = true;
input double   MaxEntryDistanceATR      = 1.00;

input bool     UseTrendLegProtection    = true;
input int      MaxEntriesPerTrendLeg    = 2;
input double   TrendResetATR            = 0.25;

input bool     BlockDeepRSIChase        = true;
input double   DeepBullRSI              = 68.0;
input double   DeepBearRSI              = 32.0;

// Trigger types.
input bool     AllowEMA20CrossTrigger   = true;
input bool     AllowEMAReclaimTrigger   = true;
input bool     AllowMomentumTrigger     = true;
input bool     RequireTriggerCandle     = true;

// M5/M1 alignment and candle quality.
input bool     RequireM5Alignment       = true;
input bool     RequireM1EMA50Side        = true;
input bool     UseTriggerCandleQuality   = true;
input double   MinTriggerBodyATR        = 0.15;
input double   BullCloseLocationMin     = 0.60;
input double   BearCloseLocationMax     = 0.40;

// RSI quality window.
input bool     UseRSIQualityWindow      = true;
input double   BullRSIMax               = 68.0;
input double   BearRSIMin               = 32.0;

// Risk / limits.
input double   RiskPercent              = 0.75;
input double   MaxDailyLossPercent      = 3.0;
input int      MaxTradesPerDay          = 5;
input int      MagicNumber              = 1001;

// Asymmetric adaptive stops.
// V5.6.6 still produced average losses near $97 while average wins
// were only ~$44. V5.6.7 therefore reduces initial stop distance
// and delays aggressive trailing so winners have room to develop.
input double   ATR_SL_Multiplier        = 1.60;
input double   ATR_TP_Multiplier        = 3.00;
input int      MinimumSLPoints          = 100;
input int      MinimumTPPoints          = 150;

// Protected exit management.
input bool     UseBreakEven             = true;
input double   BreakEvenATR             = 0.90;
input double   BreakEvenPlusPoints      = 3.0;

input bool     UseProtectedProfit       = true;
input double   ProtectedProfitATR       = 1.30;
input double   ProtectedProfitATRLock   = 0.25;

input bool     UseTrailingStop          = true;
input double   TrailingATR              = 1.10;
input double   TrailingStartATR         = 1.80;
input double   TrailingStepPoints       = 25.0;
input bool     TrailOnlyOnNewM1Bar      = false;

// Debug.
input bool     DebugMode                = true;
input bool     LogFilterBlocks          = true;
input bool     LogOnlyFilterChange      = true;

//==================================================================
// GLOBALS
//==================================================================
datetime LastBar                 = 0;
datetime LastManagementBar       = 0;
datetime LastClosedTradeTime     = 0;

int      TradeDay                = -1;
int      TradesToday             = 0;
int      ConsecutiveLosses       = 0;
double   DayStartBalance         = 0.0;

bool     IndicatorsReady         = false;
bool     TradingHoursOK          = true;
bool     SpreadOK                = false;
double   CurrentSpread           = 0.0;

double EMA20_H4=0, EMA50_H4=0;
double EMA20_H1=0, EMA50_H1=0;
double EMA20_M15=0, EMA50_M15=0;
double EMA20_M5=0, EMA50_M5=0;
double EMA20_M1=0, EMA50_M1=0;

double EMA20_H4_Prev=0;
double EMA20_H1_Prev=0;
double EMA20_M15_Prev=0;
double EMA20_M5_Prev=0;

double RSI_M15=0;
double ATR_M15=0;
double ADX_M15=0;
long   Volume_M15=0;

double TrendScore=0;
double EntryScore=0;

bool IsH4Bull=false, IsH4Bear=false;
bool IsH1Bull=false, IsH1Bear=false;
bool IsM15Bull=false, IsM15Bear=false;
bool IsM5Bull=false, IsM5Bear=false;
bool IsM1Bull=false, IsM1Bear=false;

int  BullPullbackAge=0;
int  BearPullbackAge=0;
bool RecentBullCross=false;
bool RecentBearCross=false;

int  TrendLegDirection=0;
int  EntriesThisTrendLeg=0;
bool BullTrendReset=false;
bool BearTrendReset=false;

string LastFilterBlock="";
string LastGuardBlock="";

//==================================================================
// INITIALIZATION
//==================================================================
int OnInit()
{
   LastBar=0;
   LastManagementBar=0;
   BullPullbackAge=0;
   BearPullbackAge=0;
   RecentBullCross=false;
   RecentBearCross=false;
   TrendLegDirection=0;
   EntriesThisTrendLeg=0;
   BullTrendReset=false;
   BearTrendReset=false;

   ResetDailyCounters();

   Print("====================================================");
   Print("T100 Trend Rider v5.67 STARTED");
   Print("Symbol=",Symbol()," Period=",Period());
   Print("SAST session=",TradingStartHour,":00 -> ",TradingEndHour,":00");
   Print("TrendScore min=",MinimumTrendScore,
         " TriggerScore min=",MinimumTriggerScore);
   Print("Risk=",DoubleToString(RiskPercent,2),"%",
         " SL ATR=",DoubleToString(ATR_SL_Multiplier,2),
         " TP ATR=",DoubleToString(ATR_TP_Multiplier,2));
   Print("Protected exits enabled=",UseProtectedProfit,
         " trailing=",UseTrailingStop);
   Print("====================================================");

   return(INIT_SUCCEEDED);
}

//==================================================================
// DEINITIALIZATION
//==================================================================
void OnDeinit(const int reason)
{
   Comment("");
   Print("T100 Trend Rider v5.67 stopped.");
}

//==================================================================
// MAIN LOOP
//==================================================================
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
   {
      LogBlock("INDICATORS","indicator history/data not ready");
      return;
   }

   if(!MarketReady())
      return;

   CalculateTrend();
   UpdateTrendLegState();
   UpdatePullbackState();
   CalculateEntryScore();

   if(!EntryGuardsOK())
      return;

   if(DebugMode)
      PrintStatus();

   if(EntryReady())
      OpenTrade();
   else if(DebugMode)
      Print("ENTRY NOT READY: TrendScore=",DoubleToString(TrendScore,0),
            " EntryScore=",DoubleToString(EntryScore,0));
}

//==================================================================
// NEW BAR
//==================================================================
bool IsNewBar()
{
   datetime t=iTime(Symbol(),PERIOD_M1,0);

   if(t<=0)
      return(false);

   if(t!=LastBar)
   {
      LastBar=t;
      return(true);
   }

   return(false);
}

//==================================================================
// HISTORY / INDICATORS
//==================================================================
bool HistoryReadyTF(int tf)
{
   int requiredBars=SlowEMA+15;

   if(iBars(Symbol(),tf)<requiredBars)
      return(false);

   if(iTime(Symbol(),tf,SlowEMA+2)<=0)
      return(false);

   if(iTime(Symbol(),tf,2)<=0)
      return(false);

   return(true);
}

bool ValidIndicator(double value)
{
   return(value!=EMPTY_VALUE && value>0.0);
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

   if(!ValidIndicator(EMA20_H4) || !ValidIndicator(EMA50_H4) ||
      !ValidIndicator(EMA20_H1) || !ValidIndicator(EMA50_H1) ||
      !ValidIndicator(EMA20_M15) || !ValidIndicator(EMA50_M15) ||
      !ValidIndicator(EMA20_M5) || !ValidIndicator(EMA50_M5) ||
      !ValidIndicator(EMA20_M1) || !ValidIndicator(EMA50_M1) ||
      !ValidIndicator(RSI_M15) || !ValidIndicator(ATR_M15) ||
      !ValidIndicator(ADX_M15))
      return(false);

   IndicatorsReady=true;
   return(true);
}

//==================================================================
// SAST SESSION
//==================================================================
datetime SASTNow()
{
   return(TimeCurrent()+
          (SASTUTCOffsetHours-BrokerUTCOffsetHours)*3600);
}

int SASTHour()
{
   return(TimeHour(SASTNow()));
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
   {
      TradingHoursOK=true;
      return;
   }

   if(TradingStartHour<TradingEndHour)
      TradingHoursOK=(h>=TradingStartHour && h<TradingEndHour);
   else
      TradingHoursOK=(h>=TradingStartHour || h<TradingEndHour);
}

void CheckSpread()
{
   CurrentSpread=MarketInfo(Symbol(),MODE_SPREAD);
   SpreadOK=(CurrentSpread>=0 && CurrentSpread<=MaxSpread);
}

//==================================================================
// MARKET FILTERS
//==================================================================
bool ATR_OK()
{
   if(MinATRPoints<=0.0)
      return(true);

   return((ATR_M15/Point)>=MinATRPoints);
}

bool Volume_OK()
{
   if(MinVolume<=0)
      return(true);

   return(Volume_M15>=MinVolume);
}

bool ADX_OK()
{
   if(MinADX<=0.0)
      return(true);

   return(ADX_M15>=MinADX);
}

bool DailyRiskOK()
{
   if(MaxDailyLossPercent<=0.0 || DayStartBalance<=0.0)
      return(true);

   double lossPct=100.0*(DayStartBalance-AccountEquity())/DayStartBalance;
   return(lossPct<MaxDailyLossPercent);
}

bool MarketReady()
{
   if(!IndicatorsReady)
   {
      LogBlock("MARKET","indicators not ready");
      return(false);
   }

   if(!TradingHoursOK)
   {
      LogBlock("SESSION","outside SAST trading window");
      return(false);
   }

   if(!SpreadOK)
   {
      LogBlock("SPREAD","spread="+DoubleToString(CurrentSpread,0));
      return(false);
   }

   if(!ATR_OK())
   {
      LogBlock("ATR","ATR below minimum");
      return(false);
   }

   if(!Volume_OK())
   {
      LogBlock("VOLUME","M15 volume below minimum");
      return(false);
   }

   if(!ADX_OK())
   {
      LogBlock("ADX","M15 ADX below minimum");
      return(false);
   }

   return(true);
}

//==================================================================
// TREND
//==================================================================
void CalculateTrend()
{
   IsH4Bull=(EMA20_H4>EMA50_H4);
   IsH4Bear=(EMA20_H4<EMA50_H4);

   IsH1Bull=(EMA20_H1>EMA50_H1);
   IsH1Bear=(EMA20_H1<EMA50_H1);

   IsM15Bull=(EMA20_M15>EMA50_M15);
   IsM15Bear=(EMA20_M15<EMA50_M15);

   IsM5Bull=(EMA20_M5>EMA50_M5);
   IsM5Bear=(EMA20_M5<EMA50_M5);

   IsM1Bull=(EMA20_M1>EMA50_M1);
   IsM1Bear=(EMA20_M1<EMA50_M1);

   TrendScore=0;

   if(IsH4Bull) TrendScore+=30;
   if(IsH4Bear) TrendScore-=30;

   if(IsH1Bull) TrendScore+=25;
   if(IsH1Bear) TrendScore-=25;

   if(IsM15Bull) TrendScore+=20;
   if(IsM15Bear) TrendScore-=20;

   if(IsM5Bull) TrendScore+=15;
   if(IsM5Bear) TrendScore-=15;

   double h4Slope=EMA20_H4-EMA20_H4_Prev;
   double h1Slope=EMA20_H1-EMA20_H1_Prev;
   double m15Slope=EMA20_M15-EMA20_M15_Prev;
   double m5Slope=EMA20_M5-EMA20_M5_Prev;

   if(IsH4Bull && h4Slope>0) TrendScore+=3;
   if(IsH4Bear && h4Slope<0) TrendScore-=3;

   if(IsH1Bull && h1Slope>0) TrendScore+=2;
   if(IsH1Bear && h1Slope<0) TrendScore-=2;

   if(IsM15Bull && m15Slope>0) TrendScore+=2;
   if(IsM15Bear && m15Slope<0) TrendScore-=2;

   if(IsM5Bull && m5Slope>0) TrendScore+=1;
   if(IsM5Bear && m5Slope<0) TrendScore-=1;

   if(ADX_M15>=25.0)
   {
      if(TrendScore>0) TrendScore+=3;
      if(TrendScore<0) TrendScore-=3;
   }
}

bool BullTrend()
{
   return(TrendScore>=MinimumTrendScore);
}

bool BearTrend()
{
   return(TrendScore<=-MinimumTrendScore);
}

//==================================================================
// TREND LEG PROTECTION
//==================================================================
void UpdateTrendLegState()
{
   int direction=0;

   if(BullTrend()) direction=1;
   else if(BearTrend()) direction=-1;

   if(direction==0)
      return;

   if(TrendLegDirection==0)
   {
      TrendLegDirection=direction;
      EntriesThisTrendLeg=0;
      BullTrendReset=false;
      BearTrendReset=false;
      return;
   }

   if(direction!=TrendLegDirection)
   {
      TrendLegDirection=direction;
      EntriesThisTrendLeg=0;
      BullTrendReset=false;
      BearTrendReset=false;
      return;
   }

   // A sufficiently deep pullback away from EMA20/EMA50 resets the leg.
   double resetDistance=TrendResetATR*ATR_M15;

   if(direction>0)
   {
      double close1=iClose(Symbol(),PERIOD_M1,1);
      if(close1<EMA20_M1-resetDistance)
         BullTrendReset=true;

      if(BullTrendReset && close1>EMA20_M1)
      {
         EntriesThisTrendLeg=0;
         BullTrendReset=false;
      }
   }
   else
   {
      double close1=iClose(Symbol(),PERIOD_M1,1);
      if(close1>EMA20_M1+resetDistance)
         BearTrendReset=true;

      if(BearTrendReset && close1<EMA20_M1)
      {
         EntriesThisTrendLeg=0;
         BearTrendReset=false;
      }
   }
}

//==================================================================
// PULLBACK STATE
//==================================================================
bool BullPullbackDetected()
{
   double close1=iClose(Symbol(),PERIOD_M1,1);
   double low1=iLow(Symbol(),PERIOD_M1,1);

   double maxDistance=PullbackATRMax*ATR_M15;

   bool nearEMA=(MathAbs(close1-EMA20_M1)<=maxDistance);
   bool touchedEMA=(low1<=EMA20_M1+maxDistance);

   bool trendStillBull=(EMA20_M15>=EMA50_M15 &&
                        EMA20_M5>=EMA50_M5);

   return(trendStillBull && (nearEMA || touchedEMA));
}

bool BearPullbackDetected()
{
   double close1=iClose(Symbol(),PERIOD_M1,1);
   double high1=iHigh(Symbol(),PERIOD_M1,1);

   double maxDistance=PullbackATRMax*ATR_M15;

   bool nearEMA=(MathAbs(close1-EMA20_M1)<=maxDistance);
   bool touchedEMA=(high1>=EMA20_M1-maxDistance);

   bool trendStillBear=(EMA20_M15<=EMA50_M15 &&
                        EMA20_M5<=EMA50_M5);

   return(trendStillBear && (nearEMA || touchedEMA));
}

void UpdatePullbackState()
{
   RecentBullCross=false;
   RecentBearCross=false;

   if(BullPullbackDetected())
      BullPullbackAge=1;
   else if(BullPullbackAge>0)
      BullPullbackAge++;

   if(BearPullbackDetected())
      BearPullbackAge=1;
   else if(BearPullbackAge>0)
      BearPullbackAge++;

   if(BullPullbackAge>PullbackMaxBars)
      BullPullbackAge=0;

   if(BearPullbackAge>PullbackMaxBars)
      BearPullbackAge=0;

   double f1=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double s1=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double f2=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double s2=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,2);

   RecentBullCross=(f2<=s2 && f1>s1);
   RecentBearCross=(f2>=s2 && f1<s1);
}

//==================================================================
// CANDLE QUALITY
//==================================================================
bool BullTriggerCandleOK()
{
   if(!UseTriggerCandleQuality)
      return(true);

   double o=iOpen(Symbol(),PERIOD_M1,1);
   double c=iClose(Symbol(),PERIOD_M1,1);
   double h=iHigh(Symbol(),PERIOD_M1,1);
   double l=iLow(Symbol(),PERIOD_M1,1);

   double range=h-l;
   if(range<=0.0)
      return(false);

   double body=MathAbs(c-o);

   if(body<(MinTriggerBodyATR*ATR_M15))
      return(false);

   double location=(c-l)/range;

   return(c>o && location>=BullCloseLocationMin);
}

bool BearTriggerCandleOK()
{
   if(!UseTriggerCandleQuality)
      return(true);

   double o=iOpen(Symbol(),PERIOD_M1,1);
   double c=iClose(Symbol(),PERIOD_M1,1);
   double h=iHigh(Symbol(),PERIOD_M1,1);
   double l=iLow(Symbol(),PERIOD_M1,1);

   double range=h-l;
   if(range<=0.0)
      return(false);

   double body=MathAbs(c-o);

   if(body<(MinTriggerBodyATR*ATR_M15))
      return(false);

   double location=(c-l)/range;

   return(c<o && location<=BearCloseLocationMax);
}

//==================================================================
// TRIGGER SCORE
//==================================================================
void CalculateEntryScore()
{
   EntryScore=0;

   double close1=iClose(Symbol(),PERIOD_M1,1);
   double close2=iClose(Symbol(),PERIOD_M1,2);

   bool bull=false;
   bool bear=false;

   if(AllowEMA20CrossTrigger)
   {
      if(RecentBullCross) bull=true;
      if(RecentBearCross) bear=true;
   }

   if(AllowEMAReclaimTrigger)
   {
      if(close2<=EMA20_M1 && close1>EMA20_M1)
         bull=true;

      if(close2>=EMA20_M1 && close1<EMA20_M1)
         bear=true;
   }

   if(AllowMomentumTrigger)
   {
      double move=close1-close2;

      if(move>0 && close1>EMA20_M1)
         bull=true;

      if(move<0 && close1<EMA20_M1)
         bear=true;
   }

   IsM1Bull=bull;
   IsM1Bear=bear;

   if(BullTrend() && IsM1Bull)
   {
      EntryScore+=35;

      if(RecentBullCross) EntryScore+=20;
      if(close1>EMA20_M1) EntryScore+=10;
      if(EMA20_M1>EMA50_M1) EntryScore+=10;

      if(RequireM5Alignment && IsM5Bull)
         EntryScore+=10;

      if(BullTriggerCandleOK())
         EntryScore+=10;
   }

   if(BearTrend() && IsM1Bear)
   {
      EntryScore+=35;

      if(RecentBearCross) EntryScore+=20;
      if(close1<EMA20_M1) EntryScore+=10;
      if(EMA20_M1<EMA50_M1) EntryScore+=10;

      if(RequireM5Alignment && IsM5Bear)
         EntryScore+=10;

      if(BearTriggerCandleOK())
         EntryScore+=10;
   }
}

//==================================================================
// ENTRY FILTERS
//==================================================================
bool M1SideOK(int type)
{
   double close1=iClose(Symbol(),PERIOD_M1,1);

   if(type==OP_BUY)
   {
      if(RequireM1EMA50Side && close1<=EMA50_M1)
         return(false);
      return(true);
   }

   if(type==OP_SELL)
   {
      if(RequireM1EMA50Side && close1>=EMA50_M1)
         return(false);
      return(true);
   }

   return(false);
}

bool RSIQualityOK(int type)
{
   if(!UseRSIQualityWindow)
      return(true);

   if(type==OP_BUY)
      return(RSI_M15>=BullRSI && RSI_M15<=BullRSIMax);

   if(type==OP_SELL)
      return(RSI_M15<=BearRSI && RSI_M15>=BearRSIMin);

   return(false);
}

bool DeepRSIChaseOK(int type)
{
   if(!BlockDeepRSIChase)
      return(true);

   if(type==OP_BUY)
      return(RSI_M15<DeepBullRSI);

   if(type==OP_SELL)
      return(RSI_M15>DeepBearRSI);

   return(false);
}

bool EntryDistanceOK(int type)
{
   if(!UseMaxEntryDistance)
      return(true);

   double price=(type==OP_BUY ? Ask : Bid);
   double distance=MathAbs(price-EMA20_M1);

   return(distance<=MaxEntryDistanceATR*ATR_M15);
}

bool EntryCooldownOK()
{
   if(ReEntryCooldownBars<=0 || LastClosedTradeTime<=0)
      return(true);

   int shift=iBarShift(Symbol(),PERIOD_M1,LastClosedTradeTime,false);

   if(shift<0)
      return(true);

   return(shift>=ReEntryCooldownBars);
}

bool LossLimitOK()
{
   if(MaxConsecutiveLosses<=0)
      return(true);

   return(ConsecutiveLosses<MaxConsecutiveLosses);
}

bool PositionExists()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;

      if(OrderSymbol()!=Symbol())
         continue;

      if(OrderMagicNumber()!=MagicNumber)
         continue;

      if(OrderType()==OP_BUY || OrderType()==OP_SELL)
         return(true);
   }

   return(false);
}

bool EntryGuardsOK()
{
   if(!DailyRiskOK())
   {
      LogBlock("DAILY_RISK","daily loss limit");
      return(false);
   }

   if(MaxTradesPerDay>0 && TradesToday>=MaxTradesPerDay)
   {
      LogBlock("DAILY_TRADES","max trades reached");
      return(false);
   }

   if(!EntryCooldownOK())
   {
      LogBlock("COOLDOWN","re-entry cooldown");
      return(false);
   }

   if(!LossLimitOK())
   {
      LogBlock("LOSS_STREAK","consecutive loss limit");
      return(false);
   }

   if(PositionExists())
   {
      LogBlock("POSITION","existing position");
      return(false);
   }

   if(UseTrendLegProtection &&
      MaxEntriesPerTrendLeg>0 &&
      EntriesThisTrendLeg>=MaxEntriesPerTrendLeg)
   {
      LogBlock("TREND_LEG","max entries in current trend leg");
      return(false);
   }

   return(true);
}

bool EntryReady()
{
   if(TrendScore>=MinimumTrendScore)
   {
      if(!IsM1Bull)
         return(false);

      if(EntryScore<MinimumTriggerScore)
         return(false);

      if(BullPullbackAge<=0 && !RecentBullCross)
         return(false);

      if(RequireTriggerCandle && !BullTriggerCandleOK())
         return(false);

      if(!M1SideOK(OP_BUY))
         return(false);

      if(!RSIQualityOK(OP_BUY))
         return(false);

      if(!DeepRSIChaseOK(OP_BUY))
         return(false);

      if(!EntryDistanceOK(OP_BUY))
         return(false);

      return(true);
   }

   if(TrendScore<=-MinimumTrendScore)
   {
      if(!IsM1Bear)
         return(false);

      if(EntryScore<MinimumTriggerScore)
         return(false);

      if(BearPullbackAge<=0 && !RecentBearCross)
         return(false);

      if(RequireTriggerCandle && !BearTriggerCandleOK())
         return(false);

      if(!M1SideOK(OP_SELL))
         return(false);

      if(!RSIQualityOK(OP_SELL))
         return(false);

      if(!DeepRSIChaseOK(OP_SELL))
         return(false);

      if(!EntryDistanceOK(OP_SELL))
         return(false);

      return(true);
   }

   return(false);
}

//==================================================================
// LOT SIZE
//==================================================================
double LotStep()
{
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   if(step<=0.0) step=0.01;
   return(step);
}

double NormalizeLot(double lot)
{
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   double step=LotStep();

   if(lot<minLot) lot=minLot;
   if(lot>maxLot) lot=maxLot;

   lot=MathFloor(lot/step+0.0000001)*step;

   if(lot<minLot) lot=minLot;

   int digitsLot=2;
   if(step>=1.0) digitsLot=0;
   else if(step>=0.1) digitsLot=1;

   return(NormalizeDouble(lot,digitsLot));
}

double CalculateLot(double stopDistancePrice)
{
   if(RiskPercent<=0.0)
      return(NormalizeLot(MarketInfo(Symbol(),MODE_MINLOT)));

   double riskMoney=AccountBalance()*RiskPercent/100.0;
   double tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
   double tickSize=MarketInfo(Symbol(),MODE_TICKSIZE);

   if(tickValue<=0.0 || tickSize<=0.0 || stopDistancePrice<=0.0)
      return(NormalizeLot(MarketInfo(Symbol(),MODE_MINLOT)));

   double moneyPerLot=stopDistancePrice/tickSize*tickValue;

   if(moneyPerLot<=0.0)
      return(NormalizeLot(MarketInfo(Symbol(),MODE_MINLOT)));

   double lot=riskMoney/moneyPerLot;

   return(NormalizeLot(lot));
}

//==================================================================
// STOPS
//==================================================================
double StopLevelPrice()
{
   return(MarketInfo(Symbol(),MODE_STOPLEVEL)*Point);
}

double FreezeLevelPrice()
{
   return(MarketInfo(Symbol(),MODE_FREEZELEVEL)*Point);
}

double MinStopDistancePrice()
{
   double brokerMin=StopLevelPrice()+2.0*Point;
   return(MathMax(brokerMin,MinimumSLPoints*Point));
}

double MinTPDistancePrice()
{
   double brokerMin=StopLevelPrice()+2.0*Point;
   return(MathMax(brokerMin,MinimumTPPoints*Point));
}

void BuildStops(int type,double entry,double &sl,double &tp)
{
   double slDistance=MathMax(ATR_M15*ATR_SL_Multiplier,
                             MinStopDistancePrice());

   double tpDistance=MathMax(ATR_M15*ATR_TP_Multiplier,
                             MinTPDistancePrice());

   if(type==OP_BUY)
   {
      sl=entry-slDistance;
      tp=entry+tpDistance;
   }
   else
   {
      sl=entry+slDistance;
      tp=entry-tpDistance;
   }

   sl=NormalizeDouble(sl,Digits);
   tp=NormalizeDouble(tp,Digits);
}

//==================================================================
// ORDER OPEN
//==================================================================
void OpenTrade()
{
   RefreshRates();

   int type=-1;
   double price=0.0;

   if(TrendScore>=MinimumTrendScore && IsM1Bull)
   {
      type=OP_BUY;
      price=Ask;
   }
   else if(TrendScore<=-MinimumTrendScore && IsM1Bear)
   {
      type=OP_SELL;
      price=Bid;
   }
   else
      return;

   double sl=0.0;
   double tp=0.0;

   BuildStops(type,price,sl,tp);

   double stopDistance=MathAbs(price-sl);
   double lots=CalculateLot(stopDistance);

   if(lots<=0.0)
   {
      Print("ORDER BLOCKED: calculated lot <= 0");
      return;
   }

   string comment="T100 Trend Rider v5.67";

   ResetLastError();

   int ticket=OrderSend(Symbol(),
                        type,
                        lots,
                        NormalizeDouble(price,Digits),
                        20,
                        sl,
                        tp,
                        comment,
                        MagicNumber,
                        0,
                        clrNONE);

   if(ticket<0)
   {
      int err=GetLastError();
      Print("OrderSend FAILED. error=",err,
            " type=",type,
            " lots=",DoubleToString(lots,2),
            " price=",DoubleToString(price,Digits),
            " SL=",DoubleToString(sl,Digits),
            " TP=",DoubleToString(tp,Digits));
      return;
   }

   TradesToday++;
   EntriesThisTrendLeg++;

   if(type==OP_BUY)
      BullPullbackAge=0;
   else
      BearPullbackAge=0;

   Print("ORDER OPENED ticket=",ticket,
         " type=",type==OP_BUY ? "BUY":"SELL",
         " lots=",DoubleToString(lots,2),
         " price=",DoubleToString(price,Digits),
         " SL=",DoubleToString(sl,Digits),
         " TP=",DoubleToString(tp,Digits),
         " TrendScore=",DoubleToString(TrendScore,0),
         " EntryScore=",DoubleToString(EntryScore,0));
}

//==================================================================
// TRADE MANAGEMENT
//==================================================================
bool BetterStop(int type,double proposed,double currentSL)
{
   if(type==OP_BUY)
   {
      if(currentSL<=0.0) return(true);
      return(proposed>currentSL+TrailingStepPoints*Point);
   }

   if(type==OP_SELL)
   {
      if(currentSL<=0.0) return(true);
      return(proposed<currentSL-TrailingStepPoints*Point);
   }

   return(false);
}

bool ValidStopForBroker(int type,double stop)
{
   RefreshRates();

   double minDist=StopLevelPrice()+2.0*Point;

   if(type==OP_BUY)
      return((Bid-stop)>=minDist);

   if(type==OP_SELL)
      return((stop-Ask)>=minDist);

   return(false);
}

bool ModifyStop(int ticket,double newSL,double currentTP)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET))
      return(false);

   double oldSL=OrderStopLoss();
   int type=OrderType();

   if(!BetterStop(type,newSL,oldSL))
      return(false);

   if(!ValidStopForBroker(type,newSL))
      return(false);

   newSL=NormalizeDouble(newSL,Digits);

   ResetLastError();

   bool ok=OrderModify(ticket,
                       OrderOpenPrice(),
                       newSL,
                       currentTP,
                       0,
                       clrNONE);

   if(!ok)
   {
      int err=GetLastError();

      if(DebugMode)
         Print("OrderModify FAILED ticket=",ticket,
               " error=",err,
               " newSL=",DoubleToString(newSL,Digits));

      return(false);
   }

   return(true);
}

void ManageBuy()
{
   int ticket=OrderTicket();
   double open=OrderOpenPrice();
   double currentSL=OrderStopLoss();
   double tp=OrderTakeProfit();

   RefreshRates();

   double profitDistance=Bid-open;

   if(profitDistance<=0.0)
      return;

   double atr=ATR_M15;
   if(atr<=0.0)
      atr=iATR(Symbol(),PERIOD_M15,ATRPeriod,0);

   if(atr<=0.0)
      return;

   // Stage 1: break-even.
   if(UseBreakEven && profitDistance>=BreakEvenATR*atr)
   {
      double be=open+BreakEvenPlusPoints*Point;
      ModifyStop(ticket,be,tp);
   }

   // Stage 2: protected profit.
   if(UseProtectedProfit &&
      profitDistance>=ProtectedProfitATR*atr)
   {
      double lock=open+ProtectedProfitATRLock*atr;
      ModifyStop(ticket,lock,tp);
   }

   // Stage 3: adaptive trailing.
   if(UseTrailingStop &&
      profitDistance>=TrailingStartATR*atr)
   {
      double trail=Bid-TrailingATR*atr;
      ModifyStop(ticket,trail,tp);
   }
}

void ManageSell()
{
   int ticket=OrderTicket();
   double open=OrderOpenPrice();
   double currentSL=OrderStopLoss();
   double tp=OrderTakeProfit();

   RefreshRates();

   double profitDistance=open-Ask;

   if(profitDistance<=0.0)
      return;

   double atr=ATR_M15;
   if(atr<=0.0)
      atr=iATR(Symbol(),PERIOD_M15,ATRPeriod,0);

   if(atr<=0.0)
      return;

   // Stage 1: break-even.
   if(UseBreakEven && profitDistance>=BreakEvenATR*atr)
   {
      double be=open-BreakEvenPlusPoints*Point;
      ModifyStop(ticket,be,tp);
   }

   // Stage 2: protected profit.
   if(UseProtectedProfit &&
      profitDistance>=ProtectedProfitATR*atr)
   {
      double lock=open-ProtectedProfitATRLock*atr;
      ModifyStop(ticket,lock,tp);
   }

   // Stage 3: adaptive trailing.
   if(UseTrailingStop &&
      profitDistance>=TrailingStartATR*atr)
   {
      double trail=Ask+TrailingATR*atr;
      ModifyStop(ticket,trail,tp);
   }
}

void ManageOpenTrades()
{
   if(TrailOnlyOnNewM1Bar)
   {
      datetime t=iTime(Symbol(),PERIOD_M1,0);

      if(t==LastManagementBar)
         return;

      LastManagementBar=t;
   }

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;

      if(OrderSymbol()!=Symbol())
         continue;

      if(OrderMagicNumber()!=MagicNumber)
         continue;

      if(OrderType()==OP_BUY)
         ManageBuy();
      else if(OrderType()==OP_SELL)
         ManageSell();
   }
}

//==================================================================
// DAILY / HISTORY STATE
//==================================================================
int CurrentDayKey()
{
   datetime now=SASTNow();
   return(TimeYear(now)*10000+TimeMonth(now)*100+TimeDay(now));
}

void ResetDailyCounters()
{
   TradeDay=CurrentDayKey();
   TradesToday=0;
   DayStartBalance=AccountBalance();
}

void UpdateDailyCounters()
{
   int d=CurrentDayKey();

   if(d!=TradeDay)
   {
      TradeDay=d;
      TradesToday=0;
      DayStartBalance=AccountBalance();
      ConsecutiveLosses=0;

      if(DebugMode)
         Print("NEW SAST TRADING DAY. StartBalance=",
               DoubleToString(DayStartBalance,2));
   }
}

void UpdateClosedTradeState()
{
   datetime newest=LastClosedTradeTime;
   double newestProfit=0.0;
   bool found=false;

   int total=OrdersHistoryTotal();

   for(int i=total-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))
         continue;

      if(OrderSymbol()!=Symbol())
         continue;

      if(OrderMagicNumber()!=MagicNumber)
         continue;

      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL)
         continue;

      if(OrderCloseTime()<=0)
         continue;

      if(OrderCloseTime()>newest)
      {
         newest=OrderCloseTime();
         newestProfit=OrderProfit()+OrderSwap()+OrderCommission();
         found=true;
      }
   }

   if(found)
   {
      LastClosedTradeTime=newest;

      if(newestProfit<0.0)
         ConsecutiveLosses++;
      else if(newestProfit>0.0)
         ConsecutiveLosses=0;
   }
}

//==================================================================
// LOGGING / STATUS
//==================================================================
void LogBlock(string group,string detail)
{
   if(!LogFilterBlocks)
      return;

   string msg=group+": "+detail;

   if(LogOnlyFilterChange && msg==LastFilterBlock)
      return;

   LastFilterBlock=msg;

   if(DebugMode)
      Print("BLOCKED ",msg);
}

void PrintStatus()
{
   Comment(
      "T100 Trend Rider v5.67\n",
      "SAST Hour: ",SASTHour(),"\n",
      "Session OK: ",TradingHoursOK,
      " Spread: ",DoubleToString(CurrentSpread,0),"/",MaxSpread,"\n",
      "TrendScore: ",DoubleToString(TrendScore,0),
      " EntryScore: ",DoubleToString(EntryScore,0),"\n",
      "H4 ",IsH4Bull?"BULL":IsH4Bear?"BEAR":"FLAT",
      " | H1 ",IsH1Bull?"BULL":IsH1Bear?"BEAR":"FLAT","\n",
      "M15 ",IsM15Bull?"BULL":IsM15Bear?"BEAR":"FLAT",
      " | M5 ",IsM5Bull?"BULL":IsM5Bear?"BEAR":"FLAT","\n",
      "M1 ",IsM1Bull?"BULL":IsM1Bear?"BEAR":"FLAT",
      " RSI15 ",DoubleToString(RSI_M15,1),
      " ADX ",DoubleToString(ADX_M15,1),"\n",
      "Trades today: ",TradesToday,"/",
      MaxTradesPerDay,
      " Loss streak: ",ConsecutiveLosses,"\n",
      "Trend leg entries: ",EntriesThisTrendLeg,"/",
      MaxEntriesPerTrendLeg
   );
}
