//+------------------------------------------------------------------+
//|                                                T100 Trend Rider  |
//|                           Version 2.0                            |
//|                     Professional Multi-Timeframe EA              |
//|                       Copyright 2026 Rupert                      |
//+------------------------------------------------------------------+

#property strict
#property version   "2.00"

//==========================================================
// INPUTS
//==========================================================

//---------------- Trend ----------------
input int      FastEMA              =20;
input int      SlowEMA              =50;

//---------------- RSI ------------------
input int      RSIPeriod            =14;
input double   BullRSI              =55;
input double   BearRSI              =45;

//---------------- ATR ------------------
input int      ATRPeriod            =14;
input double   MinATR               =0.0008;

//---------------- ADX ------------------
input int      ADXPeriod            =14;
input double   MinADX               =20;

//---------------- Money Management -----
input double   RiskPercent          =1.0;
input double   MaxDailyLoss         =3.0;
input int    MaxTradesPerDay      =5;

//---------------- Stops ----------------
input int      StopLoss             =100;
input int      TakeProfit           =200;
input double BreakEvenATR = 2.0;
input double TrailingATR  = 1.5;

//---------------- Filters --------------
input int      MaxSpread            =50;
input long     MinVolume            =100;

//---------------- Trading Hours --------
input int      TradingStartHour     =0;
input int      TradingEndHour       =24;

//---------------- General --------------
input int      MagicNumber          =1001;
input bool     DebugMode            =true;

extern int RequiredEntryScore = 70;

input int MinimumTradeScore = 70;

input double ATR_SL_Multiplier = 2.0;
input double ATR_TP_Multiplier = 3.0;


//==========================================================
// GLOBAL VARIABLES
//==========================================================

bool IsH4Bull=false;
bool IsH4Bear=false;

bool IsH1Bull=false;
bool IsH1Bear=false;

bool IsM15Bull=false;
bool IsM15Bear=false;

bool IsM5Bull=false;
bool IsM5Bear=false;

bool IsM1Bull=false;
bool IsM1Bear=false;

bool TradingHoursOK=false;
bool SpreadOK=false;
bool PauseTrading=false;

double CurrentSpread=0;
double CurrentATR=0;
double CurrentRSI=0;
double CurrentADX=0;

long CurrentVolume=0;

double TrendScore=0;
double TradeScore=0;

datetime LastBar=0;
datetime LastDashboardUpdate=0;

int WinningTrades=0;
int LosingTrades=0;

double TotalProfit=0;

double LargestWin=0;
double LargestLoss=0;

datetime LastTradeTime=0;
int TradesToday=0;
int TradeDay=-1;

bool NewBar=false;

double FastEMA_M1 = 0;
double SlowEMA_M1 = 0;

//==========================================================
// INDICATOR CACHE
//==========================================================

double EMA20_H4;
double EMA50_H4;

double EMA20_H1;
double EMA50_H1;

double EMA20_M15;
double EMA50_M15;

double EMA20_M5;
double EMA50_M5;

double EMA20_M1;
double EMA50_M1;

double RSI_M15;
double ATR_M15;
double ADX_M15;

long Volume_M15;

int OnInit()
{
   Print("=======================================");
   Print("T100 Trend Rider Version 2.0 Started");
   Print("=======================================");

   LastBar=0;

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Comment("");

   Print("T100 Trend Rider stopped.");
}

bool IsNewBar()
{
   datetime CurrentBar=iTime(Symbol(),PERIOD_M1,0);

   if(CurrentBar!=LastBar)
   {
      LastBar=CurrentBar;
      return(true);
   }

   return(false);
}

