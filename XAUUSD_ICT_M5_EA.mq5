//+------------------------------------------------------------------+
//|                                             XAUUSD_ICT_M5_EA.mq5 |
//|            ICT-style Expert Advisor for XAUUSD on M5 (FX24 demo) |
//+------------------------------------------------------------------+
#property copyright   "MetaTrader Assistant"
#property link        ""
#property version     "1.00"
#property description "XAUUSD M5 EA: EMA20/50/200 + RSI filter with BOS, CHOCH, Liquidity Sweep, Order Block and FVG (ICT) pattern detection."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Trade settings ==="
input double InpLotSize            = 0.01;    // Lot size (0.01 recommended)
input int    InpStopLossPoints     = 500;     // Stop Loss in points (100 pts = 1.00 on XAUUSD)
input int    InpTakeProfitPoints   = 1000;    // Take Profit in points
input long   InpMagicNumber        = 250508;  // Magic number
input bool   InpOnePositionAtATime = true;    // Only one open position at a time
input int    InpMaxSpreadPoints    = 300;     // Max spread allowed (points)
input int    InpSlippagePoints     = 50;      // Max slippage (points)

input group "=== Indicator settings ==="
input int    InpEmaFastPeriod      = 20;      // EMA fast period (20)
input int    InpEmaMidPeriod       = 50;      // EMA mid period (50)
input int    InpEmaSlowPeriod      = 200;     // EMA slow period (200)
input int    InpRsiPeriod          = 14;      // RSI period (14)
input double InpRsiBuyLevel        = 50.0;    // RSI buy threshold (>=)
input double InpRsiSellLevel       = 50.0;    // RSI sell threshold (<=)

input group "=== Pattern detection settings ==="
input bool   InpUseBOS             = true;    // Enable BOS (Break of Structure)
input bool   InpUseCHOCH           = true;    // Enable CHOCH (Change of Character)
input bool   InpUseLiquiditySweep  = true;    // Enable Liquidity Sweep
input bool   InpUseOrderBlock      = true;    // Enable Order Block
input bool   InpUseFVG             = true;    // Enable FVG (Fair Value Gap)
input int    InpSwingStrength      = 2;       // Swing points strength (bars each side)
input int    InpSwingLookback      = 15;      // Swing points search window (bars)
input int    InpFreshBars          = 5;       // Pattern freshness window (bars)
input int    InpOrderBlockLookback = 20;      // Order Block search window (bars)
input int    InpFVGLookback        = 20;      // FVG search window (bars)
input int    InpMinImpulsePoints   = 250;     // Min impulse move for Order Block (points)
input bool   InpDebugPrints        = false;   // Print detected patterns on every bar

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade   trade;
int      hEmaFast = INVALID_HANDLE;
int      hEmaMid  = INVALID_HANDLE;
int      hEmaSlow = INVALID_HANDLE;
int      hRSI     = INVALID_HANDLE;
double   gEmaFast[];
double   gEmaMid[];
double   gEmaSlow[];
double   gRSI[];
datetime gLastBarTime = 0;

#define EA_NEED_BARS 300   // minimum bars to be loaded for a stable EMA200

