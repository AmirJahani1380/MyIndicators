//+------------------------------------------------------------------+
//|                                               Backtesting BO.mq5   |
//|  Semi-automatic breakout annotation and CSV export indicator.      |
//|                                                                  |
//|  Workflow:                                                        |
//|  B or button: select breakout candle                              |
//|  F or button: select follow-through candle                        |
//|  P or button: set breakout point                                  |
//|  L or button: select leg start, leg end, pullback end              |
//|  S or button: select broken swing                                 |
//|  Save Event: stores row in memory                                  |
//|  Export CSV: writes all saved rows to MQL5/Files                   |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_plots 0
#property strict

//----------------------------- Inputs ------------------------------
input int      InpATRPeriod          = 14;       // ATR period
input int      InpEMA20Period        = 20;       // EMA 20 period
input int      InpEMA60Period        = 60;       // EMA 60 period
input int      InpEMA20SlopeLookback = 10;       // EMA20 slope lookback bars
input int      InpMaxOutcomeBars     = 100;      // Maximum bars to scan outcomes
input double   InpPipSize            = 0.0;      // Pip size, 0 = auto

input string   InpKeyBO              = "B";      // Keyboard shortcut: breakout candle
input string   InpKeyFT              = "F";      // Keyboard shortcut: follow-through candle
input string   InpKeyBOPoint         = "P";      // Keyboard shortcut: breakout point
input string   InpKeyLeg             = "L";      // Keyboard shortcut: leg/pullback points
input string   InpKeySwing           = "S";      // Keyboard shortcut: broken swing

// Default actual exchange sessions in broker/server time, editable.
input string   InpSydneyOpen         = "03:00";  // Sydney session open
input string   InpSydneyClose        = "09:00";  // Sydney session close
input string   InpTokyoOpen          = "03:00";  // Tokyo session open
input string   InpTokyoClose         = "09:30";  // Tokyo session close
input string   InpLondonOpen         = "10:00";  // London session open
input string   InpLondonClose        = "18:30";  // London session close
input string   InpNewYorkOpen        = "16:30";  // New York session open
input string   InpNewYorkClose       = "23:00";  // New York session close

input string   InpDefaultExportName  = "backtesting_bo.csv"; // Default export file name
input bool     InpUseCommonFiles     = false;    // Export to common Files folder
input bool     InpShowPanel          = true;     // Show annotation panel
input int      InpPanelX             = 10;       // Panel X position
input int      InpPanelY             = 20;       // Panel Y position
input int      InpPanelWidth         = 430;      // Panel width
input color    InpPanelBgColor       = clrWhiteSmoke;
input color    InpPanelBorderColor   = clrSilver;
input color    InpMarkerBOColor      = clrDodgerBlue;
input color    InpMarkerFTColor      = clrMediumSeaGreen;
input color    InpMarkerPointColor   = clrOrangeRed;

//----------------------------- Globals -----------------------------
string PREFIX = "BTBO_";

int atr_handle   = INVALID_HANDLE;
int ema20_handle = INVALID_HANDLE;
int ema60_handle = INVALID_HANDLE;

enum SelectMode
{
   MODE_NONE = 0,
   MODE_BO,
   MODE_FT,
   MODE_BO_POINT,
   MODE_LEG,
   MODE_SWING
};

SelectMode g_mode = MODE_NONE;
int        g_leg_click_step = 0;

bool     g_has_bo = false;
bool     g_has_ft = false;
bool     g_has_bo_point = false;
bool     g_has_leg = false;
bool     g_has_swing = false;

int      g_bo_index = -1;
int      g_ft_index = -1;
int      g_leg_start_index = -1;
int      g_leg_end_index = -1;
int      g_pb_end_index = -1;
int      g_swing_index = -1;

datetime g_bo_time = 0;
datetime g_ft_time = 0;
datetime g_leg_start_time = 0;
datetime g_leg_end_time = 0;
datetime g_pb_end_time = 0;
datetime g_swing_time = 0;

double   g_bo_point = 0.0;
double   g_leg_start_price = 0.0;
double   g_leg_end_price = 0.0;
double   g_pb_end_price = 0.0;
double   g_swing_price = 0.0;

int      g_swing_period = -1;

string   g_rows[];
int      g_saved_count = 0;

//----------------------------- Helpers -----------------------------
string Obj(const string name)
{
   return PREFIX + name;
}

string Trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

int UpperFirstCode(const string s)
{
   if(StringLen(s) <= 0)
      return 0;
   int c = (int)StringGetCharacter(s, 0);
   if(c >= 'a' && c <= 'z')
      c -= 32;
   return c;
}

