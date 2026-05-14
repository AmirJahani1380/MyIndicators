//+------------------------------------------------------------------+
//|                                           EMA_STD_Touch_Gap.mq5   |
//|                                EMA / STD bands touch indicator    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   7

//--- Plot 1: EMA color line
#property indicator_label1  "EMA"
#property indicator_type1   DRAW_COLOR_LINE

//--- Plot 2: Upper band
#property indicator_label2  "Upper STD Band"
#property indicator_type2   DRAW_LINE

//--- Plot 3: Lower band
#property indicator_label3  "Lower STD Band"
#property indicator_type3   DRAW_LINE

//--- Plot 4: Touch from above arrow, below candle
#property indicator_label4  "Touch From Above"
#property indicator_type4   DRAW_ARROW

//--- Plot 5: Touch from below arrow, above candle
#property indicator_label5  "Touch From Below"
#property indicator_type5   DRAW_ARROW

//--- Plot 6: Gap down arrow
#property indicator_label6  "EMA Gap Down"
#property indicator_type6   DRAW_ARROW

//--- Plot 7: Gap up arrow
#property indicator_label7  "EMA Gap Up"
#property indicator_type7   DRAW_ARROW

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+

input group "Main EMA Settings"
input bool              InpShowEMA                    = true;
input int               InpEMAPeriod                  = 50;
input ENUM_MA_METHOD    InpEMAMethod                  = MODE_EMA;
input ENUM_APPLIED_PRICE InpAppliedPrice              = PRICE_CLOSE;
input color             InpEMAColorNormal             = clrCyan;
input color             InpEMAColorSlopeInside        = clrLime;
input ENUM_LINE_STYLE   InpEMAStyle                   = STYLE_SOLID;
input int               InpEMAWidth                   = 2;

input group "STD Band Settings"
input bool              InpShowUpperBand              = true;
input bool              InpShowLowerBand              = true;
input int               InpStdDevPeriod               = 50;
input ENUM_MA_METHOD    InpStdDevMethod               = MODE_SMA;
input double            InpUpperStdMultiplier         = 1.0;
input double            InpLowerStdMultiplier         = 1.0;

input color             InpUpperBandColor             = clrOrange;
input ENUM_LINE_STYLE   InpUpperBandStyle             = STYLE_DASH;
input int               InpUpperBandWidth             = 1;

input color             InpLowerBandColor             = clrOrange;
input ENUM_LINE_STYLE   InpLowerBandStyle             = STYLE_DASH;
input int               InpLowerBandWidth             = 1;

input group "Touch Signal Settings"
input bool              InpEnableTouchSignals         = true;
input bool              InpEnableEMATouch             = true;
input bool              InpEnableUpperBandTouch       = true;
input bool              InpEnableLowerBandTouch       = true;
input int               InpMinBarsBetweenTouches      = 5;
input int               InpTouchArrowOffsetPoints     = 100;

input color             InpTouchFromAboveColor        = clrLime;
input color             InpTouchFromBelowColor        = clrRed;
input int               InpTouchFromAboveArrowCode    = 233;
input int               InpTouchFromBelowArrowCode    = 234;
input int               InpTouchArrowWidth            = 2;

input group "EMA Slope Filter Settings"
input bool              InpUseSlopeFilter             = false;
input bool              InpColorEMAWhenSlopeInside    = true;
input int               InpSlopeLookbackBars          = 5;
input int               InpAverageSlopeBars           = 3;
input double            InpMinSlopePointsPerBar       = -10.0;
input double            InpMaxSlopePointsPerBar       = 10.0;

input group "EMA Gap Bar Settings"
input bool              InpEnableGapSignals           = true;
input bool              InpEnableGapDownAfterAbove    = true;
input bool              InpEnableGapUpAfterBelow      = true;
input bool              InpApplySlopeFilterToGap      = false;
input int               InpGapBars                    = 20;
input int               InpGapArrowOffsetPoints       = 150;

input color             InpGapDownColor               = clrMagenta;
input color             InpGapUpColor                 = clrDodgerBlue;
input int               InpGapDownArrowCode           = 234;
input int               InpGapUpArrowCode             = 233;
input int               InpGapArrowWidth              = 2;

//+------------------------------------------------------------------+
//| Indicator buffers                                                |
//+------------------------------------------------------------------+

double BufferEMA[];
double BufferEMAColorIndex[];
double BufferUpperBand[];
double BufferLowerBand[];
double BufferTouchFromAbove[];
double BufferTouchFromBelow[];
double BufferGapDown[];
double BufferGapUp[];

double StdDevValues[];

//+------------------------------------------------------------------+
//| Handles                                                          |
//+------------------------------------------------------------------+