//--- prototypes
bool   IsNewBar();
bool   InitIndicatorHandles();
bool   UpdateIndicatorBuffers(int needBars);
bool   CanTrade();
bool   HasOpenPosition();
int    FindLatestSwingHigh(const MqlRates &r[], int fromShift, int toShift, int strength);
int    FindLatestSwingLow (const MqlRates &r[], int fromShift, int toShift, int strength);
bool   SignalBullishBOS(const MqlRates &r[], int total);
bool   SignalBearishBOS(const MqlRates &r[], int total);
bool   SignalBullishCHOCH(const MqlRates &r[], int total);
bool   SignalBearishCHOCH(const MqlRates &r[], int total);
bool   SignalBullishSweep(const MqlRates &r[], int total);
bool   SignalBearishSweep(const MqlRates &r[], int total);
bool   SignalBullishOB(const MqlRates &r[], int total);
bool   SignalBearishOB(const MqlRates &r[], int total);
bool   SignalBullishFVG(const MqlRates &r[], int total);
bool   SignalBearishFVG(const MqlRates &r[], int total);
bool   PlaceOrder(bool isBuy, string reason);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(!InitIndicatorHandles())
      return(INIT_FAILED);

   if(InpLotSize <= 0.0)
      Print("Warning: invalid lot size, using 0.01.");
   if(InpStopLossPoints <= 0)
      Print("Warning: Stop Loss is disabled (0).");
   if(InpTakeProfitPoints <= 0)
      Print("Warning: Take Profit is disabled (0).");

   Print("XAUUSD_ICT_M5_EA initialized. Symbol = ", _Symbol,
         ", Period = ", EnumToString(Period()));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hEmaFast != INVALID_HANDLE) IndicatorRelease(hEmaFast);
   if(hEmaMid  != INVALID_HANDLE) IndicatorRelease(hEmaMid);
   if(hEmaSlow != INVALID_HANDLE) IndicatorRelease(hEmaSlow);
   if(hRSI     != INVALID_HANDLE) IndicatorRelease(hRSI);
   Print("XAUUSD_ICT_M5_EA deinitialized. Reason code = ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- work only once on each new (completed) bar
   if(!IsNewBar())
      return;

   int needBars = EA_NEED_BARS;
   if(!UpdateIndicatorBuffers(needBars))
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, needBars, rates);
   if(copied < needBars)
   {
      Print("Not enough bars copied: ", copied);
      return;
   }

   if(!CanTrade())
      return;

   if(InpOnePositionAtATime && HasOpenPosition())
      return;

   //--- collect all pattern signals
   bool bosB  = InpUseBOS            ? SignalBullishBOS(rates, copied)   : false;
   bool bosS  = InpUseBOS            ? SignalBearishBOS(rates, copied)   : false;
   bool chB   = InpUseCHOCH          ? SignalBullishCHOCH(rates, copied) : false;
   bool chS   = InpUseCHOCH          ? SignalBearishCHOCH(rates, copied) : false;
   bool swB   = InpUseLiquiditySweep ? SignalBullishSweep(rates, copied) : false;
   bool swS   = InpUseLiquiditySweep ? SignalBearishSweep(rates, copied) : false;
   bool obB   = InpUseOrderBlock     ? SignalBullishOB(rates, copied)    : false;
   bool obS   = InpUseOrderBlock     ? SignalBearishOB(rates, copied)    : false;
   bool fvgB  = InpUseFVG            ? SignalBullishFVG(rates, copied)   : false;
   bool fvgS  = InpUseFVG            ? SignalBearishFVG(rates, copied)   : false;

   //--- optional debug print (useful in the Strategy Tester)
   if(InpDebugPrints)
   {
      Print("[ICT] BOS(", bosB, "/", bosS, ") CHOCH(", chB, "/", chS,
            ") SWEEP(", swB, "/", swS, ") OB(", obB, "/", obS,
            ") FVG(", fvgB, "/", fvgS, ")");
   }

   //--- trend filter: EMA alignment
   bool trendUp   = (gEmaFast[1] > gEmaMid[1] && gEmaMid[1] > gEmaSlow[1]);
   bool trendDown = (gEmaFast[1] < gEmaMid[1] && gEmaMid[1] < gEmaSlow[1]);

   //--- momentum filter: RSI
   bool rsiUp   = (gRSI[1] >= InpRsiBuyLevel);
   bool rsiDown = (gRSI[1] <= InpRsiSellLevel);

   //--- BUY logic: uptrend + RSI + at least one bullish ICT pattern
   string reason = "";
   bool doBuy  = false;
   bool doSell = false;

   if(trendUp && rsiUp)
   {
      if(bosB)       { doBuy = true; reason = "BOS"; }
      else if(chB)   { doBuy = true; reason = "CHOCH"; }
      else if(swB)   { doBuy = true; reason = "Liquidity Sweep"; }
      else if(obB)   { doBuy = true; reason = "Order Block"; }
      else if(fvgB)  { doBuy = true; reason = "FVG"; }
   }

   //--- SELL logic: downtrend + RSI + at least one bearish ICT pattern
   if(trendDown && rsiDown)
   {
      if(bosS)       { doSell = true; reason = "BOS"; }
      else if(chS)   { doSell = true; reason = "CHOCH"; }
      else if(swS)   { doSell = true; reason = "Liquidity Sweep"; }
      else if(obS)   { doSell = true; reason = "Order Block"; }
      else if(fvgS)  { doSell = true; reason = "FVG"; }
   }

   //--- execute one direction only
   if(doBuy && !doSell)
   {
      if(PlaceOrder(true, reason))
         Print("BUY signal fired (", reason, ") at ", TimeToString(TimeCurrent()));
   }
   else if(doSell && !doBuy)
   {
      if(PlaceOrder(false, reason))
         Print("SELL signal fired (", reason, ") at ", TimeToString(TimeCurrent()));
   }
}

