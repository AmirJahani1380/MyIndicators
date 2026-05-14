//+------------------------------------------------------------------+
//|                                               Backtesting BO.mq5   |
//|  Semi-automatic breakout annotation and CSV export indicator.      |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_plots   1
#property indicator_buffers 5
#property strict

#property indicator_label1  "Selected BO/FT Candles"
#property indicator_type1   DRAW_COLOR_CANDLES
#property indicator_color1  clrNONE, clrDarkViolet, clrDarkViolet
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

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
input int      InpPanelWidth         = 620;      // Panel width
input int      InpPanelHeight        = 620;      // Panel height
input color    InpPanelBgColor       = clrWhiteSmoke;
input color    InpPanelBorderColor   = clrSilver;
input color    InpEditBgColor        = clrWhite;
input color    InpEditTextColor      = clrBlack;
input string   InpUIFont            = "Arial";  // Panel font
input int      InpUIFontSize         = 8;        // Panel font size

// Selected candle color. Selected BO and FT candles are drawn with DRAW_COLOR_CANDLES.
input color    InpSelectedCandleColor = clrDarkViolet;

// Short horizontal marker line settings.
input color    InpBOPointLineColor    = clrOrangeRed;
input ENUM_LINE_STYLE InpBOPointLineStyle = STYLE_SOLID;
input int      InpBOPointLineWidth    = 2;
input color    InpLegLineColor        = clrSlateBlue;
input ENUM_LINE_STYLE InpLegLineStyle = STYLE_SOLID;
input int      InpLegLineWidth        = 2;
input color    InpSwingLineColor      = clrPurple;
input ENUM_LINE_STYLE InpSwingLineStyle = STYLE_DOT;
input int      InpSwingLineWidth      = 2;

//----------------------------- Indicator buffers -------------------
double SelOpenBuffer[];
double SelHighBuffer[];
double SelLowBuffer[];
double SelCloseBuffer[];
double SelColorBuffer[];

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

enum PanelTab
{
   TAB_FORM = 0,
   TAB_ROWS = 1
};

SelectMode g_mode = MODE_NONE;
PanelTab   g_tab  = TAB_FORM;
int        g_leg_click_step = 0;
bool       g_ignore_next_chart_click = false;
int        g_row_offset = 0;
int        g_col_offset = 0;

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

// Form state is stored here so switching tabs does not erase input text.
string g_export_name;
string g_break_out_of_what = "";
string g_pattern = "";
string g_from_pullback = "";
string g_at_leg = "";
string g_htf_location = "";
string g_market_condition = "";
string g_market_direction = "";
string g_ft_before_pb = "";
string g_screenshot_path = "";
string g_note = "";

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

void DeleteObjectsContaining(const string token)
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, PREFIX) == 0 && StringFind(name, token) >= 0)
         ObjectDelete(0, name);
   }
}

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

//----------------------------- Visual markers ----------------------
void RefreshSelectedCandles()
{
   ChartRedraw(0);
}

void DrawShortHLine(const string name,
                    datetime t,
                    double price,
                    color c,
                    ENUM_LINE_STYLE style,
                    int width)
{
   string obj = Obj(name);
   ObjectDelete(0, obj);

   datetime t2 = t + (datetime)(2 * PeriodSeconds(_Period));

   if(!ObjectCreate(0, obj, OBJ_TREND, 0, t, price, t2, price))
      return;

   ObjectSetInteger(0, obj, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, obj, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, c);
   ObjectSetInteger(0, obj, OBJPROP_STYLE, style);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
}

//----------------------------- Panel UI ----------------------------
void ApplyTextStyle(const string obj, int font_size = -1)
{
   ObjectSetString(0, obj, OBJPROP_FONT, InpUIFont);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, font_size > 0 ? font_size : InpUIFontSize);
}

void MakeLabel(const string name, int x, int y, int w, const string text, color clr = clrBlack)
{
   string obj = Obj(name);
   ObjectDelete(0, obj);
   ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
   ApplyTextStyle(obj);
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
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ApplyTextStyle(obj);
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
   ObjectSetInteger(0, obj, OBJPROP_COLOR, InpEditTextColor);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, InpEditBgColor);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ApplyTextStyle(obj);
}