int EMAHandle    = INVALID_HANDLE;
int StdDevHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Helper functions                                                 |
//+------------------------------------------------------------------+

bool IsValidNumber(const double value)
{
   return(value != EMPTY_VALUE && MathIsValidNumber(value));
}

//+------------------------------------------------------------------+

bool CandleTouchesLine(const int i, const double line_value,
                       const double &high[], const double &low[])
{
   if(!IsValidNumber(line_value))
      return false;

   return(low[i] <= line_value && high[i] >= line_value);
}

//+------------------------------------------------------------------+

bool TouchIsFromAbove(const int i, const double line_value,
                      const double &open[], const double &close[])
{
   if(open[i] > line_value)
      return true;

   if(open[i] < line_value)
      return false;

   if(i > 0)
   {
      if(close[i - 1] > line_value)
         return true;

      if(close[i - 1] < line_value)
         return false;
   }

   return(close[i] > line_value);
}

//+------------------------------------------------------------------+

double RawSlopePointsPerBar(const double &ema[], const int i, const int lookback)
{
   if(lookback <= 0)
      return 0.0;

   if(i - lookback < 0)
      return 0.0;

   if(!IsValidNumber(ema[i]) || !IsValidNumber(ema[i - lookback]))
      return 0.0;

   return((ema[i] - ema[i - lookback]) / (double)lookback / _Point);
}

//+------------------------------------------------------------------+

double AverageSlopePointsPerBar(const double &ema[], const int i,
                                const int lookback, const int average_bars)
{
   if(lookback <= 0 || average_bars <= 0)
      return 0.0;

   double sum   = 0.0;
   int    count = 0;

   int first_bar = i - average_bars + 1;

   if(first_bar < lookback)
      first_bar = lookback;

   for(int j = first_bar; j <= i; j++)
   {
      if(j - lookback < 0)
         continue;

      sum += RawSlopePointsPerBar(ema, j, lookback);
      count++;
   }

   if(count <= 0)
      return 0.0;

   return(sum / (double)count);
}

//+------------------------------------------------------------------+

bool SlopeInsideBoundary(const double slope)
{
   return(slope >= InpMinSlopePointsPerBar && slope <= InpMaxSlopePointsPerBar);
}

//+------------------------------------------------------------------+

bool CandleFullyAboveEMA(const int i,
                         const double &open[],
                         const double &high[],
                         const double &low[],
                         const double &close[],
                         const double &ema[])
{
   if(!IsValidNumber(ema[i]))
      return false;

   return(open[i]  > ema[i] &&
          high[i]  > ema[i] &&
          low[i]   > ema[i] &&
          close[i] > ema[i]);
}

//+------------------------------------------------------------------+

bool CandleFullyBelowEMA(const int i,
                         const double &open[],
                         const double &high[],
                         const double &low[],
                         const double &close[],
                         const double &ema[])
{
   if(!IsValidNumber(ema[i]))
      return false;

   return(open[i]  < ema[i] &&
          high[i]  < ema[i] &&
          low[i]   < ema[i] &&
          close[i] < ema[i]);
}

//+------------------------------------------------------------------+