bool ParseHHMM(const string text, int &minutes)
{
   string s = Trim(text);
   string parts[];
   int n = StringSplit(s, ':', parts);
   if(n != 2)
      return false;

   int h = (int)StringToInteger(parts[0]);
   int m = (int)StringToInteger(parts[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59)
      return false;

   minutes = h * 60 + m;
   return true;
}

int MinutesOfDay(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.hour * 60 + dt.min;
}

bool IsInSession(datetime t, const string open_text, const string close_text)
{
   int open_m, close_m;
   if(!ParseHHMM(open_text, open_m) || !ParseHHMM(close_text, close_m))
      return false;

   int m = MinutesOfDay(t);

   if(open_m <= close_m)
      return (m >= open_m && m <= close_m);

   return (m >= open_m || m <= close_m);
}

string GetSessions(datetime t)
{
   string result = "";

   if(IsInSession(t, InpSydneyOpen, InpSydneyClose))
      result += (result == "" ? "Sydney" : ",Sydney");
   if(IsInSession(t, InpTokyoOpen, InpTokyoClose))
      result += (result == "" ? "Tokyo" : ",Tokyo");
   if(IsInSession(t, InpLondonOpen, InpLondonClose))
      result += (result == "" ? "London" : ",London");
   if(IsInSession(t, InpNewYorkOpen, InpNewYorkClose))
      result += (result == "" ? "NewYork" : ",NewYork");

   if(result == "")
      result = "OutsideSessions";

   return result;
}

double PipSize()
{
   if(InpPipSize > 0.0)
      return InpPipSize;

   if(_Digits == 3 || _Digits == 5)
      return _Point * 10.0;

   return _Point;
}

string Dbl(double value, int digits = 5)
{
   if(value == EMPTY_VALUE)
      return "";
   return DoubleToString(value, digits);
}

string BoolText(bool value)
{
   return value ? "true" : "false";
}

string TimeframeToString()
{
   switch(_Period)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
   }
   return IntegerToString((int)_Period);
}

string CsvEscape(string s)
{
   StringReplace(s, "\"", "\"\"");
   return "\"" + s + "\"";
}

string JoinCsv(const string &fields[])
{
   string row = "";
   int n = ArraySize(fields);
   for(int i = 0; i < n; i++)
   {
      if(i > 0)
         row += ",";
      row += CsvEscape(fields[i]);
   }
   return row;
}

string GetEdit(const string name)
{
   string obj = Obj(name);
   if(ObjectFind(0, obj) < 0)
      return "";
   return ObjectGetString(0, obj, OBJPROP_TEXT);
}

void SetLabelText(const string name, const string text)
{
   string obj = Obj(name);
   if(ObjectFind(0, obj) >= 0)
      ObjectSetString(0, obj, OBJPROP_TEXT, text);
}

void DeleteObjects()
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, PREFIX) == 0)
         ObjectDelete(0, name);
   }
}

//----------------------------- Indicator buffers -------------------
bool GetBufferValue(int handle, int shift, double &value)
{
   if(handle == INVALID_HANDLE || shift < 0)
      return false;

   double buffer[];
   ArraySetAsSeries(buffer, true);
   if(CopyBuffer(handle, 0, shift, 1, buffer) != 1)
      return false;

   value = buffer[0];
   return true;
}

//----------------------------- Candle metrics ----------------------
string CandleDirection(int shift)
{
   double o = iOpen(_Symbol, _Period, shift);
   double c = iClose(_Symbol, _Period, shift);
   if(c > o)
      return "bullish";
   if(c < o)
      return "bearish";
   return "doji";
}

double CandleRange(int shift)
{
   return iHigh(_Symbol, _Period, shift) - iLow(_Symbol, _Period, shift);
}

double CandleBodyToRange(int shift)
{
   double r = CandleRange(shift);
   if(r <= 0.0)
      return EMPTY_VALUE;
   double o = iOpen(_Symbol, _Period, shift);
   double c = iClose(_Symbol, _Period, shift);
   return MathAbs(c - o) / r;
}

double ClosePercentageDistanceFromExtreme(int shift)
{
   double h = iHigh(_Symbol, _Period, shift);
   double l = iLow(_Symbol, _Period, shift);
   double c = iClose(_Symbol, _Period, shift);
   double r = h - l;
   if(r <= 0.0)
      return EMPTY_VALUE;

   string dir = CandleDirection(shift);
   if(dir == "bullish")
      return (h - c) / r;
   if(dir == "bearish")
      return (c - l) / r;

   return EMPTY_VALUE;
}

bool IsEngulfingBO(int shift)
{
   string dir = CandleDirection(shift);
   string prev = CandleDirection(shift + 1);

   if(dir == "bullish" && prev == "bearish")
      return (iClose(_Symbol, _Period, shift) > iHigh(_Symbol, _Period, shift + 1));

   if(dir == "bearish" && prev == "bullish")
      return (iClose(_Symbol, _Period, shift) < iLow(_Symbol, _Period, shift + 1));

   return false;
}

double CandleRangeInATR(int shift)
{
   double atr;
   if(!GetBufferValue(atr_handle, shift, atr) || atr <= 0.0)
      return EMPTY_VALUE;
   return CandleRange(shift) / atr;
}

//----------------------------- Markers -----------------------------
void DrawVerticalMarker(const string name, datetime t, color c, const string text)
{
   string line = Obj(name + "_LINE");
   string lbl  = Obj(name + "_LBL");

   ObjectDelete(0, line);
   ObjectDelete(0, lbl);

   ObjectCreate(0, line, OBJ_VLINE, 0, t, 0.0);
   ObjectSetInteger(0, line, OBJPROP_COLOR, c);
   ObjectSetInteger(0, line, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, line, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, line, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, line, OBJPROP_HIDDEN, true);

   int shift = iBarShift(_Symbol, _Period, t, false);
   double price = shift >= 0 ? iHigh(_Symbol, _Period, shift) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   ObjectCreate(0, lbl, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, lbl, OBJPROP_TEXT, text);
   ObjectSetInteger(0, lbl, OBJPROP_COLOR, c);
   ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, lbl, OBJPROP_HIDDEN, true);
}

