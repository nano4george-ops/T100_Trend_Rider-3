//+------------------------------------------------------------------+
//|                 T100_Trend_Rider_v5_64_Adaptive.mq4               |
//|                 T100 Trend Rider - Version 5.64                  |
//|  Adaptive MTF trend scoring + quality pullback + flexible M1 entry + controlled trailing |
//+------------------------------------------------------------------+
#property strict
#property version   "5.64"
#property description "T100 Trend Rider v5.64 - SAST session filter + protected break-even/trailing"

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

input bool     UseTradingHours          = true;
input int      TradingStartHour         = 10;      // South Africa local time
input int      TradingEndHour           = 2;       // South Africa local time; overnight session
input int      BrokerUTCOffsetHours     = 2;       // Broker server UTC offset
input int      SASTUTCOffsetHours       = 2;       // South Africa UTC+2

// Trend score: H4=30, H1=25, M15=20, M5=15.
// Small slope/ADX bonuses are added.
input int      MinimumTrendScore        = 25;

// Old v5.30 used 55. This is deliberately lower because the M1
// trigger now accepts a cross, EMA reclaim/rejection, or momentum.
input int      MinimumTriggerScore      = 40;

input double   MinEMADistancePoints     = 2.0;
input double   PullbackATRMax           = 1.75;

input int      PullbackLookbackBars     = 4;
input int      PullbackMaxBars          = 8;

// Entry quality / anti-overtrading.
input int      ReEntryCooldownBars      = 10;
input int      MaxConsecutiveLosses     = 2;

// v5.61 surgical controls. Disabled by default so the proven v5.5
// entry behaviour is preserved while we isolate the cause of v5.6
// underperformance. Enable one at a time in Strategy Tester.
input bool     UseMaxEntryDistance      = false;
input double   MaxEntryDistanceATR      = 0.75;
input bool     UseTrendLegProtection    = false;
input int      MaxEntriesPerTrendLeg    = 2;
input double   TrendResetATR            = 0.25;
input bool     BlockDeepRSIChase        = true;
input double   DeepBullRSI              = 35.0;
input double   DeepBearRSI              = 65.0;

// Flexible M1 trigger options.
input bool     AllowEMA20CrossTrigger   = true;
input bool     AllowEMAReclaimTrigger   = true;
input bool     AllowMomentumTrigger     = true;
input bool     RequireTriggerCandle     = false;

// Risk / limits.
input double   RiskPercent              = 1.0;
input double   MaxDailyLossPercent      = 3.0;
input int      MaxTradesPerDay          = 5;
input int      MagicNumber              = 1001;

// Stops.
input double   ATR_SL_Multiplier        = 2.0;
input double   ATR_TP_Multiplier        = 3.0;
input int      MinimumSLPoints          = 100;
input int      MinimumTPPoints          = 150;

// Trade management.
input bool     UseBreakEven             = true;
input double   BreakEvenATR             = 1.25;
input double   BreakEvenPlusPoints      = 2.0;
input double   BreakEvenStepPoints      = 1.0;
input bool     UseTrailingStop          = true;
input double   TrailingATR              = 1.5;
input double   TrailingStartATR         = 2.50;
input double   TrailingStepPoints       = 25.0;
input bool     TrailOnlyOnNewM1Bar      = false;
input int      SlippagePoints           = 10;

input bool     DebugMode                = true;
input bool     LogFilterBlocks          = true;
input bool     LogOnlyFilterChange       = true;

//==================================================================
// GLOBALS
//==================================================================
datetime LastBar = 0;
int      TradeDay = -1;
int      TradesToday = 0;
double   DayStartBalance = 0.0;
int      ConsecutiveLosses = 0;
datetime LastClosedTradeTime = 0;
datetime LastManagementBar = 0;

bool   IndicatorsReady = false;
bool   TradingHoursOK  = true;
bool   SpreadOK        = false;
double CurrentSpread   = 0.0;

// Closed-bar indicator cache.
double EMA20_H4=0,  EMA50_H4=0;
double EMA20_H1=0,  EMA50_H1=0;
double EMA20_M15=0, EMA50_M15=0;
double EMA20_M5=0,  EMA50_M5=0;
double EMA20_M1=0,  EMA50_M1=0;

double EMA20_H4_Prev=0, EMA20_H1_Prev=0;
double EMA20_M15_Prev=0, EMA20_M5_Prev=0;

double RSI_M15=0;
double ATR_M15=0;
double ADX_M15=0;
long   Volume_M15=0;

double TrendScore=0;
double EntryScore=0;

bool IsH4Bull=false,  IsH4Bear=false;
bool IsH1Bull=false,  IsH1Bear=false;
bool IsM15Bull=false, IsM15Bear=false;
bool IsM5Bull=false,  IsM5Bear=false;
bool IsM1Bull=false,  IsM1Bear=false;

int  BullPullbackAge=0;
int  BearPullbackAge=0;
bool RecentBullCross=false;
bool RecentBearCross=false;

int  TrendLegDirection=0;
int  EntriesThisTrendLeg=0;
bool BullTrendReset=false;
bool BearTrendReset=false;