bool PreviousBarsWereNotFullyBelowEMA(const int i,
                                      const int bars_count,
                                      const double &open[],
                                      const double &high[],
                                      const double &low[],
                                      const double &close[],
                                      const double &ema[])
{
   if(bars_count <= 0)
      return false;

   if(i - bars_count < 0)
      return false;

   for(int j = i - bars_count; j < i; j++)
   {
      if(CandleFullyBelowEMA(j, open, high, low, close, ema))
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+

bool PreviousBarsWereNotFullyAboveEMA(const int i,
                                      const int bars_count,
                                      const double &open[],
                                      const double &high[],
                                      const double &low[],
                                      const double &close[],
                                      const double &ema[])
{
   if(bars_count <= 0)
      return false;

   if(i - bars_count < 0)
      return false;

   for(int j = i - bars_count; j < i; j++)
   {
      if(CandleFullyAboveEMA(j, open, high, low, close, ema))
         return false;
   }

   return true;
}
//+------------------------------------------------------------------+

void ConfigurePlots()
{
   //--- EMA
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, InpShowEMA ? DRAW_COLOR_LINE : DRAW_NONE);
   PlotIndexSetInteger(0, PLOT_LINE_STYLE, InpEMAStyle);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpEMAWidth);
   PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 2);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, InpEMAColorNormal);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, InpEMAColorSlopeInside);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Upper band
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, InpShowUpperBand ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpUpperBandColor);
   PlotIndexSetInteger(1, PLOT_LINE_STYLE, InpUpperBandStyle);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, InpUpperBandWidth);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Lower band
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, InpShowLowerBand ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpLowerBandColor);
   PlotIndexSetInteger(2, PLOT_LINE_STYLE, InpLowerBandStyle);
   PlotIndexSetInteger(2, PLOT_LINE_WIDTH, InpLowerBandWidth);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Touch from above
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, InpEnableTouchSignals ? DRAW_ARROW : DRAW_NONE);
   PlotIndexSetInteger(3, PLOT_ARROW, InpTouchFromAboveArrowCode);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpTouchFromAboveColor);
   PlotIndexSetInteger(3, PLOT_LINE_WIDTH, InpTouchArrowWidth);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Touch from below
   PlotIndexSetInteger(4, PLOT_DRAW_TYPE, InpEnableTouchSignals ? DRAW_ARROW : DRAW_NONE);
   PlotIndexSetInteger(4, PLOT_ARROW, InpTouchFromBelowArrowCode);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, InpTouchFromBelowColor);
   PlotIndexSetInteger(4, PLOT_LINE_WIDTH, InpTouchArrowWidth);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Gap down
   PlotIndexSetInteger(5, PLOT_DRAW_TYPE, InpEnableGapSignals ? DRAW_ARROW : DRAW_NONE);
   PlotIndexSetInteger(5, PLOT_ARROW, InpGapDownArrowCode);
   PlotIndexSetInteger(5, PLOT_LINE_COLOR, InpGapDownColor);
   PlotIndexSetInteger(5, PLOT_LINE_WIDTH, InpGapArrowWidth);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Gap up
   PlotIndexSetInteger(6, PLOT_DRAW_TYPE, InpEnableGapSignals ? DRAW_ARROW : DRAW_NONE);
   PlotIndexSetInteger(6, PLOT_ARROW, InpGapUpArrowCode);
   PlotIndexSetInteger(6, PLOT_LINE_COLOR, InpGapUpColor);
   PlotIndexSetInteger(6, PLOT_LINE_WIDTH, InpGapArrowWidth);
   PlotIndexSetDouble(6, PLOT_EMPTY_VALUE, EMPTY_VALUE);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+