void DrawPriceMarker(const string name, datetime t, double price, color c, const string text)
{
   string obj = Obj(name);
   ObjectDelete(0, obj);

   ObjectCreate(0, obj, OBJ_ARROW_RIGHT_PRICE, 0, t, price);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, c);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
}

//----------------------------- Panel UI ----------------------------
void MakeLabel(const string name, int x, int y, int w, const string text, color clr = clrBlack)
{
   string obj = Obj(name);
   ObjectDelete(0, obj);
   ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
}

void MakeButton(const string name, int x, int y, int w, int h, const string text)
{
   string obj = Obj(name);
   ObjectDelete(0, obj);
   ObjectCreate(0, obj, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
}

void MakeEdit(const string name, int x, int y, int w, int h, const string text)
{
   string obj = Obj(name);
   ObjectDelete(0, obj);
   ObjectCreate(0, obj, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
}

void CreatePanel()
{
   if(!InpShowPanel)
      return;

   int x = InpPanelX;
   int y = InpPanelY;
   int w = InpPanelWidth;

   string bg = Obj("PANEL_BG");
   ObjectDelete(0, bg);
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 560);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, InpPanelBgColor);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, InpPanelBorderColor);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);

   MakeLabel("TITLE", x + 10, y + 8, w - 20, "Backtesting BO", clrBlack);
   MakeLabel("MODE",  x + 10, y + 28, w - 20, "Mode: NONE", clrDarkBlue);
   MakeLabel("STATUS",x + 10, y + 46, w - 20, "Saved rows: 0", clrDimGray);

   int by = y + 70;
   MakeButton("BTN_BO",       x + 10,  by, 70, 22, "B: BO");
   MakeButton("BTN_FT",       x + 85,  by, 70, 22, "F: FT");
   MakeButton("BTN_POINT",    x + 160, by, 70, 22, "P: Point");
   MakeButton("BTN_LEG",      x + 235, by, 80, 22, "L: Leg/PB");
   MakeButton("BTN_SWING",    x + 320, by, 85, 22, "S: Swing");

   by += 28;
   MakeButton("BTN_SAVE",     x + 10,  by, 100, 24, "Save Event");
   MakeButton("BTN_EXPORT",   x + 115, by, 100, 24, "Export CSV");
   MakeButton("BTN_CLEAR",    x + 220, by, 90, 24, "Clear Sel.");

   by += 34;
   MakeLabel("LBL_EXPORT", x + 10, by, 110, "Export name");
   MakeEdit("EDIT_EXPORT_NAME", x + 120, by - 3, 285, 20, InpDefaultExportName);

   by += 30;
   MakeLabel("LBL_WHAT", x + 10, by, 150, "Break out of what");
   MakeEdit("EDIT_BREAK_OUT_OF_WHAT", x + 160, by - 3, 245, 20, "");

   by += 24;
   MakeLabel("OPT_WHAT", x + 160, by, 245,
             "EMA20,swing high/low,LTF swing,PDH/PDL,round,trendline,channel,TTR,ii,ioi,inside,h1,h2,h3,l1,l2,l3", clrDimGray);

   by += 28;
   MakeLabel("LBL_PATTERN", x + 10, by, 150, "Pattern");
   MakeEdit("EDIT_PATTERN", x + 160, by - 3, 245, 20, "");

   by += 24;
   MakeLabel("OPT_PATTERN", x + 160, by, 245,
             "wedge,double top,double bottom,triangle,expanding triangle,channel,compression", clrDimGray);

   by += 28;
   MakeLabel("LBL_PB", x + 10, by, 150, "BO from pullback");
   MakeEdit("EDIT_FROM_PULLBACK", x + 160, by - 3, 245, 20, "");

   by += 28;
   MakeLabel("LBL_LEGCOUNT", x + 10, by, 150, "At what leg");
   MakeEdit("EDIT_AT_LEG", x + 160, by - 3, 245, 20, "");

   by += 28;
   MakeLabel("LBL_HTF", x + 10, by, 150, "HTF location");
   MakeEdit("EDIT_HTF_LOCATION", x + 160, by - 3, 245, 20, "");

   by += 28;
   MakeLabel("LBL_CONDITION", x + 10, by, 150, "Market condition");
   MakeEdit("EDIT_MARKET_CONDITION", x + 160, by - 3, 245, 20, "");

   by += 28;
   MakeLabel("LBL_DIRECTION", x + 10, by, 150, "Market direction");
   MakeEdit("EDIT_MARKET_DIRECTION", x + 160, by - 3, 245, 20, "");

   by += 28;
   MakeLabel("LBL_FTCOUNT", x + 10, by, 150, "# FT before first PB");
   MakeEdit("EDIT_FT_BEFORE_PB", x + 160, by - 3, 245, 20, "");

   by += 28;
   MakeLabel("LBL_SCREEN", x + 10, by, 150, "Screenshot path");
   MakeEdit("EDIT_SCREENSHOT", x + 160, by - 3, 245, 20, "");

   by += 28;
   MakeLabel("LBL_NOTE", x + 10, by, 150, "Note");
   MakeEdit("EDIT_NOTE", x + 160, by - 3, 245, 48, "");

   by += 58;
   MakeLabel("HELP1", x + 10, by, w - 20, "Click modes: B=BO, F=FT, P=breakout price, L=leg start/end/PB end, S=swing.", clrDimGray);
   by += 18;
   MakeLabel("HELP2", x + 10, by, w - 20, "Manual fields may be blank. Multi-label fields can be comma-separated.", clrDimGray);

   ChartRedraw(0);
}