void OnTick()
{
   if(Bars < 60)
   {
      Print("Not enough bars: ", Bars);
      return;
   }

   if(!IsNewBar())
      return;

   Print("================ NEW BAR ================");

   UpdateIndicators();
   Print("Indicators updated");

   CheckTradingHours();
   Print("TradingHoursOK = ", TradingHoursOK);

   CheckSpread();
   Print("SpreadOK = ", SpreadOK);

   Print("IndicatorsReady = ", IndicatorsReady);

   if(!MarketReady())
   {
      Print("MarketReady = FALSE");
      return;
   }

   Print("MarketReady = TRUE");

   CalculateTrend();
   Print("TrendScore = ", TrendScore);

   CalculateTradeSetup();
   Print("TradeScore = ", TradeScore);
   
   Print("RSI_OK = ", RSI_OK);
Print("ATR_Filter_OK = ", ATR_Filter_OK);
Print("Volume_Filter_OK = ", Volume_Filter_OK);
Print("ADX_Filter_OK = ", ADX_Filter_OK);
Print("Candle_OK = ", Candle_OK);
Print("Pullback_OK = ", Pullback_OK);
Print("Momentum_OK = ", Momentum_OK);
Print("SetupReady = ", SetupReady);
  
   CheckEntry();
   
  CalculateEntryScore();
      Print("EntryScore = ", EntryScore);
         Print("IsM1Bull = ", IsM1Bull);
Print("IsM1Bear = ", IsM1Bear);
Print("BullCross = ", BullCross());
Print("BearCross = ", BearCross());
Print("Close = ", Close[1]);
Print("EMA20_M1_Current = ", EMA20_M1_Current);
Print("TradeSetupReady = ", TradeSetupReady());

   Print("IsM1Bull = ", IsM1Bull);
   Print("IsM1Bear = ", IsM1Bear);

   if(EntryReady() && EntryScore >= MinimumTradeScore)
{
   OpenTrade();
}
   else
   {
      Print("ENTRY NOT READY");
   }

   ManageOpenTrades();

   Print("=========================================");
} 
   
//==========================================================
// UPDATE ALL INDICATORS
//==========================================================

