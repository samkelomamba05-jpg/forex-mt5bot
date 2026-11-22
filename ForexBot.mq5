
//+------------------------------------------------------------------+
//| ForexBot.mq5 - Conservative H1/H4 Forex Expert Advisor           |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
CTrade trade;

input double RiskPercent = 1.0;
input int FastEMA = 20;
input int SlowEMA = 50;
input int ATRPeriod = 14;
input double ATRMultiplier = 2.0;
input double RewardRisk = 2.0;
input int MaxSpreadPoints = 30;
input ulong MagicNumber = 20261122;

int fastH1, slowH1, fastH4, slowH4, atrH1;

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   fastH1 = iMA(_Symbol, PERIOD_H1, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowH1 = iMA(_Symbol, PERIOD_H1, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   fastH4 = iMA(_Symbol, PERIOD_H4, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowH4 = iMA(_Symbol, PERIOD_H4, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   atrH1  = iATR(_Symbol, PERIOD_H1, ATRPeriod);

   if(fastH1 == INVALID_HANDLE || slowH1 == INVALID_HANDLE ||
      fastH4 == INVALID_HANDLE || slowH4 == INVALID_HANDLE ||
      atrH1 == INVALID_HANDLE)
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}

bool ReadValue(int handle, int shift, double &value)
{
   double data[];
   ArraySetAsSeries(data, true);

   if(CopyBuffer(handle, 0, shift, 1, data) != 1)
      return false;

   value = data[0];
   return true;
}

int VolumeDigits(double step)
{
   for(int d = 0; d <= 8; d++)
      if(MathAbs(step - NormalizeDouble(step, d)) < 0.00000001)
         return d;
   return 2;
}

double CalculateLots(double stopDistance)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * RiskPercent / 100.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(tickValue <= 0 || tickSize <= 0 || step <= 0)
      return 0;

   double lossPerLot = (stopDistance / tickSize) * tickValue;
   if(lossPerLot <= 0)
      return 0;

   double lots = riskMoney / lossPerLot;
   lots = MathFloor(lots / step) * step;

   if(lots < minLot)
      return 0;

   lots = MathMin(lots, maxLot);
   return NormalizeDouble(lots, VolumeDigits(step));
}

void OnTick()
{
   // Evaluate once per new H1 candle
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_H1, 0);

   if(currentBar == 0 || currentBar == lastBar)
      return;

   lastBar = currentBar;

   // Avoid trading when spread is too high
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if((ask - bid) / _Point > MaxSpreadPoints)
      return;

   // One open position at a time on this symbol
   if(PositionSelect(_Symbol))
      return;

   double f1, s1, f2, s2, fh4, sh4, atr;

   if(!ReadValue(fastH1, 1, f1) ||
      !ReadValue(slowH1, 1, s1) ||
      !ReadValue(fastH1, 2, f2) ||
      !ReadValue(slowH1, 2, s2) ||
      !ReadValue(fastH4, 1, fh4) ||
      !ReadValue(slowH4, 1, sh4) ||
      !ReadValue(atrH1, 1, atr))
      return;

   if(atr <= 0)
      return;

   bool buySignal = (f2 <= s2 && f1 > s1 && fh4 > sh4);
   bool sellSignal = (f2 >= s2 && f1 < s1 && fh4 < sh4);

   double stopDistance = atr * ATRMultiplier;
   double lots = CalculateLots(stopDistance);

   if(lots <= 0)
      return;

   if(buySignal)
   {
      double sl = NormalizeDouble(ask - stopDistance, _Digits);
      double tp = NormalizeDouble(ask + stopDistance * RewardRisk, _Digits);

      trade.Buy(lots, _Symbol, 0, sl, tp, "ForexBot Buy");
   }

   if(sellSignal)
   {
      double sl = NormalizeDouble(bid + stopDistance, _Digits);
      double tp = NormalizeDouble(bid - stopDistance * RewardRisk, _Digits);

      trade.Sell(lots, _Symbol, 0, sl, tp, "ForexBot Sell");
   }
}

void OnDeinit(const int reason)
{
   IndicatorRelease(fastH1);
   IndicatorRelease(slowH1);
   IndicatorRelease(fastH4);
   IndicatorRelease(slowH4);
   IndicatorRelease(atrH1);
}
