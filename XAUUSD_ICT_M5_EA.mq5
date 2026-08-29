//+------------------------------------------------------------------+
//| XAUUSD_ICT_M5_EA.mq5                                             |
//| ICT/SMC multi-confirmation EA for XAUUSD M5                      |
//| Safe-by-default: Demo/Strategy Tester first                      |
//+------------------------------------------------------------------+
#property strict
#property version   "2.01"
#property description "XAUUSD M5 ICT/SMC EA with MSS, BOS, CHOCH, liquidity, OB, FVG, Fibonacci, EMA, RSI and ATR confirmations."

#include <Trade/Trade.mqh>
CTrade trade;

input group "=== Safety / Trading ==="
input bool   InpEnableTrading       = false;
input double InpLotSize              = 0.01;
input long   InpMagicNumber          = 250508;
input bool   InpOnePositionAtATime   = true;
input int    InpMaxSpreadPoints      = 300;
input int    InpSlippagePoints       = 50;
input int    InpMaxTradesPerDay      = 3;
input double InpMaxDailyLossMoney    = 10.0;

input group "=== Risk / Exits ==="
input int    InpATRPeriod             = 14;
input double InpSL_ATR_Mult           = 1.5;
input double InpTP_RR                 = 2.0;
input int    InpMinSLPoints           = 300;
input int    InpMaxSLPoints           = 1500;

input group "=== EMA / RSI ==="
input int    InpEmaFastPeriod         = 20;
input int    InpEmaMidPeriod          = 50;
input int    InpEmaSlowPeriod         = 200;
input int    InpRsiPeriod              = 14;
input double InpRsiBuyLevel            = 52.0;
input double InpRsiSellLevel           = 48.0;

input group "=== Structure / ICT ==="
input int    InpSwingStrength          = 2;
input int    InpSwingLookback          = 80;
input int    InpStructureBufferPoints  = 10;
input int    InpFreshBars              = 8;
input int    InpMinImpulsePoints       = 150;

input group "=== Fibonacci ==="
input bool   InpUseFibonacci           = true;
input double InpFibMin                 = 0.618;
input double InpFibOTE1                = 0.705;
input double InpFibOTE2                = 0.786;
input double InpFibMax                 = 0.786;
input int    InpFibTolerancePoints     = 100;

input group "=== Confirmation Score ==="
input bool   InpRequireLiquidity       = true;
input bool   InpRequireStructure       = true;
input int    InpMinScore               = 7;
input bool   InpDebugPrints            = true;

int hEma20=INVALID_HANDLE,hEma50=INVALID_HANDLE,hEma200=INVALID_HANDLE,hRSI=INVALID_HANDLE,hATR=INVALID_HANDLE;
double ema20[],ema50[],ema200[],rsi[],atr[];
datetime lastBar=0;
int tradesToday=0;
datetime dayStart=0;

enum Direction { DIR_NONE=0, DIR_BUY=1, DIR_SELL=-1 };

bool IsNewBar();
bool LoadIndicators();
bool CanTrade();
bool HasPosition();
int  SwingHigh(const MqlRates &r[],int total,int fromShift);
int  SwingLow(const MqlRates &r[],int total,int fromShift);
bool BullBOS(const MqlRates &r[],int total);
bool BearBOS(const MqlRates &r[],int total);
bool BullCHOCH(const MqlRates &r[],int total);
bool BearCHOCH(const MqlRates &r[],int total);
bool BullMSS(const MqlRates &r[],int total);
bool BearMSS(const MqlRates &r[],int total);
bool BullSweep(const MqlRates &r[],int total);
bool BearSweep(const MqlRates &r[],int total);
bool BullOB(const MqlRates &r[],int total);
bool BearOB(const MqlRates &r[],int total);
bool BullFVG(const MqlRates &r[],int total);
bool BearFVG(const MqlRates &r[],int total);
bool BullFib(const MqlRates &r[],int total);
bool BearFib(const MqlRates &r[],int total);
void EvaluateAndTrade(const MqlRates &r[],int total);
bool PlaceOrder(bool buy,string reason);
void ResetDailyCounters();

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   hEma20=iMA(_Symbol,PERIOD_CURRENT,InpEmaFastPeriod,0,MODE_EMA,PRICE_CLOSE);
   hEma50=iMA(_Symbol,PERIOD_CURRENT,InpEmaMidPeriod,0,MODE_EMA,PRICE_CLOSE);
   hEma200=iMA(_Symbol,PERIOD_CURRENT,InpEmaSlowPeriod,0,MODE_EMA,PRICE_CLOSE);
   hRSI=iRSI(_Symbol,PERIOD_CURRENT,InpRsiPeriod,PRICE_CLOSE);
   hATR=iATR(_Symbol,PERIOD_CURRENT,InpATRPeriod);

   if(hEma20==INVALID_HANDLE || hEma50==INVALID_HANDLE || hEma200==INVALID_HANDLE || hRSI==INVALID_HANDLE || hATR==INVALID_HANDLE)
      return INIT_FAILED;

   ResetDailyCounters();
   Print("XAUUSD ICT M5 EA v2.01 initialized. Trading=",InpEnableTrading," Symbol=",_Symbol," TF=",EnumToString((ENUM_TIMEFRAMES)_Period));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hEma20!=INVALID_HANDLE) IndicatorRelease(hEma20);
   if(hEma50!=INVALID_HANDLE) IndicatorRelease(hEma50);
   if(hEma200!=INVALID_HANDLE) IndicatorRelease(hEma200);
   if(hRSI!=INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
}

