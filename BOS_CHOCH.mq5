//+------------------------------------------------------------------+
//|                                                   BOS_CHOCH.mq5  |
//|             MT5 port (chronological, left->right scan)          |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_color1 clrRed
#property indicator_color2 clrBlue

//---- Inputs (same names & defaults)
input int    SwingPeriod          = 3;        // Lookback period for identifying swings
input int    CandleWindow         = 200;      // Number of candles to analyze (latest bars only)
input int    ATRPeriod            = 14;       // Period for ATR calculation
input double ATRMultiplier        = 5;        // Multiplier for ATR filtering
input double MinCorrectionDepth   = 0.5;      // Minimum correction depth in percentage (50%)
input color  BOSLineColor         = clrBlue;  // Line color for BOS
input color  CHOCHLineColor       = clrBlue;  // Line color for CHOCH
input color  ImportantLineColor   = clrAqua;  // Line color for Important Breaks
input int    BOSLineStyle         = 2;        // Line style for BOS
input int    CHOCHLineStyle       = 2;        // Line style for CHOCH
input int    ImportantLineStyle   = 0;        // Line style for Important Breaks
input int    LineWidth            = 1;        // Line width
input bool   OnlySwingHigh        = false;    // Identify only swing high breaks
input bool   OnlySwingLow         = false;    // Identify only swing low breaks
input bool   CheckCandleClose     = false;    // Check if swing was broken with candle close

//---- Globals
int       LastTimeFrame = -1;
datetime  LastUpdateTime = 0;

// ATR handle (MT5)
int atrHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| init                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "BOS_CHOCH");
   RemoveDrawingsForPreviousTimeFrame();
   LastTimeFrame  = Period();

   atrHandle = iATR(_Symbol, _Period, ATRPeriod);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle.");
      return(INIT_FAILED);
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   if(Period() != LastTimeFrame) LastTimeFrame = Period();

   if (rates_total < (CandleWindow + SwingPeriod))
   {
      Print("Not enough data available.");
      return(rates_total);
   }

   // --- Build local CHRONO arrays: 0=oldest .... last=newest (latest CandleWindow only)
   int count = MathMin(CandleWindow, rates_total);
   int last  = count - 1;

   datetime t[]; double o[]; double h[]; double l[]; double c[];
   ArrayResize(t, count); ArrayResize(o, count);
   ArrayResize(h, count); ArrayResize(l, count); ArrayResize(c, count);

   bool srcSeries = ArrayGetAsSeries(high);
   if(srcSeries)
   {
      // Source is series (0=newest). Take last 'count' bars and reverse -> chronological.
      for(int j=0; j<count; j++)
      {
         int src = count-1-j;   // oldest within the window
         t[j]=time[src]; o[j]=open[src]; h[j]=high[src]; l[j]=low[src]; c[j]=close[src];
      }
   }
   else
   {
      // Source is chronological already. Copy the last 'count' slice.
      int start = rates_total - count;
      for(int j=0; j<count; j++)
      {
         int src = start + j;
         t[j]=time[src]; o[j]=open[src]; h[j]=high[src]; l[j]=low[src]; c[j]=close[src];
      }
   }

   // --- ATR (latest value)
   double atrBuf[1];
   if(atrHandle == INVALID_HANDLE || CopyBuffer(atrHandle, 0, 0, 1, atrBuf) < 1)
   {
      Print("ATRValue calculation failed or returned no data.");
      return(rates_total);
   }
   double ATRValue = atrBuf[0];
   if (ATRValue <= 0.0)
   {
      Print("ATRValue calculation failed or returned zero.");
      return(rates_total);
   }

   // --- LEFT -> RIGHT scan over the local chronological window
   int    lastSwingLowIndex  = -1, lastSwingHighIndex = -1;
   double lastSwingLow       = -1.0, lastSwingHigh    = -1.0;

   // Start where swings are evaluable and move FORWARD in time
   for(int i = SwingPeriod; i <= last - SwingPeriod; i++)
   {
      // Swing Highs
      if((!OnlySwingLow) && IsSwingHighChrono(h, l, i, last))
      {
         if(lastSwingHigh == -1.0 || h[i] > lastSwingHigh)
         {
            lastSwingHigh      = h[i];
            lastSwingHighIndex = i;
         }
      }

      // Swing Lows
      if((!OnlySwingHigh) && IsSwingLowChrono(h, l, i, last))
      {
         if(lastSwingLow == -1.0 || l[i] < lastSwingLow)
         {
            lastSwingLow      = l[i];
            lastSwingLowIndex = i;
         }
      }

      // Break of swing high
      if(lastSwingHigh > -1.0 && h[i] >= lastSwingHigh)
      {
         int breakIndex = FindBreakIndexChrono(h, l, c, i, last, lastSwingHigh, CheckCandleClose, true);
         double difference = lastSwingHigh - GetMinimumPriceChrono(h, l, lastSwingHighIndex, breakIndex);

         string name = "TF_" + IntegerToString(Period()) + "_BOS_" + TimeToString(t[i]);
         if(MathAbs(difference) >= MathAbs(ATRMultiplier * ATRValue))
            DrawLine(name, t[i], lastSwingHigh, t[breakIndex], lastSwingHigh, ImportantLineColor, ImportantLineStyle);
         else
            DrawLine(name, t[i], lastSwingHigh, t[breakIndex], lastSwingHigh, BOSLineColor, BOSLineStyle);

         lastSwingHigh = -1.0; // Reset
      }

      // Break of swing low
      if(lastSwingLow > -1.0 && l[i] <= lastSwingLow)
      {
         int breakIndex = FindBreakIndexChrono(h, l, c, i, last, lastSwingLow, CheckCandleClose, false);
         double difference = lastSwingLow - GetMaximumPriceChrono(h, l, lastSwingLowIndex, breakIndex);

         string nameImp = "TF_" + IntegerToString(Period()) + "_BOS_"   + TimeToString(t[i]);
         string nameChg = "TF_" + IntegerToString(Period()) + "_CHOCH_" + TimeToString(t[i]);

         if(MathAbs(difference) >= MathAbs(ATRMultiplier * ATRValue))
            DrawLine(nameImp, t[i], lastSwingLow, t[breakIndex], lastSwingLow, ImportantLineColor, ImportantLineStyle);
         else
            DrawLine(nameChg, t[i], lastSwingLow, t[breakIndex], lastSwingLow, CHOCHLineColor, CHOCHLineStyle);

         lastSwingLow = -1.0; // Reset
      }
   }

   LastUpdateTime = t[last]; // most recent time in our local window
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Helpers: CHRONO arrays (0=oldest .. last=newest)                 |
//+------------------------------------------------------------------+
bool IsSwingHighChrono(const double &high[], const double &low[], int index, int last)
{
   if(index < SwingPeriod || index > (last - SwingPeriod))
      return(false);
   for(int i = index - SwingPeriod; i <= index + SwingPeriod; i++)
      if(high[index] < high[i]) return(false);
   return ((high[index] - low[index]) > 0);
}