//==================================================================
// INITIALIZATION
//==================================================================
int OnInit()
{
   LastBar = 0;
   BullPullbackAge = 0;
   BearPullbackAge = 0;
   RecentBullCross = false;
   RecentBearCross = false;
   TrendLegDirection=0;
   EntriesThisTrendLeg=0;
   BullTrendReset=false;
   BearTrendReset=false;
   ResetDailyCounters();

   Print("====================================================");
   Print("T100 Trend Rider v5.62 STARTED");
   Print("Symbol: ",Symbol()," Period: ",Period());
   Print("Adaptive trend + flexible M1 trigger + SAST session + protected trailing");
   Print("MinimumTrendScore=",MinimumTrendScore,
         " MinimumTriggerScore=",MinimumTriggerScore);
   Print("====================================================");

   return(INIT_SUCCEEDED);
}

//==================================================================
// DEINITIALIZATION
//==================================================================
void OnDeinit(const int reason)
{
   Comment("");
   Print("T100 Trend Rider v5.62 stopped.");
}

//==================================================================
// MAIN LOOP
//==================================================================
void OnTick()
{
   // Trade management runs on every tick.
   ManageOpenTrades();

   // Entry logic runs once per completed/new M1 bar.
   if(!IsNewBar())
      return;

   UpdateDailyCounters();
   UpdateClosedTradeState();
   CheckTradingHours();
   CheckSpread();

   if(!UpdateIndicators())
   {
      if(DebugMode)
         Print("BLOCKED: indicator history/data not ready");
      return;
   }

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
   {
      PrintStatus();

      Print("TrendScore=",DoubleToString(TrendScore,0),
            " EntryScore=",DoubleToString(EntryScore,0),
            " M1Bull=",IsM1Bull,
            " M1Bear=",IsM1Bear,
            " BullPB=",BullPullbackAge,
            " BearPB=",BearPullbackAge,
            " BullCross=",RecentBullCross,
            " BearCross=",RecentBearCross);
   }

   if(EntryReady())
      OpenTrade();
   else if(DebugMode)
      Print("ENTRY NOT READY");
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
// HISTORY HANDLING
//==================================================================
bool HistoryReadyTF(int tf)
{
   int requiredBars=SlowEMA+10;
   int bars=iBars(Symbol(),tf);

   if(bars<requiredBars)
      return(false);

   // Confirm the requested history is actually accessible.
   if(iTime(Symbol(),tf,SlowEMA+2)<=0)
      return(false);

   if(iTime(Symbol(),tf,2)<=0)
      return(false);

   return(true);
}

bool ValidIndicator(double value)
{
   if(value==EMPTY_VALUE)
      return(false);

   if(value<=0.0)
      return(false);

   return(true);
}

//==================================================================
// INDICATORS
// All entry values use CLOSED candles. Shift 0 is not used here.
//==================================================================
bool UpdateIndicators()
{
   IndicatorsReady=false;

   if(!HistoryReadyTF(PERIOD_H4) ||
      !HistoryReadyTF(PERIOD_H1) ||
      !HistoryReadyTF(PERIOD_M15) ||
      !HistoryReadyTF(PERIOD_M5) ||
      !HistoryReadyTF(PERIOD_M1))
      return(false);

   EMA20_H4 = iMA(Symbol(),PERIOD_H4,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_H4 = iMA(Symbol(),PERIOD_H4,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);

   EMA20_H1 = iMA(Symbol(),PERIOD_H1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_H1 = iMA(Symbol(),PERIOD_H1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);

   EMA20_M15 = iMA(Symbol(),PERIOD_M15,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_M15 = iMA(Symbol(),PERIOD_M15,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);

   EMA20_M5 = iMA(Symbol(),PERIOD_M5,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_M5 = iMA(Symbol(),PERIOD_M5,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);

   EMA20_M1 = iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_M1 = iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);

   EMA20_H4_Prev  = iMA(Symbol(),PERIOD_H4,FastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   EMA20_H1_Prev  = iMA(Symbol(),PERIOD_H1,FastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   EMA20_M15_Prev = iMA(Symbol(),PERIOD_M15,FastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   EMA20_M5_Prev  = iMA(Symbol(),PERIOD_M5,FastEMA,0,MODE_EMA,PRICE_CLOSE,2);

   RSI_M15 = iRSI(Symbol(),PERIOD_M15,RSIPeriod,PRICE_CLOSE,1);
   ATR_M15 = iATR(Symbol(),PERIOD_M15,ATRPeriod,1);
   ADX_M15 = iADX(Symbol(),PERIOD_M15,ADXPeriod,PRICE_CLOSE,MODE_MAIN,1);

   Volume_M15 = iVolume(Symbol(),PERIOD_M15,1);
   CurrentSpread = MarketInfo(Symbol(),MODE_SPREAD);

   if(!ValidIndicator(EMA20_H4) ||
      !ValidIndicator(EMA50_H4) ||
      !ValidIndicator(EMA20_H1) ||
      !ValidIndicator(EMA50_H1) ||
      !ValidIndicator(EMA20_M15) ||
      !ValidIndicator(EMA50_M15) ||
      !ValidIndicator(EMA20_M5) ||
      !ValidIndicator(EMA50_M5) ||
      !ValidIndicator(EMA20_M1) ||
      !ValidIndicator(EMA50_M1) ||
      !ValidIndicator(RSI_M15) ||
      !ValidIndicator(ATR_M15) ||
      !ValidIndicator(ADX_M15))
      return(false);

   IndicatorsReady=true;
   return(true);
}

//==================================================================
// FILTERS
//==================================================================
datetime SASTNow()
{
   return(TimeCurrent() + (SASTUTCOffsetHours - BrokerUTCOffsetHours) * 3600);
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

   double lossPercent=
      100.0*(DayStartBalance-AccountEquity())/DayStartBalance;

   return(lossPercent<MaxDailyLossPercent);
}

bool MarketReady()
{
   if(!IndicatorsReady) return(false);
   if(!TradingHoursOK) return(false);
   if(!SpreadOK) return(false);
   if(!ATR_OK()) return(false);
   if(!Volume_OK()) return(false);
   if(!ADX_OK()) return(false);
   return(true);
}

// Entry guards are deliberately separate from the market-condition filters.
// MaxTradesPerDay, daily loss, cooldown and consecutive-loss limits do not mean
// the market is closed; they only mean this EA is not permitted to enter.
bool EntryGuardsOK()
{
   if(!DailyRiskOK()) return(false);

   if(MaxTradesPerDay>0 && TradesToday>=MaxTradesPerDay)
      return(false);

   if(!EntryCooldownOK()) return(false);
   if(!LossLimitOK()) return(false);

   return(true);
}

void LogMarketFilterBlock()
{
   static string lastReason="";
   static datetime lastBar=0;
   string reason="";

   if(!IndicatorsReady)
      reason="INDICATORS_NOT_READY";
   else if(!TradingHoursOK)
      reason="TRADING_HOURS";
   else if(!SpreadOK)
      reason="SPREAD";
   else if(!ATR_OK())
      reason="ATR";
   else if(!Volume_OK())
      reason="VOLUME";
   else if(!ADX_OK())
      reason="ADX";
   else
      reason="UNKNOWN";

   datetime bar=iTime(Symbol(),PERIOD_M1,0);
   bool shouldLog=DebugMode && LogFilterBlocks;
   if(LogOnlyFilterChange)
      shouldLog=shouldLog && (reason!=lastReason);

   if(shouldLog)
   {
      if(reason=="SPREAD")
         Print("MARKET FILTER BLOCKED: SPREAD=",DoubleToString(CurrentSpread,1)," MAX=",MaxSpread);
      else if(reason=="ATR")
         Print("MARKET FILTER BLOCKED: ATR_POINTS=",DoubleToString(ATR_M15/Point,1)," MIN=",DoubleToString(MinATRPoints,1));
      else if(reason=="VOLUME")
         Print("MARKET FILTER BLOCKED: VOLUME=",Volume_M15," MIN=",MinVolume);
      else if(reason=="ADX")
         Print("MARKET FILTER BLOCKED: ADX=",DoubleToString(ADX_M15,2)," MIN=",DoubleToString(MinADX,2));
      else if(reason=="TRADING_HOURS")
         Print("MARKET FILTER BLOCKED: TRADING HOURS");
      else if(reason=="INDICATORS_NOT_READY")
         Print("MARKET FILTER BLOCKED: INDICATORS NOT READY");
      else
         Print("MARKET FILTER BLOCKED: UNKNOWN REASON");
   }

   lastReason=reason;
   lastBar=bar;
}

void LogEntryGuardBlock()
{
   static string lastReason="";
   static datetime lastBar=0;
   string reason="";

   if(!DailyRiskOK())
      reason="DAILY_LOSS_LIMIT";
   else if(MaxTradesPerDay>0 && TradesToday>=MaxTradesPerDay)
      reason="MAX_TRADES_PER_DAY";
   else if(!EntryCooldownOK())
      reason="REENTRY_COOLDOWN";
   else if(!LossLimitOK())
      reason="CONSECUTIVE_LOSS_LIMIT";
   else
      reason="UNKNOWN";

   datetime bar=iTime(Symbol(),PERIOD_M1,0);
   bool shouldLog=DebugMode && LogFilterBlocks;
   if(LogOnlyFilterChange)
      shouldLog=shouldLog && (reason!=lastReason);

   if(shouldLog)
   {
      if(reason=="DAILY_LOSS_LIMIT")
         Print("ENTRY GUARD BLOCKED: DAILY LOSS LIMIT");
      else if(reason=="MAX_TRADES_PER_DAY")
         Print("ENTRY GUARD BLOCKED: MAX TRADES TODAY ",TradesToday,"/",MaxTradesPerDay);
      else if(reason=="REENTRY_COOLDOWN")
         Print("ENTRY GUARD BLOCKED: RE-ENTRY COOLDOWN");
      else if(reason=="CONSECUTIVE_LOSS_LIMIT")
         Print("ENTRY GUARD BLOCKED: CONSECUTIVE LOSSES ",ConsecutiveLosses,"/",MaxConsecutiveLosses);
      else
         Print("ENTRY GUARD BLOCKED: UNKNOWN REASON");
   }

   lastReason=reason;
   lastBar=bar;
}

//==================================================================
// TREND SCORING
//
// IMPORTANT CHANGE:
// v5.30 required H4+H1+M15+M5 agreement for a regime.
// That made the bearish side effectively disappear during a common
// transition where H4 is still bullish but H1/M15/M5 are already
// strongly bearish.
//
// v5.50 uses the actual weighted trend score. H4 remains the strongest
// timeframe, but lower timeframes can establish a bearish regime when
// they clearly outweigh the stale H4 direction.
//==================================================================
int Direction(double fast,double slow)
{
   if(fast>slow) return(1);
   if(fast<slow) return(-1);
   return(0);
}

int SlopeDirection(double now,double previous)
{
   double eps=Point*0.25;

   if(now>previous+eps) return(1);
   if(now<previous-eps) return(-1);

   return(0);
}

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

   TrendScore=0;

   // Base score.
   TrendScore += 30*Direction(EMA20_H4,EMA50_H4);
   TrendScore += 25*Direction(EMA20_H1,EMA50_H1);
   TrendScore += 20*Direction(EMA20_M15,EMA50_M15);
   TrendScore += 15*Direction(EMA20_M5,EMA50_M5);

   // EMA20 slope confirms whether the current direction is actually
   // strengthening or weakening.
   TrendScore += 5*SlopeDirection(EMA20_H4,EMA20_H4_Prev);
   TrendScore += 4*SlopeDirection(EMA20_H1,EMA20_H1_Prev);
   TrendScore += 3*SlopeDirection(EMA20_M15,EMA20_M15_Prev);
   TrendScore += 2*SlopeDirection(EMA20_M5,EMA20_M5_Prev);

   // ADX strengthens the M15 regime when it is genuinely trending.
   if(ADX_M15>=30.0)
   {
      if(IsM15Bull) TrendScore+=5;
      if(IsM15Bear) TrendScore-=5;
   }
}

bool BullRegime()
{
   return(TrendScore>=MinimumTrendScore);
}

bool BearRegime()
{
   return(TrendScore<=-MinimumTrendScore);
}

//==================================================================
// M1 TRIGGERS
//==================================================================
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

// Bullish EMA20 reclaim after a pullback.
bool BullReclaim()
{
   double o=iOpen(Symbol(),PERIOD_M1,1);
   double c=iClose(Symbol(),PERIOD_M1,1);
   double h=iHigh(Symbol(),PERIOD_M1,1);
   double l=iLow(Symbol(),PERIOD_M1,1);

   double ema=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);

   return(l<=ema &&
          c>ema &&
          c>o &&
          h>l);
}

// Correct bearish mirror:
// price trades at/above EMA20 and closes back below it.
bool BearReclaim()
{
   double o=iOpen(Symbol(),PERIOD_M1,1);
   double c=iClose(Symbol(),PERIOD_M1,1);
   double h=iHigh(Symbol(),PERIOD_M1,1);
   double l=iLow(Symbol(),PERIOD_M1,1);

   double ema=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);

   return(h>=ema &&
          c<ema &&
          c<o &&
          h>l);
}

bool BullMomentum()
{
   double c1=iClose(Symbol(),PERIOD_M1,1);
   double c2=iClose(Symbol(),PERIOD_M1,2);
   double ema=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);

   return(c1>c2 && c1>ema);
}

bool BearMomentum()
{
   double c1=iClose(Symbol(),PERIOD_M1,1);
   double c2=iClose(Symbol(),PERIOD_M1,2);
   double ema=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);

   return(c1<c2 && c1<ema);
}

bool BullCandleOK()
{
   double o=iOpen(Symbol(),PERIOD_M1,1);
   double c=iClose(Symbol(),PERIOD_M1,1);
   double pc=iClose(Symbol(),PERIOD_M1,2);

   return(c>o || c>pc);
}

bool BearCandleOK()
{
   double o=iOpen(Symbol(),PERIOD_M1,1);
   double c=iClose(Symbol(),PERIOD_M1,1);
   double pc=iClose(Symbol(),PERIOD_M1,2);

   return(c<o || c<pc);
}

//==================================================================
// PULLBACK DETECTION
//
// The old bearish logic depended on MarketBearish(), which required
// every timeframe including H4 to be bearish. That is too restrictive.
// v5.50 uses the adaptive regime score and checks several completed
// M1 bars, making bearish pullbacks symmetrical with bullish ones.
//==================================================================
bool BullPullback()
{
   if(!BullRegime()) return(false);
   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);
   if(atr<=0) return(false);
   int lookback=MathMax(1,PullbackLookbackBars);
   double maxDist=atr*PullbackATRMax;
   bool recentTouch=false, recentAbove=false;

   for(int shift=1;shift<=lookback;shift++)
   {
      double ema20=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,shift);
      double ema50=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,shift);
      double c=iClose(Symbol(),PERIOD_M1,shift);
      double l=iLow(Symbol(),PERIOD_M1,shift);
      if(MathAbs(c-ema20)<=maxDist || MathAbs(l-ema20)<=maxDist) recentTouch=true;
      if(c>ema20 || c>ema50) recentAbove=true;
   }

   double ema=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double c1=iClose(Symbol(),PERIOD_M1,1);
   double o1=iOpen(Symbol(),PERIOD_M1,1);
   double l1=iLow(Symbol(),PERIOD_M1,1);
   bool immediate=(l1<=ema && c1>ema && c1>=o1);
   bool shallow=(recentTouch && c1>ema && recentAbove);
   return(immediate || shallow);
}