void OnTick()
{
   if(!IsNewBar()) return;
   if(!LoadIndicators()) return;

   MqlRates r[];
   ArraySetAsSeries(r,true);
   int n=CopyRates(_Symbol,PERIOD_CURRENT,0,350,r);
   if(n<250) return;

   ResetDailyCounters();
   if(!CanTrade()) return;
   if(InpOnePositionAtATime && HasPosition()) return;
   EvaluateAndTrade(r,n);
}

bool IsNewBar()
{
   datetime t=iTime(_Symbol,PERIOD_CURRENT,0);
   if(t<=0) return false;
   if(t!=lastBar)
   {
      lastBar=t;
      return true;
   }
   return false;
}

bool LoadIndicators()
{
   ArraySetAsSeries(ema20,true);
   ArraySetAsSeries(ema50,true);
   ArraySetAsSeries(ema200,true);
   ArraySetAsSeries(rsi,true);
   ArraySetAsSeries(atr,true);
   const int n=350;

   if(CopyBuffer(hEma20,0,0,n,ema20)<n) return false;
   if(CopyBuffer(hEma50,0,0,n,ema50)<n) return false;
   if(CopyBuffer(hEma200,0,0,n,ema200)<n) return false;
   if(CopyBuffer(hRSI,0,0,n,rsi)<n) return false;
   if(CopyBuffer(hATR,0,0,n,atr)<n) return false;
   return true;
}

void ResetDailyCounters()
{
   MqlDateTime d;
   TimeToStruct(TimeCurrent(),d);
   d.hour=0; d.min=0; d.sec=0;
   datetime ds=StructToTime(d);
   if(ds!=dayStart)
   {
      dayStart=ds;
      tradesToday=0;
   }
}

bool CanTrade()
{
   if(!InpEnableTrading) return false;

   ENUM_SYMBOL_TRADE_MODE mode=(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   if(mode!=SYMBOL_TRADE_MODE_FULL && mode!=SYMBOL_TRADE_MODE_LONGONLY && mode!=SYMBOL_TRADE_MODE_SHORTONLY)
      return false;

   long spread=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   if(spread>InpMaxSpreadPoints) return false;
   if(tradesToday>=InpMaxTradesPerDay) return false;

   if(InpMaxDailyLossMoney>0)
   {
      double pnl=0.0;
      if(HistorySelect(dayStart,TimeCurrent()))
      {
         int deals=HistoryDealsTotal();
         for(int i=0;i<deals;i++)
         {
            ulong tk=HistoryDealGetTicket(i);
            if(tk>0 && HistoryDealGetString(tk,DEAL_SYMBOL)==_Symbol && HistoryDealGetInteger(tk,DEAL_MAGIC)==InpMagicNumber)
               pnl+=HistoryDealGetDouble(tk,DEAL_PROFIT)+HistoryDealGetDouble(tk,DEAL_SWAP)+HistoryDealGetDouble(tk,DEAL_COMMISSION);
         }
      }
      if(pnl<=-InpMaxDailyLossMoney) return false;
   }
   return true;
}

bool HasPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong tk=PositionGetTicket(i);
      if(tk>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)
         return true;
   }
   return false;
}

bool IsSH(const MqlRates &r[],int s,int st,int total)
{
   if(s-st<1 || s+st>=total) return false;
   double h=r[s].high;
   for(int k=1;k<=st;k++)
      if(r[s-k].high>=h || r[s+k].high>=h) return false;
   return true;
}

bool IsSL(const MqlRates &r[],int s,int st,int total)
{
   if(s-st<1 || s+st>=total) return false;
   double l=r[s].low;
   for(int k=1;k<=st;k++)
      if(r[s-k].low<=l || r[s+k].low<=l) return false;
   return true;
}

