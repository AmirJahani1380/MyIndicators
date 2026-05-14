//+------------------------------------------------------------------+
//|                                              SessionBoxes.mq5     |
//|  Draws subtle session range boxes for Tokyo, London, New York,    |
//|  and Sydney using broker-server time.                             |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_plots 0
#property strict

//------------------------- Inputs ----------------------------------
input int  InpDaysBack = 10;                    // Number of days back to draw
input bool InpDrawTokyo   = true;               // Draw Tokyo session
input bool InpDrawLondon  = true;               // Draw London session
input bool InpDrawNewYork = true;               // Draw New York session
input bool InpDrawSydney  = true;               // Draw Sydney session

// Times are based on the broker/server clock shown on your chart.
// Format: HH:MM, 24-hour time.
input string InpTokyoOpen    = "00:00";         // Tokyo open, broker time
input string InpTokyoClose   = "09:00";         // Tokyo close, broker time
input string InpLondonOpen   = "08:00";         // London open, broker time
input string InpLondonClose  = "17:00";         // London close, broker time
input string InpNewYorkOpen  = "13:00";         // New York open, broker time
input string InpNewYorkClose = "22:00";         // New York close, broker time
input string InpSydneyOpen   = "22:00";         // Sydney open, broker time
input string InpSydneyClose  = "07:00";         // Sydney close, broker time

// Subtle but vibrant defaults for a white chart.
// Fill transparency is controlled separately below.
input color InpTokyoColor    = clrLightSkyBlue; // Tokyo box color
input color InpLondonColor   = clrPaleGreen;    // London box color
input color InpNewYorkColor  = clrMistyRose;    // New York box color
input color InpSydneyColor   = clrPlum;         // Sydney box color

input uchar InpFillAlpha     = 28;              // Fill opacity, 0 transparent, 255 solid
input uchar InpBorderAlpha   = 90;              // Border opacity, 0 transparent, 255 solid
input int   InpBorderWidth   = 1;               // Border width
input bool  InpDrawBehind    = true;            // Draw boxes behind candles
input bool  InpShowLabels    = true;            // Show small session labels
input int   InpLabelFontSize = 8;               // Label font size

input bool  InpClearOldObjectsOnRemove = true;  // Delete boxes when indicator is removed

//------------------------- Globals ---------------------------------
string PREFIX = "SBX_";

struct SessionDef
{
   string name;
   bool   enabled;
   string open_text;
   string close_text;
   color  base_color;
};

//+------------------------------------------------------------------+
//| Utility: trim spaces                                              |
//+------------------------------------------------------------------+
string TrimString(string value)
{
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
}

//+------------------------------------------------------------------+
//| Parse HH:MM into minutes from midnight                            |
//+------------------------------------------------------------------+
bool ParseTimeHHMM(const string text, int &minutes)
{
   string s = TrimString(text);
   string parts[];
   int count = StringSplit(s, ':', parts);
   if(count != 2)
      return false;

   int hh = (int)StringToInteger(parts[0]);
   int mm = (int)StringToInteger(parts[1]);

   if(hh < 0 || hh > 23 || mm < 0 || mm > 59)
      return false;

   minutes = hh * 60 + mm;
   return true;
}

//+------------------------------------------------------------------+
//| Return midnight of a broker/server-time date                      |
//+------------------------------------------------------------------+
datetime DayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| ARGB color helper                                                 |
//+------------------------------------------------------------------+
color WithAlpha(color c, uchar alpha)
{
   return (color)ColorToARGB(c, alpha);
}

//+------------------------------------------------------------------+
//| Delete all objects created by this indicator                      |
//+------------------------------------------------------------------+
void DeleteSessionObjects()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, PREFIX) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Find high and low between start and end                           |
//+------------------------------------------------------------------+
bool GetSessionHighLow(datetime start_time, datetime end_time, double &session_high, double &session_low)
{
   if(end_time <= start_time)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, false);

   int copied = CopyRates(_Symbol, _Period, start_time, end_time, rates);
   if(copied <= 0)
      return false;

   session_high = rates[0].high;
   session_low  = rates[0].low;

   for(int i = 1; i < copied; i++)
   {
      if(rates[i].high > session_high)
         session_high = rates[i].high;
      if(rates[i].low < session_low)
         session_low = rates[i].low;
   }

   return session_high > session_low;
}

