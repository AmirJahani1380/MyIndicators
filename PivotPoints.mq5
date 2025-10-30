// --- Description: Williams-style swing points plotted as DOTS (no arrows). Dots are drawn exactly at swing highs/lows in red.
// --- Author: Amir
// --- Based on: MQL5 Official Documentation

#property strict
#property indicator_chart_window
#property indicator_plots 2
#property indicator_buffers 2

//--- Inputs
input group "Section :: Main"
input int   InpPeriod      = 10;          // Swing period (bars to each side)

// Using a Wingdings "dot" symbol via PLOT_ARROW (159 is a solid small dot in Wingdings on most MT5 fonts)
input group "Section :: Style"
input int   ArrowCode      = 159;         // Dot (Wingdings) code
input int   InpDotSize     = 1;           // Dot size (line width)
input color InpDotColor    = clrRed;      // Dot color

//--- Buffers
double ExtHigherHighBuffer[];
double ExtLowerLowBuffer[];

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);

   //--- Higher High (dots)
   SetIndexBuffer(0,ExtHigherHighBuffer,INDICATOR_DATA);
   PlotIndexSetString(0,PLOT_LABEL,"Swing High");
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(0,PLOT_DRAW_TYPE,DRAW_ARROW);          // We will draw a dot using Wingdings symbol
   PlotIndexSetInteger(0,PLOT_ARROW,ArrowCode);               // Dot code (233 by default)
   PlotIndexSetInteger(0,PLOT_ARROW_SHIFT,0);                 // No vertical shift – place right on the price
   PlotIndexSetInteger(0,PLOT_LINE_WIDTH,InpDotSize);         // Size of the dot
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,InpDotColor);        // Red (by default)

   //--- Lower Low (dots)
   SetIndexBuffer(1,ExtLowerLowBuffer,INDICATOR_DATA);
   PlotIndexSetString(1,PLOT_LABEL,"Swing Low");
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(1,PLOT_DRAW_TYPE,DRAW_ARROW);
   PlotIndexSetInteger(1,PLOT_ARROW,ArrowCode);               // Same dot for lows
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,0);
   PlotIndexSetInteger(1,PLOT_LINE_WIDTH,InpDotSize);
   PlotIndexSetInteger(1,PLOT_LINE_COLOR,InpDotColor);

   //--- Prepare buffers
   ArraySetAsSeries(ExtHigherHighBuffer,true);
   ArraySetAsSeries(ExtLowerLowBuffer,true);
   ArrayInitialize(ExtHigherHighBuffer,EMPTY_VALUE);
   ArrayInitialize(ExtLowerLowBuffer,EMPTY_VALUE);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // No logs per user request; clean buffers
   ArrayInitialize(ExtHigherHighBuffer,EMPTY_VALUE);
   ArrayInitialize(ExtLowerLowBuffer,EMPTY_VALUE);
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
   //--- Need enough bars on both sides of the swing point
   if(rates_total < (InpPeriod*2 + 1))
      return(rates_total);

   //--- Use series orientation (bar 0 is the latest)
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);

   //--- Determine from where to (re)calculate
   int start = (prev_calculated==0) ? InpPeriod : MathMax(InpPeriod, rates_total - prev_calculated - InpPeriod - 1);
   int finish = rates_total - InpPeriod - 1;

   //--- Clear the newly affected range to avoid stale points
   for(int k=start; k<=finish; k++)
   {
      ExtHigherHighBuffer[k] = EMPTY_VALUE;
      ExtLowerLowBuffer[k]   = EMPTY_VALUE;
   }

   //--- Main loop: check swings with InpPeriod bars to the left and right
   for(int i=start; i<=finish; i++)
   {
      bool isHigherHigh = true;
      bool isLowerLow   = true;

      // Check left side (older bars are with higher index in series arrays)
      for(int j=i+1; j<=i+InpPeriod; j++)
      {
         if(high[i] <= high[j]) isHigherHigh = false;
         if(low[i]  >= low[j])  isLowerLow   = false;
         if(!isHigherHigh && !isLowerLow) break;
      }

      // Check right side (newer bars are with smaller index)
      if(isHigherHigh || isLowerLow)
      {
         for(int j=i-1; j>=i-InpPeriod; j--)
         {
            if(high[i] < high[j])  isHigherHigh = false; // strict on right to avoid duplicates
            if(low[i]  > low[j])   isLowerLow   = false;
            if(!isHigherHigh && !isLowerLow) break;
         }
      }

      //--- Plot dots exactly at the swing price (no vertical shift)
      if(isHigherHigh)
         ExtHigherHighBuffer[i] = high[i];
      if(isLowerLow)
         ExtLowerLowBuffer[i]   = low[i];
   }

   return(rates_total);
}
//+------------------------------------------------------------------+

/*
Summary:
- Replaces arrows with DOTS by using DRAW_ARROW + Wingdings code (default 233) to render a small filled dot right on the swing high/low price.
- Both swing highs and lows are plotted in red (configurable), with no vertical shift and adjustable dot size.
*/