void MakeCell(const string name, int x, int y, int w, int h, const string text, bool header=false)
{
   string bg = Obj(name + "_BG");
   ObjectDelete(0, bg);
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, header ? C'235,235,235' : clrWhite);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);

   string lbl = Obj(name + "_TXT");
   ObjectDelete(0, lbl);
   ObjectCreate(0, lbl, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, lbl, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, lbl, OBJPROP_XDISTANCE, x + 3);
   ObjectSetInteger(0, lbl, OBJPROP_YDISTANCE, y + 3);
   ObjectSetInteger(0, lbl, OBJPROP_XSIZE, w - 6);
   ObjectSetInteger(0, lbl, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, lbl, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, lbl, OBJPROP_TEXT, text);
   ApplyTextStyle(lbl, InpUIFontSize);
}

void SaveFormState()
{
   if(ObjectFind(0, Obj("FORM_EDIT_EXPORT_NAME")) >= 0)
      g_export_name = GetEdit("FORM_EDIT_EXPORT_NAME");
   if(ObjectFind(0, Obj("FORM_EDIT_BREAK_OUT_OF_WHAT")) >= 0)
      g_break_out_of_what = GetEdit("FORM_EDIT_BREAK_OUT_OF_WHAT");
   if(ObjectFind(0, Obj("FORM_EDIT_PATTERN")) >= 0)
      g_pattern = GetEdit("FORM_EDIT_PATTERN");
   if(ObjectFind(0, Obj("FORM_EDIT_FROM_PULLBACK")) >= 0)
      g_from_pullback = GetEdit("FORM_EDIT_FROM_PULLBACK");
   if(ObjectFind(0, Obj("FORM_EDIT_AT_LEG")) >= 0)
      g_at_leg = GetEdit("FORM_EDIT_AT_LEG");
   if(ObjectFind(0, Obj("FORM_EDIT_HTF_LOCATION")) >= 0)
      g_htf_location = GetEdit("FORM_EDIT_HTF_LOCATION");
   if(ObjectFind(0, Obj("FORM_EDIT_MARKET_CONDITION")) >= 0)
      g_market_condition = GetEdit("FORM_EDIT_MARKET_CONDITION");
   if(ObjectFind(0, Obj("FORM_EDIT_MARKET_DIRECTION")) >= 0)
      g_market_direction = GetEdit("FORM_EDIT_MARKET_DIRECTION");
   if(ObjectFind(0, Obj("FORM_EDIT_FT_BEFORE_PB")) >= 0)
      g_ft_before_pb = GetEdit("FORM_EDIT_FT_BEFORE_PB");
   if(ObjectFind(0, Obj("FORM_EDIT_SCREENSHOT")) >= 0)
      g_screenshot_path = GetEdit("FORM_EDIT_SCREENSHOT");
   if(ObjectFind(0, Obj("FORM_EDIT_NOTE")) >= 0)
      g_note = GetEdit("FORM_EDIT_NOTE");
}

void ClearDynamicPanelObjects()
{
   DeleteObjectsContaining("ROW_");
   DeleteObjectsContaining("FORM_");
}

void CreatePanelBase()
{
   if(!InpShowPanel)
      return;

   int x = InpPanelX;
   int y = InpPanelY;
   int w = InpPanelWidth;
   int h = InpPanelHeight;

   string bg = Obj("PANEL_BG");
   ObjectDelete(0, bg);
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, InpPanelBgColor);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, InpPanelBorderColor);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);

   MakeLabel("TITLE", x + 10, y + 8, w - 60, "Backtesting BO", clrBlack);
   MakeButton("BTN_CLOSE", x + w - 32, y + 5, 22, 20, "X");
   MakeButton("BTN_TAB_FORM", x + 10, y + 34, 80, 22, "Form");
   MakeButton("BTN_TAB_ROWS", x + 95, y + 34, 80, 22, "Rows");
   MakeLabel("MODE",  x + 185, y + 37, w - 195, "Mode: NONE", clrDarkBlue);
   MakeLabel("STATUS",x + 10, y + 60, w - 20, "Saved rows: 0", clrDimGray);
}