bool BearPullback()
{
   if(!BearRegime()) return(false);
   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);
   if(atr<=0) return(false);
   int lookback=MathMax(1,PullbackLookbackBars);
   double maxDist=atr*PullbackATRMax;
   bool recentTouch=false, recentBelow=false;

   for(int shift=1;shift<=lookback;shift++)
   {
      double ema20=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,shift);
      double ema50=iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,shift);
      double c=iClose(Symbol(),PERIOD_M1,shift);
      double h=iHigh(Symbol(),PERIOD_M1,shift);
      if(MathAbs(c-ema20)<=maxDist || MathAbs(h-ema20)<=maxDist) recentTouch=true;
      if(c<ema20 || c<ema50) recentBelow=true;
   }

   double ema=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double c1=iClose(Symbol(),PERIOD_M1,1);
   double o1=iOpen(Symbol(),PERIOD_M1,1);
   double h1=iHigh(Symbol(),PERIOD_M1,1);
   bool immediate=(h1>=ema && c1<ema && c1<=o1);
   bool shallow=(recentTouch && c1<ema && recentBelow);
   return(immediate || shallow);
}

bool EntryDistanceOK(bool bullish)
{
   if(!UseMaxEntryDistance || MaxEntryDistanceATR<=0.0)
      return(true);

   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);
   if(atr<=0) return(false);

   double ema=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double price=bullish ? Ask : Bid;
   return(MathAbs(price-ema)<=atr*MaxEntryDistanceATR);
}

