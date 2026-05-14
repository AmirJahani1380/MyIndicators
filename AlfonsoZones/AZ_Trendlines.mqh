
#include "AZ_State.mqh"
#include "AZ_Core.mqh"
#include "AZ_Zones.mqh"

//------------------------- Trendline names/drawing -------------------
string TFToStr(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:   return "M1";
      case PERIOD_M2:   return "M2";
      case PERIOD_M3:   return "M3";
      case PERIOD_M4:   return "M4";
      case PERIOD_M5:   return "M5";
      case PERIOD_M6:   return "M6";
      case PERIOD_M10:  return "M10";
      case PERIOD_M12:  return "M12";
      case PERIOD_M15:  return "M15";
      case PERIOD_M20:  return "M20";
      case PERIOD_M30:  return "M30";
      case PERIOD_H1:   return "H1";
      case PERIOD_H2:   return "H2";
      case PERIOD_H3:   return "H3";
      case PERIOD_H4:   return "H4";
      case PERIOD_H6:   return "H6";
      case PERIOD_H8:   return "H8";
      case PERIOD_H12:  return "H12";
      case PERIOD_D1:   return "D1";
      case PERIOD_W1:   return "W1";
      case PERIOD_MN1:  return "MN1";
      default:          return "TF"+(string)PeriodSeconds(tf);
   }
}

string ObjName(bool isHigh)
{
   return StringFormat("SwingTL_%s_%s_P%d_%s",
                       _Symbol,
                       TFToStr((ENUM_TIMEFRAMES)_Period),
                       SwingPeriod,
                       isHigh ? "HIGH" : "LOW");
}

void DeleteAllLines()
{
   ObjectDelete(0, ObjName(true));
   ObjectDelete(0, ObjName(false));
}

bool IsSwingHigh_NS(const double &h[], int i, int p, int rates_total, bool seriesArrays)
{
   if(i-p < 0 || i+p >= rates_total) return(false);
   int ai = MapNS2Arr(i, rates_total, seriesArrays);
   for(int k=1; k<=p; ++k)
   {
      int aim = MapNS2Arr(i-k, rates_total, seriesArrays);
      int aip = MapNS2Arr(i+k, rates_total, seriesArrays);
      if(!(h[ai] > h[aim] && h[ai] > h[aip])) return(false);
   }
   return(true);
}

bool IsSwingLow_NS(const double &l[], int i, int p, int rates_total, bool seriesArrays)
{
   if(i-p < 0 || i+p >= rates_total) return(false);
   int ai = MapNS2Arr(i, rates_total, seriesArrays);
   for(int k=1; k<=p; ++k)
   {
      int aim = MapNS2Arr(i-k, rates_total, seriesArrays);
      int aip = MapNS2Arr(i+k, rates_total, seriesArrays);
      if(!(l[ai] < l[aim] && l[ai] < l[aip])) return(false);
   }
   return(true);
}

void ConsiderPoint(int i, double price,
                   int &idx_newest, double &px_newest,
                   int &idx_second, double &px_second)
{
   if(idx_newest < 0 || i > idx_newest)
   {
      idx_second = idx_newest; px_second = px_newest;
      idx_newest = i;          px_newest = price;
   }
   else if(idx_second < 0 || i > idx_second)
   {
      idx_second = i;          px_second = price;
   }
}

bool GetATRAtArrIndex(AZState &st, const int arrIndex, double &atrVal)
{
   atrVal = 0.0;
   if(st.atrHandle == INVALID_HANDLE) return false;
   double buf[];
   if(CopyBuffer(st.atrHandle, 0, arrIndex, 1, buf) != 1) return false;
   atrVal = buf[0];
   return (atrVal > 0.0);
}

bool AnglePass_ByATR(double older_px, double newer_px, int bars, double atr_val)
{
   if(!AngleBased) return true;
   if(bars <= 0) return false;
   if(atr_val <= 0.0) return false;
   double angle = (MathAbs(newer_px - older_px) / atr_val) / bars;
   return(angle >= MinAngle && angle <= MaxAngle);
}