void CreateFormTab()
{
   int x = InpPanelX;
   int y = InpPanelY;

   int by = y + 86;
   MakeButton("FORM_BTN_BO",       x + 10,  by, 70, 22, "B: BO");
   MakeButton("FORM_BTN_FT",       x + 85,  by, 70, 22, "F: FT");
   MakeButton("FORM_BTN_POINT",    x + 160, by, 70, 22, "P: Point");
   MakeButton("FORM_BTN_LEG",      x + 235, by, 80, 22, "L: Leg/PB");
   MakeButton("FORM_BTN_SWING",    x + 320, by, 85, 22, "S: Swing");

   by += 28;
   MakeButton("FORM_BTN_SAVE",     x + 10,  by, 100, 24, "Save Event");
   MakeButton("FORM_BTN_EXPORT",   x + 115, by, 100, 24, "Export CSV");
   MakeButton("FORM_BTN_NEW",      x + 220, by, 90, 24, "New File");
   MakeButton("FORM_BTN_CLEAR",    x + 315, by, 90, 24, "Clear Sel.");

   by += 34;
   MakeLabel("FORM_LBL_EXPORT", x + 10, by, 110, "Export name");
   MakeEdit("FORM_EDIT_EXPORT_NAME", x + 120, by - 3, 455, 20, g_export_name);

   by += 30;
   MakeLabel("FORM_LBL_WHAT", x + 10, by, 150, "Break out of what");
   MakeEdit("FORM_EDIT_BREAK_OUT_OF_WHAT", x + 160, by - 3, 415, 20, g_break_out_of_what);

   by += 28;
   MakeLabel("FORM_LBL_PATTERN", x + 10, by, 150, "Pattern");
   MakeEdit("FORM_EDIT_PATTERN", x + 160, by - 3, 415, 20, g_pattern);

   by += 28;
   MakeLabel("FORM_LBL_PB", x + 10, by, 150, "BO from pullback");
   MakeEdit("FORM_EDIT_FROM_PULLBACK", x + 160, by - 3, 415, 20, g_from_pullback);

   by += 28;
   MakeLabel("FORM_LBL_LEGCOUNT", x + 10, by, 150, "At what leg");
   MakeEdit("FORM_EDIT_AT_LEG", x + 160, by - 3, 415, 20, g_at_leg);

   by += 28;
   MakeLabel("FORM_LBL_HTF", x + 10, by, 150, "HTF location");
   MakeEdit("FORM_EDIT_HTF_LOCATION", x + 160, by - 3, 415, 20, g_htf_location);

   by += 28;
   MakeLabel("FORM_LBL_CONDITION", x + 10, by, 150, "Market condition");
   MakeEdit("FORM_EDIT_MARKET_CONDITION", x + 160, by - 3, 415, 20, g_market_condition);

   by += 28;
   MakeLabel("FORM_LBL_DIRECTION", x + 10, by, 150, "Market direction");
   MakeEdit("FORM_EDIT_MARKET_DIRECTION", x + 160, by - 3, 415, 20, g_market_direction);

   by += 28;
   MakeLabel("FORM_LBL_FTCOUNT", x + 10, by, 150, "# FT before first PB");
   MakeEdit("FORM_EDIT_FT_BEFORE_PB", x + 160, by - 3, 415, 20, g_ft_before_pb);

   by += 28;
   MakeLabel("FORM_LBL_SCREEN", x + 10, by, 150, "Screenshot path");
   MakeEdit("FORM_EDIT_SCREENSHOT", x + 160, by - 3, 415, 20, g_screenshot_path);

   by += 28;
   MakeLabel("FORM_LBL_NOTE", x + 10, by, 150, "Note");
   MakeEdit("FORM_EDIT_NOTE", x + 160, by - 3, 415, 48, g_note);

   by += 62;
   MakeLabel("FORM_HELP1", x + 10, by, InpPanelWidth - 20, "Click modes: B=BO, F=FT, P=breakout price, L=leg start/end/PB end, S=swing.", clrDimGray);
   by += 18;
   MakeLabel("FORM_HELP2", x + 10, by, InpPanelWidth - 20, "Manual fields may be blank. Multi-label fields can be comma-separated.", clrDimGray);
}

string FieldAtCsvIndex(const string row, int wanted)
{
   string out = "";
   int idx = 0;
   bool quoted = false;
   string cur = "";

   for(int i = 0; i < StringLen(row); i++)
   {
      ushort ch = StringGetCharacter(row, i);
      if(ch == '"')
      {
         if(quoted && i + 1 < StringLen(row) && StringGetCharacter(row, i + 1) == '"')
         {
            cur += "\"";
            i++;
         }
         else
            quoted = !quoted;
      }
      else if(ch == ',' && !quoted)
      {
         if(idx == wanted)
            return cur;
         cur = "";
         idx++;
      }
      else
         cur += ShortToString(ch);
   }

   if(idx == wanted)
      return cur;
   return out;
}