int OnInit()
{
   if(InpEMAPeriod <= 0)
   {
      Print("EMA period must be greater than zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpStdDevPeriod <= 0)
   {
      Print("STD period must be greater than zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpSlopeLookbackBars <= 0)
   {
      Print("Slope lookback bars must be greater than zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpAverageSlopeBars <= 0)
   {
      Print("Average slope bars must be greater than zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpGapBars <= 0)
   {
      Print("Gap bars must be greater than zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   EMAHandle = iMA(_Symbol,
                   _Period,
                   InpEMAPeriod,
                   0,
                   InpEMAMethod,
                   InpAppliedPrice);

   if(EMAHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA handle.");
      return INIT_FAILED;
   }

   StdDevHandle = iStdDev(_Symbol,
                          _Period,
                          InpStdDevPeriod,
                          0,
                          InpStdDevMethod,
                          InpAppliedPrice);

   if(StdDevHandle == INVALID_HANDLE)
   {
      Print("Failed to create STD handle.");
      return INIT_FAILED;
   }

   SetIndexBuffer(0, BufferEMA, INDICATOR_DATA);
   SetIndexBuffer(1, BufferEMAColorIndex, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, BufferUpperBand, INDICATOR_DATA);
   SetIndexBuffer(3, BufferLowerBand, INDICATOR_DATA);
   SetIndexBuffer(4, BufferTouchFromAbove, INDICATOR_DATA);
   SetIndexBuffer(5, BufferTouchFromBelow, INDICATOR_DATA);
   SetIndexBuffer(6, BufferGapDown, INDICATOR_DATA);
   SetIndexBuffer(7, BufferGapUp, INDICATOR_DATA);

   ConfigurePlots();

   IndicatorSetString(INDICATOR_SHORTNAME, "EMA STD Touch Gap");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
{
   if(EMAHandle != INVALID_HANDLE)
      IndicatorRelease(EMAHandle);

   if(StdDevHandle != INVALID_HANDLE)
      IndicatorRelease(StdDevHandle);
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   int minimum_bars = MathMax(InpEMAPeriod, InpStdDevPeriod);
   minimum_bars = MathMax(minimum_bars, InpSlopeLookbackBars + InpAverageSlopeBars + 2);
   minimum_bars = MathMax(minimum_bars, InpGapBars + 2);

   if(rates_total < minimum_bars)
      return 0;

   ArrayResize(StdDevValues, rates_total);

   int copied_ema = CopyBuffer(EMAHandle, 0, 0, rates_total, BufferEMA);
   if(copied_ema <= 0)
      return 0;

   int copied_std = CopyBuffer(StdDevHandle, 0, 0, rates_total, StdDevValues);
   if(copied_std <= 0)
      return 0;

   int last_touch_bar = -1000000;
   int last_gap_down_bar = -1000000;
   int last_gap_up_bar   = -1000000;

   for(int i = 0; i < rates_total; i++)
   {
      BufferEMAColorIndex[i]    = 0.0;
      BufferUpperBand[i]        = EMPTY_VALUE;
      BufferLowerBand[i]        = EMPTY_VALUE;
      BufferTouchFromAbove[i]   = EMPTY_VALUE;
      BufferTouchFromBelow[i]   = EMPTY_VALUE;
      BufferGapDown[i]          = EMPTY_VALUE;
      BufferGapUp[i]            = EMPTY_VALUE;

      if(!IsValidNumber(BufferEMA[i]) || !IsValidNumber(StdDevValues[i]))
         continue;

      double upper_band = BufferEMA[i] + InpUpperStdMultiplier * StdDevValues[i];
      double lower_band = BufferEMA[i] - InpLowerStdMultiplier * StdDevValues[i];

      BufferUpperBand[i] = upper_band;
      BufferLowerBand[i] = lower_band;

      double average_slope = AverageSlopePointsPerBar(BufferEMA,
                                                      i,
                                                      InpSlopeLookbackBars,
                                                      InpAverageSlopeBars);

      bool slope_inside = SlopeInsideBoundary(average_slope);

      if(InpColorEMAWhenSlopeInside && slope_inside)
         BufferEMAColorIndex[i] = 1.0;
      else
         BufferEMAColorIndex[i] = 0.0;

      bool slope_allows_touch = true;

      if(InpUseSlopeFilter)
         slope_allows_touch = slope_inside;

      //--- Touch signals
      if(InpEnableTouchSignals && slope_allows_touch)
      {
         bool touch_from_above = false;
         bool touch_from_below = false;

         if(InpEnableEMATouch && CandleTouchesLine(i, BufferEMA[i], high, low))
         {
            if(TouchIsFromAbove(i, BufferEMA[i], open, close))
               touch_from_above = true;
            else
               touch_from_below = true;
         }

         if(InpEnableUpperBandTouch && CandleTouchesLine(i, upper_band, high, low))
         {
            if(TouchIsFromAbove(i, upper_band, open, close))
               touch_from_above = true;
            else
               touch_from_below = true;
         }

         if(InpEnableLowerBandTouch && CandleTouchesLine(i, lower_band, high, low))
         {
            if(TouchIsFromAbove(i, lower_band, open, close))
               touch_from_above = true;
            else
               touch_from_below = true;
         }

         bool has_touch_signal = touch_from_above || touch_from_below;

         if(has_touch_signal)
         {
            bool distance_ok = true;

            if(InpMinBarsBetweenTouches > 0)
            {
               if(i - last_touch_bar < InpMinBarsBetweenTouches)
                  distance_ok = false;
            }

            if(distance_ok)
            {
               if(touch_from_above)
                  BufferTouchFromAbove[i] = low[i] - InpTouchArrowOffsetPoints * _Point;

               if(touch_from_below)
                  BufferTouchFromBelow[i] = high[i] + InpTouchArrowOffsetPoints * _Point;

               last_touch_bar = i;
            }
         }
      }

      //--- EMA gap bar signals
      if(InpEnableGapSignals)
      {
         bool slope_allows_gap = true;

         if(InpApplySlopeFilterToGap)
            slope_allows_gap = slope_inside;

         if(slope_allows_gap)
         {
            if(InpEnableGapDownAfterAbove)
            {
               bool gap_down =
                              CandleFullyBelowEMA(i, open, high, low, close, BufferEMA) &&
                              PreviousBarsWereNotFullyBelowEMA(i,
                                    InpGapBars,
                                    open,
                                    high,
                                    low,
                                    close,
                                    BufferEMA);

               if(gap_down && i != last_gap_down_bar)
               {
                  BufferGapDown[i] = high[i] + InpGapArrowOffsetPoints * _Point;
                  last_gap_down_bar = i;
               }
            }

            if(InpEnableGapUpAfterBelow)
            {
               bool gap_up =
                     CandleFullyAboveEMA(i, open, high, low, close, BufferEMA) &&
                     PreviousBarsWereNotFullyAboveEMA(i,
                                                      InpGapBars,
                                                      open,
                                                      high,
                                                      low,
                                                      close,
                                                      BufferEMA);

               if(gap_up && i != last_gap_up_bar)
               {
                  BufferGapUp[i] = low[i] - InpGapArrowOffsetPoints * _Point;
                  last_gap_up_bar = i;
               }
            }
         }
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+