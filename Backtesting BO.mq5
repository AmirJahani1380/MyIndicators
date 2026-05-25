//+------------------------------------------------------------------+
//|                                               Backtesting BO.mq5  |
//|  Semi-automatic breakout annotation and CSV export indicator.     |
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
input int      InpPanelWidth         = 590;      // Panel width
input int      InpPanelHeight        = 505;      // Panel height
input color    InpPanelBgColor       = clrWhiteSmoke;
input color    InpPanelBorderColor   = clrSilver;
input color    InpEditBgColor        = clrWhite;
input color    InpEditTextColor      = clrBlack;
input string   InpUIFont            = "Arial";  // Panel font
input int      InpUIFontSize         = 8;        // Panel font size

// Separate rows window settings.
input int      InpRowsWindowX        = 630;      // Rows window X position
input int      InpRowsWindowY        = 20;       // Rows window Y position
input int      InpRowsWindowWidth    = 760;      // Rows window width
input int      InpRowsWindowHeight   = 430;      // Rows window height
input int      InpRowsVisibleCols    = 6;        // Visible table columns in rows window
input int      InpMouseWheelRowsStep = 3;        // Rows moved per mouse wheel step

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

enum RowsDragKind
{
   ROWS_DRAG_NONE = 0,
   ROWS_DRAG_WINDOW,
   ROWS_DRAG_VSCROLL,
   ROWS_DRAG_HSCROLL
};

SelectMode g_mode = MODE_NONE;
PanelTab   g_tab  = TAB_FORM;
int        g_leg_click_step = 0;
bool       g_ignore_next_chart_click = false;
int        g_row_offset = 0;
int        g_col_offset = 0;

bool g_rows_window_visible = false;
RowsDragKind g_rows_drag_kind = ROWS_DRAG_NONE;
int  g_rows_window_x = 0;
int  g_rows_window_y = 0;
int  g_rows_drag_offset_x = 0;
int  g_rows_drag_offset_y = 0;
int  g_last_mouse_x = 0;
int  g_last_mouse_y = 0;

int  g_rows_visible_rows = 1;
int  g_rows_visible_cols = 1;
int  g_rows_table_x = 0;
int  g_rows_table_y = 0;
int  g_rows_table_w = 0;
int  g_rows_table_h = 0;
int  g_rows_vtrack_x = 0;
int  g_rows_vtrack_y = 0;
int  g_rows_vtrack_w = 0;
int  g_rows_vtrack_h = 0;
int  g_rows_vthumb_x = 0;
int  g_rows_vthumb_y = 0;
int  g_rows_vthumb_w = 0;
int  g_rows_vthumb_h = 0;
int  g_rows_htrack_x = 0;
int  g_rows_htrack_y = 0;
int  g_rows_htrack_w = 0;
int  g_rows_htrack_h = 0;
int  g_rows_hthumb_x = 0;
int  g_rows_hthumb_y = 0;
int  g_rows_hthumb_w = 0;
int  g_rows_hthumb_h = 0;

bool g_chart_mouse_scroll_initial = true;
bool g_chart_mouse_scroll_current = true;

#define KEY_PGUP   33
#define KEY_PGDN   34
#define KEY_LEFT   37
#define KEY_UP     38
#define KEY_RIGHT  39
#define KEY_DOWN   40

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

// Form state is stored here so switching/rebuilding UI does not erase input text.
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

// Convert a stable candle open time back to the current MT5 shift.
// This prevents selected candles from moving when a new live candle appears.
int ShiftFromTime(datetime candle_time)
{
   if(candle_time <= 0)
      return -1;

   return iBarShift(_Symbol, _Period, candle_time, true);
}

// The stored times are the source of truth. Indexes are only a cache.
void SyncSelectionIndexesFromTimes()
{
   if(g_has_bo)
      g_bo_index = ShiftFromTime(g_bo_time);

   if(g_has_ft)
      g_ft_index = ShiftFromTime(g_ft_time);

   if(g_has_leg)
   {
      g_leg_start_index = ShiftFromTime(g_leg_start_time);
      g_leg_end_index   = ShiftFromTime(g_leg_end_time);
      g_pb_end_index    = ShiftFromTime(g_pb_end_time);
   }

   if(g_has_swing)
      g_swing_index = ShiftFromTime(g_swing_time);
}

bool PointInRect(const int px, const int py, const int x, const int y, const int w, const int h)
{
   return (px >= x && px <= x + w && py >= y && py <= y + h);
}

bool MainPanelHitXY(const int px, const int py)
{
   if(!InpShowPanel)
      return false;

   return PointInRect(px, py, InpPanelX, InpPanelY, InpPanelWidth, InpPanelHeight);
}

void SetChartMouseScrollState(const bool enabled)
{
   if(g_chart_mouse_scroll_current == enabled)
      return;

   ChartSetInteger(0, CHART_MOUSE_SCROLL, enabled);
   g_chart_mouse_scroll_current = enabled;
}