void UpdateTrendLegState()
{
   if(!UseTrendLegProtection) return;

   int direction=0;
   if(BullRegime()) direction=1;
   else if(BearRegime()) direction=-1;

   if(direction!=TrendLegDirection)
   {
      TrendLegDirection=direction;
      EntriesThisTrendLeg=0;
      BullTrendReset=(direction!=1);
      BearTrendReset=(direction!=-1);
   }

   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);
   if(atr<=0) return;

   double ema=iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double c=iClose(Symbol(),PERIOD_M1,1);

   if(direction==1 && c<ema-atr*TrendResetATR) BullTrendReset=true;
   if(direction==-1 && c>ema+atr*TrendResetATR) BearTrendReset=true;
}

bool TrendLegEntryOK(bool bullish)
{
   if(!UseTrendLegProtection || MaxEntriesPerTrendLeg<=0)
      return(true);

   if(EntriesThisTrendLeg<MaxEntriesPerTrendLeg)
      return(true);

   return(bullish ? BullTrendReset : BearTrendReset);
}

void UpdatePullbackState()
{
   bool bullPB=BullPullback();
   bool bearPB=BearPullback();

   if(!BullRegime())
      BullPullbackAge=0;

   if(!BearRegime())
      BearPullbackAge=0;

   if(bullPB)
   {
      BullPullbackAge=1;
      BearPullbackAge=0;
   }
   else if(BullPullbackAge>0)
   {
      BullPullbackAge++;

      if(PullbackMaxBars>0 &&
         BullPullbackAge>PullbackMaxBars)
         BullPullbackAge=0;
   }

   if(bearPB)
   {
      BearPullbackAge=1;
      BullPullbackAge=0;
   }
   else if(BearPullbackAge>0)
   {
      BearPullbackAge++;

      if(PullbackMaxBars>0 &&
         BearPullbackAge>PullbackMaxBars)
         BearPullbackAge=0;
   }

   RecentBullCross=BullCross();
   RecentBearCross=BearCross();
}