// BOS helpers
double MaxHighBetweenNS(const double &h[], int ns_a, int ns_b, int rates_total, bool seriesArrays)
{
   int lo = MathMin(ns_a, ns_b);
   int hi = MathMax(ns_a, ns_b);
   double mx = -DBL_MAX;
   for(int i=lo; i<=hi; ++i)
   {
      int ai = MapNS2Arr(i, rates_total, seriesArrays);
      mx = MathMax(mx, h[ai]);
   }
   return mx;
}

double MinLowBetweenNS(const double &l[], int ns_a, int ns_b, int rates_total, bool seriesArrays)
{
   int lo = MathMin(ns_a, ns_b);
   int hi = MathMax(ns_a, ns_b);
   double mn = DBL_MAX;
   for(int i=lo; i<=hi; ++i)
   {
      int ai = MapNS2Arr(i, rates_total, seriesArrays);
      mn = MathMin(mn, l[ai]);
   }
   return mn;
}

int FindNextSwingAfter_NS(const bool wantHighSwing,
                          const double &h[], const double &l[],
                          int start_ns, int end_ns, int p,
                          int rates_total, bool seriesArrays)
{
   for(int i=start_ns; i<=end_ns; ++i)
   {
      bool ok = wantHighSwing ? IsSwingHigh_NS(h, i, p, rates_total, seriesArrays)
                              : IsSwingLow_NS (l, i, p, rates_total, seriesArrays);
      if(ok) return i;
   }
   return -1;
}

bool ExistsBreakBefore_NS(const bool breakAbove,
                          const double &h[], const double &l[],
                          double level,
                          int from_ns, int to_ns,
                          int rates_total, bool seriesArrays)
{
   double eps = _Point * 0.5;
   if(to_ns < from_ns) return false;
   for(int i=from_ns; i<=to_ns; ++i)
   {
      int ai = MapNS2Arr(i, rates_total, seriesArrays);
      if(breakAbove)
      {
         if(h[ai] > level + eps) return true;
      }
      else
      {
         if(l[ai] < level - eps) return true;
      }
   }
   return false;
}

int FindFirstBOSBreak_NS(const bool breakAbove,
                         const double &h[], const double &l[],
                         const double level,
                         const int ns_from, const int ns_to,
                         const int rates_total, const bool seriesArrays)
{
   if(ns_to < ns_from) return -1;

   const double eps = _Point * 0.5;

   for(int ns = ns_from; ns <= ns_to; ++ns)
   {
      int ai = MapNS2Arr(ns, rates_total, seriesArrays);
      if(breakAbove)
      {
         if(h[ai] > level + eps) return ns;   // first BOS candle (NS index)
      }
      else
      {
         if(l[ai] < level - eps) return ns;   // first BOS candle (NS index)
      }
   }
   return -1;
}

// Option A: "broken" means FULL candle break (same as TL break logic)
// Demand TL (lows): broken if a candle is FULLY BELOW line  => FullOHLC_BelowLine (uses high[])
// Supply TL (highs): broken if a candle is FULLY ABOVE line => FullOHLC_AboveLine (uses low[])
bool TrendlineBrokenBeforeBOS(const bool isHighTL,
                              const datetime &time[],
                              const double &high[],
                              const double &low[],
                              const int rates_total, const bool seriesArrays,
                              const int ns1, const double p1, const int ns2, const double p2,
                              const int ns_from, const int ns_to_inclusive)
{
   if(ns_to_inclusive < ns_from) return false;

   for(int ns = ns_from; ns <= ns_to_inclusive; ++ns)
   {
      int ai = MapNS2Arr(ns, rates_total, seriesArrays);

      if(!isHighTL)
      {
         // Demand TL broken DOWN
         if(FullOHLC_BelowLine(time, high, ai, ns1, p1, ns2, p2))
            return true;
      }
      else
      {
         // Supply TL broken UP
         if(FullOHLC_AboveLine(time, low, ai, ns1, p1, ns2, p2))
            return true;
      }
   }
   return false;
}