void CreateRowsTab()
{
   int x = InpPanelX;
   int y = InpPanelY;
   int by = y + 88;

   MakeButton("ROW_BTN_EXPORT", x + 10, by, 100, 24, "Export CSV");
   MakeButton("ROW_BTN_NEW", x + 115, by, 90, 24, "New File");
   MakeButton("ROW_BTN_UP", x + 210, by, 34, 24, "Up");
   MakeButton("ROW_BTN_DN", x + 248, by, 34, 24, "Dn");
   MakeButton("ROW_BTN_LEFT", x + 286, by, 40, 24, "Left");
   MakeButton("ROW_BTN_RIGHT", x + 330, by, 45, 24, "Right");
   MakeLabel("ROW_COUNT", x + 385, by + 4, 220, "Rows: " + IntegerToString(g_saved_count), clrBlack);

   by += 34;

   int total_cols = 47;
   int visible_cols = 5;
   int visible_rows = (InpPanelHeight - (by - y) - 25) / 22 - 1;
   if(visible_rows < 1)
      visible_rows = 1;

   if(g_col_offset < 0) g_col_offset = 0;
   if(g_col_offset > MathMax(0, total_cols - visible_cols))
      g_col_offset = MathMax(0, total_cols - visible_cols);

   if(g_row_offset < 0) g_row_offset = 0;
   if(g_row_offset > MathMax(0, g_saved_count - visible_rows))
      g_row_offset = MathMax(0, g_saved_count - visible_rows);

   int cell_h = 22;
   int col0_w = 38;
   int cell_w = (InpPanelWidth - 20 - col0_w) / visible_cols;

   MakeCell("ROW_CELL_H0", x + 10, by, col0_w, cell_h, "#", true);

   for(int c = 0; c < visible_cols; c++)
   {
      int col_idx = g_col_offset + c;
      if(col_idx >= total_cols)
         break;
      string header = FieldAtCsvIndex(HeaderRow(), col_idx);
      MakeCell("ROW_CELL_H" + IntegerToString(c + 1), x + 10 + col0_w + c * cell_w, by, cell_w, cell_h, header, true);
   }

   for(int r = 0; r < visible_rows; r++)
   {
      int row_idx = g_row_offset + r;
      int yy = by + cell_h * (r + 1);
      if(row_idx >= g_saved_count)
         break;

      MakeCell("ROW_CELL_R" + IntegerToString(r) + "_N", x + 10, yy, col0_w, cell_h, IntegerToString(row_idx + 1), false);

      for(int c = 0; c < visible_cols; c++)
      {
         int col_idx = g_col_offset + c;
         if(col_idx >= total_cols)
            break;
         string value = FieldAtCsvIndex(g_rows[row_idx], col_idx);
         if(StringLen(value) > 18)
            value = StringSubstr(value, 0, 17) + "...";
         MakeCell("ROW_CELL_R" + IntegerToString(r) + "_C" + IntegerToString(c),
                  x + 10 + col0_w + c * cell_w, yy, cell_w, cell_h, value, false);
      }
   }

   MakeLabel("ROW_SCROLL_INFO", x + 10, y + InpPanelHeight - 22, InpPanelWidth - 20,
             "Row " + IntegerToString(g_saved_count == 0 ? 0 : g_row_offset + 1) + "/" + IntegerToString(g_saved_count) +
             " | Col " + IntegerToString(g_col_offset + 1) + "/" + IntegerToString(total_cols), clrDimGray);
}

void RebuildPanel()
{
   SaveFormState();
   ClearDynamicPanelObjects();
   CreatePanelBase();
   if(g_tab == TAB_FORM)
      CreateFormTab();
   else
      CreateRowsTab();
   UpdateModeLabel();
   ChartRedraw(0);
}

void CreatePanel()
{
   CreatePanelBase();
   CreateFormTab();
   UpdateModeLabel();
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
   SetLabelText("ROW_COUNT", "Rows: " + IntegerToString(g_saved_count));
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
   RefreshSelectedCandles();
   SetMode(MODE_NONE);
}

void SelectFT(int bar_index, datetime t)
{
   g_has_ft = true;
   g_ft_index = bar_index;
   g_ft_time = t;
   RefreshSelectedCandles();
   SetMode(MODE_NONE);
}