void UpdateChartMouseScrollProtection(const int px, const int py, const bool left_down)
{
   bool over_rows_window = false;
   if(g_rows_window_visible)
      over_rows_window = PointInRect(px, py, g_rows_window_x, g_rows_window_y,
                                     InpRowsWindowWidth, InpRowsWindowHeight);

   bool over_ui = MainPanelHitXY(px, py) || over_rows_window || g_rows_drag_kind != ROWS_DRAG_NONE;

   if(over_ui || (left_down && g_rows_drag_kind != ROWS_DRAG_NONE))
      SetChartMouseScrollState(false);
   else
      SetChartMouseScrollState(g_chart_mouse_scroll_initial);
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
void PaintSelectedCandleBuffer(const int shift, const int color_index)
{
   int rates_total = Bars(_Symbol, _Period);
   if(rates_total <= 0 || shift < 0)
      return;

   int idx = rates_total - 1 - shift;

   if(idx < 0 || idx >= rates_total)
      return;

   if(idx >= ArraySize(SelOpenBuffer) ||
      idx >= ArraySize(SelHighBuffer) ||
      idx >= ArraySize(SelLowBuffer) ||
      idx >= ArraySize(SelCloseBuffer) ||
      idx >= ArraySize(SelColorBuffer))
      return;

   SelOpenBuffer[idx]  = iOpen(_Symbol, _Period, shift);
   SelHighBuffer[idx]  = iHigh(_Symbol, _Period, shift);
   SelLowBuffer[idx]   = iLow(_Symbol, _Period, shift);
   SelCloseBuffer[idx] = iClose(_Symbol, _Period, shift);
   SelColorBuffer[idx] = color_index;
}

void RefreshSelectedCandles()
{
   int rates_total = Bars(_Symbol, _Period);
   SyncSelectionIndexesFromTimes();

   int n = ArraySize(SelOpenBuffer);
   if(ArraySize(SelHighBuffer) < n)   n = ArraySize(SelHighBuffer);
   if(ArraySize(SelLowBuffer) < n)    n = ArraySize(SelLowBuffer);
   if(ArraySize(SelCloseBuffer) < n)  n = ArraySize(SelCloseBuffer);
   if(ArraySize(SelColorBuffer) < n)  n = ArraySize(SelColorBuffer);
   if(rates_total < n)                n = rates_total;

   for(int i = 0; i < n; i++)
   {
      SelOpenBuffer[i]  = EMPTY_VALUE;
      SelHighBuffer[i]  = EMPTY_VALUE;
      SelLowBuffer[i]   = EMPTY_VALUE;
      SelCloseBuffer[i] = EMPTY_VALUE;
      SelColorBuffer[i] = 0;
   }

   if(g_has_bo)
      PaintSelectedCandleBuffer(g_bo_index, 1);

   if(g_has_ft)
      PaintSelectedCandleBuffer(g_ft_index, 2);

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

void MakeRect(const string name,
              int x,
              int y,
              int w,
              int h,
              color bg_color,
              color border_color,
              bool selectable = false)
{
   string obj = Obj(name);
   ObjectDelete(0, obj);
   ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, border_color);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, selectable);
   ObjectSetInteger(0, obj, OBJPROP_BACK, false);
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
   ObjectSetInteger(0, obj, OBJPROP_STATE, false);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ApplyTextStyle(obj);
}

void ResetButtonState(const string obj_name)
{
   if(ObjectFind(0, obj_name) < 0)
      return;

   long type = ObjectGetInteger(0, obj_name, OBJPROP_TYPE);
   if(type != OBJ_BUTTON)
      return;

   ObjectSetInteger(0, obj_name, OBJPROP_STATE, false);
   ChartRedraw(0);
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

   MakeRect("PANEL_BG", x, y, w, h, InpPanelBgColor, InpPanelBorderColor);

   MakeLabel("TITLE", x + 10, y + 8, w - 60, "Backtesting BO", clrBlack);
   MakeButton("BTN_CLOSE", x + w - 32, y + 5, 22, 20, "X");

   MakeButton("BTN_TAB_FORM", x + 10,  y + 34, 90, 22, "Input Form");
   MakeButton("BTN_TAB_ROWS", x + 105, y + 34, 95, 22, "Open Rows");

   MakeLabel("MODE",  x + 210, y + 37, w - 220, "Mode: NONE", clrDarkBlue);
   MakeLabel("STATUS",x + 10,  y + 60, w - 20, "Saved rows: 0", clrDimGray);
}