//+------------------------------------------------------------------+
//| Create indicator handles                                         |
//+------------------------------------------------------------------+
bool InitIndicatorHandles()
{
   hEmaFast = iMA(_Symbol, PERIOD_CURRENT, InpEmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hEmaMid  = iMA(_Symbol, PERIOD_CURRENT, InpEmaMidPeriod,  0, MODE_EMA, PRICE_CLOSE);
   hEmaSlow = iMA(_Symbol, PERIOD_CURRENT, InpEmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hRSI     = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);

   if(hEmaFast == INVALID_HANDLE || hEmaMid == INVALID_HANDLE ||
      hEmaSlow == INVALID_HANDLE || hRSI == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles. Error: ", GetLastError());
      return(false);
   }
   return(true);
}

//+------------------------------------------------------------------+
//| Copy fresh indicator values                                      |
//+------------------------------------------------------------------+
bool UpdateIndicatorBuffers(int needBars)
{
   if(Bars(_Symbol, PERIOD_CURRENT) < needBars)
   {
      Print("Not enough bars on the chart: ", Bars(_Symbol, PERIOD_CURRENT));
      return(false);
   }

   ArraySetAsSeries(gEmaFast, true);
   ArraySetAsSeries(gEmaMid,  true);
   ArraySetAsSeries(gEmaSlow, true);
   ArraySetAsSeries(gRSI,     true);

   if(CopyBuffer(hEmaFast, 0, 0, needBars, gEmaFast) < needBars) return(false);
   if(CopyBuffer(hEmaMid,  0, 0, needBars, gEmaMid)  < needBars) return(false);
   if(CopyBuffer(hEmaSlow, 0, 0, needBars, gEmaSlow) < needBars) return(false);
   if(CopyBuffer(hRSI,     0, 0, needBars, gRSI)     < needBars) return(false);

   return(true);
}

//+------------------------------------------------------------------+
//| Detect a new closed bar                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = (datetime)SeriesInfoInteger(_Symbol, PERIOD_CURRENT, SERIES_LASTBAR_TIME);
   if(t != gLastBarTime)
   {
      gLastBarTime = t;
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Pre-trade safety checks                                          |
//+------------------------------------------------------------------+
bool CanTrade()
{
   long tradeMode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tradeMode != SYMBOL_TRADE_MODE_FULL &&
      tradeMode != SYMBOL_TRADE_MODE_LONG &&
      tradeMode != SYMBOL_TRADE_MODE_SHORT)
   {
      Print("Trading is disabled for ", _Symbol, " (trade mode = ", tradeMode, ")");
      return(false);
   }

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
   {
      Print("Spread too high: ", spread, " points (max ", InpMaxSpreadPoints, "). Skipping.");
      return(false);
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double margin = 0.0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, InpLotSize, ask, margin))
   {
      Print("OrderCalcMargin failed. Error: ", GetLastError());
      return(false);
   }
   if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      Print("Not enough free margin: need ", margin, ", available ",
            AccountInfoDouble(ACCOUNT_MARGIN_FREE));
      return(false);
   }

   return(true);
}

//+------------------------------------------------------------------+
//| Check for an open position with our magic number                 |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Swing point helpers (as-series shifts)                           |
//+------------------------------------------------------------------+
bool IsSwingHighAt(const MqlRates &r[], int s, int strength)
{
   if(s - strength < 1)
      return(false);
   double h = r[s].high;
   for(int k = 1; k <= strength; k++)
   {
      if(r[s - k].high >= h || r[s + k].high >= h)
         return(false);
   }
   return(true);
}

bool IsSwingLowAt(const MqlRates &r[], int s, int strength)
{
   if(s - strength < 1)
      return(false);
   double l = r[s].low;
   for(int k = 1; k <= strength; k++)
   {
      if(r[s - k].low <= l || r[s + k].low <= l)
         return(false);
   }
   return(true);
}

int FindLatestSwingHigh(const MqlRates &r[], int fromShift, int toShift, int strength)
{
   for(int s = fromShift; s <= toShift; s++)
   {
      if(IsSwingHighAt(r, s, strength))
         return(s);
   }
   return(-1);
}

int FindLatestSwingLow(const MqlRates &r[], int fromShift, int toShift, int strength)
{
   for(int s = fromShift; s <= toShift; s++)
   {
      if(IsSwingLowAt(r, s, strength))
         return(s);
   }
   return(-1);
}

