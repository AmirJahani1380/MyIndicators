//+------------------------------------------------------------------+
//|                                             EngulfingColored.mq5 |
//|                      Copyright 2023, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.20" // Version updated with fix
#property indicator_chart_window

//--- Indicator plots
#property indicator_plots   1

//--- Indicator buffers
//--- DRAW_COLOR_CANDLES requires 5 buffers: 4 for OHLC and 1 for color
#property indicator_buffers 5

//--- Plot properties
#property indicator_label1  "Engulfing Color"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_color1  clrNONE // Colors are controlled by the color buffer
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- Input parameters for colors
input color BullishColor = clrGreen; // Color for Bullish Engulfing
input color BearishColor = C'221,0,0';       // Color for Bearish Engulfing

//--- Indicator buffers
double OpenBuffer[];
double HighBuffer[];
double LowBuffer[];
double CloseBuffer[];
double ColorBuffer[]; // Buffer for color indices

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Map the indicator buffers
   SetIndexBuffer(0, OpenBuffer,  INDICATOR_DATA);
   SetIndexBuffer(1, HighBuffer,  INDICATOR_DATA);
   SetIndexBuffer(2, LowBuffer,   INDICATOR_DATA);
   SetIndexBuffer(3, CloseBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, ColorBuffer, INDICATOR_COLOR_INDEX);

//--- Set the plot to be of type DRAW_COLOR_CANDLES
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_COLOR_CANDLES);

//--- We will use 3 colors for this plot (Default, Bullish, Bearish)
   PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 3);

//--- Set the colors for our palette
   // Index 0: Default candle colors (clrNONE tells it to use chart defaults)
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, clrNONE);
   // Index 1: Bullish Engulfing color
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, BullishColor);
   // Index 2: Bearish Engulfing color
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 2, BearishColor);
   
//--- We are not using an empty value; every candle will be drawn
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);

//--- Name for DataWindow and indicator subwindow label
   IndicatorSetString(INDICATOR_SHORTNAME, "EngulfingColored");

//--- Initialization successful
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
//--- Determine the starting bar for the calculation
   int start;
   if(prev_calculated > 0)
      start = prev_calculated - 1;
   else
      start = 1; // Start from the second bar as we need the previous one

//--- Main calculation loop
   for(int i = start; i < rates_total; i++)
     {
      //--- Populate the OHLC buffers for every candle
      OpenBuffer[i]  = open[i];
      HighBuffer[i]  = high[i];
      LowBuffer[i]   = low[i];
      CloseBuffer[i] = close[i];

      //--- Set default color index first
      ColorBuffer[i] = 0;

      //--- Bullish Engulfing Pattern Detection
      // 1. Previous candle is bearish (close < open).
      // 2. Current candle is bullish (close > open).
      // 3. Current candle's body completely engulfs the previous candle's body.
      if(close[i-1] < open[i-1] && close[i] > open[i] && open[i] <= high[i-1] && close[i] >= high[i-1])
        {
         // Set the color index to 1 (BullishColor)
         ColorBuffer[i] = 1;
        }
      //--- Bearish Engulfing Pattern Detection
      // 1. Previous candle is bullish (close > open).
      // 2. Current candle is bearish (close < open).
      // 3. Current candle's body completely engulfs the previous candle's body.
      else if(close[i-1] > open[i-1] && close[i] < open[i] && open[i] >= low[i-1] && close[i] <= low[i-1])
        {
         // Set the color index to 2 (BearishColor)
         ColorBuffer[i] = 2;
        }
     }
//--- Return the number of calculated bars for the next call
   return(rates_total);
  }
//+------------------------------------------------------------------+
