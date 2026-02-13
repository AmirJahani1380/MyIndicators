
#include "AZ_State.mqh"
#include "AZ_Core.mqh"
#include "AZ_Zones.mqh"
#include "AZ_Trendlines.mqh"

//------------------------- Drawing (filled rectangle) ----------------
bool ShouldDrawStatus(ZoneStatus st)
{
   if(st == Potential)  return InpShowPotential;
   if(st == Confirmed)  return InpShowConfirmed;
   return InpShowEliminated;
}

color ZoneColorFor(const Zone &z)
{
   if(z.status == Eliminated) return InpEliminatedColor;
   if(z.status == Confirmed)  return InpConfirmedColor;
   return (z.type == Demand ? InpPotentialDemandColor : InpPotentialSupplyColor);
}

int ZoneWidthFor(const Zone &z)
{
   if(z.status == Confirmed)  return InpWidthConfirmed;
   if(z.status == Eliminated) return InpWidthEliminated;
   return InpWidthPotential;
}

bool DrawZone(const Zone &z)
{
   if(!ShouldDrawStatus(z.status))
   {
      DeleteObjectExact(z.name);
      return true;
   }

   const long chart_id = 0;

   double top = MathMax(z.proximal, z.distal);
   double bot = MathMin(z.proximal, z.distal);
   if(MathAbs(top - bot) < (_Point * 2.0))
      top = bot + (_Point * 10.0);

   datetime t1 = z.tStart;
   datetime t2 = z.tEnd;
   if(t2 <= t1)
      t2 = t1 + (datetime)PeriodSeconds(_Period);

   if(ObjectFind(chart_id, z.name) < 0)
   {
      if(!ObjectCreate(chart_id, z.name, OBJ_RECTANGLE, 0, t1, top, t2, bot))
      {
         if(InpDebug) PrintFormat("ObjectCreate failed '%s' err=%d", z.name, GetLastError());
         return false;
      }
   }
   else
   {
      ObjectMove(chart_id, z.name, 0, t1, top);
      ObjectMove(chart_id, z.name, 1, t2, bot);
   }

   color c = ZoneColorFor(z);
   int w = ZoneWidthFor(z);

   ObjectSetInteger(chart_id, z.name, OBJPROP_COLOR, (long)c);
   ObjectSetInteger(chart_id, z.name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(chart_id, z.name, OBJPROP_WIDTH, w);
   ObjectSetInteger(chart_id, z.name, OBJPROP_FILL, true);
   ObjectSetInteger(chart_id, z.name, OBJPROP_BACK, true);

   string desc =
      z.tag + " | " +
      (z.type==Demand ? "Demand" : "Supply") + " | " +
      (z.status==Potential ? "Potential" : (z.status==Confirmed ? "Confirmed" : "Eliminated")) +
      " | base: " + TimeToString(z.tStart, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +
      " -> "      + TimeToString(z.tBaseEnd, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +
      " | legOut: " + TimeToString(z.tLegOut, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +
      " | end: "  + TimeToString(z.tEnd, TIME_DATE|TIME_MINUTES|TIME_SECONDS);

   if(z.status != Potential)
   {
      string r = (z.confirmReason == "" ? "UNKNOWN" : z.confirmReason);
      desc += " | confirmedBy: " + r;
      if(z.tConfirmed > 0)
         desc += " @ " + TimeToString(z.tConfirmed, TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   }

   ObjectSetString(chart_id, z.name, OBJPROP_TOOLTIP, desc);
   return true;
}

//------------------------- Reset helpers -----------------------------
void AZ_ResetRuntimeState(AZState &st)
{
   ArrayResize(st.zonesActive, 0);
   ArrayResize(st.zonesDead, 0);

   st.lastClosedTime = 0;
   st.high_lastBreak = 0;
   st.low_lastBreak  = 0;

   st.high_sig_t1 = st.high_sig_t2 = 0;
   st.low_sig_t1  = st.low_sig_t2  = 0;
   st.high_sig_broken = false;
   st.low_sig_broken  = false;
}

//------------------------- Full reset state + objects ----------------
void ResetAllState(AZState &st)
{
   DeleteObjectsByPrefix(MakeZonePrefix());
   DeleteObjectsByPrefix(MakeBrokenTLPfx());
   DeleteAllLines();

   AZ_ResetRuntimeState(st);
}

//------------------------- Historical rebuild ------------------------
void RebuildFromHistory(AZState &st,
                        const int rates_total,
                        const datetime &time[],
                        const double &open[],
                        const double &high[],
                        const double &low[],
                        const double &close[],
                        const bool series,
                        const int winOldest,
                        const int winNewest)
{
   ResetAllState(st);

   int iClsArr = IndexLastClosedBar(time, rates_total);
   int ns_winOldest = MapArr2NS(winOldest, rates_total, series);
   int ns_iCls      = MapArr2NS(iClsArr,  rates_total, series);

   int created = 0;

   int warmup = MathMax(2*SwingPeriod + 2, InpAvgRangeLen + 2);
   int ns_start = MathMax(ns_winOldest, warmup);

   for(int ns = ns_start; ns <= ns_iCls; ++ns)
   {
      int iCls = MapNS2Arr(ns, rates_total, series);
      int iCur = iCls;

      if(created < InpMaxZonesProcess)
      {
         Zone z;
         if(BuildZoneFromLegOut(time, open, high, low, close,
                                iCls, iCls, iCur, series, winOldest, winNewest,
                                z))
         {
            if(FindZoneByName(z.name, st.zonesActive) < 0 &&
               FindZoneByName(z.name, st.zonesDead)   < 0)
            {
               int n = ArraySize(st.zonesActive);
               ArrayResize(st.zonesActive, n + 1);
               st.zonesActive[n] = z;
               created++;
            }
         }
      }

      ProcessZonesOnClose(st, time, high, low, iCls, iCur, series);

      TLInfo tlHigh, tlLow;
      ComputeTrendlineAt(st, time, high, low, rates_total, series, ns, true,  tlHigh);
      ComputeTrendlineAt(st, time, high, low, rates_total, series, ns, false, tlLow);

      if(!OnlySwingLow)
         CheckAndProcessTLBreakUpToBar(st, true, tlHigh, time, high, low, rates_total, iCls, series, st.high_lastBreak);

      if(!OnlySwingHigh)
         CheckAndProcessTLBreakUpToBar(st, false, tlLow, time, high, low, rates_total, iCls, series, st.low_lastBreak);
   }

   st.lastClosedTime = time[iClsArr];

   for(int i=0; i<ArraySize(st.zonesActive); ++i) DrawZone(st.zonesActive[i]);
   for(int i=0; i<ArraySize(st.zonesDead);   ++i) DrawZone(st.zonesDead[i]);

   DrawCurrentTrendlines(st, time, high, low, rates_total, series, iClsArr);
}