void ComputeTrendlineAt(AZState &st,
                        const datetime &t[],
                        const double &h[],
                        const double &l[],
                        const int rates_total,
                        const bool seriesArrays,
                        const int ns_end,
                        const bool isHigh,
                        TLInfo &out)
{
   out.has = false;
   out.t1 = out.t2 = 0;
   out.p1 = out.p2 = 0.0;
   out.ns1 = -1;
   out.ns2 = -1;
   out.swing_ns = -1;
   out.swingTime = 0;
   out.idx_old_arr = -1;
   out.idx_new_arr = -1;

   const int p = MathMax(1, SwingPeriod);
   if(rates_total < (2*p + 1)) return;

   const int i_end   = ns_end - p;
   const int i_start = MathMax(p, ns_end - CandleWindow - p);
   if(i_end < i_start) return;

   // Collect up to last 10 swings (newest first)
   #define MAX_SW 10
   int      sw_ns[MAX_SW];
   int      sw_ai[MAX_SW];
   double   sw_px[MAX_SW];
   datetime sw_t[MAX_SW];
   int      sw_cnt = 0;

   for(int ns = i_end; ns >= i_start && sw_cnt < MAX_SW; --ns)
   {
      bool ok = isHigh ? IsSwingHigh_NS(h, ns, p, rates_total, seriesArrays)
                       : IsSwingLow_NS (l, ns, p, rates_total, seriesArrays);

      if(!ok) continue;

      int ai = MapNS2Arr(ns, rates_total, seriesArrays);
      double price = isHigh ? h[ai] : l[ai];

      sw_ns[sw_cnt] = ns;
      sw_ai[sw_cnt] = ai;
      sw_px[sw_cnt] = price;
      sw_t[sw_cnt]  = t[ai];
      sw_cnt++;
   }

   if(sw_cnt < 2) return;

   // Always use latest swing as endpoint
   const int      newer_idx = sw_ns[0];
   const int      anew      = sw_ai[0];
   const double   newer_px  = sw_px[0];
   const datetime newer_t   = sw_t[0];

   // Try closest older swings first (latest possible match)
   for(int k = 1; k < sw_cnt; ++k)
   {
      const int      older_idx = sw_ns[k];
      const int      aold      = sw_ai[k];
      const double   older_px  = sw_px[k];
      const datetime older_t   = sw_t[k];

      // Ensure ordering older -> newer in NS space
      if(older_idx >= newer_idx) continue;

      // Must be >= SwingPeriod candles apart
      if((newer_idx - older_idx) < SwingPeriod) continue;

      // Slope direction rule
      if(!isHigh)
      {
         // Demand TL: higher low
         if(!(newer_px > older_px)) continue;
      }
      else
      {
         // Supply TL: lower high
         if(!(newer_px < older_px)) continue;
      }

      // Additional validation
      if(!InpUseBOSValidation)
      {
         // Same as your old "non-BOS" filter
         if(!isHigh)
         {
            if(!(h[anew] > h[aold])) continue;
         }
         else
         {
            if(!(l[anew] < l[aold])) continue;
         }
      }
      else
      {
         // BOS must happen BEFORE the next swing of same type after the newer swing
         if(!isHigh)
         {
            const double H12 = MaxHighBetweenNS(h, older_idx, newer_idx, rates_total, seriesArrays);

            const int nextL = FindNextSwingAfter_NS(false, h, l, newer_idx+1, i_end, p, rates_total, seriesArrays);
            const int limit = (nextL >= 0 ? (nextL - 1) : i_end);

            // Find first BOS candle (high breaks above H12)
            const int bos_ns = FindFirstBOSBreak_NS(true, h, l, H12, newer_idx+1, limit, rates_total, seriesArrays);
            if(bos_ns < 0) continue;

            // Reject if TL would have been broken BEFORE BOS happens (Option A: full candle break)
            // "Before BOS" => scan newer+1 .. bos-1
            if(TrendlineBrokenBeforeBOS(false, t, h, l, rates_total, seriesArrays,
                                       older_idx, older_px, newer_idx, newer_px,
                                       newer_idx+1, bos_ns-1))
               continue;
         }
         else
         {
            const double L12 = MinLowBetweenNS(l, older_idx, newer_idx, rates_total, seriesArrays);

            const int nextH = FindNextSwingAfter_NS(true, h, l, newer_idx+1, i_end, p, rates_total, seriesArrays);
            const int limit = (nextH >= 0 ? (nextH - 1) : i_end);

            // Find first BOS candle (low breaks below L12)
            const int bos_ns = FindFirstBOSBreak_NS(false, h, l, L12, newer_idx+1, limit, rates_total, seriesArrays);
            if(bos_ns < 0) continue;

            // Reject if TL would have been broken BEFORE BOS happens (Option A: full candle break)
            if(TrendlineBrokenBeforeBOS(true, t, h, l, rates_total, seriesArrays,
                                       older_idx, older_px, newer_idx, newer_px,
                                       newer_idx+1, bos_ns-1))
               continue;
         }
      }

      // Angle filter (unchanged logic)
      if(AngleBased)
      {
         double atr_val = 0.0;
         if(!GetATRAtArrIndex(st, anew, atr_val)) continue;

         const int bars = (newer_idx - older_idx);
         if(!AnglePass_ByATR(older_px, newer_px, bars, atr_val)) continue;
      }

      // Guard (object endpoints must be distinct in time)
      if(older_t == newer_t) continue;

      // If we reached here => this is the latest valid match. Set output and stop.
      out.has = true;

      out.t1 = older_t; out.p1 = older_px;
      out.t2 = newer_t; out.p2 = newer_px;

      out.ns1 = older_idx;
      out.ns2 = newer_idx;

      out.swing_ns = newer_idx;
      out.swingTime = newer_t;

      out.idx_old_arr = aold;
      out.idx_new_arr = anew;

      return;
   }

   // No valid match => no trendline
   out.has = false;
}