bool IsSwingLowChrono(const double &high[], const double &low[], int index, int last)
{
   if(index < SwingPeriod || index > (last - SwingPeriod))
      return(false);
   for(int i = index - SwingPeriod; i <= index + SwingPeriod; i++)
      if(low[index] > low[i]) return(false);
   return ((high[index] - low[index]) > 0);
}

int FindBreakIndexChrono(const double &high[], const double &low[], const double &close[],
                         int startIndex, int last, double swingPrice, bool checkCandleClose, bool isSwingHigh)
{
   int breakIndex = startIndex;
   // Scan FORWARD in time: startIndex .. last
   for(int i = startIndex; i <= last; i++)
   {
      if(isSwingHigh)
      {
         if(checkCandleClose) { if(close[i] > swingPrice) { breakIndex = i; break; } }
         else                 { if(high[i]  > swingPrice) { breakIndex = i; break; } }
      }
      else
      {
         if(checkCandleClose) { if(close[i] < swingPrice) { breakIndex = i; break; } }
         else                 { if(low[i]   < swingPrice) { breakIndex = i; break; } }
      }
   }
   return breakIndex;
}

double GetMinimumPriceChrono(const double &high[], const double &low[], int a, int b)
{
   if(a > b) { int t=a; a=b; b=t; }
   double minPrice = high[a];
   for(int i=a; i<=b; i++) if(low[i] < minPrice) minPrice = low[i];
   return minPrice;
}

double GetMaximumPriceChrono(const double &high[], const double &low[], int a, int b)
{
   if(a > b) { int t=a; a=b; b=t; }
   double maxPrice = low[a];
   for(int i=a; i<=b; i++) if(high[i] > maxPrice) maxPrice = high[i];
   return maxPrice;
}

//+------------------------------------------------------------------+
//| Remove drawings for the previous timeframe                       |
//+------------------------------------------------------------------+
void RemoveDrawingsForPreviousTimeFrame()
{
   string prefix = "TF_";
   int totalObjects = ObjectsTotal(0, -1, -1);
   for (int i = totalObjects - 1; i >= 0; i--)
   {
      string objName = ObjectName(0, i);
      if (StringFind(objName, prefix) == 0)
         ObjectDelete(0, objName);
   }
}

//+------------------------------------------------------------------+
//| Draw line (zero-length safeguard)                                |
//+------------------------------------------------------------------+
void DrawLine(string name, datetime time1, double price1, datetime time2, double price2,
              color lineColor, int lineStyle)
{
   if(time2 == time1) // ensure a non-zero time span
   {
      int sec = PeriodSeconds(_Period);
      if(sec <= 0) sec = 60;
      time2 = (datetime)((long)time2 + sec);
   }

   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price2))
      {
         Print("Failed to create object: ", name);
      }
      else
      {
         ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, LineWidth);
         ObjectSetInteger(0, name, OBJPROP_STYLE, lineStyle);
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      }
   }
   else
   {
      ObjectMove(0, name, 0, time1, price1);
      ObjectMove(0, name, 1, time2, price2);
      ObjectSetInteger(0, name, OBJPROP_STYLE, lineStyle);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, LineWidth);
      ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
}
//+------------------------------------------------------------------+