void UpdateModeLabel()
{
   string txt = "Mode: NONE";
   if(g_mode == MODE_BO)
      txt = "Mode: SELECT BREAKOUT CANDLE";
   else if(g_mode == MODE_FT)
      txt = "Mode: SELECT FOLLOW-THROUGH CANDLE";
   else if(g_mode == MODE_BO_POINT)
      txt = "Mode: SET BREAKOUT POINT";
   else if(g_mode == MODE_LEG)
      txt = "Mode: SELECT LEG/PB POINT " + IntegerToString(g_leg_click_step + 1) + " of 3";
   else if(g_mode == MODE_SWING)
      txt = "Mode: SELECT BROKEN SWING";

   SetLabelText("MODE", txt);
   SetLabelText("STATUS", "Saved rows: " + IntegerToString(g_saved_count));
}

void SetMode(SelectMode mode)
{
   g_mode = mode;
   if(mode == MODE_LEG)
      g_leg_click_step = 0;
   UpdateModeLabel();
}

//----------------------------- Selection logic ---------------------
bool GetClickedPoint(const long &lparam, const double &dparam, datetime &t, double &price, int &bar_index)
{
   int sub = 0;
   int x = (int)lparam;
   int y = (int)dparam;

   if(!ChartXYToTimePrice(0, x, y, sub, t, price))
      return false;

   bar_index = iBarShift(_Symbol, _Period, t, false);
   if(bar_index < 0)
      return false;

   t = iTime(_Symbol, _Period, bar_index);
   return true;
}

void SelectBO(int bar_index, datetime t)
{
   g_has_bo = true;
   g_bo_index = bar_index;
   g_bo_time = t;
   DrawVerticalMarker("BO", t, InpMarkerBOColor, "BO");
   SetMode(MODE_NONE);
}

void SelectFT(int bar_index, datetime t)
{
   g_has_ft = true;
   g_ft_index = bar_index;
   g_ft_time = t;
   DrawVerticalMarker("FT", t, InpMarkerFTColor, "FT");
   SetMode(MODE_NONE);
}

void SelectBOPoint(datetime t, double price)
{
   g_has_bo_point = true;
   g_bo_point = price;
   DrawPriceMarker("BO_POINT", t, price, InpMarkerPointColor, "BO point");
   SetMode(MODE_NONE);
}

void SelectLegPoint(int bar_index, datetime t, double price)
{
   if(g_leg_click_step == 0)
   {
      g_leg_start_index = bar_index;
      g_leg_start_time = t;
      g_leg_start_price = price;
      DrawPriceMarker("LEG_START", t, price, clrSlateBlue, "Leg start");
      g_leg_click_step = 1;
   }
   else if(g_leg_click_step == 1)
   {
      g_leg_end_index = bar_index;
      g_leg_end_time = t;
      g_leg_end_price = price;
      DrawPriceMarker("LEG_END", t, price, clrSlateBlue, "Leg end");
      g_leg_click_step = 2;
   }
   else
   {
      g_pb_end_index = bar_index;
      g_pb_end_time = t;
      g_pb_end_price = price;
      DrawPriceMarker("PB_END", t, price, clrSlateBlue, "PB end");
      g_has_leg = true;
      g_leg_click_step = 0;
      SetMode(MODE_NONE);
      return;
   }

   UpdateModeLabel();
}

int CalculateSwingPeriod(int bar_index)
{
   if(bar_index <= 0)
      return -1;

   string dir = "";
   if(g_has_bo)
      dir = CandleDirection(g_bo_index);

   bool swing_high = (dir != "bearish");
   double center = swing_high ? iHigh(_Symbol, _Period, bar_index) : iLow(_Symbol, _Period, bar_index);

   int older = 0;
   int newer = 0;
   int bars_total = Bars(_Symbol, _Period);

   for(int i = bar_index + 1; i < bars_total; i++)
   {
      double v = swing_high ? iHigh(_Symbol, _Period, i) : iLow(_Symbol, _Period, i);
      if(swing_high)
      {
         if(v < center) older++; else break;
      }
      else
      {
         if(v > center) older++; else break;
      }
   }

   for(int i = bar_index - 1; i >= 0; i--)
   {
      double v = swing_high ? iHigh(_Symbol, _Period, i) : iLow(_Symbol, _Period, i);
      if(swing_high)
      {
         if(v < center) newer++; else break;
      }
      else
      {
         if(v > center) newer++; else break;
      }
   }

   return MathMin(older, newer);
}

void SelectSwing(int bar_index, datetime t, double price)
{
   g_has_swing = true;
   g_swing_index = bar_index;
   g_swing_time = t;
   g_swing_price = price;
   g_swing_period = CalculateSwingPeriod(bar_index);
   DrawPriceMarker("SWING", t, price, clrPurple, "Swing " + IntegerToString(g_swing_period));
   SetMode(MODE_NONE);
}

