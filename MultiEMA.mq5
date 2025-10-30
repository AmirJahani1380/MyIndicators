//+------------------------------------------------------------------+
//|                                             MultiTimeframeEMA.mq5|
//|                      Copyright 2024, MetaQuotes Software Corp. |
//|                                       https://www.metaquotes.net |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.metaquotes.net"
#property version   "1.20"
#property indicator_chart_window

//--- We need 5 buffers and 5 plots for the 5 possible EMA lines
#property indicator_buffers 5
#property indicator_plots   5

//--- Global EMA Settings
input group           "EMA Settings"
input int             ema_period = 20;            // EMA Period for all timeframes
input ENUM_MA_METHOD  ema_method = MODE_EMA;      // EMA Method
input ENUM_APPLIED_PRICE price_to_use = PRICE_CLOSE; // Applied price

//--- 5-Minute EMA
input group           "5-Minute EMA"
input bool            show_5m_ema = false;         // Show 5M EMA
input color           color_5m = clrSteelBlue;   // 5M EMA Color
input ENUM_LINE_STYLE style_5m = STYLE_DOT;       // 5M EMA Style
input int             width_5m = 1;               // 5M EMA Width

//--- 15-Minute EMA
input group           "15-Minute EMA"
input bool            show_15m_ema = true;        // Show 15M EMA
input color           color_15m = clrSteelBlue;   // 15M EMA Color
input ENUM_LINE_STYLE style_15m = STYLE_DOT;      // 15M EMA Style
input int             width_15m = 1;              // 15M EMA Width

//--- 1-Hour EMA
input group           "1-Hour EMA"
input bool            show_1h_ema = true;         // Show H1 EMA
input color           color_1h = clrSteelBlue;   // H1 EMA Color
input ENUM_LINE_STYLE style_1h = STYLE_DOT;       // H1 EMA Style
input int             width_1h = 1;               // H1 EMA Width

//--- 4-Hour EMA
input group           "4-Hour EMA"
input bool            show_4h_ema = false;        // Show H4 EMA
input color           color_4h = clrSteelBlue;    // H4 EMA Color
input ENUM_LINE_STYLE style_4h = STYLE_DOT;       // H4 EMA Style
input int             width_4h = 1;               // H4 EMA Width

//--- Daily EMA
input group           "Daily EMA"
input bool            show_1d_ema = false;        // Show 1D EMA
input color           color_1d = clrSteelBlue;       // 1D EMA Color
input ENUM_LINE_STYLE style_1d = STYLE_DOT;       // 1D EMA Style
input int             width_1d = 1;               // 1D EMA Width

//--- These are the buffers that will hold the final data to be plotted
double buffer_5m[];
double buffer_15m[];
double buffer_1h[];
double buffer_4h[];
double buffer_1d[];

//--- These variables will hold the handles to the internal MQL5 indicators
int handle_5m, handle_15m, handle_1h, handle_4h, handle_1d;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- For each enabled timeframe, get a handle to the BUILT-IN iMA indicator.
//--- This ensures we are using the platform's native calculations.
   if(show_5m_ema)  handle_5m  = iMA(_Symbol, PERIOD_M5,  ema_period, 0, ema_method, price_to_use);
   if(show_15m_ema) handle_15m = iMA(_Symbol, PERIOD_M15, ema_period, 0, ema_method, price_to_use);
   if(show_1h_ema)  handle_1h  = iMA(_Symbol, PERIOD_H1,  ema_period, 0, ema_method, price_to_use);
   if(show_4h_ema)  handle_4h  = iMA(_Symbol, PERIOD_H4,  ema_period, 0, ema_method, price_to_use);
   if(show_1d_ema)  handle_1d  = iMA(_Symbol, PERIOD_D1,  ema_period, 0, ema_method, price_to_use);