bool BullPullbackArmed()
{
   return(BullRegime() &&
          BullPullbackAge>0 &&
          (PullbackMaxBars<=0 ||
           BullPullbackAge<=PullbackMaxBars));
}

bool BearPullbackArmed()
{
   return(BearRegime() &&
          BearPullbackAge>0 &&
          (PullbackMaxBars<=0 ||
           BearPullbackAge<=PullbackMaxBars));
}

//==================================================================
// ENTRY SCORE
//==================================================================
bool EMADistanceOK()
{
   double distancePoints=
      MathAbs(EMA20_M15-EMA50_M15)/Point;

   return(distancePoints>=MinEMADistancePoints);
}

void CalculateEntryScore()
{
   EntryScore=0;
   IsM1Bull=false;
   IsM1Bear=false;

   bool bull=BullRegime();
   bool bear=BearRegime();

   bool bullPB=BullPullbackArmed();
   bool bearPB=BearPullbackArmed();

   bool bullCross=
      AllowEMA20CrossTrigger &&
      RecentBullCross;

   bool bearCross=
      AllowEMA20CrossTrigger &&
      RecentBearCross;

   bool bullReclaim=
      AllowEMAReclaimTrigger &&
      BullReclaim();

   bool bearReclaim=
      AllowEMAReclaimTrigger &&
      BearReclaim();

   bool bullMom=
      AllowMomentumTrigger &&
      BullMomentum();

   bool bearMom=
      AllowMomentumTrigger &&
      BearMomentum();

   // Trend quality.
   if(bull) EntryScore+=30;
   if(bear) EntryScore-=30;

   if(bull && RSI_M15>=BullRSI) EntryScore+=10;
   if(bear && RSI_M15<=BearRSI) EntryScore-=10;

   bool deepChase=DeepRSIChaseBlocked(bull,bear);

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

   // Pullback quality.
   if(bullPB) EntryScore+=20;
   if(bearPB) EntryScore-=20;

   // Choose the strongest ONE M1 trigger.
   int bullTrigger=0;
   int bearTrigger=0;

   if(bullCross)
      bullTrigger=20;
   else if(bullReclaim)
      bullTrigger=16;
   else if(bullMom)
      bullTrigger=12;

   if(bearCross)
      bearTrigger=20;
   else if(bearReclaim)
      bearTrigger=16;
   else if(bearMom)
      bearTrigger=12;

   if(bull)
      EntryScore+=bullTrigger;

   if(bear)
      EntryScore-=bearTrigger;

   if(deepChase)
   {
      if(bear && bearTrigger<20) EntryScore+=bearTrigger;
      if(bull && bullTrigger<20) EntryScore-=bullTrigger;
   }

   // Optional candle requirement is a hard trigger filter.
   bool bullCandle=true;
   bool bearCandle=true;

   if(RequireTriggerCandle)
   {
      bullCandle=BullCandleOK();
      bearCandle=BearCandleOK();
   }

   bool bullTriggerOK=
      bullTrigger>0 &&
      bullCandle;

   bool bearTriggerOK=
      bearTrigger>0 &&
      bearCandle;

   IsM1Bull=
      bull &&
      bullPB &&
      bullTriggerOK &&
      EntryScore>=MinimumTriggerScore &&
      EntryDistanceOK(true) &&
      TrendLegEntryOK(true);

   IsM1Bear=
      bear &&
      bearPB &&
      bearTriggerOK &&
      EntryScore<=-MinimumTriggerScore &&
      EntryDistanceOK(false) &&
      TrendLegEntryOK(false);
}

