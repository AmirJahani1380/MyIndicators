//+------------------------------------------------------------------+
//|                                           BodyRangeAtrFilter.mq5 |
//|                                     Copyright 2024, Gemini @ Google AI |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Gemini @ Google AI"
#property link      ""
#property version   "1.03" // Version updated to use a standard dot character

//--- Indicator settings
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

//--- Plot1 settings (the dot)
#property indicator_label1  "DetectionDot"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- User Input Parameters ---
// These inputs allow the user to customize the indicator's behavior from the settings window.

// Group: Candle Body Filter
input group "Candle Body Filter Settings"
input double InpBodyRatio = 50.0; // Body to Range Ratio (%) - Max percentage of body relative to the candle's full range.
input color  InpDotColor  = clrRed; // Dot Color - The color of the detection dot.

// Group: ATR Filter
input group "ATR Filter Settings"
input bool   InpFilterByAtr   = false;   // Enable ATR Filter - If true, filter candles by their ATR size.
input int    InpAtrPeriod     = 14;     // ATR Period - The period for the Average True Range calculation.
input double InpAtrMultiplier = 1.0;    // ATR Multiplier - Candles with a range larger than (ATR * Multiplier) will be ignored.

//--- Indicator Buffers ---
// Buffers are arrays that hold the data to be plotted on the chart.
double       DetectionDotBuffer[];

//--- Global Variables ---
// Handle for the iATR indicator
int          AtrHandle;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Indicator buffers mapping ---
   SetIndexBuffer(0, DetectionDotBuffer, INDICATOR_DATA);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE); // Use EMPTY_VALUE to not draw a dot

//--- Set plot properties from user input ---
   // Set the plot symbol to a standard period (dot).
   // ASCII code for '.' is 46.
   PlotIndexSetInteger(0, PLOT_ARROW, 158);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpDotColor);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 2); // A width of 2 or 3 helps make the dot more visible
   PlotIndexSetString(0, PLOT_LABEL, "Small Body Candle");

//--- Set indicator name ---
   IndicatorSetString(INDICATOR_SHORTNAME, "BodyRange(" + (string)InpBodyRatio + "%)");

//--- Get the handle for the iATR indicator ---
// We get this once during initialization for efficiency.
   AtrHandle = iATR(_Symbol, _Period, InpAtrPeriod);
   if(AtrHandle == INVALID_HANDLE)
     {
      Print("Error creating ATR indicator handle - error:", GetLastError());
      return(INIT_FAILED);
     }

//--- Initialization successful ---
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
//--- Determine the starting bar for calculation ---
   int start_bar;
   if(prev_calculated > 0)
      start_bar = prev_calculated - 1; // Recalculate the last bar
   else
      start_bar = 0; // Calculate all bars on first run

//--- Array to hold ATR values ---
   double atr_values[1];

//--- Main calculation loop ---
// Loop through each bar from the start bar to the most recent bar.
   for(int i = start_bar; i < rates_total; i++)
     {
      // Set default value to empty, so no dot is drawn unless conditions are met
      DetectionDotBuffer[i] = EMPTY_VALUE;

      //--- Calculate candle properties ---
      double candleRange = high[i] - low[i];
      double candleBody = MathAbs(close[i] - open[i]);

      // Avoid division by zero for doji candles where high == low
      if(candleRange <= 0)
         continue;

      //--- ATR Filter Logic ---
      if(InpFilterByAtr)
        {
         // Copy the latest ATR value into our array
         if(CopyBuffer(AtrHandle, 0, i, 1, atr_values) <= 0)
           {
            // If we can't get the ATR value yet, skip this bar
            continue;
           }

         // Check if the candle's range is larger than the allowed ATR size
         if(candleRange > (atr_values[0] * InpAtrMultiplier))
           {
            // This candle is too big, so we ignore it and move to the next one
            continue;
           }
        }

      //--- Body to Range Ratio Check ---
      double bodyRatio = (candleBody / candleRange) * 100.0;

      if(bodyRatio < InpBodyRatio)
        {
         // Condition met! Place the dot in the middle of the candle's body.
         DetectionDotBuffer[i] = (open[i] + close[i]) / 2.0;
        }
     }
//--- Return value of prev_calculated for the next call ---
   return(rates_total);
  }
//+------------------------------------------------------------------+