void SelectBOPoint(datetime t, double price)
{
   g_has_bo_point = true;
   g_bo_point = price;
   DrawShortHLine("BO_POINT_LINE", t, price, InpBOPointLineColor, InpBOPointLineStyle, InpBOPointLineWidth);
   SetMode(MODE_NONE);
}

void SelectLegPoint(int bar_index, datetime t, double price)
{
   if(g_leg_click_step == 0)
   {
      g_leg_start_index = bar_index;
      g_leg_start_time = t;
      g_leg_start_price = price;
      DrawShortHLine("LEG_START_LINE", t, price, InpLegLineColor, InpLegLineStyle, InpLegLineWidth);
      g_leg_click_step = 1;
   }
   else if(g_leg_click_step == 1)
   {
      g_leg_end_index = bar_index;
      g_leg_end_time = t;
      g_leg_end_price = price;
      DrawShortHLine("LEG_END_LINE", t, price, InpLegLineColor, InpLegLineStyle, InpLegLineWidth);
      g_leg_click_step = 2;
   }
   else
   {
      g_pb_end_index = bar_index;
      g_pb_end_time = t;
      g_pb_end_price = price;
      DrawShortHLine("PB_END_LINE", t, price, InpLegLineColor, InpLegLineStyle, InpLegLineWidth);
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
   DrawShortHLine("SWING_LINE", t, price, InpSwingLineColor, InpSwingLineStyle, InpSwingLineWidth);
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

   string names[] = {"BO_POINT_LINE", "LEG_START_LINE", "LEG_END_LINE", "PB_END_LINE", "SWING_LINE"};
   for(int i = 0; i < ArraySize(names); i++)
      ObjectDelete(0, Obj(names[i]));

   RefreshSelectedCandles();
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
   ArrayResize(h, 47);
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
   h[k++] = "ema20_slope_lookback";
   h[k++] = "pip_size";
   h[k++] = "indicator_version";
   return JoinCsv(h);
}

string BuildEventRow()
{
   SaveFormState();

   string f[];
   ArrayResize(f, 47);
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
   f[k++] = g_ft_before_pb;

   f[k++] = g_has_bo_point ? Dbl(g_bo_point, _Digits) : "";
   f[k++] = g_has_leg ? Dbl(g_leg_start_price, _Digits) : "";
   f[k++] = g_has_leg ? Dbl(g_leg_end_price, _Digits) : "";
   f[k++] = g_has_leg ? Dbl(g_pb_end_price, _Digits) : "";

   f[k++] = g_break_out_of_what;
   f[k++] = g_pattern;
   f[k++] = g_from_pullback;
   f[k++] = g_at_leg;
   f[k++] = g_has_swing ? IntegerToString(g_swing_period) : "";
   f[k++] = g_htf_location;
   f[k++] = g_market_condition;
   f[k++] = g_market_direction;

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

   f[k++] = g_note;
   f[k++] = g_screenshot_path;
   f[k++] = IntegerToString(InpEMA20SlopeLookback);
   f[k++] = Dbl(pip, _Digits);
   f[k++] = "1.2";

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

   if(g_tab == TAB_ROWS)
      RebuildPanel();
   else
      UpdateModeLabel();

   Alert("Saved Backtesting BO event. Rows in memory: ", g_saved_count);
}

string CurrentExportName()
{
   SaveFormState();
   string filename = Trim(g_export_name);
   if(filename == "")
      filename = InpDefaultExportName;
   if(StringFind(filename, ".csv") < 0)
      filename += ".csv";
   return filename;
}

void ExportCsv()
{
   string filename = CurrentExportName();

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

void NewFile()
{
   if(g_saved_count > 0)
   {
      int ans = MessageBox("Start a new file? Current saved rows in memory will be cleared. Export first if needed.",
                           "Backtesting BO", MB_YESNO | MB_ICONQUESTION);
      if(ans != IDYES)
         return;
   }

   ArrayResize(g_rows, 0);
   g_saved_count = 0;
   g_row_offset = 0;
   g_col_offset = 0;
   ClearSelections();
   if(g_tab == TAB_ROWS)
      RebuildPanel();
   else
      UpdateModeLabel();
}

void CloseIndicatorFromButton()
{
   ChartIndicatorDelete(0, 0, "Backtesting BO");
}

//----------------------------- Events ------------------------------
void HandleObjectClick(const string obj_name)
{
   g_ignore_next_chart_click = true;

   if(obj_name == Obj("BTN_CLOSE"))
      CloseIndicatorFromButton();
   else if(obj_name == Obj("BTN_TAB_FORM"))
   {
      g_tab = TAB_FORM;
      RebuildPanel();
   }
   else if(obj_name == Obj("BTN_TAB_ROWS"))
   {
      g_tab = TAB_ROWS;
      RebuildPanel();
   }
   else if(obj_name == Obj("FORM_BTN_BO"))
      SetMode(MODE_BO);
   else if(obj_name == Obj("FORM_BTN_FT"))
      SetMode(MODE_FT);
   else if(obj_name == Obj("FORM_BTN_POINT"))
      SetMode(MODE_BO_POINT);
   else if(obj_name == Obj("FORM_BTN_LEG"))
      SetMode(MODE_LEG);
   else if(obj_name == Obj("FORM_BTN_SWING"))
      SetMode(MODE_SWING);
   else if(obj_name == Obj("FORM_BTN_SAVE"))
      SaveCurrentEvent();
   else if(obj_name == Obj("FORM_BTN_EXPORT") || obj_name == Obj("ROW_BTN_EXPORT"))
      ExportCsv();
   else if(obj_name == Obj("FORM_BTN_NEW") || obj_name == Obj("ROW_BTN_NEW"))
      NewFile();
   else if(obj_name == Obj("ROW_BTN_UP"))
   {
      g_row_offset--;
      RebuildPanel();
   }
   else if(obj_name == Obj("ROW_BTN_DN"))
   {
      g_row_offset++;
      RebuildPanel();
   }
   else if(obj_name == Obj("ROW_BTN_LEFT"))
   {
      g_col_offset--;
      RebuildPanel();
   }
   else if(obj_name == Obj("ROW_BTN_RIGHT"))
   {
      g_col_offset++;
      RebuildPanel();
   }
   else if(obj_name == Obj("FORM_BTN_CLEAR"))
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

bool ClickInsidePanel(const long &lparam, const double &dparam)
{
   int x = (int)lparam;
   int y = (int)dparam;
   return (x >= InpPanelX && x <= InpPanelX + InpPanelWidth &&
           y >= InpPanelY && y <= InpPanelY + InpPanelHeight);
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
      if(g_ignore_next_chart_click)
      {
         g_ignore_next_chart_click = false;
         return;
      }

      if(ClickInsidePanel(lparam, dparam))
         return;

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
   g_export_name = InpDefaultExportName;

   SetIndexBuffer(0, SelOpenBuffer,  INDICATOR_DATA);
   SetIndexBuffer(1, SelHighBuffer,  INDICATOR_DATA);
   SetIndexBuffer(2, SelLowBuffer,   INDICATOR_DATA);
   SetIndexBuffer(3, SelCloseBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, SelColorBuffer, INDICATOR_COLOR_INDEX);

   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_COLOR_CANDLES);
   PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 3);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, clrNONE);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, InpSelectedCandleColor);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 2, InpSelectedCandleColor);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

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
   ChartRedraw(0);
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
   for(int i = 0; i < rates_total; i++)
   {
      SelOpenBuffer[i]  = EMPTY_VALUE;
      SelHighBuffer[i]  = EMPTY_VALUE;
      SelLowBuffer[i]   = EMPTY_VALUE;
      SelCloseBuffer[i] = EMPTY_VALUE;
      SelColorBuffer[i] = 0;
   }

   if(g_has_bo)
   {
      int idx = rates_total - 1 - g_bo_index;
      if(idx >= 0 && idx < rates_total)
      {
         SelOpenBuffer[idx]  = open[idx];
         SelHighBuffer[idx]  = high[idx];
         SelLowBuffer[idx]   = low[idx];
         SelCloseBuffer[idx] = close[idx];
         SelColorBuffer[idx] = 1;
      }
   }

   if(g_has_ft)
   {
      int idx = rates_total - 1 - g_ft_index;
      if(idx >= 0 && idx < rates_total)
      {
         SelOpenBuffer[idx]  = open[idx];
         SelHighBuffer[idx]  = high[idx];
         SelLowBuffer[idx]   = low[idx];
         SelCloseBuffer[idx] = close[idx];
         SelColorBuffer[idx] = 2;
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+