void DrawTrendlineObject(const string name,
                         datetime t1,double p1, datetime t2,double p2,
                         color clr, ENUM_LINE_STYLE style, int width,
                         bool rayRight)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);

   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);

   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,  false);
   ObjectSetInteger(0, name, OBJPROP_STYLE, (int)style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, MathMax(1, width));
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

void DrawCurrentTrendlines(AZState &st,
                           const datetime &t[],
                           const double &h[],
                           const double &l[],
                           const int rates_total,
                           const bool seriesArrays,
                           const int iClsArr)
{
   int ns_end = MapArr2NS(iClsArr, rates_total, seriesArrays);

   TLInfo hi, lo;
   ComputeTrendlineAt(st, t, h, l, rates_total, seriesArrays, ns_end, true,  hi);
   ComputeTrendlineAt(st, t, h, l, rates_total, seriesArrays, ns_end, false, lo);

   int s = MathMax(0, MathMin(4, LineStyle));
   string nameHigh = ObjName(true);
   string nameLow  = ObjName(false);

   if((OnlySwingHigh || (!OnlySwingHigh && !OnlySwingLow) || (OnlySwingHigh && OnlySwingLow)) && hi.has)
      DrawTrendlineObject(nameHigh, hi.t1, hi.p1, hi.t2, hi.p2, LineColor, (ENUM_LINE_STYLE)s, LineWidth, true);
   else
      ObjectDelete(0, nameHigh);

   if((OnlySwingLow || (!OnlySwingHigh && !OnlySwingLow) || (OnlySwingHigh && OnlySwingLow)) && lo.has)
      DrawTrendlineObject(nameLow, lo.t1, lo.p1, lo.t2, lo.p2, LineColor, (ENUM_LINE_STYLE)s, LineWidth, true);
   else
      ObjectDelete(0, nameLow);
}

//------------------------- Line math + break tests -------------------
double LinePriceAt(const int ns_t, const int ns1, const double p1, const int ns2, const double p2)
{
   int di = (ns2 - ns1);
   if(di == 0) return p2;
   double slope = (p2 - p1) / (double)di;
   return p1 + slope * (double)(ns_t - ns1);
}

datetime CandleCloseTime(const datetime &timeOpen)
{
   return (datetime)((long)timeOpen + (long)PeriodSeconds(_Period));
}

// “full OHLC” reduces to single extreme test
bool FullOHLC_AboveLine(const datetime &time[], const double &low[],
                        const int i, const int ns1, const double p1, const int ns2, const double p2)
{
   const int rates_total = ArraySize(time);
   const bool seriesArrays = (rates_total > 1 && time[0] > time[rates_total-1]);

   // Evaluate line at candle close => +1 candle step in NS space
   const int nsClose = MapArr2NS(i, rates_total, seriesArrays) + 1;

   const double lp = LinePriceAt(nsClose, ns1, p1, ns2, p2);
   const double eps = _Point * 0.5;
   return (low[i] > lp + eps);
}