void ClearSelections()
{
   g_has_bo = false;
   g_has_ft = false;
   g_has_bo_point = false;
   g_has_leg = false;
   g_has_swing = false;

   g_bo_index = -1;
   g_ft_index = -1;
   g_leg_start_index = -1;
   g_leg_end_index = -1;
   g_pb_end_index = -1;
   g_swing_index = -1;

   g_bo_point = 0.0;
   g_leg_start_price = 0.0;
   g_leg_end_price = 0.0;
   g_pb_end_price = 0.0;
   g_swing_period = -1;

   string names[] = {"BO_LINE", "BO_LBL", "FT_LINE", "FT_LBL", "BO_POINT", "LEG_START", "LEG_END", "PB_END", "SWING"};
   for(int i = 0; i < ArraySize(names); i++)
      ObjectDelete(0, Obj(names[i]));

   SetMode(MODE_NONE);
}

//----------------------------- Outcome logic -----------------------
string CheckLegEndReached(const string dir)
{
   if(!g_has_leg)
      return "";

   int start = g_pb_end_index;
   if(start < 0)
      return "";

   int last = MathMax(0, start - InpMaxOutcomeBars);

   for(int i = start; i >= last; i--)
   {
      bool hit_target = false;
      bool hit_stop = false;

      if(dir == "bullish")
      {
         hit_target = (iHigh(_Symbol, _Period, i) >= g_leg_end_price);
         hit_stop   = (iLow(_Symbol, _Period, i) <= g_leg_start_price);
      }
      else if(dir == "bearish")
      {
         hit_target = (iLow(_Symbol, _Period, i) <= g_leg_end_price);
         hit_stop   = (iHigh(_Symbol, _Period, i) >= g_leg_start_price);
      }

      if(hit_target && hit_stop)
         return "ambiguous";
      if(hit_target)
         return "true";
      if(hit_stop)
         return "false";
   }

   return "false";
}

string CheckSymmetricLegReached(const string dir)
{
   if(!g_has_leg)
      return "";

   double leg_size = MathAbs(g_leg_end_price - g_leg_start_price);
   if(leg_size <= 0.0)
      return "";

   double target = 0.0;
   if(dir == "bullish")
      target = g_pb_end_price + leg_size;
   else if(dir == "bearish")
      target = g_pb_end_price - leg_size;
   else
      return "";

   int start = g_pb_end_index;
   int last = MathMax(0, start - InpMaxOutcomeBars);

   for(int i = start; i >= last; i--)
   {
      bool hit_target = false;
      bool hit_stop = false;

      if(dir == "bullish")
      {
         hit_target = (iHigh(_Symbol, _Period, i) >= target);
         hit_stop   = (iLow(_Symbol, _Period, i) <= g_leg_start_price);
      }
      else
      {
         hit_target = (iLow(_Symbol, _Period, i) <= target);
         hit_stop   = (iHigh(_Symbol, _Period, i) >= g_leg_start_price);
      }

      if(hit_target && hit_stop)
         return "ambiguous";
      if(hit_target)
         return "true";
      if(hit_stop)
         return "false";
   }

   return "false";
}

int CandlesToReachBOPointDuringPullback(const string dir, int &touch_index)
{
   touch_index = -1;
   if(!g_has_leg || !g_has_bo_point)
      return -1;

   int start = g_leg_end_index;
   int end   = g_pb_end_index;

   if(start < 0 || end < 0)
      return -1;

   int step = (start >= end) ? -1 : 1;

   for(int i = start; ; i += step)
   {
      bool touched = false;
      if(dir == "bullish")
         touched = (iLow(_Symbol, _Period, i) <= g_bo_point);
      else if(dir == "bearish")
         touched = (iHigh(_Symbol, _Period, i) >= g_bo_point);

      if(touched)
      {
         touch_index = i;
         return MathAbs(start - i);
      }

      if(i == end)
         break;
   }

   return -1;
}

void CheckRTargets(const string dir, const int touch_index, string &r1_status, string &r2_status)
{
   r1_status = "";
   r2_status = "";

   if(touch_index < 0 || !g_has_bo_point || !g_has_leg)
      return;

   double entry = g_bo_point;
   double stop = g_leg_start_price;
   double risk = 0.0;
   double r1 = 0.0;
   double r2 = 0.0;

   if(dir == "bullish")
   {
      risk = entry - stop;
      if(risk <= 0.0)
         return;
      r1 = entry + risk;
      r2 = entry + 2.0 * risk;
   }
   else if(dir == "bearish")
   {
      risk = stop - entry;
      if(risk <= 0.0)
         return;
      r1 = entry - risk;
      r2 = entry - 2.0 * risk;
   }
   else
      return;

   r1_status = "false";
   r2_status = "false";

   int last = MathMax(0, touch_index - InpMaxOutcomeBars);

   for(int i = touch_index; i >= last; i--)
   {
      bool hit_stop = false;
      bool hit_r1 = false;
      bool hit_r2 = false;

      if(dir == "bullish")
      {
         hit_stop = (iLow(_Symbol, _Period, i) <= stop);
         hit_r1   = (iHigh(_Symbol, _Period, i) >= r1);
         hit_r2   = (iHigh(_Symbol, _Period, i) >= r2);
      }
      else
      {
         hit_stop = (iHigh(_Symbol, _Period, i) >= stop);
         hit_r1   = (iLow(_Symbol, _Period, i) <= r1);
         hit_r2   = (iLow(_Symbol, _Period, i) <= r2);
      }

      if(hit_r1 && hit_stop && r1_status == "false")
         r1_status = "ambiguous";
      else if(hit_r1 && r1_status == "false")
         r1_status = "true";

      if(hit_r2 && hit_stop && r2_status == "false")
      {
         r2_status = "ambiguous";
         return;
      }
      else if(hit_r2 && r2_status == "false")
      {
         r2_status = "true";
         return;
      }

      if(hit_stop)
         return;
   }
}