//+------------------------------------------------------------------+
//| Draw one rectangle and optional label                             |
//+------------------------------------------------------------------+
void DrawSessionBox(const string session_name,
                    datetime start_time,
                    datetime end_time,
                    double session_high,
                    double session_low,
                    color base_color)
{
   string stamp = TimeToString(start_time, TIME_DATE | TIME_MINUTES);
   StringReplace(stamp, ".", "");
   StringReplace(stamp, ":", "");
   StringReplace(stamp, " ", "_");

   string rect_name  = PREFIX + session_name + "_BOX_" + stamp;
   string label_name = PREFIX + session_name + "_LBL_" + stamp;

   ObjectDelete(0, rect_name);
   ObjectDelete(0, label_name);

   if(!ObjectCreate(0, rect_name, OBJ_RECTANGLE, 0, start_time, session_high, end_time, session_low))
      return;

   ObjectSetInteger(0, rect_name, OBJPROP_COLOR, WithAlpha(base_color, InpBorderAlpha));
   ObjectSetInteger(0, rect_name, OBJPROP_BGCOLOR, WithAlpha(base_color, InpFillAlpha));
   ObjectSetInteger(0, rect_name, OBJPROP_FILL, true);
   ObjectSetInteger(0, rect_name, OBJPROP_BACK, InpDrawBehind);
   ObjectSetInteger(0, rect_name, OBJPROP_WIDTH, InpBorderWidth);
   ObjectSetInteger(0, rect_name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, rect_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, rect_name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, rect_name, OBJPROP_HIDDEN, true);

   if(InpShowLabels)
   {
      double label_price = session_high;
      if(ObjectCreate(0, label_name, OBJ_TEXT, 0, start_time, label_price))
      {
         ObjectSetString(0, label_name, OBJPROP_TEXT, session_name);
         ObjectSetInteger(0, label_name, OBJPROP_COLOR, WithAlpha(base_color, 160));
         ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, InpLabelFontSize);
         ObjectSetString(0, label_name, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0, label_name, OBJPROP_BACK, InpDrawBehind);
         ObjectSetInteger(0, label_name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, label_name, OBJPROP_SELECTED, false);
         ObjectSetInteger(0, label_name, OBJPROP_HIDDEN, true);
      }
   }
}

//+------------------------------------------------------------------+
//| Draw all instances of one session                                 |
//+------------------------------------------------------------------+
void DrawSession(const SessionDef &s, datetime today_start)
{
   if(!s.enabled)
      return;

   int open_minutes, close_minutes;
   if(!ParseTimeHHMM(s.open_text, open_minutes) || !ParseTimeHHMM(s.close_text, close_minutes))
   {
      Print("Invalid session time for ", s.name, ". Use HH:MM format, for example 08:00.");
      return;
   }

   // Include one extra day so overnight sessions, such as Sydney 22:00-07:00,
   // are still drawn correctly at the edge of the requested lookback.
   for(int d = InpDaysBack; d >= 0; d--)
   {
      datetime day = today_start - (datetime)(d * 86400);
      datetime start_time = day + (datetime)(open_minutes * 60);
      datetime end_time   = day + (datetime)(close_minutes * 60);

      // If close is earlier than open, session crosses midnight.
      if(close_minutes <= open_minutes)
         end_time += 86400;

      // Do not draw sessions that have not started yet.
      datetime now_time = TimeCurrent();
      if(start_time > now_time)
         continue;

      // For the current still-open session, draw only up to now.
      datetime effective_end = end_time;
      if(effective_end > now_time)
         effective_end = now_time;

      double hi, lo;
      if(GetSessionHighLow(start_time, effective_end, hi, lo))
         DrawSessionBox(s.name, start_time, effective_end, hi, lo, s.base_color);
   }
}

//+------------------------------------------------------------------+
//| Indicator initialization                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   PREFIX = "SBX_" + _Symbol + "_" + IntegerToString(_Period) + "_";
   IndicatorSetString(INDICATOR_SHORTNAME, "Session Boxes");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Indicator deinitialization                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(InpClearOldObjectsOnRemove)
      DeleteSessionObjects();
}

//+------------------------------------------------------------------+
//| Main calculation                                                  |
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
   if(rates_total <= 0 || InpDaysBack < 0)
      return rates_total;

   DeleteSessionObjects();

   datetime today_start = DayStart(TimeCurrent());

   SessionDef sessions[4];

   sessions[0].name       = "Tokyo";
   sessions[0].enabled    = InpDrawTokyo;
   sessions[0].open_text  = InpTokyoOpen;
   sessions[0].close_text = InpTokyoClose;
   sessions[0].base_color = InpTokyoColor;

   sessions[1].name       = "London";
   sessions[1].enabled    = InpDrawLondon;
   sessions[1].open_text  = InpLondonOpen;
   sessions[1].close_text = InpLondonClose;
   sessions[1].base_color = InpLondonColor;

   sessions[2].name       = "NewYork";
   sessions[2].enabled    = InpDrawNewYork;
   sessions[2].open_text  = InpNewYorkOpen;
   sessions[2].close_text = InpNewYorkClose;
   sessions[2].base_color = InpNewYorkColor;

   sessions[3].name       = "Sydney";
   sessions[3].enabled    = InpDrawSydney;
   sessions[3].open_text  = InpSydneyOpen;
   sessions[3].close_text = InpSydneyClose;
   sessions[3].base_color = InpSydneyColor;

   for(int i = 0; i < 4; i++)
      DrawSession(sessions[i], today_start);

   ChartRedraw(0);
   return rates_total;
}
//+------------------------------------------------------------------+