bool FullOHLC_BelowLine(const datetime &time[], const double &high[],
                        const int i, const int ns1, const double p1, const int ns2, const double p2)
{
   const int rates_total = ArraySize(time);
   const bool seriesArrays = (rates_total > 1 && time[0] > time[rates_total-1]);

   // Evaluate line at candle close => +1 candle step in NS space
   const int nsClose = MapArr2NS(i, rates_total, seriesArrays) + 1;

   const double lp = LinePriceAt(nsClose, ns1, p1, ns2, p2);
   const double eps = _Point * 0.5;
   return (high[i] < lp - eps);
}

void DrawBrokenTrendlineSegment(const bool breakOnHighLine,
                                const TLInfo &tl,
                                const datetime &time[],
                                const int breakBarIdx)
{
   if(!InpShowBrokenTrendlines) return;
   if(!tl.has) return;

   datetime tEnd = time[breakBarIdx];

   const int rates_total = ArraySize(time);
   const bool seriesArrays = (rates_total > 1 && time[0] > time[rates_total-1]);
   const int nsEnd = MapArr2NS(breakBarIdx, rates_total, seriesArrays);

   double   pEnd = LinePriceAt(nsEnd, tl.ns1, tl.p1, tl.ns2, tl.p2);

   string nm = BrokenTLObjName(breakOnHighLine, time[breakBarIdx]);

   int s = MathMax(0, MathMin(4, LineStyle));
   DrawTrendlineObject(nm, tl.t1, tl.p1, tEnd, pEnd, LineColor, (ENUM_LINE_STYLE)s, LineWidth, false);
}

//------------------------- TL-break -> confirm zones -----------------
bool ZoneTouchesLineWick(const Zone &z,
                         const datetime &time[],
                         const double &high[], const double &low[],
                         const bool series,
                         const int ns1,double p1, const int ns2,double p2)
{
   const int rates_total = ArraySize(time);

   int idx = z.baseStart;
   while(true)
   {
      const int ns = MapArr2NS(idx, rates_total, series);
      double lp = LinePriceAt(ns, ns1, p1, ns2, p2);
      if(low[idx] <= lp && high[idx] >= lp)
         return true;

      if(idx == z.baseEnd) break;
      idx = NewerIndex(idx, 1, series);
      if(idx < 0) break;
   }
   return false;
}

void ConfirmZonesByTLBreak(AZState &st,
                           bool breakOnHighLine,
                           datetime swingTime, datetime breakTime,
                           const datetime &time[],
                           const double &high[], const double &low[],
                           const bool series,
                           const int ns1,double p1, const int ns2,double p2)
{
   if(breakTime <= 0 || swingTime <= 0) return;

   ZoneType toConfirm = breakOnHighLine ? Demand : Supply;

   // Normalize window [a..b]
   datetime a = swingTime;
   datetime b = breakTime;
   if(b < a){ datetime tmp=a; a=b; b=tmp; }

   // 1) Find EXTREME zone (same rule as before)
   int extremeIdx = -1;
   double extremeDistal = (toConfirm==Demand ? DBL_MAX : -DBL_MAX);

   for(int i=0; i<ArraySize(st.zonesActive); ++i)
   {
      if(st.zonesActive[i].status != Potential) continue;
      if(st.zonesActive[i].type   != toConfirm) continue;

      // must overlap swing->break window
      if(st.zonesActive[i].tStart   > b) continue;
      if(st.zonesActive[i].tBaseEnd < a) continue;

      if(toConfirm == Demand)
      {
         if(st.zonesActive[i].distal < extremeDistal)
         {
            extremeDistal = st.zonesActive[i].distal;
            extremeIdx = i;
         }
      }
      else
      {
         if(st.zonesActive[i].distal > extremeDistal)
         {
            extremeDistal = st.zonesActive[i].distal;
            extremeIdx = i;
         }
      }
   }

   // 2) Find LAST touching zone (most recent base that touches the trendline before break)
   //    "Last" = greatest tBaseEnd (closest to breakTime), but still inside window.
   int touchIdx = -1;
   datetime bestBaseEnd = 0;

   for(int i=0; i<ArraySize(st.zonesActive); ++i)
   {
      if(st.zonesActive[i].status != Potential) continue;
      if(st.zonesActive[i].type   != toConfirm) continue;

      // must overlap swing->break window
      if(st.zonesActive[i].tStart   > b) continue;
      if(st.zonesActive[i].tBaseEnd < a) continue;

      // defensive: ignore bases ending after break
      if(st.zonesActive[i].tBaseEnd > b) continue;

      // base touches the line (wick touch anywhere during base candles)
      if(!ZoneTouchesLineWick(st.zonesActive[i], time, high, low, series, ns1, p1, ns2, p2))
         continue;

      if(touchIdx < 0 || st.zonesActive[i].tBaseEnd > bestBaseEnd)
      {
         touchIdx = i;
         bestBaseEnd = st.zonesActive[i].tBaseEnd;
      }
   }

   // 3) Confirm LAST touching zone (if found)
   if(touchIdx >= 0)
   {
      st.zonesActive[touchIdx].status = Confirmed;
      st.zonesActive[touchIdx].tConfirmed = breakTime;
   }

   // 4) Confirm EXTREME zone too (if found and not already the touching zone)
   if(extremeIdx >= 0 && extremeIdx != touchIdx)
   {
      st.zonesActive[extremeIdx].status = Confirmed;
      st.zonesActive[extremeIdx].tConfirmed = breakTime;
   }
}

