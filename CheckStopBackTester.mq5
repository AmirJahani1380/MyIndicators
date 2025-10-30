//+------------------------------------------------------------------+
//|                                           CheckStopBackTester.mq5|
//+------------------------------------------------------------------+
#property version   "1.05"
#property indicator_chart_window

//---- user-editable dummy RR value
input double InpRR = 1.00;     // Risk/Reward (dummy, editable in Inputs)

//---- panel look & feel
input int    InpPanelX   = 6;     // X distance from corner (px)
input int    InpPanelY   = 15;    // Y distance from corner (px)
input int    InpPanelW   = 180;   // Panel width (px)
input color  InpBgColor  = clrAliceBlue;
input color  InpTextColor= clrBlack;
input int    InpFontSize = 9;
input string InpFontName = "Tahoma";
input int    InpLinePad  = 6;     // vertical padding per line (px)
input int    InpSidePad  = 8;     // left/right text padding inside panel (px)

//---- naming prefix (deterministic)
string CSBT_PREFIX = "CSBT_";

//---- object names (per run)
string PANEL_BG;
string L1,L2,L3,L4,L5,L6,L7;

//------------------------------------------------------------------//
// Cleanup helpers

void CleanupCsbtObjects()
{
   // Walk backwards because indices shift when deleting
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; --i)
   {
      string name = ObjectName(0, i, -1, -1);
      if(name != "" && StringFind(name, CSBT_PREFIX, 0) == 0)
         ObjectDelete(0, name);
   }
}

string MakeName(const string suffix)
{
   // Include ChartID to avoid cross-chart collisions
   return(CSBT_PREFIX + IntegerToString((long)ChartID()) + "_" + suffix);
}

//------------------------------------------------------------------//
// UI helpers

bool EnsureRectBG(const int panel_h)
{
   if(ObjectFind(0, PANEL_BG) < 0)
   {
      if(!ObjectCreate(0, PANEL_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return(false);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_SELECTED,  false);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_HIDDEN,    true); // hidden objects
      ObjectSetInteger(0, PANEL_BG, OBJPROP_BACK,      true);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_ZORDER,    0);
      ObjectSetInteger(0, PANEL_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   }
   ObjectSetInteger(0, PANEL_BG, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_YDISTANCE, InpPanelY);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_XSIZE,     InpPanelW);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_YSIZE,     panel_h);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_BGCOLOR,   InpBgColor);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_COLOR,     InpBgColor);
   return(true);
}

bool EnsureLineLabel(const string &name,const int y_off,const string &text)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return(false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,  false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);  // hidden objects
      ObjectSetInteger(0, name, OBJPROP_ZORDER,    1);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,    ANCHOR_LEFT_UPPER);
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  InpPanelX + InpSidePad);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  InpPanelY + y_off);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      InpTextColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   InpFontSize);
   ObjectSetString (0, name, OBJPROP_FONT,       InpFontName);
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
   return(true);
}

int CountObjectsOfType(const ENUM_OBJECT type)
{
   return(ObjectsTotal(0, 0, (int)type));
}

// Find earliest and latest time among check/stop signs
bool GetSignsRange(datetime &t_first, datetime &t_last)
{
   bool found=false; t_first=0; t_last=0;
   const ENUM_OBJECT types[2]={OBJ_ARROW_CHECK, OBJ_ARROW_STOP};

   for(int ti=0; ti<2; ++ti)
   {
      const int cnt = ObjectsTotal(0, 0, (int)types[ti]);
      for(int i=0;i<cnt;i++)
      {
         string name = ObjectName(0, i, 0, (int)types[ti]);
         if(name=="") continue;
         datetime t = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
         if(!found){ t_first=t_last=t; found=true; }
         else{ if(t<t_first) t_first=t; if(t>t_last) t_last=t; }
      }
   }
   return(found);
}

string FormatYMD(datetime t)
{
   MqlDateTime dt; TimeToStruct(t, dt);
   return(StringFormat("%04d,%02d,%02d", dt.year, dt.mon, dt.day));
}

int InclusiveDays(datetime t_start, datetime t_end)
{
   MqlDateTime ds, de;
   TimeToStruct(t_start, ds); ds.hour=0; ds.min=0; ds.sec=0;
   TimeToStruct(t_end,   de); de.hour=0; de.min=0; de.sec=0;
   datetime d0 = StructToTime(ds);
   datetime d1 = StructToTime(de);
   int days = (int)((d1 - d0)/86400) + 1;
   if(days<1) days=1;
   return(days);
}

void RefreshStatsPanel()
{
   const int wins   = CountObjectsOfType(OBJ_ARROW_CHECK);
   const int losses = CountObjectsOfType(OBJ_ARROW_STOP);
   const int total  = wins + losses;
   const double winrate = (total>0) ? (double)wins/(double)total : 0.0;

   // Date range & avg/day
   datetime t0, t1;
   bool have_range = GetSignsRange(t0, t1);
   // Requested date-line format:
   string date_line = have_range ? (FormatYMD(t0) + " - " + FormatYMD(t1)) : "date: -";
   double avg_per_day = 0.0;
   if(have_range && total>0)
   {
      int days = InclusiveDays(t0, t1);
      avg_per_day = (days>0) ? ((double)total / (double)days) : 0.0;
   }

   // Layout metrics (7 lines)
   const int lines = 7;
   const int line_h = InpFontSize + InpLinePad;
   const int top_pad = InpLinePad;
   const int panel_h = top_pad + lines*line_h + InpLinePad;

   EnsureRectBG(panel_h);

   int y = top_pad;
   EnsureLineLabel(L1, y, StringFormat("winrate: %.2f", winrate)); y += line_h;
   EnsureLineLabel(L2, y, StringFormat("wins: %d", wins));         y += line_h;
   EnsureLineLabel(L3, y, StringFormat("losses: %d", losses));     y += line_h;
   EnsureLineLabel(L4, y, StringFormat("total: %d", total));       y += line_h;
   EnsureLineLabel(L5, y, StringFormat("RR: %.2f", InpRR));        y += line_h;
   EnsureLineLabel(L6, y, date_line);    y += line_h;
   EnsureLineLabel(L7, y, StringFormat("avg/day: %.2f", avg_per_day));
}

//------------------------------------------------------------------//
// Lifecycle

int OnInit()
{
   // Clean up any leftover CSBT_* objects from previous runs/sessions
   CleanupCsbtObjects();

   // Per-run names (deterministic with ChartID)
   PANEL_BG = MakeName("BG");
   L1 = MakeName("L1"); L2 = MakeName("L2"); L3 = MakeName("L3");
   L4 = MakeName("L4"); L5 = MakeName("L5"); L6 = MakeName("L6"); L7 = MakeName("L7");

   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, 1);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, 1);

   EventSetMillisecondTimer(500);

   RefreshStatsPanel();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   // Thorough cleanup (covers indicator removal, template/profile change, chart close, etc.)
   CleanupCsbtObjects();
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const int begin,
                const double &price[])
{
   RefreshStatsPanel();
   return(rates_total);
}

void OnTimer()
{
   RefreshStatsPanel();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_CREATE ||
      id==CHARTEVENT_OBJECT_DELETE ||
      id==CHARTEVENT_OBJECT_CHANGE ||
      id==CHARTEVENT_OBJECT_DRAG)
   {
      RefreshStatsPanel();
   }

   // Clean on chart change and immediately rebuild
   if(id==CHARTEVENT_CHART_CHANGE)
   {
      CleanupCsbtObjects();
      RefreshStatsPanel();
   }
}