int SwingHigh(const MqlRates &r[],int total,int from)
{
   int end=MathMin(total-InpSwingStrength-1,from+InpSwingLookback);
   for(int s=from;s<=end;s++)
      if(IsSH(r,s,InpSwingStrength,total)) return s;
   return -1;
}

int SwingLow(const MqlRates &r[],int total,int from)
{
   int end=MathMin(total-InpSwingStrength-1,from+InpSwingLookback);
   for(int s=from;s<=end;s++)
      if(IsSL(r,s,InpSwingStrength,total)) return s;
   return -1;
}

bool BullBOS(const MqlRates &r[],int n)
{
   int h=SwingHigh(r,n,InpSwingStrength+1);
   return h>0 && r[1].close>r[h].high+InpStructureBufferPoints*_Point;
}

bool BearBOS(const MqlRates &r[],int n)
{
   int l=SwingLow(r,n,InpSwingStrength+1);
   return l>0 && r[1].close<r[l].low-InpStructureBufferPoints*_Point;
}

bool BullCHOCH(const MqlRates &r[],int n)
{
   int h=SwingHigh(r,n,InpSwingStrength+1);
   int l=SwingLow(r,n,InpSwingStrength+1);
   if(h<0 || l<0) return false;
   int older=h+10;
   if(older>=n) older=n-1;
   return r[h].high<r[older].high && r[1].close>r[h].high;
}

bool BearCHOCH(const MqlRates &r[],int n)
{
   int h=SwingHigh(r,n,InpSwingStrength+1);
   int l=SwingLow(r,n,InpSwingStrength+1);
   if(h<0 || l<0) return false;
   int older=l+10;
   if(older>=n) older=n-1;
   return r[l].low>r[older].low && r[1].close<r[l].low;
}

bool BullMSS(const MqlRates &r[],int n)
{
   return BullCHOCH(r,n) || BullBOS(r,n);
}

bool BearMSS(const MqlRates &r[],int n)
{
   return BearCHOCH(r,n) || BearBOS(r,n);
}

bool BullSweep(const MqlRates &r[],int n)
{
   int l=SwingLow(r,n,InpSwingStrength+1);
   return l>0 && r[1].low<r[l].low-InpStructureBufferPoints*_Point && r[1].close>r[l].low;
}

bool BearSweep(const MqlRates &r[],int n)
{
   int h=SwingHigh(r,n,InpSwingStrength+1);
   return h>0 && r[1].high>r[h].high+InpStructureBufferPoints*_Point && r[1].close<r[h].high;
}

bool BullOB(const MqlRates &r[],int n)
{
   for(int s=2;s<=InpFreshBars+2 && s<n-2;s++)
   {
      if(r[s].close<r[s].open)
      {
         double imp=r[s-1].high-r[s].low;
         if(imp>=InpMinImpulsePoints*_Point && r[1].close>r[s].high) return true;
      }
   }
   return false;
}

bool BearOB(const MqlRates &r[],int n)
{
   for(int s=2;s<=InpFreshBars+2 && s<n-2;s++)
   {
      if(r[s].close>r[s].open)
      {
         double imp=r[s].high-r[s-1].low;
         if(imp>=InpMinImpulsePoints*_Point && r[1].close<r[s].low) return true;
      }
   }
   return false;
}

bool BullFVG(const MqlRates &r[],int n)
{
   for(int s=1;s<=InpFreshBars && s+2<n;s++)
      if(r[s].low>r[s+2].high) return true;
   return false;
}

bool BearFVG(const MqlRates &r[],int n)
{
   for(int s=1;s<=InpFreshBars && s+2<n;s++)
      if(r[s].high<r[s+2].low) return true;
   return false;
}

bool InFib(double price,double a,double b)
{
   double hi=MathMax(a,b),lo=MathMin(a,b),range=hi-lo;
   if(range<=0) return false;
   double z1=hi-range*InpFibMin;
   double z2=hi-range*InpFibMax;
   double z3=hi-range*InpFibOTE1;
   double z4=hi-range*InpFibOTE2;
   double minz=MathMin(MathMin(z1,z2),MathMin(z3,z4));
   double maxz=MathMax(MathMax(z1,z2),MathMax(z3,z4));
   return price>=minz-InpFibTolerancePoints*_Point && price<=maxz+InpFibTolerancePoints*_Point;
}