bool CheckAndProcessTLBreakUpToBar(AZState &st,
                                  const bool breakOnHighLine,
                                  const TLInfo &tl,
                                  const datetime &time[],
                                  const double &high[],
                                  const double &low[],
                                  const int rates_total,
                                  const int barIdx,
                                  const bool series,
                                  datetime &lastBreakStore)
{
   if(!tl.has) return false;

   // lock per TL anchors (t1,t2)
   if(breakOnHighLine)
   {
      if(tl.t1 != st.high_sig_t1 || tl.t2 != st.high_sig_t2)
      {
         st.high_sig_t1 = tl.t1;
         st.high_sig_t2 = tl.t2;
         st.high_sig_broken = false;
      }
      if(st.high_sig_broken) return false;
   }
   else
   {
      if(tl.t1 != st.low_sig_t1 || tl.t2 != st.low_sig_t2)
      {
         st.low_sig_t1 = tl.t1;
         st.low_sig_t2 = tl.t2;
         st.low_sig_broken = false;
      }
      if(st.low_sig_broken) return false;
   }

   if(tl.idx_new_arr < 0 || tl.idx_new_arr >= rates_total) return false;

   int start = NewerIndex(tl.idx_new_arr, 1, series);
   if(start < 0 || start >= rates_total) return false;

   int breakIdx = -1;

   if(series)
   {
      int s = start;
      int e = barIdx;
      if(s < e) s = e;

      for(int i = s; i >= e; --i)
      {
         if(time[i] <= tl.swingTime) continue;
         if(time[i] <= lastBreakStore) continue;

         bool isBreak = breakOnHighLine
                        ? FullOHLC_AboveLine(time, low,  i, tl.ns1,tl.p1, tl.ns2,tl.p2)
                        : FullOHLC_BelowLine(time, high, i, tl.ns1,tl.p1, tl.ns2,tl.p2);

         if(isBreak){ breakIdx = i; break; }
      }
   }
   else
   {
      int s = start;
      int e = barIdx;
      if(s > e) s = e;

      for(int i = s; i <= e; ++i)
      {
         if(time[i] <= tl.swingTime) continue;
         if(time[i] <= lastBreakStore) continue;

         bool isBreak = breakOnHighLine
                        ? FullOHLC_AboveLine(time, low,  i, tl.ns1,tl.p1, tl.ns2,tl.p2)
                        : FullOHLC_BelowLine(time, high, i, tl.ns1,tl.p1, tl.ns2,tl.p2);

         if(isBreak){ breakIdx = i; break; }
      }
   }

   if(breakIdx < 0) return false;

   datetime breakTime = time[breakIdx];

   DrawBrokenTrendlineSegment(breakOnHighLine, tl, time, breakIdx);

   lastBreakStore = breakTime;

   if(breakOnHighLine) st.high_sig_broken = true;
   else                st.low_sig_broken  = true;

   ConfirmZonesByTLBreak(st,
                         breakOnHighLine,
                         tl.swingTime, breakTime,
                         time, high, low, series,
                         tl.ns1,tl.p1, tl.ns2,tl.p2);

   return true;
}