void UpdateIndicators()
{
   //--------------- H4 EMA ----------------
   EMA20_H4 = iMA(Symbol(),PERIOD_H4,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_H4 = iMA(Symbol(),PERIOD_H4,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);

   //--------------- H1 EMA ----------------
   EMA20_H1 = iMA(Symbol(),PERIOD_H1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_H1 = iMA(Symbol(),PERIOD_H1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);

   //--------------- M15 EMA ---------------
   EMA20_M15 = iMA(Symbol(),PERIOD_M15,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_M15 = iMA(Symbol(),PERIOD_M15,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);

   //--------------- M5 EMA ----------------
   EMA20_M5 = iMA(Symbol(),PERIOD_M5,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_M5 = iMA(Symbol(),PERIOD_M5,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);

   //--------------- M1 EMA ----------------
   EMA20_M1 = iMA(Symbol(),PERIOD_M1,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   EMA50_M1 = iMA(Symbol(),PERIOD_M1,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);

   //--------------- RSI -------------------
   RSI_M15 = iRSI(Symbol(),PERIOD_M15,RSIPeriod,PRICE_CLOSE,1);

   //--------------- ATR -------------------
   ATR_M15 = iATR(Symbol(),PERIOD_M15,ATRPeriod,1);

   //--------------- ADX -------------------
   ADX_M15 = iADX(Symbol(),PERIOD_M15,ADXPeriod,PRICE_CLOSE,MODE_MAIN,1);
   
   //--------------- Volume ----------------
   Volume_M15 = iVolume(Symbol(),PERIOD_M15,1);

   CurrentSpread = MarketInfo(Symbol(),MODE_SPREAD);

   ValidateIndicators();
}

//==========================================================
// VALIDATE INDICATORS
//==========================================================

bool IndicatorsReady=false;

void ValidateIndicators()
{
   IndicatorsReady = true;

   if(EMA20_H4==0)
   {
      IndicatorsReady=false;
      Print("EMA20_H4 not ready");
   }

   if(EMA50_H4==0)
   {
      IndicatorsReady=false;
      Print("EMA50_H4 not ready");
   }

   if(EMA20_H1==0)
   {
      IndicatorsReady=false;
      Print("EMA20_H1 not ready");
   }

   if(EMA50_H1==0)
   {
      IndicatorsReady=false;
      Print("EMA50_H1 not ready");
   }

   if(EMA20_M15==0)
   {
      IndicatorsReady=false;
      Print("EMA20_M15 not ready");
        }

   if(EMA50_M15==0)
   {
      IndicatorsReady=false;
      Print("EMA50_M15 not ready");
   }

   if(ATR_M15<=0)
   {
      IndicatorsReady=false;
      Print("ATR_M15 not ready");
   }

   if(RSI_M15<=0)
   {
      IndicatorsReady=false;
      Print("RSI_M15 not ready");
   }

   if(ADX_M15<=0)
   {
      IndicatorsReady=false;
      Print("ADX_M15 not ready");
   }

   if(Volume_M15<=0)
   {
      IndicatorsReady=false;
      Print("Volume_M15 not ready");
   }
}

//==========================================================
// CHECK TRADING HOURS
//==========================================================

void CheckTradingHours()
{
   TradingHoursOK=false;

   int HourNow=Hour();

   if(HourNow>=TradingStartHour &&
      HourNow<TradingEndHour)
      TradingHoursOK=true;
}

//==========================================================
// CHECK SPREAD
//==========================================================

void CheckSpread()
{
   SpreadOK=false;

   CurrentSpread=MarketInfo(Symbol(),MODE_SPREAD);

   if(CurrentSpread<=MaxSpread)
      SpreadOK=true;
}

//==========================================================
// ATR FILTER
//==========================================================

bool ATR_OK()
{
   return(ATR_M15>=MinATR);
}

//==========================================================
// VOLUME FILTER
//==========================================================

bool Volume_OK()
{
   return(Volume_M15>=MinVolume);
}

//==========================================================
// ADX FILTER
//==========================================================

bool ADX_OK()
{
   return(ADX_M15>=MinADX);
}

//==========================================================
// MARKET READY
//==========================================================

bool MarketReady()
{
   if(!IndicatorsReady)
      return(false);

   if(!TradingHoursOK)
      return(false);

   if(!SpreadOK)
      return(false);

   if(!ATR_OK())
      return(false);

   if(!Volume_OK())
      return(false);

   if(!ADX_OK())
      return(false);

   return(true);
}

void PrintIndicators()
{
   if(!DebugMode)
      return;

   Print("---------------------------");

   Print("EMA20 H4 = ",EMA20_H4);
   Print("EMA50 H4 = ",EMA50_H4);

   Print("EMA20 H1 = ",EMA20_H1);
   Print("EMA50 H1 = ",EMA50_H1);

   Print("EMA20 M15 = ",EMA20_M15);
   Print("EMA50 M15 = ",EMA50_M15);

   Print("RSI = ",DoubleToString(RSI_M15,2));

   Print("ATR = ",DoubleToString(ATR_M15,5));

   Print("ADX = ",DoubleToString(ADX_M15,2));

   Print("Volume = ",Volume_M15);

   Print("Spread = ",CurrentSpread);

   Print("---------------------------");
}

//==========================================================
// CALCULATE TREND
//==========================================================

void CalculateTrend()
{
   //-------------------------
   // Reset
   //-------------------------

   IsH4Bull=false;
   IsH4Bear=false;

   IsH1Bull=false;
   IsH1Bear=false;

   IsM15Bull=false;
   IsM15Bear=false;

   IsM5Bull=false;
   IsM5Bear=false;

   //-------------------------
   // H4
   //-------------------------

   if(EMA20_H4 > EMA50_H4)
      IsH4Bull=true;

   if(EMA20_H4 < EMA50_H4)
      IsH4Bear=true;

   //-------------------------
   // H1
   //-------------------------

   if(EMA20_H1 > EMA50_H1)
      IsH1Bull=true;
     
   if(EMA20_H1 < EMA50_H1)
      IsH1Bear=true;

   //-------------------------
   // M15
   //-------------------------

   if(EMA20_M15 > EMA50_M15)
      IsM15Bull=true;

   if(EMA20_M15 < EMA50_M15)
      IsM15Bear=true;

   //-------------------------
   // M5
   //-------------------------

   if(EMA20_M5 > EMA50_M5)
      IsM5Bull=true;

   if(EMA20_M5 < EMA50_M5)
      IsM5Bear=true;

   CalculateTrendScore();
}

 //==========================================================
// TREND SCORE
//==========================================================

void CalculateTrendScore()
{
   TrendScore = 0;

   // H4 and H1 MUST agree
   if(IsH4Bull && IsH1Bull)
   {
      TrendScore = 70;

      if(IsM15Bull)
         TrendScore += 20;

      if(IsM5Bull)
         TrendScore += 10;
   }
   else
   if(IsH4Bear && IsH1Bear)
   {
      TrendScore = -70;

      if(IsM15Bear)
         TrendScore -= 20;

      if(IsM5Bear)
         TrendScore -= 10;
   }
}

//=====================================================
// Trade Score Guide
//
// +100 = Strong Buy
// +70  = Buy
// +50  = Weak Buy
// 0    = Sideways
// -50  = Weak Sell
// -70  = Sell
// -100 = Strong Sell

//==========================================================
// MARKET DIRECTION
//==========================================================

bool MarketBullish()
{
   return(TrendScore >= 40);
}

bool MarketBearish()
{
   return(TrendScore <= -40);
}

//==========================================================
// TREND AGREEMENT
//==========================================================

bool TrendAgreement()
{
   if(IsH4Bull && IsH1Bull)
      return(true);

   if(IsH4Bear && IsH1Bear)
      return(true);

   return(false);
}

input double MinEMADistance = 10;
//==========================================================
// TREND STRENGTH
//==========================================================

bool TrendStrong()
{
   double Distance=MathAbs(EMA20_M15-EMA50_M15);

   if(Distance>=MinEMADistance*Point)
      return(true);

   return(false);
}

//==========================================================
// TREND FILTER
//==========================================================

bool TrendReady()
{
   if(!TrendAgreement())
      return(false);

   if(!TrendStrong())
      return(false);

   return(true);
}

void PrintTrend()
{
   if(!DebugMode)
      return;

   Print("========== Trend ==========");

   Print("H4 Bull = ",IsH4Bull,
         " Bear = ",IsH4Bear);

   Print("H1 Bull = ",IsH1Bull,
         " Bear = ",IsH1Bear);

   Print("M15 Bull = ",IsM15Bull,
         " Bear = ",IsM15Bear);

   Print("M5 Bull = ",IsM5Bull,
         " Bear = ",IsM5Bear);

   Print("Trend Score = ",TrendScore);

   Print("Bullish = ",MarketBullish());

   Print("Bearish = ",MarketBearish());

   Print("Trend Ready = ",TrendReady());

   Print("===========================");
}


//==========================================================
// TRADE SETUP
//==========================================================

bool SetupReady = false;

bool RSI_OK = false;
bool ATR_Filter_OK = false;
bool Volume_Filter_OK = false;
bool ADX_Filter_OK = false;
bool Candle_OK = false;
bool Pullback_OK = false;
bool Momentum_OK = false;

//==========================================================
// CALCULATE TRADE SETUP
//==========================================================

void CalculateTradeSetup()
{
   TradeScore = 0;

   RSI_OK = false;
   ATR_Filter_OK = false;
   Volume_Filter_OK = false;
   ADX_Filter_OK = false;
   Candle_OK = false;
   Pullback_OK = false;
   Momentum_OK = false;

   CheckRSI();

   CheckATR();

   CheckVolume();

   CheckADX();

   CheckCandle();

   CheckPullback();

   CheckMomentum();

 SetupReady =
(
   ATR_Filter_OK &&
   Volume_Filter_OK &&
   ADX_Filter_OK &&
   (
      RSI_OK ||
      Momentum_OK ||
      Candle_OK ||
      Pullback_OK
   )
);
}

//==========================================================
// RSI CHECK
//==========================================================

void CheckRSI()
{
   if(MarketBullish())
   {
      if(RSI_M15 > BullRSI)
      {
         RSI_OK = true;
         TradeScore += 20;
      }
   }

   if(MarketBearish())
   {
      if(RSI_M15 < BearRSI)
      {
         RSI_OK = true;
         TradeScore += 20;
      }
   }
}

//==========================================================
// ATR CHECK
//==========================================================

void CheckATR()
{
   if(ATR_M15 >= MinATR)
   {
      ATR_Filter_OK = true;
      TradeScore += 10;
   }
}

//==========================================================
// VOLUME CHECK
//==========================================================

void CheckVolume()
{
   if(Volume_M15 >= MinVolume)
   {
      Volume_Filter_OK = true;
      TradeScore += 10;
   }
}

//==========================================================
// ADX CHECK
//==========================================================

void CheckADX()
{
   if(ADX_M15 >= MinADX)
   {
      ADX_Filter_OK = true;
      TradeScore += 10;
   }
}

//==========================================================
// CANDLE FILTER
//==========================================================

void CheckCandle()
{
double CandleOpen =
   iOpen(Symbol(),PERIOD_M1,1);

double CandleClose =
   iClose(Symbol(),PERIOD_M1,1);

   if(MarketBullish())
   {
      if(CandleClose > CandleOpen)
      {
         Candle_OK = true;
         TradeScore += 10;
      }
   }

   if(MarketBearish())
   {
      if(CandleClose < CandleOpen)
      {
         Candle_OK = true;
         TradeScore += 10;
      }
   }
}

input double PullbackDistance = 25;
//==========================================================
// PULLBACK CHECK
//==========================================================

void CheckPullback()
{
   double Price = iClose(Symbol(), PERIOD_M1, 1);

   double Distance = MathAbs(Price - EMA20_M15);

   if(Distance <= PullbackDistance * Point)
   {
      Pullback_OK = true;
      TradeScore += 10;
   }
}

//==========================================================
// MOMENTUM CHECK
//==========================================================

void CheckMomentum()
{
   double Body1 =
      MathAbs(
         iClose(Symbol(), PERIOD_M1,1) -
         iOpen(Symbol(), PERIOD_M1,1));

   double Body2 =
      MathAbs(
         iClose(Symbol(), PERIOD_M1,2) -
         iOpen(Symbol(), PERIOD_M1,2));

   if(Body1 > Body2)
   {
      Momentum_OK = true;
      TradeScore += 10;
   }
}

bool TradeSetupReady()
{
   return(SetupReady);
}

void PrintTradeSetup()
{
   if(!DebugMode)
      return;

   Print("========== Trade Setup ==========");

   Print("RSI OK      = ", RSI_OK);

   Print("ATR OK      = ", ATR_Filter_OK);

   Print("Volume OK   = ", Volume_Filter_OK);

   Print("ADX OK      = ", ADX_Filter_OK);

   Print("Candle OK   = ", Candle_OK);

   Print("Pullback OK = ", Pullback_OK);

   Print("Momentum OK = ", Momentum_OK);

   Print("Trade Score = ", TradeScore);

   Print("Setup Ready = ", SetupReady);

   Print("===============================");
}


//==========================================================
// RESET ENTRY SIGNALS
//==========================================================

void ResetEntrySignals()
{
   IsM1Bull = false;
   IsM1Bear = false;
}

//==========================================================
// M1 EMA VALUES
//==========================================================

double EMA20_M1_Current = 0;
double EMA20_M1_Previous = 0;

double EMA50_M1_Current = 0;
double EMA50_M1_Previous = 0;

//==========================================================
// UPDATE M1 EMA VALUES
//==========================================================

void UpdateM1EMAs()
{
   EMA20_M1_Current =
      iMA(Symbol(), PERIOD_M1, FastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);

   EMA20_M1_Previous =
      iMA(Symbol(), PERIOD_M1, FastEMA, 0, MODE_EMA, PRICE_CLOSE, 2);

   EMA50_M1_Current =
      iMA(Symbol(), PERIOD_M1, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);

   EMA50_M1_Previous =
      iMA(Symbol(), PERIOD_M1, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
}

bool BullCross()
{
   return(EMA20_M1_Current > EMA50_M1_Current);
}

bool BearCross()
{
   return(EMA20_M1_Current < EMA50_M1_Current);
}

void CheckEntry()
{
   ResetEntrySignals();
   
   UpdateM1EMAs();
   
   Print("TradeSetupReady = ", TradeSetupReady());
Print("MarketBullish = ", MarketBullish());
Print("MarketBearish = ", MarketBearish());

Print("BullCross = ", BullCross());
Print("BearCross = ", BearCross());

Print("Close = ", Close[1]);
Print("EMA20 = ", EMA20_M1_Current);

   if(!TradeSetupReady())
      return;

   IsM1Bull =
   (
      MarketBullish() &&
      BullCross() &&
      Close[1] > EMA20_M1_Current
   );

   IsM1Bear =
   (
      MarketBearish() &&
      BearCross() &&
      Close[1] < EMA20_M1_Current
   );
}
  

double EntryScore = 0;

void CalculateEntryScore()
{
   EntryScore = 0;

   // BUY
  if(IsM1Bull)
{
   EntryScore += 30;

   if(Momentum_OK)
      EntryScore += 20;

   if(Candle_OK)
      EntryScore += 20;

   if(Pullback_OK)
      EntryScore += 20;

   if(ADX_M15 > MinADX)
      EntryScore += 10;
} 

   // SELL
 if(IsM1Bear)
{
   EntryScore += 30;

   if(Momentum_OK)
      EntryScore += 20;

   if(Candle_OK)
      EntryScore += 20;

   if(Pullback_OK)
      EntryScore += 20;

   if(ADX_M15 > MinADX)
      EntryScore += 10;
}
}

input double MinimumEntryScore = 70;
bool EntryReady()
{
   return(EntryScore >= MinimumEntryScore);
}

void PrintEntry()
{
   if(!DebugMode)
      return;

   Print("========== ENTRY ==========");

   Print("BullCross = ",BullCross());

   Print("BearCross = ",BearCross());

   Print("Entry Score = ",EntryScore);

   Print("Entry Ready = ",EntryReady());

   Print("BUY Signal = ",IsM1Bull);

   Print("SELL Signal = ",IsM1Bear);

   Print("===========================");
}


//========================
// DAILY TRADE LIMIT
//========================

bool DailyTradeLimit()
{
   if(Day()!=TradeDay)
   {
      TradeDay=Day();
      TradesToday=0;
   }

   return(TradesToday<MaxTradesPerDay);
}

//==========================================================
// BROKER CHECK
//==========================================================

bool BrokerReady()
{
   if(!IsTradeAllowed())
   {
      Print("Trading not allowed.");
      return(false);
   }

   if(IsTradeContextBusy())
   {
      Print("Trade context busy.");
      return(false);
   }

   if(AccountFreeMargin()<=0)
   {
      Print("No free margin.");
      return(false);
   }

   return(true);
}

//==========================================================
// CALCULATE LOT SIZE
//==========================================================

double CalculateLot()
{
   double RiskMoney = AccountBalance() * RiskPercent / 100.0;

   double StopDistance = ATR_M15 * ATR_SL_Multiplier;

   if(StopDistance <= 0)
      return(MarketInfo(Symbol(),MODE_MINLOT));

   double TickValue = MarketInfo(Symbol(),MODE_TICKVALUE);

   if(TickValue <= 0)
      return(MarketInfo(Symbol(),MODE_MINLOT));

   double Lots =
      RiskMoney /
      ((StopDistance/Point) * TickValue);

   double MinLot  = MarketInfo(Symbol(),MODE_MINLOT);
   double MaxLot  = MarketInfo(Symbol(),MODE_MAXLOT);
   double LotStep = MarketInfo(Symbol(),MODE_LOTSTEP);

   Lots=MathMax(MinLot,Lots);
   Lots=MathMin(MaxLot,Lots);

   Lots=MathFloor(Lots/LotStep)*LotStep;

   return(NormalizeDouble(Lots,2));
}

int BrokerStopLevel=(int)MarketInfo(Symbol(),MODE_STOPLEVEL);
//==========================================================
// STOPLEVEL CHECK
//==========================================================

bool CheckStopLevel(double SLDistance,double TPDistance)
{
   int StopLevel=(int)MarketInfo(Symbol(),MODE_STOPLEVEL);

   if(SLDistance<StopLevel*Point)
      return(false);

   if(TPDistance<StopLevel*Point)
      return(false);

   return(true);
}

bool PositionExists()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;

      if(OrderMagicNumber()!=MagicNumber)
         continue;

      if(OrderSymbol()!=Symbol())
         continue;

      return(true);
   }

   return(false);
}

void OpenTrade()
{
   if(PositionExists())
      return;

   if(!DailyTradeLimit())
      return;
      
   double Lots = CalculateLot();

   RefreshRates();

   double AskPrice = NormalizeDouble(Ask,Digits);
   double BidPrice = NormalizeDouble(Bid,Digits);

   double StopDistance = ATR_M15 * ATR_SL_Multiplier;
   double TakeDistance = ATR_M15 * ATR_TP_Multiplier;

   if(!CheckStopLevel(StopDistance,TakeDistance))
      return;

   int ticket=-1;

   //--------------------------------------------------
   // BUY
   //--------------------------------------------------

 if(IsM1Bull &&
   EntryReady() &&
   EntryScore >= MinimumTradeScore)
   {
      double BuySL = NormalizeDouble(AskPrice-StopDistance,Digits);
      double BuyTP = NormalizeDouble(AskPrice+TakeDistance,Digits);
  
      ticket=
      OrderSend(
         Symbol(),
         OP_BUY,
         Lots,
         AskPrice,
         3,
         BuySL,
         BuyTP,
         "T100 Trend Rider",
         MagicNumber,
         0,
         clrBlue);

      if(ticket<0)
      {
         PrintTradeError(GetLastError());
         return;
      }
   }

   //--------------------------------------------------
   // SELL
   //--------------------------------------------------

  if(IsM1Bear &&
   EntryReady() &&
   EntryScore >= MinimumTradeScore)
   {
      double SellSL = NormalizeDouble(BidPrice+StopDistance,Digits);
      double SellTP = NormalizeDouble(BidPrice-TakeDistance,Digits);
      
      ticket=
      OrderSend(
         Symbol(),
         OP_SELL,
         Lots,
         BidPrice,
         3,
         SellSL,
         SellTP,
         "T100 Trend Rider",
         MagicNumber,
         0,
         clrRed);

      if(ticket<0)
      {
         PrintTradeError(GetLastError());
         return;
      }
   }

   LastTradeTime = TimeCurrent();
   TradesToday++;

   Print("Trade opened. Ticket=",ticket);
}    

void PrintTradeError(int error)
{
   Print("Trade Error: ",error);

   switch(error)
   {
      case 129: Print("Invalid price"); break;
      case 130: Print("Invalid stops"); break;
      case 131: Print("Invalid volume"); break;
      case 133: Print("Trading disabled"); break;
      case 134: Print("Not enough money"); break;
      case 136: Print("Off quotes"); break;
      case 138: Print("Requote"); break;
      case 146: Print("Trade context busy"); break;

      default:
         Print("Unknown trade error.");
   }
} 


void ManageOpenTrades()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         continue;

      if(OrderMagicNumber()!=MagicNumber)
         continue;

      if(OrderSymbol()!=Symbol())
         continue;

      if(OrderType()==OP_BUY)
         ManageBuyTrade();

      if(OrderType()==OP_SELL)
         ManageSellTrade();
   }
}


void ManageBuyTrade()
{
   double ProfitPoints = (Bid - OrderOpenPrice()) / Point;

   //=========================
   // Break-even
   //=========================

double BreakEvenPoints = (ATR_M15 * BreakEvenATR) / Point;
   if(ProfitPoints >= BreakEvenPoints)
   {
      if(OrderStopLoss() < OrderOpenPrice())
      {
         bool modified = OrderModify(
            OrderTicket(),
            OrderOpenPrice(),
            NormalizeDouble(OrderOpenPrice(),Digits),
            OrderTakeProfit(),
            0,
            clrBlue);

         if(!modified)
            Print("BreakEven BUY Error ",GetLastError());
      }
   }


//=========================
// Trailing Stop
//=========================

double TrailingPoints = ATR_M15 * TrailingATR;

if(ProfitPoints >= TrailingPoints / Point)
{
   double NewSL =
      NormalizeDouble(
         Bid - TrailingPoints,
         Digits);

   if(NewSL > OrderStopLoss())
   {
      bool modified = OrderModify(
         OrderTicket(),
         OrderOpenPrice(),
         NewSL,
         OrderTakeProfit(),
         0,
         clrBlue);

      if(!modified)
         Print("Trailing BUY Error ", GetLastError());
   }
 } 
}

void ManageSellTrade()
{
   double ProfitPoints =
      (OrderOpenPrice()-Ask)/Point;

 //-------------------------------------------------
   // Break Even
   //-------------------------------------------------

 double BreakEvenPoints = (ATR_M15 * BreakEvenATR) / Point;

if(ProfitPoints >= BreakEvenPoints)
   {
      if(OrderStopLoss() > OrderOpenPrice() ||
         OrderStopLoss() == 0)
      {
         bool modified =
            OrderModify(
               OrderTicket(),
               OrderOpenPrice(),
               NormalizeDouble(OrderOpenPrice(),Digits),
               OrderTakeProfit(),
               0,
               clrRed);

         if(!modified)
            Print("OrderModify Error ",GetLastError());
      }
   }

//=========================
// Trailing Stop
//=========================

double TrailingPoints = ATR_M15 * TrailingATR;

if(ProfitPoints >= TrailingPoints / Point)
{
   double NewSL =
      NormalizeDouble(
         Ask + TrailingPoints,
         Digits);

   if(OrderStopLoss()==0 || NewSL < OrderStopLoss())
   {
      bool modified = OrderModify(
         OrderTicket(),
         OrderOpenPrice(),
         NewSL,
         OrderTakeProfit(),
         0,
         clrRed);

      if(!modified)
         Print("Trailing SELL Error ", GetLastError());
   }
 } 
}
    void UpdateTradeStatistics()
{

WinningTrades = 0;
LosingTrades  = 0;
TotalProfit   = 0;

LargestWin    = 0;
LargestLoss   = 0;

   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))
         continue;

      if(OrderMagicNumber()!=MagicNumber)
         continue;

      if(OrderSymbol()!=Symbol())
         continue;

      double Profit=
         OrderProfit()+
         OrderSwap()+
         OrderCommission();

      TotalProfit+=Profit;

      if(Profit>0)
      {
         WinningTrades++;

         if(Profit>LargestWin)
            LargestWin=Profit;
      }
  
      if(Profit<0)
      {
         LosingTrades++;

         if(Profit<LargestLoss)
            LargestLoss=Profit;
      }
   }
}

      