bool BearInFib(double price,double a,double b)
{
   double hi=MathMax(a,b),lo=MathMin(a,b),range=hi-lo;
   if(range<=0) return false;
   double z1=lo+range*InpFibMin;
   double z2=lo+range*InpFibMax;
   double z3=lo+range*InpFibOTE1;
   double z4=lo+range*InpFibOTE2;
   double minz=MathMin(MathMin(z1,z2),MathMin(z3,z4));
   double maxz=MathMax(MathMax(z1,z2),MathMax(z3,z4));
   return price>=minz-InpFibTolerancePoints*_Point && price<=maxz+InpFibTolerancePoints*_Point;
}

bool BullFib(const MqlRates &r[],int n)
{
   int h=SwingHigh(r,n,InpSwingStrength+1),l=SwingLow(r,n,InpSwingStrength+1);
   return h>0 && l>0 && h<l && InFib(r[1].close,r[h].high,r[l].low);
}

bool BearFib(const MqlRates &r[],int n)
{
   int h=SwingHigh(r,n,InpSwingStrength+1),l=SwingLow(r,n,InpSwingStrength+1);
   return h>0 && l>0 && l<h && BearInFib(r[1].close,r[l].low,r[h].high);
}

void EvaluateAndTrade(const MqlRates &r[],int n)
{
   bool up=ema20[1]>ema50[1] && ema50[1]>ema200[1];
   bool dn=ema20[1]<ema50[1] && ema50[1]<ema200[1];
   bool rb=rsi[1]>=InpRsiBuyLevel;
   bool rs=rsi[1]<=InpRsiSellLevel;

   bool msb=BullMSS(r,n),mss=BearMSS(r,n);
   bool swb=BullSweep(r,n),sws=BearSweep(r,n);
   bool obb=BullOB(r,n),obs=BearOB(r,n);
   bool fvgb=BullFVG(r,n),fvgs=BearFVG(r,n);
   bool fibB=!InpUseFibonacci || BullFib(r,n);
   bool fibS=!InpUseFibonacci || BearFib(r,n);

   int buy=0,sell=0;
   if(up) buy+=2;
   if(dn) sell+=2;
   if(rb) buy++;
   if(rs) sell++;
   if(msb) buy+=2;
   if(mss) sell+=2;
   if(swb) buy+=2;
   if(sws) sell+=2;
   if(obb) buy++;
   if(obs) sell++;
   if(fvgb) buy++;
   if(fvgs) sell++;
   if(fibB) buy++;
   if(fibS) sell++;

   if(InpRequireLiquidity && !swb) buy=0;
   if(InpRequireLiquidity && !sws) sell=0;
   if(InpRequireStructure && !msb) buy=0;
   if(InpRequireStructure && !mss) sell=0;

   if(InpDebugPrints)
      PrintFormat("ICT score BUY=%d SELL=%d | MSS %d/%d Sweep %d/%d OB %d/%d FVG %d/%d Fib %d/%d EMA %d/%d RSI %.1f",buy,sell,msb,mss,swb,sws,obb,obs,fvgb,fvgs,fibB,fibS,up,dn,rsi[1]);

   if(buy>=InpMinScore && buy>sell)
   {
      string why="MSS+Sweep";
      if(fibB) why+="+Fib";
      if(obb) why+="+OB";
      if(fvgb) why+="+FVG";
      PlaceOrder(true,why);
   }
   else if(sell>=InpMinScore && sell>buy)
   {
      string why="MSS+Sweep";
      if(fibS) why+="+Fib";
      if(obs) why+="+OB";
      if(fvgs) why+="+FVG";
      PlaceOrder(false,why);
   }
}

bool PlaceOrder(bool buy,string reason)
{
   double price=buy ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double a=atr[1];
   if(a<=0) return false;

   int slPts=(int)MathRound(a/_Point*InpSL_ATR_Mult);
   slPts=MathMax(InpMinSLPoints,MathMin(InpMaxSLPoints,slPts));
   int tpPts=(int)MathRound(slPts*InpTP_RR);

   double sl=buy ? price-slPts*_Point : price+slPts*_Point;
   double tp=buy ? price+tpPts*_Point : price-tpPts*_Point;

   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   sl=NormalizeDouble(sl,digits);
   tp=NormalizeDouble(tp,digits);

   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double vol=MathMax(minLot,MathMin(maxLot,InpLotSize));
   if(step>0) vol=MathFloor(vol/step)*step;
   vol=NormalizeDouble(vol,2);

   bool ok=buy ? trade.Buy(vol,_Symbol,0.0,sl,tp,"ICT "+reason) : trade.Sell(vol,_Symbol,0.0,sl,tp,"ICT "+reason);
   if(ok) tradesToday++;
   else Print("Order failed. Retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
   return ok;
}
//+------------------------------------------------------------------+