void CreateFormTab()
{
   int x = InpPanelX;
   int y = InpPanelY;

   int edit_x = x + 155;
   int edit_w = InpPanelWidth - 170;
   if(edit_w < 150)
      edit_w = 150;

   int by = y + 78;

   MakeButton("FORM_BTN_BO",       x + 10,  by, 64, 20, "B: BO");
   MakeButton("FORM_BTN_FT",       x + 78,  by, 64, 20, "F: FT");
   MakeButton("FORM_BTN_POINT",    x + 146, by, 74, 20, "P: Point");
   MakeButton("FORM_BTN_LEG",      x + 224, by, 78, 20, "L: Leg/PB");
   MakeButton("FORM_BTN_SWING",    x + 306, by, 82, 20, "S: Swing");

   by += 26;
   MakeButton("FORM_BTN_SAVE",     x + 10,  by, 98, 22, "Save Event");
   MakeButton("FORM_BTN_EXPORT",   x + 112, by, 98, 22, "Export CSV");
   MakeButton("FORM_BTN_NEW",      x + 214, by, 88, 22, "New File");
   MakeButton("FORM_BTN_CLEAR",    x + 306, by, 88, 22, "Clear Sel.");

   by += 30;
   MakeLabel("FORM_LBL_EXPORT", x + 10, by, 140, "Export name");
   MakeEdit("FORM_EDIT_EXPORT_NAME", edit_x, by - 3, edit_w, 20, g_export_name);

   by += 26;
   MakeLabel("FORM_LBL_WHAT", x + 10, by, 140, "Break out of what");
   MakeEdit("FORM_EDIT_BREAK_OUT_OF_WHAT", edit_x, by - 3, edit_w, 20, g_break_out_of_what);

   by += 26;
   MakeLabel("FORM_LBL_PATTERN", x + 10, by, 140, "Pattern");
   MakeEdit("FORM_EDIT_PATTERN", edit_x, by - 3, edit_w, 20, g_pattern);

   by += 26;
   MakeLabel("FORM_LBL_PB", x + 10, by, 140, "BO from pullback");
   MakeEdit("FORM_EDIT_FROM_PULLBACK", edit_x, by - 3, edit_w, 20, g_from_pullback);

   by += 26;
   MakeLabel("FORM_LBL_LEGCOUNT", x + 10, by, 140, "At what leg");
   MakeEdit("FORM_EDIT_AT_LEG", edit_x, by - 3, edit_w, 20, g_at_leg);

   by += 26;
   MakeLabel("FORM_LBL_HTF", x + 10, by, 140, "HTF location");
   MakeEdit("FORM_EDIT_HTF_LOCATION", edit_x, by - 3, edit_w, 20, g_htf_location);

   by += 26;
   MakeLabel("FORM_LBL_CONDITION", x + 10, by, 140, "Market condition");
   MakeEdit("FORM_EDIT_MARKET_CONDITION", edit_x, by - 3, edit_w, 20, g_market_condition);

   by += 26;
   MakeLabel("FORM_LBL_DIRECTION", x + 10, by, 140, "Market direction");
   MakeEdit("FORM_EDIT_MARKET_DIRECTION", edit_x, by - 3, edit_w, 20, g_market_direction);

   by += 26;
   MakeLabel("FORM_LBL_FTCOUNT", x + 10, by, 140, "# FT before first PB");
   MakeEdit("FORM_EDIT_FT_BEFORE_PB", edit_x, by - 3, edit_w, 20, g_ft_before_pb);

   by += 26;
   MakeLabel("FORM_LBL_SCREEN", x + 10, by, 140, "Screenshot path");
   MakeEdit("FORM_EDIT_SCREENSHOT", edit_x, by - 3, edit_w, 20, g_screenshot_path);

   by += 26;
   MakeLabel("FORM_LBL_NOTE", x + 10, by, 140, "Note");
   MakeEdit("FORM_EDIT_NOTE", edit_x, by - 3, edit_w, 42, g_note);

   by += 54;
   MakeLabel("FORM_HELP1", x + 10, by, InpPanelWidth - 20,
             "Click modes: B=BO, F=FT, P=breakout price, L=leg start/end/PB end, S=swing.", clrDimGray);
   by += 16;
   MakeLabel("FORM_HELP2", x + 10, by, InpPanelWidth - 20,
             "Open Rows shows a separate draggable table window with scrollbars.", clrDimGray);
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

//----------------------------- Rows floating window ----------------
void DeleteRowsWindowObjects()
{
   DeleteObjectsContaining("ROWSWIN_");
}

bool RowsWindowHit(const int px, const int py)
{
   if(!g_rows_window_visible)
      return false;

   return PointInRect(px, py, g_rows_window_x, g_rows_window_y,
                      InpRowsWindowWidth, InpRowsWindowHeight);
}

bool RowsWindowTitleHit(const int px, const int py)
{
   if(!g_rows_window_visible)
      return false;

   return PointInRect(px, py, g_rows_window_x, g_rows_window_y,
                      InpRowsWindowWidth - 42, 28);
}

bool RowsVThumbHit(const int px, const int py)
{
   return PointInRect(px, py, g_rows_vthumb_x, g_rows_vthumb_y,
                      g_rows_vthumb_w, g_rows_vthumb_h);
}

bool RowsHThumbHit(const int px, const int py)
{
   return PointInRect(px, py, g_rows_hthumb_x, g_rows_hthumb_y,
                      g_rows_hthumb_w, g_rows_hthumb_h);
}

bool RowsVTrackHit(const int px, const int py)
{
   return PointInRect(px, py, g_rows_vtrack_x, g_rows_vtrack_y,
                      g_rows_vtrack_w, g_rows_vtrack_h);
}

bool RowsHTrackHit(const int px, const int py)
{
   return PointInRect(px, py, g_rows_htrack_x, g_rows_htrack_y,
                      g_rows_htrack_w, g_rows_htrack_h);
}

string ShortCellText(const string text, const int cell_width)
{
   int max_chars = (cell_width - 8) / 7;
   if(max_chars < 4)
      max_chars = 4;

   if(StringLen(text) <= max_chars)
      return text;

   if(max_chars <= 3)
      return StringSubstr(text, 0, max_chars);

   return StringSubstr(text, 0, max_chars - 3) + "...";
}

void ClampRowsOffsets(const int visible_rows, const int visible_cols)
{
   int total_cols = 47;

   if(g_col_offset < 0)
      g_col_offset = 0;

   int max_col = MathMax(0, total_cols - visible_cols);
   if(g_col_offset > max_col)
      g_col_offset = max_col;

   if(g_row_offset < 0)
      g_row_offset = 0;

   int max_row = MathMax(0, g_saved_count - visible_rows);
   if(g_row_offset > max_row)
      g_row_offset = max_row;
}

int ThumbSize(const int track_size, const int visible_count, const int total_count)
{
   if(total_count <= 0 || visible_count >= total_count)
      return track_size;

   int size = (int)MathRound((double)track_size * (double)visible_count / (double)total_count);
   if(size < 22)
      size = 22;
   if(size > track_size)
      size = track_size;
   return size;
}

int ThumbPos(const int track_pos, const int track_size, const int thumb_size,
             const int offset, const int max_offset)
{
   if(max_offset <= 0 || track_size <= thumb_size)
      return track_pos;

   return track_pos + (int)MathRound((double)(track_size - thumb_size) * (double)offset / (double)max_offset);
}

int OffsetFromThumb(const int mouse_pos,
                    const int drag_offset,
                    const int track_pos,
                    const int track_size,
                    const int thumb_size,
                    const int max_offset)
{
   if(max_offset <= 0 || track_size <= thumb_size)
      return 0;

   int pos = mouse_pos - drag_offset;
   if(pos < track_pos)
      pos = track_pos;

   int max_pos = track_pos + track_size - thumb_size;
   if(pos > max_pos)
      pos = max_pos;

   return (int)MathRound((double)(pos - track_pos) * (double)max_offset / (double)(track_size - thumb_size));
}

void CreateRowsWindow()
{
   DeleteRowsWindowObjects();

   if(!g_rows_window_visible)
      return;

   int x = g_rows_window_x;
   int y = g_rows_window_y;
   int w = InpRowsWindowWidth;
   int h = InpRowsWindowHeight;

   if(w < 360)
      w = 360;
   if(h < 220)
      h = 220;

   MakeRect("ROWSWIN_BG", x, y, w, h, InpPanelBgColor, InpPanelBorderColor);
   MakeRect("ROWSWIN_TITLE_BG", x, y, w, 28, C'230,230,230', InpPanelBorderColor);

   MakeLabel("ROWSWIN_TITLE", x + 10, y + 7, w - 110, "Saved Rows Table", clrBlack);
   MakeButton("ROWSWIN_BTN_CLOSE", x + w - 32, y + 4, 22, 20, "X");

   MakeButton("ROWSWIN_BTN_EXPORT", x + 10,  y + 34, 100, 22, "Export CSV");
   MakeButton("ROWSWIN_BTN_NEW",    x + 115, y + 34, 90,  22, "New File");
   MakeLabel("ROWSWIN_COUNT",       x + 215, y + 38, w - 225,
             "Rows: " + IntegerToString(g_saved_count), clrBlack);

   int scroll_size = 15;
   int table_x = x + 10;
   int table_y = y + 64;
   int table_w = w - 20 - scroll_size;
   int table_h = h - 94 - scroll_size;

   if(table_w < 220)
      table_w = 220;
   if(table_h < 66)
      table_h = 66;

   int total_cols = 47;
   int visible_cols = InpRowsVisibleCols;
   if(visible_cols < 1)
      visible_cols = 1;
   if(visible_cols > total_cols)
      visible_cols = total_cols;

   int cell_h = 22;
   int visible_rows = table_h / cell_h - 1;
   if(visible_rows < 1)
      visible_rows = 1;

   g_rows_visible_rows = visible_rows;
   g_rows_visible_cols = visible_cols;

   ClampRowsOffsets(visible_rows, visible_cols);

   int col0_w = 42;
   int cell_w = (table_w - col0_w) / visible_cols;
   if(cell_w < 60)
      cell_w = 60;

   g_rows_table_x = table_x;
   g_rows_table_y = table_y;
   g_rows_table_w = table_w;
   g_rows_table_h = table_h;

   MakeCell("ROWSWIN_CELL_H0", table_x, table_y, col0_w, cell_h, "#", true);

   for(int c = 0; c < visible_cols; c++)
   {
      int col_idx = g_col_offset + c;
      if(col_idx >= total_cols)
         break;

      string header = FieldAtCsvIndex(HeaderRow(), col_idx);
      header = ShortCellText(header, cell_w);

      MakeCell("ROWSWIN_CELL_H" + IntegerToString(c + 1),
               table_x + col0_w + c * cell_w,
               table_y,
               cell_w,
               cell_h,
               header,
               true);
   }

   for(int r = 0; r < visible_rows; r++)
   {
      int row_idx = g_row_offset + r;
      if(row_idx >= g_saved_count)
         break;

      int yy = table_y + cell_h * (r + 1);

      MakeCell("ROWSWIN_CELL_R" + IntegerToString(r) + "_N",
               table_x,
               yy,
               col0_w,
               cell_h,
               IntegerToString(row_idx + 1),
               false);

      for(int c = 0; c < visible_cols; c++)
      {
         int col_idx = g_col_offset + c;
         if(col_idx >= total_cols)
            break;

         string value = FieldAtCsvIndex(g_rows[row_idx], col_idx);
         value = ShortCellText(value, cell_w);

         MakeCell("ROWSWIN_CELL_R" + IntegerToString(r) + "_C" + IntegerToString(c),
                  table_x + col0_w + c * cell_w,
                  yy,
                  cell_w,
                  cell_h,
                  value,
                  false);
      }
   }

   // Vertical scrollbar.
   g_rows_vtrack_x = table_x + table_w + 2;
   g_rows_vtrack_y = table_y;
   g_rows_vtrack_w = scroll_size - 2;
   g_rows_vtrack_h = table_h;

   int max_row = MathMax(0, g_saved_count - visible_rows);
   g_rows_vthumb_w = g_rows_vtrack_w;
   g_rows_vthumb_h = ThumbSize(g_rows_vtrack_h, visible_rows, MathMax(g_saved_count, visible_rows));
   g_rows_vthumb_x = g_rows_vtrack_x;
   g_rows_vthumb_y = ThumbPos(g_rows_vtrack_y, g_rows_vtrack_h, g_rows_vthumb_h, g_row_offset, max_row);

   MakeRect("ROWSWIN_VTRACK", g_rows_vtrack_x, g_rows_vtrack_y,
            g_rows_vtrack_w, g_rows_vtrack_h, C'245,245,245', clrSilver);
   MakeRect("ROWSWIN_VTHUMB", g_rows_vthumb_x, g_rows_vthumb_y,
            g_rows_vthumb_w, g_rows_vthumb_h, C'185,185,185', clrGray);

   // Horizontal scrollbar.
   g_rows_htrack_x = table_x + col0_w;
   g_rows_htrack_y = table_y + table_h + 2;
   g_rows_htrack_w = table_w - col0_w;
   g_rows_htrack_h = scroll_size - 2;

   int max_col = MathMax(0, total_cols - visible_cols);
   g_rows_hthumb_h = g_rows_htrack_h;
   g_rows_hthumb_w = ThumbSize(g_rows_htrack_w, visible_cols, total_cols);
   g_rows_hthumb_x = ThumbPos(g_rows_htrack_x, g_rows_htrack_w, g_rows_hthumb_w, g_col_offset, max_col);
   g_rows_hthumb_y = g_rows_htrack_y;

   MakeRect("ROWSWIN_HTRACK", g_rows_htrack_x, g_rows_htrack_y,
            g_rows_htrack_w, g_rows_htrack_h, C'245,245,245', clrSilver);
   MakeRect("ROWSWIN_HTHUMB", g_rows_hthumb_x, g_rows_hthumb_y,
            g_rows_hthumb_w, g_rows_hthumb_h, C'185,185,185', clrGray);

   MakeLabel("ROWSWIN_SCROLL_INFO",
             x + 10,
             y + h - 24,
             w - 20,
             "Mouse wheel: rows | Drag scrollbars: rows/columns | Arrow keys scroll | Drag title bar to move"
             + " | Row "
             + IntegerToString(g_saved_count == 0 ? 0 : g_row_offset + 1)
             + "/"
             + IntegerToString(g_saved_count)
             + " | Col "
             + IntegerToString(g_col_offset + 1)
             + "/"
             + IntegerToString(total_cols),
             clrDimGray);

   ChartRedraw(0);
}

void RebuildRowsWindow()
{
   if(g_rows_window_visible)
      CreateRowsWindow();
}

void OpenRowsWindow()
{
   SaveFormState();

   if(g_rows_window_x <= 0)
      g_rows_window_x = InpRowsWindowX;
   if(g_rows_window_y <= 0)
      g_rows_window_y = InpRowsWindowY;

   g_rows_window_visible = true;
   CreateRowsWindow();
}

void CloseRowsWindow()
{
   g_rows_window_visible = false;
   g_rows_drag_kind = ROWS_DRAG_NONE;
   DeleteRowsWindowObjects();
   ChartRedraw(0);
}

bool ClickInsideRowsWindow(const long &lparam, const double &dparam)
{
   int px = (int)lparam;
   int py = (int)dparam;
   return RowsWindowHit(px, py);
}

void ScrollRowsBy(const int row_delta, const int col_delta)
{
   g_row_offset += row_delta;
   g_col_offset += col_delta;
   ClampRowsOffsets(g_rows_visible_rows, g_rows_visible_cols);
   RebuildRowsWindow();
}

bool HandleRowsWindowClick(const long &lparam, const double &dparam)
{
   if(!g_rows_window_visible)
      return false;

   int px = (int)lparam;
   int py = (int)dparam;
   g_last_mouse_x = px;
   g_last_mouse_y = py;

   if(!RowsWindowHit(px, py))
      return false;

   int page_rows = MathMax(1, g_rows_visible_rows - 1);
   int page_cols = MathMax(1, g_rows_visible_cols - 1);

   if(RowsVTrackHit(px, py) && !RowsVThumbHit(px, py))
   {
      if(py < g_rows_vthumb_y)
         ScrollRowsBy(-page_rows, 0);
      else
         ScrollRowsBy(page_rows, 0);
      return true;
   }

   if(RowsHTrackHit(px, py) && !RowsHThumbHit(px, py))
   {
      if(px < g_rows_hthumb_x)
         ScrollRowsBy(0, -page_cols);
      else
         ScrollRowsBy(0, page_cols);
      return true;
   }

   return true;
}

bool HandleRowsWindowWheel(const long &lparam, const double &dparam, const string &sparam)
{
   if(!g_rows_window_visible)
      return false;

   if(!RowsWindowHit(g_last_mouse_x, g_last_mouse_y))
      return false;

   int delta = (int)dparam;
   if(delta == 0)
      return true;

   int flags = (int)StringToInteger(sparam);
   bool horizontal = ((flags & 4) != 0 || (flags & 8) != 0); // usually Shift or Ctrl

   if(horizontal)
   {
      if(delta > 0)
         ScrollRowsBy(0, -1);
      else
         ScrollRowsBy(0, 1);
   }
   else
   {
      int step = InpMouseWheelRowsStep;
      if(step < 1)
         step = 1;

      if(delta > 0)
         ScrollRowsBy(-step, 0);
      else
         ScrollRowsBy(step, 0);
   }

   return true;
}

bool HandleRowsWindowKey(const int key)
{
   if(!g_rows_window_visible)
      return false;

   if(key == KEY_UP)
   {
      ScrollRowsBy(-1, 0);
      return true;
   }
   if(key == KEY_DOWN)
   {
      ScrollRowsBy(1, 0);
      return true;
   }
   if(key == KEY_LEFT)
   {
      ScrollRowsBy(0, -1);
      return true;
   }
   if(key == KEY_RIGHT)
   {
      ScrollRowsBy(0, 1);
      return true;
   }
   if(key == KEY_PGUP)
   {
      ScrollRowsBy(-MathMax(1, g_rows_visible_rows - 1), 0);
      return true;
   }
   if(key == KEY_PGDN)
   {
      ScrollRowsBy(MathMax(1, g_rows_visible_rows - 1), 0);
      return true;
   }

   return false;
}

bool IsLeftButtonDown(const string state_text)
{
   int state = (int)StringToInteger(state_text);
   return ((state & 1) != 0);
}

bool HandleRowsWindowMouseMove(const long &lparam, const double &dparam, const string &sparam)
{
   int px = (int)lparam;
   int py = (int)dparam;
   g_last_mouse_x = px;
   g_last_mouse_y = py;

   if(!g_rows_window_visible)
      return false;

   bool left_down = IsLeftButtonDown(sparam);

   if(!left_down)
   {
      g_rows_drag_kind = ROWS_DRAG_NONE;
      return false;
   }

   if(g_rows_drag_kind == ROWS_DRAG_NONE)
   {
      if(RowsVThumbHit(px, py))
      {
         g_rows_drag_kind = ROWS_DRAG_VSCROLL;
         g_rows_drag_offset_y = py - g_rows_vthumb_y;
         return true;
      }
      if(RowsHThumbHit(px, py))
      {
         g_rows_drag_kind = ROWS_DRAG_HSCROLL;
         g_rows_drag_offset_x = px - g_rows_hthumb_x;
         return true;
      }
      if(RowsWindowTitleHit(px, py))
      {
         g_rows_drag_kind = ROWS_DRAG_WINDOW;
         g_rows_drag_offset_x = px - g_rows_window_x;
         g_rows_drag_offset_y = py - g_rows_window_y;
         return true;
      }

      return RowsWindowHit(px, py);
   }

   if(g_rows_drag_kind == ROWS_DRAG_WINDOW)
   {
      int new_x = px - g_rows_drag_offset_x;
      int new_y = py - g_rows_drag_offset_y;

      if(new_x < 0)
         new_x = 0;
      if(new_y < 0)
         new_y = 0;

      if(new_x != g_rows_window_x || new_y != g_rows_window_y)
      {
         g_rows_window_x = new_x;
         g_rows_window_y = new_y;
         RebuildRowsWindow();
      }
      return true;
   }

   if(g_rows_drag_kind == ROWS_DRAG_VSCROLL)
   {
      int max_row = MathMax(0, g_saved_count - g_rows_visible_rows);
      int new_offset = OffsetFromThumb(py, g_rows_drag_offset_y,
                                       g_rows_vtrack_y, g_rows_vtrack_h,
                                       g_rows_vthumb_h, max_row);
      if(new_offset != g_row_offset)
      {
         g_row_offset = new_offset;
         RebuildRowsWindow();
      }
      return true;
   }

   if(g_rows_drag_kind == ROWS_DRAG_HSCROLL)
   {
      int max_col = MathMax(0, 47 - g_rows_visible_cols);
      int new_offset = OffsetFromThumb(px, g_rows_drag_offset_x,
                                       g_rows_htrack_x, g_rows_htrack_w,
                                       g_rows_hthumb_w, max_col);
      if(new_offset != g_col_offset)
      {
         g_col_offset = new_offset;
         RebuildRowsWindow();
      }
      return true;
   }

   return false;
}

// Kept as a compatibility wrapper. Rows are now shown in a separate window.
void CreateRowsTab()
{
   OpenRowsWindow();
}

//----------------------------- Panel rebuild/status ----------------
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
   SetLabelText("ROWSWIN_COUNT", "Rows: " + IntegerToString(g_saved_count));
}