//==================================================================
// ENTRY QUALITY / COOLDOWN
//==================================================================
bool EntryCooldownOK()
{
   if(ReEntryCooldownBars<=0 || LastClosedTradeTime<=0)
      return(true);
   int barsSince=iBarShift(Symbol(),PERIOD_M1,LastClosedTradeTime,false);
   if(barsSince<0) return(true);
   return(barsSince>=ReEntryCooldownBars);
}

bool LossLimitOK()
{
   if(MaxConsecutiveLosses<=0) return(true);
   return(ConsecutiveLosses<MaxConsecutiveLosses);
}

bool DeepRSIChaseBlocked(bool bull,bool bear)
{
   if(!BlockDeepRSIChase) return(false);
   if(bear && RSI_M15<DeepBullRSI) return(true);
   if(bull && RSI_M15>DeepBearRSI) return(true);
   return(false);
}

//==================================================================
// ENTRY READY
//==================================================================
bool EntryReady()
{
   if(PositionExists())
      return(false);

   if(!DailyRiskOK())
      return(false);

   if(MaxTradesPerDay>0 &&
      TradesToday>=MaxTradesPerDay)
      return(false);

   if(!EntryCooldownOK() || !LossLimitOK())
      return(false);

   return(IsM1Bull || IsM1Bear);
}

//==================================================================
// POSITION EXISTS
//==================================================================
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

      if(OrderType()==OP_BUY ||
         OrderType()==OP_SELL)
         return(true);
   }

   return(false);
}

//==================================================================
// RISK LOT SIZE
//==================================================================
double CalculateLot(double stopDistancePrice)
{
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   double lotStep=MarketInfo(Symbol(),MODE_LOTSTEP);
   double tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
   double tickSize=MarketInfo(Symbol(),MODE_TICKSIZE);

   if(lotStep<=0)
      lotStep=0.01;

   if(RiskPercent<=0 ||
      tickValue<=0 ||
      tickSize<=0 ||
      stopDistancePrice<=0)
      return(minLot);

   double riskMoney=
      AccountBalance()*RiskPercent/100.0;

   double lossPerLot=
      (stopDistancePrice/tickSize)*tickValue;

   if(lossPerLot<=0)
      return(minLot);

   double lots=riskMoney/lossPerLot;

   lots=MathFloor(lots/lotStep)*lotStep;
   lots=MathMax(minLot,lots);
   lots=MathMin(maxLot,lots);

   int lotDigits=2;

   if(lotStep>=1.0)
      lotDigits=0;
   else if(lotStep>=0.1)
      lotDigits=1;

   return(NormalizeDouble(lots,lotDigits));
}