//--- Setup the drawing properties for each line
   if(show_5m_ema)  SetupPlot(0, "EMA(5M)",  buffer_5m,  color_5m,  style_5m,  width_5m);
   if(show_15m_ema) SetupPlot(1, "EMA(15M)", buffer_15m, color_15m, style_15m, width_15m);
   if(show_1h_ema)  SetupPlot(2, "EMA(1H)",  buffer_1h,  color_1h,  style_1h,  width_1h);
   if(show_4h_ema)  SetupPlot(3, "EMA(4H)",  buffer_4h,  color_4h,  style_4h,  width_4h);
   if(show_1d_ema)  SetupPlot(4, "EMA(1D)",  buffer_1d,  color_1d,  style_1d,  width_1d);

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Release the indicator handles when the indicator is removed from the chart to free up memory
   IndicatorRelease(handle_5m);
   IndicatorRelease(handle_15m);
   IndicatorRelease(handle_1h);
   IndicatorRelease(handle_4h);
   IndicatorRelease(handle_1d);
  }
//+------------------------------------------------------------------+
//| Custom indicator calculation function                            |
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
//--- For each enabled EMA, call the function to copy and map the data from the built-in indicator
   if(show_5m_ema)  MapBufferData(handle_5m,  buffer_5m,  PERIOD_M5,  time, rates_total);
   if(show_15m_ema) MapBufferData(handle_15m, buffer_15m, PERIOD_M15, time, rates_total);
   if(show_1h_ema)  MapBufferData(handle_1h,  buffer_1h,  PERIOD_H1,  time, rates_total);
   if(show_4h_ema)  MapBufferData(handle_4h,  buffer_4h,  PERIOD_H4,  time, rates_total);
   if(show_1d_ema)  MapBufferData(handle_1d,  buffer_1d,  PERIOD_D1,  time, rates_total);

   return(rates_total);
  }
//+------------------------------------------------------------------+
//| Copies and maps data from the built-in indicator to our buffer   |
//+------------------------------------------------------------------+
void MapBufferData(int indicator_handle, double &dest_buffer[], ENUM_TIMEFRAMES source_tf, const datetime &time[], const int rates_total)
  {
//--- Exit if the handle to the internal indicator is not valid
   if(indicator_handle == INVALID_HANDLE)
      return;

//--- Create arrays to temporarily hold the data from the higher timeframe
   datetime source_time[];
   double   source_ema_data[];
   
//--- Get the time of each bar from the source timeframe
   if(CopyTime(_Symbol, source_tf, 0, rates_total, source_time) < 1)
      return;
   
//--- Using the handle, COPY the calculated values from the BUILT-IN indicator into our source_ema_data array
   if(CopyBuffer(indicator_handle, 0, 0, rates_total, source_ema_data) < 1)
      return;

//--- Map higher timeframe data to current chart bars
   for(int i = 0; i < rates_total; i++)
     {
      //--- Find the bar on the source timeframe that corresponds to the bar time on our current chart.
      //--- ArrayBsearch finds the index of the bar that was open at the time of the current bar.
      int source_bar_index = ArrayBsearch(source_time, time[i]);
      
      //--- If the time on our chart is before the very first bar of the higher timeframe, we have no data
      if(source_bar_index < 0)
        {
         // Try to use the very first available value
         source_bar_index = 0;
        }

      //--- If the time of our bar is an exact match for a higher timeframe bar,
      //--- step back one bar on the higher timeframe to get the EMA value *as of the open* of our bar.
      if(source_time[source_bar_index] > time[i] && source_bar_index > 0)
        {
         source_bar_index--;
        }
        
      //--- Assign the official, built-in EMA value to our indicator's plot buffer
      dest_buffer[i] = source_ema_data[source_bar_index];
     }
  }
//+------------------------------------------------------------------+
//| Helper function to set up plot properties                        |
//+------------------------------------------------------------------+
void SetupPlot(int plot_index, string label, double &buffer[], color plot_color, ENUM_LINE_STYLE plot_style, int plot_width)
  {
   SetIndexBuffer(plot_index, buffer, INDICATOR_DATA);
   PlotIndexSetString(plot_index, PLOT_LABEL, label + "(" + IntegerToString(ema_period) + ")");
   PlotIndexSetInteger(plot_index, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(plot_index, PLOT_LINE_STYLE, plot_style);
   PlotIndexSetInteger(plot_index, PLOT_LINE_WIDTH, plot_width);
   PlotIndexSetInteger(plot_index, PLOT_LINE_COLOR, plot_color);
   PlotIndexSetInteger(plot_index, PLOT_DRAW_BEGIN, ema_period);
  }
//+------------------------------------------------------------------+