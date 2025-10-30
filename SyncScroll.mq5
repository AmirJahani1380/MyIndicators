//+------------------------------------------------------------------+
//|                                       SyncScroll.mq5    |
//|   Sync charts of the SAME symbol by the time of the RIGHT edge   |
//|   (e.g., M5/M15/H1). No auto-snap to latest candle.              |
//+------------------------------------------------------------------+
#property copyright   "AJ"
#property version     "1.2"
#property description "Synchronize charts (same symbol) by the time of the right-most visible candle."
#property indicator_chart_window
#property strict

// ---- Inputs
input bool IncludeAllSymbols = false; // If true, sync all symbols; else only same symbol

// ---- State
bool      g_syncInProgress  = false;  // re-entrancy guard (prevents ping-pong)
datetime  g_lastRightTime   = 0;      // change detection to keep scrolling smooth

// ---- Helpers
long FirstVisibleBarOnChart(const long chart_id)
{
   return ChartGetInteger(chart_id, CHART_FIRST_VISIBLE_BAR, 0);
}
long VisibleBarsOnChart(const long chart_id)
{
   return ChartGetInteger(chart_id, CHART_VISIBLE_BARS, 0);
}
// Compute the index of the right-most visible bar on chart_id
long RightVisibleBarIndex(const long chart_id)
{
   const long first = FirstVisibleBarOnChart(chart_id);
   const long vis   = VisibleBarsOnChart(chart_id);
   long right_idx   = first - (vis - 1);
   if(right_idx < 0) right_idx = 0;
   return right_idx;
}
// Move destination so that its RIGHT edge is at dst_right_index
void MoveChartRightEdgeToIndex(const long dst_chart, const long dst_right_index)
{
   // We'll align by setting the FIRST visible bar so that right edge equals dst_right_index:
   // target_first = dst_right_index + (visible_bars - 1)
   ChartSetInteger(dst_chart, CHART_AUTOSCROLL, false);

   const long vis_dst     = VisibleBarsOnChart(dst_chart);
   if(vis_dst <= 0) return;

   const long target_first = dst_right_index + (vis_dst - 1);
   const long cur_first    = FirstVisibleBarOnChart(dst_chart);
   if(cur_first == target_first) return;

   const long delta = cur_first - target_first; // relative shift
   ChartNavigate(dst_chart, CHART_CURRENT_POS, (int)delta);
   ChartRedraw();
}

void SyncPeersRightEdgeByTime(const long src_chart,
                              const string src_symbol,
                              const datetime right_time)
{
   for(long ch = ChartFirst(); ch != -1; ch = ChartNext(ch))
   {
      if(ch == src_chart) continue;

      const string sym = ChartSymbol(ch);
      if(!IncludeAllSymbols && sym != src_symbol) continue;

      const ENUM_TIMEFRAMES dst_tf = (ENUM_TIMEFRAMES)ChartPeriod(ch);

      // Map the right-edge TIME to a bar index on the destination chart
      int dst_right_index = iBarShift(sym, dst_tf, right_time, /*exact=*/false);
      if(dst_right_index < 0) continue; // no data yet

      MoveChartRightEdgeToIndex(ch, (long)dst_right_index);
   }
}

// ---- Indicator lifecycle
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "SyncRightEdgeByTime");
   return(INIT_SUCCEEDED);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const int begin,
                const double &price[])
{
   // No buffers; event-driven.
   return(rates_total);
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id != CHARTEVENT_CHART_CHANGE) return;      // scroll/zoom/resize/etc.
   if(g_syncInProgress) return;

   const long   src_chart = ChartID();
   const string sym       = Symbol();
   const ENUM_TIMEFRAMES src_tf = (ENUM_TIMEFRAMES)Period();

   // Determine the RIGHT-edge bar/time on the source chart
   const long right_idx = RightVisibleBarIndex(src_chart);
   const datetime right_time = iTime(sym, src_tf, (int)right_idx);
   if(right_time == 0) return;

   // Only act if the right-edge time actually changed (keeps motion smooth)
   if(right_time == g_lastRightTime) return;
   g_lastRightTime = right_time;

   g_syncInProgress = true;
   SyncPeersRightEdgeByTime(src_chart, sym, right_time);
   g_syncInProgress = false;
}