//==================================================================
// OPEN TRADE
//==================================================================
void OpenTrade()
{
   if(PositionExists())
      return;

   RefreshRates();

   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);

   if(atr<=0)
      atr=ATR_M15;

   if(atr<=0)
      return;

   double slDistance=
      MathMax(atr*ATR_SL_Multiplier,
              MinimumSLPoints*Point);

   double tpDistance=
      MathMax(atr*ATR_TP_Multiplier,
              MinimumTPPoints*Point);

   double minStop=
      (MarketInfo(Symbol(),MODE_STOPLEVEL)+2)*Point;

   slDistance=MathMax(slDistance,minStop);
   tpDistance=MathMax(tpDistance,minStop);

   double lots=CalculateLot(slDistance);

   if(lots<=0)
      return;

   int type=-1;
   double price=0;
   double sl=0;
   double tp=0;

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
   else
      return;

   ResetLastError();

   int ticket=
      OrderSend(Symbol(),
                type,
                lots,
                price,
                SlippagePoints,
                sl,
                tp,
                "T100 Trend Rider v5.64",
                MagicNumber,
                0,
                type==OP_BUY ? clrBlue : clrRed);

   if(ticket<0)
   {
      Print("ORDER SEND FAILED error=",GetLastError(),
            " type=",type,
            " lots=",DoubleToString(lots,2),
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

   Print("TRADE OPENED v5.62 ticket=",ticket,
         " direction=",type==OP_BUY ? "BUY" : "SELL",
         " lots=",DoubleToString(lots,2),
         " TrendScore=",DoubleToString(TrendScore,0),
         " EntryScore=",DoubleToString(EntryScore,0));
}

//==================================================================
// TRADE MANAGEMENT
//
// v5.30 generated many repeated OrderModify records. v5.50 only
// modifies when the rounded SL has moved by at least one Point.
//==================================================================
void ManageOpenTrades()
{
   RefreshRates();

   double atr=iATR(Symbol(),PERIOD_M1,ATRPeriod,1);
   if(atr<=0)
      atr=iATR(Symbol(),PERIOD_M15,ATRPeriod,1);
   if(atr<=0)
      return;

   datetime bar=iTime(Symbol(),PERIOD_M1,0);
   bool allowTrail=true;

   if(TrailOnlyOnNewM1Bar)
   {
      allowTrail=(bar!=LastManagementBar);
      if(allowTrail)
         LastManagementBar=bar;
   }

   double beStep=MathMax(BreakEvenStepPoints,0.1)*Point;
   double trailStep=MathMax(TrailingStepPoints,1.0)*Point;
   double stopLevel=(MarketInfo(Symbol(),MODE_STOPLEVEL)+2)*Point;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;

      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber)
         continue;

      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL)
         continue;

      double open=OrderOpenPrice();
      double currentSL=OrderStopLoss();
      double newSL=currentSL;
      bool modify=false;

      if(OrderType()==OP_BUY)
      {
         double profit=Bid-open;

         // Break-even is independent of the normal trailing step.
         if(UseBreakEven && profit>=atr*BreakEvenATR)
         {
            double be=NormalizeDouble(open+BreakEvenPlusPoints*Point,Digits);

            if(currentSL<be && be<Bid-stopLevel)
            {
               newSL=be;
               modify=true;
            }
         }

         // Progressive ATR trailing starts only after the configured profit.
         if(UseTrailingStop && allowTrail && profit>=atr*TrailingStartATR)
         {
            double trail=NormalizeDouble(Bid-atr*TrailingATR,Digits);

            if(trail>newSL && trail>open && trail<Bid-stopLevel)
            {
               newSL=trail;
               modify=true;
            }
         }

         double maxSL=NormalizeDouble(Bid-stopLevel,Digits);
         if(newSL>maxSL)
            newSL=maxSL;

         newSL=NormalizeDouble(newSL,Digits);

         bool beMove=(currentSL<newSL && newSL<=NormalizeDouble(open+BreakEvenPlusPoints*Point,Digits));
         bool enoughStep=(newSL-currentSL)>=trailStep;

         if(modify && newSL>currentSL && newSL<Bid &&
            (beMove ? (newSL-currentSL)>=beStep : enoughStep))
         {
            ResetLastError();
            if(!OrderModify(OrderTicket(),open,newSL,OrderTakeProfit(),0,clrNONE))
               Print("BUY OrderModify failed ticket=",OrderTicket()," error=",GetLastError());
         }
      }
      else
      {
         double profit=open-Ask;

         // Break-even is independent of the normal trailing step.
         if(UseBreakEven && profit>=atr*BreakEvenATR)
         {
            double be=NormalizeDouble(open-BreakEvenPlusPoints*Point,Digits);

            if((currentSL==0 || currentSL>be) && be>Ask+stopLevel)
            {
               newSL=be;
               modify=true;
            }
         }

         // Progressive ATR trailing starts only after the configured profit.
         if(UseTrailingStop && allowTrail && profit>=atr*TrailingStartATR)
         {
            double trail=NormalizeDouble(Ask+atr*TrailingATR,Digits);

            if((newSL==0 || trail<newSL) && trail<open && trail>Ask+stopLevel)
            {
               newSL=trail;
               modify=true;
            }
         }

         double minSL=NormalizeDouble(Ask+stopLevel,Digits);
         if(newSL>0 && newSL<minSL)
            newSL=minSL;

         newSL=NormalizeDouble(newSL,Digits);

         bool beMove=(currentSL==0 || (newSL<currentSL && newSL>=NormalizeDouble(open-BreakEvenPlusPoints*Point,Digits)));
         bool enoughStep=(currentSL==0 || (currentSL-newSL)>=trailStep);

         if(modify && (currentSL==0 || newSL<currentSL) && newSL>Ask &&
            (currentSL==0 || (beMove ? (currentSL-newSL)>=beStep : enoughStep)))
         {
            ResetLastError();
            if(!OrderModify(OrderTicket(),open,newSL,OrderTakeProfit(),0,clrNONE))
               Print("SELL OrderModify failed ticket=",OrderTicket()," error=",GetLastError());
         }
      }
   }
}