//+------------------------------------------------------------------+
//| BOS - Break of Structure                                         |
//| Bullish: price closed above the most recent swing high.         |
//| Bearish: price closed below the most recent swing low.          |
//+------------------------------------------------------------------+
bool SignalBullishBOS(const MqlRates &r[], int total)
{
   if(total < 40)
      return(false);
   int fromShift = 1 + InpSwingStrength;
   int toShift   = fromShift + InpSwingLookback;
   int s = FindLatestSwingHigh(r, fromShift, toShift, InpSwingStrength);
   if(s < 0)
      return(false);
   for(int b = 1; b < s; b++)
   {
      if(b > InpFreshBars)
         break;
      if(r[b].close > r[s].high)
         return(true);
   }
   return(false);
}

bool SignalBearishBOS(const MqlRates &r[], int total)
{
   if(total < 40)
      return(false);
   int fromShift = 1 + InpSwingStrength;
   int toShift   = fromShift + InpSwingLookback;
   int s = FindLatestSwingLow(r, fromShift, toShift, InpSwingStrength);
   if(s < 0)
      return(false);
   for(int b = 1; b < s; b++)
   {
      if(b > InpFreshBars)
         break;
      if(r[b].close < r[s].low)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| CHOCH - Change of Character                                      |
//| Bullish: prior downtrend, then price closed above last swing    |
//|          high (character changed to bullish).                    |
//| Bearish: prior uptrend, then price closed below last swing low. |
//+------------------------------------------------------------------+
bool SignalBullishCHOCH(const MqlRates &r[], int total)
{
   if(total < 40)
      return(false);
   //--- trend was down a few bars ago
   if(gEmaFast[3] >= gEmaMid[3])
      return(false);
   int fromShift = 1 + InpSwingStrength;
   int toShift   = fromShift + InpSwingLookback;
   int s = FindLatestSwingHigh(r, fromShift, toShift, InpSwingStrength);
   if(s < 0)
      return(false);
   for(int b = 1; b < s; b++)
   {
      if(b > InpFreshBars)
         break;
      if(r[b].close > r[s].high)
         return(true);
   }
   return(false);
}

bool SignalBearishCHOCH(const MqlRates &r[], int total)
{
   if(total < 40)
      return(false);
   //--- trend was up a few bars ago
   if(gEmaFast[3] <= gEmaMid[3])
      return(false);
   int fromShift = 1 + InpSwingStrength;
   int toShift   = fromShift + InpSwingLookback;
   int s = FindLatestSwingLow(r, fromShift, toShift, InpSwingStrength);
   if(s < 0)
      return(false);
   for(int b = 1; b < s; b++)
   {
      if(b > InpFreshBars)
         break;
      if(r[b].close < r[s].low)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Liquidity Sweep (stop hunt)                                      |
//| Bullish: a recent bar wicks below a swing low but closes above  |
//|          it (sell-side liquidity swept, reversal expected).      |
//| Bearish: a recent bar wicks above a swing high but closes below |
//|          it.                                                     |
//+------------------------------------------------------------------+
bool SignalBullishSweep(const MqlRates &r[], int total)
{
   if(total < 40)
      return(false);
   int fromShift = 1 + InpSwingStrength;
   int toShift   = fromShift + InpSwingLookback;
   int s = FindLatestSwingLow(r, fromShift, toShift, InpSwingStrength);
   if(s < 0)
      return(false);
   for(int b = 1; b < s; b++)
   {
      if(b > InpFreshBars)
         break;
      if(r[b].low < r[s].low && r[b].close > r[s].low)
         return(true);
   }
   return(false);
}

bool SignalBearishSweep(const MqlRates &r[], int total)
{
   if(total < 40)
      return(false);
   int fromShift = 1 + InpSwingStrength;
   int toShift   = fromShift + InpSwingLookback;
   int s = FindLatestSwingHigh(r, fromShift, toShift, InpSwingStrength);
   if(s < 0)
      return(false);
   for(int b = 1; b < s; b++)
   {
      if(b > InpFreshBars)
         break;
      if(r[b].high > r[s].high && r[b].close < r[s].high)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Order Block (ICT)                                                |
//| Bullish: last bearish candle before a strong bullish impulse,   |
//|          then price retests the OB zone.                         |
//| Bearish: last bullish candle before a strong bearish impulse,   |
//|          then price retests the OB zone.                         |
//+------------------------------------------------------------------+
bool SignalBullishOB(const MqlRates &r[], int total)
{
   if(total < 40)
      return(false);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minMove = InpMinImpulsePoints * point;
   int limit = (int)MathMin((double)InpOrderBlockLookback, (double)(total - 3));

   for(int s = 2; s <= limit; s++)
   {
      //--- OB candle must be bearish
      if(r[s].close >= r[s].open)
         continue;
      //--- next (more recent) candle must be a strong bullish impulse
      int s1 = s - 1;
      if(r[s1].close <= r[s1].open)
         continue;
      if((r[s1].close - r[s1].open) < minMove)
         continue;
      if(r[s1].close <= r[s].high)
         continue;
      //--- retest: the last closed bar overlapped the OB zone
      if(r[1].low <= r[s].high && r[1].high >= r[s].low)
         return(true);
   }
   return(false);
}

bool SignalBearishOB(const MqlRates &r[], int total)
{
   if(total < 40)
      return(false);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minMove = InpMinImpulsePoints * point;
   int limit = (int)MathMin((double)InpOrderBlockLookback, (double)(total - 3));

   for(int s = 2; s <= limit; s++)
   {
      //--- OB candle must be bullish
      if(r[s].close <= r[s].open)
         continue;
      //--- next (more recent) candle must be a strong bearish impulse
      int s1 = s - 1;
      if(r[s1].close >= r[s1].open)
         continue;
      if((r[s1].open - r[s1].close) < minMove)
         continue;
      if(r[s1].close >= r[s].low)
         continue;
      //--- retest: the last closed bar overlapped the OB zone
      if(r[1].low <= r[s].high && r[1].high >= r[s].low)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| FVG - Fair Value Gap                                             |
//| Bullish: low of the newest candle above high of the oldest      |
//|          candle in a 3-candle sequence, then price retests the  |
//|          gap.                                                    |
//| Bearish: the mirror image.                                       |
//+------------------------------------------------------------------+
bool SignalBullishFVG(const MqlRates &r[], int total)
{
   if(total < 40)
      return(false);
   int limit = (int)MathMin((double)InpFVGLookback, (double)(total - 3));

   for(int s = 2; s <= limit; s++)
   {
      //--- bullish gap: low(s) > high(s+2)
      if(r[s].low <= r[s + 2].high)
         continue;
      //--- freshness
      if(s > InpFreshBars + 2)
         continue;
      //--- retest: last closed bar overlapped the gap zone
      if(r[1].high >= r[s + 2].high && r[1].low <= r[s].low)
         return(true);
   }
   return(false);
}

bool SignalBearishFVG(const MqlRates &r[], int total)
{
   if(total < 40)
      return(false);
   int limit = (int)MathMin((double)InpFVGLookback, (double)(total - 3));

   for(int s = 2; s <= limit; s++)
   {
      //--- bearish gap: high(s) < low(s+2)
      if(r[s].high >= r[s + 2].low)
         continue;
      //--- freshness
      if(s > InpFreshBars + 2)
         continue;
      //--- retest: last closed bar overlapped the gap zone
      if(r[1].low <= r[s + 2].low && r[1].high >= r[s].high)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Place a market order with SL/TP                                  |
//+------------------------------------------------------------------+
bool PlaceOrder(bool isBuy, string reason)
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double price  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                         : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0.0;
   double tp = 0.0;

   if(InpStopLossPoints > 0)
      sl = isBuy ? price - InpStopLossPoints * point
                 : price + InpStopLossPoints * point;
   if(InpTakeProfitPoints > 0)
      tp = isBuy ? price + InpTakeProfitPoints * point
                 : price - InpTakeProfitPoints * point;

   //--- enforce broker minimum stop distance
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLevel > 0)
   {
      double minDist = stopsLevel * point;
      if(sl > 0.0 && MathAbs(sl - price) < minDist)
         sl = isBuy ? price - minDist : price + minDist;
      if(tp > 0.0 && MathAbs(tp - price) < minDist)
         tp = isBuy ? price + minDist : price - minDist;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   string comment = "ICT_" + reason;
   bool ok = false;

   if(isBuy)
      ok = trade.Buy(InpLotSize, _Symbol, 0.0, sl, tp, comment);
   else
      ok = trade.Sell(InpLotSize, _Symbol, 0.0, sl, tp, comment);

   if(!ok)
   {
      Print("Order failed. Retcode = ", trade.ResultRetcode(),
            " (", trade.ResultRetcodeDescription(), "), error = ", GetLastError());
   }
   return(ok);
}
//+------------------------------------------------------------------+