//----------------------------- CSV row -----------------------------
string HeaderRow()
{
   string h[];
   ArrayResize(h, 56);
   int k = 0;
   h[k++] = "timestamp_of_BO";
   h[k++] = "symbol";
   h[k++] = "timeframe";
   h[k++] = "session";
   h[k++] = "ATR14";
   h[k++] = "bullish_bearish_breakout";
   h[k++] = "breakout_candle_body_to_range";
   h[k++] = "close_percentage";
   h[k++] = "engulfing";
   h[k++] = "candle_range_in_ATR";
   h[k++] = "FT_bullish_bearish";
   h[k++] = "FT_body_to_range";
   h[k++] = "FT_close_percentage";
   h[k++] = "FT_candle_range_in_ATR";
   h[k++] = "gap_between_FT_and_before_BO_pips";
   h[k++] = "gap_between_FT_and_BO_point_pips";
   h[k++] = "how_many_FT_before_first_PB";
   h[k++] = "breakout_point";
   h[k++] = "leg_start_price";
   h[k++] = "leg_end_price";
   h[k++] = "pullback_end_price";
   h[k++] = "break_out_of_what";
   h[k++] = "break_out_of_what_pattern";
   h[k++] = "is_it_a_breakout_from_a_pullback";
   h[k++] = "at_what_leg";
   h[k++] = "swing_period";
   h[k++] = "break_out_location_in_HTF";
   h[k++] = "market_condition";
   h[k++] = "market_direction";
   h[k++] = "close_distance_to_EMA20_pips";
   h[k++] = "close_distance_to_EMA20_ATR";
   h[k++] = "close_distance_to_EMA60_pips";
   h[k++] = "close_distance_to_EMA60_ATR";
   h[k++] = "EMA20_slope_simple_pips";
   h[k++] = "EMA20_slope_normalized_ATR";
   h[k++] = "pullback_depth";
   h[k++] = "how_many_candles_to_reach_BO_point";
   h[k++] = "breakout_point_entry_success_1R";
   h[k++] = "breakout_point_entry_success_2R";
   h[k++] = "leg_end_reached";
   h[k++] = "failed_or_succeeded";
   h[k++] = "symmetric_leg_reached";
   h[k++] = "note";
   h[k++] = "screenshot_path";
   h[k++] = "bo_bar_index";
   h[k++] = "ft_bar_index";
   h[k++] = "leg_start_bar_index";
   h[k++] = "leg_end_bar_index";
   h[k++] = "pullback_end_bar_index";
   h[k++] = "swing_bar_index";
   h[k++] = "max_outcome_bars";
   h[k++] = "ema20_slope_lookback";
   h[k++] = "broker_time_saved";
   h[k++] = "export_symbol_digits";
   h[k++] = "pip_size";
   h[k++] = "indicator_version";
   return JoinCsv(h);
}