//==================================================================
// DAILY COUNTERS
//==================================================================
void ResetDailyCounters()
{
   TradeDay=TimeDayOfYear(SASTNow());
   DayStartBalance=AccountBalance();
   TradesToday=0;
   ConsecutiveLosses=0;
   LastManagementBar=0;
}

void UpdateDailyCounters()
{
   int d=TimeDayOfYear(SASTNow());

   if(d!=TradeDay)
      ResetDailyCounters();
}

//==================================================================
// CLOSED TRADE RESULT TRACKING
//==================================================================
void UpdateClosedTradeState()
{
   static int lastHistoryTotal=-1;
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
   static bool historyInitialized=false;

   if(!historyInitialized)
   {
      if(newest>0)
         LastClosedTradeTime=newest;
      ConsecutiveLosses=0;
      historyInitialized=true;
      return;
   }

   if(newest>0 && newest>LastClosedTradeTime)
   {
      LastClosedTradeTime=newest;
      if(newestNet<0.0) ConsecutiveLosses++;
      else if(newestNet>0.0) ConsecutiveLosses=0;
   }
}

//==================================================================
// DEBUG STATUS
//==================================================================
void PrintStatus()
{
   Print("---------------- T100 v5.64 STATUS ----------------");

   Print("BrokerTime=",
         TimeToString(TimeCurrent(),
                      TIME_DATE|TIME_SECONDS),
         " SAST=",
         TimeToString(SASTNow(),TIME_DATE|TIME_SECONDS),
         " TradingHoursOK=",TradingHoursOK,
         " SpreadOK=",SpreadOK,
         " Spread=",DoubleToString(CurrentSpread,1));

   Print("Trend: H4Bull=",IsH4Bull,
         " H1Bull=",IsH1Bull,
         " M15Bull=",IsM15Bull,
         " M5Bull=",IsM5Bull,
         " | H4Bear=",IsH4Bear,
         " H1Bear=",IsH1Bear,
         " M15Bear=",IsM15Bear,
         " M5Bear=",IsM5Bear);

   Print("TrendScore=",DoubleToString(TrendScore,0),
         " MinTrend=",MinimumTrendScore,
         " TriggerMin=",MinimumTriggerScore);

   Print("H4 EMA20/50=",
         DoubleToString(EMA20_H4,Digits),
         " / ",
         DoubleToString(EMA50_H4,Digits),
         " H1=",
         DoubleToString(EMA20_H1,Digits),
         " / ",
         DoubleToString(EMA50_H1,Digits));

   Print("M15 EMA20/50=",
         DoubleToString(EMA20_M15,Digits),
         " / ",
         DoubleToString(EMA50_M15,Digits),
         " RSI=",
         DoubleToString(RSI_M15,2),
         " ATR=",
         DoubleToString(ATR_M15,Digits),
         " ADX=",
         DoubleToString(ADX_M15,2),
         " Vol=",
         Volume_M15);

   Print("M5 EMA20/50=",
         DoubleToString(EMA20_M5,Digits),
         " / ",
         DoubleToString(EMA50_M5,Digits),
         " M1=",
         DoubleToString(EMA20_M1,Digits),
         " / ",
         DoubleToString(EMA50_M1,Digits));

   Print("Sequence: BullPullbackAge=",
         BullPullbackAge,
         " BearPullbackAge=",
         BearPullbackAge,
         " RecentBullCross=",
         RecentBullCross,
         " RecentBearCross=",
         RecentBearCross,
         " PullbackMaxBars=",
         PullbackMaxBars,
         " Lookback=",
         PullbackLookbackBars);

   Print("Cooldown bars=",ReEntryCooldownBars,
         " ConsecutiveLosses=",ConsecutiveLosses,
         " LastClosed=",TimeToString(LastClosedTradeTime,TIME_DATE|TIME_MINUTES),
         " TrailStepPts=",DoubleToString(TrailingStepPoints,1),
         " BreakEvenATR=",DoubleToString(BreakEvenATR,2),
         " TrailStartATR=",DoubleToString(TrailingStartATR,2),
         " BEPlusPts=",DoubleToString(BreakEvenPlusPoints,1));

   Print("Daily trades=",
         TradesToday,
         " DayStartBalance=",
         DoubleToString(DayStartBalance,2),
         " Equity=",
         DoubleToString(AccountEquity(),2));

   Print("-------------------------------------------------");
}

//+------------------------------------------------------------------+
//| END OF T100 TREND RIDER v5.64                                   |
//+------------------------------------------------------------------+