void RebuildPanel()
{
   SaveFormState();
   ClearDynamicPanelObjects();
   CreatePanelBase();
   CreateFormTab();
   UpdateModeLabel();
   ChartRedraw(0);
}

void CreatePanel()
{
   CreatePanelBase();
   CreateFormTab();
   UpdateModeLabel();
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
   SyncSelectionIndexesFromTimes();

   if(g_has_swing && g_swing_index >= 0)
      g_swing_period = CalculateSwingPeriod(g_swing_index);

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
   f[k++] = "1.3";

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
   if(g_rows_window_visible)
      RebuildRowsWindow();
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

bool ExportCsv()
{
   string filename = CurrentExportName();

   int flags = FILE_WRITE | FILE_TXT | FILE_ANSI;
   if(InpUseCommonFiles)
      flags |= FILE_COMMON;

   int handle = FileOpen(filename, flags);
   if(handle == INVALID_HANDLE)
   {
      Alert("Could not open export file: ", filename, " error: ", GetLastError());
      return false;
   }

   FileWriteString(handle, HeaderRow() + "\r\n");

   for(int i = 0; i < ArraySize(g_rows); i++)
      FileWriteString(handle, g_rows[i] + "\r\n");

   FileClose(handle);

   Alert("Exported ", ArraySize(g_rows), " rows to MQL5/Files/", filename);
   return true;
}

bool IsDigitsOnly(const string text)
{
   if(StringLen(text) <= 0)
      return false;

   for(int i = 0; i < StringLen(text); i++)
   {
      ushort ch = StringGetCharacter(text, i);
      if(ch < '0' || ch > '9')
         return false;
   }

   return true;
}

string WithoutCsvExtension(const string filename)
{
   int len = StringLen(filename);
   if(len >= 4 && StringSubstr(filename, len - 4) == ".csv")
      return StringSubstr(filename, 0, len - 4);

   return filename;
}

string NextExportName()
{
   string current = CurrentExportName();
   string base = WithoutCsvExtension(current);

   int last_underscore = -1;
   for(int i = StringLen(base) - 1; i >= 0; i--)
   {
      if(StringGetCharacter(base, i) == '_')
      {
         last_underscore = i;
         break;
      }
   }

   int start_number = 1;
   if(last_underscore > 0 && last_underscore < StringLen(base) - 1)
   {
      string suffix = StringSubstr(base, last_underscore + 1);
      if(IsDigitsOnly(suffix))
      {
         start_number = (int)StringToInteger(suffix) + 1;
         base = StringSubstr(base, 0, last_underscore);
      }
   }

   int common_flag = InpUseCommonFiles ? FILE_COMMON : 0;
   for(int n = start_number; n < start_number + 10000; n++)
   {
      string candidate = base + "_" + IntegerToString(n) + ".csv";
      if(candidate != current && !FileIsExist(candidate, common_flag))
         return candidate;
   }

   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);
   return base + "_" + StringFormat("%04d%02d%02d_%02d%02d%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec) + ".csv";
}

void ResetFormStateForNewFile(const string new_export_name)
{
   g_export_name = new_export_name;
   g_break_out_of_what = "";
   g_pattern = "";
   g_from_pullback = "";
   g_at_leg = "";
   g_htf_location = "";
   g_market_condition = "";
   g_market_direction = "";
   g_ft_before_pb = "";
   g_screenshot_path = "";
   g_note = "";

   if(ObjectFind(0, Obj("FORM_EDIT_EXPORT_NAME")) >= 0)
      ObjectSetString(0, Obj("FORM_EDIT_EXPORT_NAME"), OBJPROP_TEXT, g_export_name);
   if(ObjectFind(0, Obj("FORM_EDIT_BREAK_OUT_OF_WHAT")) >= 0)
      ObjectSetString(0, Obj("FORM_EDIT_BREAK_OUT_OF_WHAT"), OBJPROP_TEXT, g_break_out_of_what);
   if(ObjectFind(0, Obj("FORM_EDIT_PATTERN")) >= 0)
      ObjectSetString(0, Obj("FORM_EDIT_PATTERN"), OBJPROP_TEXT, g_pattern);
   if(ObjectFind(0, Obj("FORM_EDIT_FROM_PULLBACK")) >= 0)
      ObjectSetString(0, Obj("FORM_EDIT_FROM_PULLBACK"), OBJPROP_TEXT, g_from_pullback);
   if(ObjectFind(0, Obj("FORM_EDIT_AT_LEG")) >= 0)
      ObjectSetString(0, Obj("FORM_EDIT_AT_LEG"), OBJPROP_TEXT, g_at_leg);
   if(ObjectFind(0, Obj("FORM_EDIT_HTF_LOCATION")) >= 0)
      ObjectSetString(0, Obj("FORM_EDIT_HTF_LOCATION"), OBJPROP_TEXT, g_htf_location);
   if(ObjectFind(0, Obj("FORM_EDIT_MARKET_CONDITION")) >= 0)
      ObjectSetString(0, Obj("FORM_EDIT_MARKET_CONDITION"), OBJPROP_TEXT, g_market_condition);
   if(ObjectFind(0, Obj("FORM_EDIT_MARKET_DIRECTION")) >= 0)
      ObjectSetString(0, Obj("FORM_EDIT_MARKET_DIRECTION"), OBJPROP_TEXT, g_market_direction);
   if(ObjectFind(0, Obj("FORM_EDIT_FT_BEFORE_PB")) >= 0)
      ObjectSetString(0, Obj("FORM_EDIT_FT_BEFORE_PB"), OBJPROP_TEXT, g_ft_before_pb);
   if(ObjectFind(0, Obj("FORM_EDIT_SCREENSHOT")) >= 0)
      ObjectSetString(0, Obj("FORM_EDIT_SCREENSHOT"), OBJPROP_TEXT, g_screenshot_path);
   if(ObjectFind(0, Obj("FORM_EDIT_NOTE")) >= 0)
      ObjectSetString(0, Obj("FORM_EDIT_NOTE"), OBJPROP_TEXT, g_note);
}

void NewFile()
{
   string current_filename = CurrentExportName();
   string next_filename = NextExportName();
   bool exported_old_file = false;

   if(g_saved_count > 0)
   {
      if(!ExportCsv())
         return;

      exported_old_file = true;
   }

   ArrayResize(g_rows, 0);
   g_saved_count = 0;
   g_row_offset = 0;
   g_col_offset = 0;

   ClearSelections();
   ResetFormStateForNewFile(next_filename);
   RebuildPanel();

   if(g_rows_window_visible)
      RebuildRowsWindow();

   if(exported_old_file)
      Alert("Exported ", current_filename, " and started a new empty CSV file: ", g_export_name);
   else
      Alert("Started a new empty CSV file: ", g_export_name);
}

void CloseIndicatorFromButton()
{
   ChartIndicatorDelete(0, 0, "Backtesting BO");
}

//----------------------------- Events ------------------------------
void HandleObjectClick(const string obj_name)
{
   g_ignore_next_chart_click = true;
   ResetButtonState(obj_name);
   SetChartMouseScrollState(false);

   if(obj_name == Obj("BTN_CLOSE"))
      CloseIndicatorFromButton();

   else if(obj_name == Obj("BTN_TAB_FORM"))
   {
      g_tab = TAB_FORM;
      RebuildPanel();
   }

   else if(obj_name == Obj("BTN_TAB_ROWS"))
      OpenRowsWindow();

   else if(obj_name == Obj("ROWSWIN_BTN_CLOSE"))
      CloseRowsWindow();

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

   else if(obj_name == Obj("FORM_BTN_EXPORT") || obj_name == Obj("ROWSWIN_BTN_EXPORT"))
      ExportCsv();

   else if(obj_name == Obj("FORM_BTN_NEW") || obj_name == Obj("ROWSWIN_BTN_NEW"))
      NewFile();

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

   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      bool left_down = IsLeftButtonDown(sparam);
      UpdateChartMouseScrollProtection((int)lparam, (int)dparam, left_down);

      if(HandleRowsWindowMouseMove(lparam, dparam, sparam))
         return;
   }

   if(id == CHARTEVENT_MOUSE_WHEEL)
   {
      if(HandleRowsWindowWheel(lparam, dparam, sparam))
         return;
   }

   if(id == CHARTEVENT_KEYDOWN)
   {
      if(HandleRowsWindowKey((int)lparam))
         return;

      HandleKey((int)lparam);
      return;
   }

   if(id == CHARTEVENT_CLICK)
   {
      g_last_mouse_x = (int)lparam;
      g_last_mouse_y = (int)dparam;
      UpdateChartMouseScrollProtection(g_last_mouse_x, g_last_mouse_y, false);

      if(g_ignore_next_chart_click)
      {
         g_ignore_next_chart_click = false;
         return;
      }

      if(HandleRowsWindowClick(lparam, dparam))
         return;

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
void OnTimer()
{
   if(InpShowPanel || g_rows_window_visible)
      ChartRedraw(0);
}

int OnInit()
{
   PREFIX = "BTBO_" + _Symbol + "_" + IntegerToString((int)_Period) + "_";
   g_export_name = InpDefaultExportName;
   g_rows_window_x = InpRowsWindowX;
   g_rows_window_y = InpRowsWindowY;
   g_chart_mouse_scroll_initial = (bool)ChartGetInteger(0, CHART_MOUSE_SCROLL);
   g_chart_mouse_scroll_current = g_chart_mouse_scroll_initial;

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
   ChartSetInteger(0, CHART_EVENT_MOUSE_WHEEL, true);
   
   EventSetTimer(1);
   
   CreatePanel();
   UpdateModeLabel();
   ChartRedraw(0);
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
   if(ema20_handle != INVALID_HANDLE)
      IndicatorRelease(ema20_handle);
   if(ema60_handle != INVALID_HANDLE)
      IndicatorRelease(ema60_handle);

   ChartSetInteger(0, CHART_MOUSE_SCROLL, g_chart_mouse_scroll_initial);
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
      int bo_shift = ShiftFromTime(g_bo_time);
      g_bo_index = bo_shift;

      int idx = rates_total - 1 - bo_shift;
      if(bo_shift >= 0 && idx >= 0 && idx < rates_total)
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
      int ft_shift = ShiftFromTime(g_ft_time);
      g_ft_index = ft_shift;

      int idx = rates_total - 1 - ft_shift;
      if(ft_shift >= 0 && idx >= 0 && idx < rates_total)
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