string BuildEventRow()
{
   string f[];
   ArrayResize(f, 56);
   int k = 0;

   double pip = PipSize();
   string bo_dir = g_has_bo ? CandleDirection(g_bo_index) : "";

   double atr = EMPTY_VALUE;
   if(g_has_bo)
      GetBufferValue(atr_handle, g_bo_index, atr);

   double ema20 = EMPTY_VALUE;
   double ema60 = EMPTY_VALUE;
   double ema20_old = EMPTY_VALUE;

   double dist20_pips = EMPTY_VALUE;
   double dist20_atr = EMPTY_VALUE;
   double dist60_pips = EMPTY_VALUE;
   double dist60_atr = EMPTY_VALUE;
   double slope_simple_pips = EMPTY_VALUE;
   double slope_norm_atr = EMPTY_VALUE;

   if(g_has_bo)
   {
      double close_bo = iClose(_Symbol, _Period, g_bo_index);
      if(GetBufferValue(ema20_handle, g_bo_index, ema20))
      {
         dist20_pips = (close_bo - ema20) / pip;
         if(atr > 0.0 && atr != EMPTY_VALUE)
            dist20_atr = (close_bo - ema20) / atr;
      }

      if(GetBufferValue(ema60_handle, g_bo_index, ema60))
      {
         dist60_pips = (close_bo - ema60) / pip;
         if(atr > 0.0 && atr != EMPTY_VALUE)
            dist60_atr = (close_bo - ema60) / atr;
      }

      if(GetBufferValue(ema20_handle, g_bo_index + InpEMA20SlopeLookback, ema20_old) && ema20 != EMPTY_VALUE)
      {
         double slope_price = ema20 - ema20_old;
         slope_simple_pips = slope_price / pip;
         if(atr > 0.0 && atr != EMPTY_VALUE)
            slope_norm_atr = slope_price / atr;
      }
   }

   double gap_ft_before_bo = EMPTY_VALUE;
   double gap_ft_bo_point = EMPTY_VALUE;
   if(g_has_bo && g_has_ft)
   {
      if(bo_dir == "bullish")
      {
         gap_ft_before_bo = (iLow(_Symbol, _Period, g_ft_index) - iHigh(_Symbol, _Period, g_bo_index + 1)) / pip;
         if(g_has_bo_point)
            gap_ft_bo_point = (iLow(_Symbol, _Period, g_ft_index) - g_bo_point) / pip;
      }
      else if(bo_dir == "bearish")
      {
         gap_ft_before_bo = (iLow(_Symbol, _Period, g_bo_index + 1) - iHigh(_Symbol, _Period, g_ft_index)) / pip;
         if(g_has_bo_point)
            gap_ft_bo_point = (g_bo_point - iHigh(_Symbol, _Period, g_ft_index)) / pip;
      }
   }

   double pullback_depth = EMPTY_VALUE;
   if(g_has_leg)
   {
      double leg_size = MathAbs(g_leg_end_price - g_leg_start_price);
      double pb_size = MathAbs(g_leg_end_price - g_pb_end_price);
      if(leg_size > 0.0)
         pullback_depth = pb_size / leg_size;
   }

   int touch_index = -1;
   int candles_to_bo_point = CandlesToReachBOPointDuringPullback(bo_dir, touch_index);
   string r1_status, r2_status;
   CheckRTargets(bo_dir, touch_index, r1_status, r2_status);

   string leg_end_reached = CheckLegEndReached(bo_dir);
   string failed_succeeded = "";
   if(leg_end_reached == "true")
      failed_succeeded = "succeeded";
   else if(leg_end_reached == "false")
      failed_succeeded = "failed";
   else if(leg_end_reached == "ambiguous")
      failed_succeeded = "ambiguous";

   string sym_leg_reached = CheckSymmetricLegReached(bo_dir);

   f[k++] = g_has_bo ? TimeToString(g_bo_time, TIME_DATE | TIME_MINUTES) : "";
   f[k++] = _Symbol;
   f[k++] = TimeframeToString();
   f[k++] = g_has_bo ? GetSessions(g_bo_time) : "";
   f[k++] = Dbl(atr, _Digits);
   f[k++] = bo_dir;
   f[k++] = g_has_bo ? Dbl(CandleBodyToRange(g_bo_index), 5) : "";
   f[k++] = g_has_bo ? Dbl(ClosePercentageDistanceFromExtreme(g_bo_index), 5) : "";
   f[k++] = g_has_bo ? BoolText(IsEngulfingBO(g_bo_index)) : "";
   f[k++] = g_has_bo ? Dbl(CandleRangeInATR(g_bo_index), 5) : "";

   f[k++] = g_has_ft ? CandleDirection(g_ft_index) : "";
   f[k++] = g_has_ft ? Dbl(CandleBodyToRange(g_ft_index), 5) : "";
   f[k++] = g_has_ft ? Dbl(ClosePercentageDistanceFromExtreme(g_ft_index), 5) : "";
   f[k++] = g_has_ft ? Dbl(CandleRangeInATR(g_ft_index), 5) : "";
   f[k++] = Dbl(gap_ft_before_bo, 2);
   f[k++] = Dbl(gap_ft_bo_point, 2);
   f[k++] = GetEdit("EDIT_FT_BEFORE_PB");

   f[k++] = g_has_bo_point ? Dbl(g_bo_point, _Digits) : "";
   f[k++] = g_has_leg ? Dbl(g_leg_start_price, _Digits) : "";
   f[k++] = g_has_leg ? Dbl(g_leg_end_price, _Digits) : "";
   f[k++] = g_has_leg ? Dbl(g_pb_end_price, _Digits) : "";

   f[k++] = GetEdit("EDIT_BREAK_OUT_OF_WHAT");
   f[k++] = GetEdit("EDIT_PATTERN");
   f[k++] = GetEdit("EDIT_FROM_PULLBACK");
   f[k++] = GetEdit("EDIT_AT_LEG");
   f[k++] = g_has_swing ? IntegerToString(g_swing_period) : "";
   f[k++] = GetEdit("EDIT_HTF_LOCATION");
   f[k++] = GetEdit("EDIT_MARKET_CONDITION");
   f[k++] = GetEdit("EDIT_MARKET_DIRECTION");

   f[k++] = Dbl(dist20_pips, 2);
   f[k++] = Dbl(dist20_atr, 5);
   f[k++] = Dbl(dist60_pips, 2);
   f[k++] = Dbl(dist60_atr, 5);
   f[k++] = Dbl(slope_simple_pips, 2);
   f[k++] = Dbl(slope_norm_atr, 5);

   f[k++] = Dbl(pullback_depth, 5);
   f[k++] = (candles_to_bo_point >= 0 ? IntegerToString(candles_to_bo_point) : "");
   f[k++] = r1_status;
   f[k++] = r2_status;
   f[k++] = leg_end_reached;
   f[k++] = failed_succeeded;
   f[k++] = sym_leg_reached;

   f[k++] = GetEdit("EDIT_NOTE");
   f[k++] = GetEdit("EDIT_SCREENSHOT");

   f[k++] = g_has_bo ? IntegerToString(g_bo_index) : "";
   f[k++] = g_has_ft ? IntegerToString(g_ft_index) : "";
   f[k++] = g_has_leg ? IntegerToString(g_leg_start_index) : "";
   f[k++] = g_has_leg ? IntegerToString(g_leg_end_index) : "";
   f[k++] = g_has_leg ? IntegerToString(g_pb_end_index) : "";
   f[k++] = g_has_swing ? IntegerToString(g_swing_index) : "";
   f[k++] = IntegerToString(InpMaxOutcomeBars);
   f[k++] = IntegerToString(InpEMA20SlopeLookback);
   f[k++] = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   f[k++] = IntegerToString(_Digits);
   f[k++] = Dbl(pip, _Digits);
   f[k++] = "1.0";

   return JoinCsv(f);
}

void SaveCurrentEvent()
{
   if(!g_has_bo)
   {
      Alert("Select a breakout candle first.");
      return;
   }

   string row = BuildEventRow();
   int n = ArraySize(g_rows);
   ArrayResize(g_rows, n + 1);
   g_rows[n] = row;
   g_saved_count = n + 1;
   UpdateModeLabel();

   Alert("Saved Backtesting BO event. Rows in memory: ", g_saved_count);
}

void ExportCsv()
{
   string filename = Trim(GetEdit("EDIT_EXPORT_NAME"));
   if(filename == "")
      filename = InpDefaultExportName;

   if(StringFind(filename, ".csv") < 0)
      filename += ".csv";

   int flags = FILE_WRITE | FILE_TXT | FILE_ANSI;
   if(InpUseCommonFiles)
      flags |= FILE_COMMON;

   int handle = FileOpen(filename, flags);
   if(handle == INVALID_HANDLE)
   {
      Alert("Could not open export file: ", filename, " error: ", GetLastError());
      return;
   }

   FileWriteString(handle, HeaderRow() + "\r\n");
   for(int i = 0; i < ArraySize(g_rows); i++)
      FileWriteString(handle, g_rows[i] + "\r\n");

   FileClose(handle);

   Alert("Exported ", ArraySize(g_rows), " rows to MQL5/Files/", filename);
}

//----------------------------- Events ------------------------------
void HandleObjectClick(const string obj_name)
{
   if(obj_name == Obj("BTN_BO"))
      SetMode(MODE_BO);
   else if(obj_name == Obj("BTN_FT"))
      SetMode(MODE_FT);
   else if(obj_name == Obj("BTN_POINT"))
      SetMode(MODE_BO_POINT);
   else if(obj_name == Obj("BTN_LEG"))
      SetMode(MODE_LEG);
   else if(obj_name == Obj("BTN_SWING"))
      SetMode(MODE_SWING);
   else if(obj_name == Obj("BTN_SAVE"))
      SaveCurrentEvent();
   else if(obj_name == Obj("BTN_EXPORT"))
      ExportCsv();
   else if(obj_name == Obj("BTN_CLEAR"))
      ClearSelections();
}

void HandleKey(int key)
{
   if(key >= 'a' && key <= 'z')
      key -= 32;

   if(key == UpperFirstCode(InpKeyBO))
      SetMode(MODE_BO);
   else if(key == UpperFirstCode(InpKeyFT))
      SetMode(MODE_FT);
   else if(key == UpperFirstCode(InpKeyBOPoint))
      SetMode(MODE_BO_POINT);
   else if(key == UpperFirstCode(InpKeyLeg))
      SetMode(MODE_LEG);
   else if(key == UpperFirstCode(InpKeySwing))
      SetMode(MODE_SWING);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      HandleObjectClick(sparam);
      return;
   }

   if(id == CHARTEVENT_KEYDOWN)
   {
      HandleKey((int)lparam);
      return;
   }

   if(id == CHARTEVENT_CLICK)
   {
      if(g_mode == MODE_NONE)
         return;

      datetime t;
      double price;
      int bar_index;
      if(!GetClickedPoint(lparam, dparam, t, price, bar_index))
         return;

      if(g_mode == MODE_BO)
         SelectBO(bar_index, t);
      else if(g_mode == MODE_FT)
         SelectFT(bar_index, t);
      else if(g_mode == MODE_BO_POINT)
         SelectBOPoint(t, price);
      else if(g_mode == MODE_LEG)
         SelectLegPoint(bar_index, t, price);
      else if(g_mode == MODE_SWING)
         SelectSwing(bar_index, t, price);
   }
}

//----------------------------- MT5 lifecycle -----------------------
int OnInit()
{
   PREFIX = "BTBO_" + _Symbol + "_" + IntegerToString((int)_Period) + "_";

   atr_handle = iATR(_Symbol, _Period, InpATRPeriod);
   ema20_handle = iMA(_Symbol, _Period, InpEMA20Period, 0, MODE_EMA, PRICE_CLOSE);
   ema60_handle = iMA(_Symbol, _Period, InpEMA60Period, 0, MODE_EMA, PRICE_CLOSE);

   if(atr_handle == INVALID_HANDLE || ema20_handle == INVALID_HANDLE || ema60_handle == INVALID_HANDLE)
   {
      Print("Backtesting BO: failed to create indicator handles. Error: ", GetLastError());
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "Backtesting BO");

   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   CreatePanel();
   UpdateModeLabel();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
   if(ema20_handle != INVALID_HANDLE)
      IndicatorRelease(ema20_handle);
   if(ema60_handle != INVALID_HANDLE)
      IndicatorRelease(ema60_handle);

   DeleteObjects();
}

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
   return rates_total;
}
//+------------------------------------------------------------------+
