
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
   out.swing_ns = -1;
   out.swingTime = 0;
   out.idx_old_arr = -1;
   out.idx_new_arr = -1;

   int p = MathMax(1, SwingPeriod);
   if(rates_total < (2*p + 1)) return;

   int i_end   = ns_end - p;
   int i_start = MathMax(p, ns_end - CandleWindow - p);
   if(i_end < i_start) return;

   int newest=-1, second=-1;
   double px_new=0.0, px_old=0.0;

   for(int i = i_end; i >= i_start; --i)
   {
      bool ok = isHigh ? IsSwingHigh_NS(h, i, p, rates_total, seriesArrays)
                       : IsSwingLow_NS (l, i, p, rates_total, seriesArrays);

      if(ok)
      {
         int ai = MapNS2Arr(i, rates_total, seriesArrays);
         double price = isHigh ? h[ai] : l[ai];
         ConsiderPoint(i, price, newest, px_new, second, px_old);
         if(newest >= 0 && second >= 0) break;
      }
   }

   if(newest < 0 || second < 0) return;

   int older_idx = second;
   int newer_idx = newest;
   double older_px = px_old;
   double newer_px = px_new;

   if(older_idx > newer_idx)
   {
      int ti = older_idx; older_idx = newer_idx; newer_idx = ti;
      double tp = older_px; older_px = newer_px; newer_px = tp;
   }

   // enforce correct slope direction
   if(!isHigh)
   {
      if(!(newer_px > older_px)) return;
   }
   else
   {
      if(!(newer_px < older_px)) return;
   }

   // validation filter
   int aold_chk = MapNS2Arr(older_idx, rates_total, seriesArrays);
   int anew_chk = MapNS2Arr(newer_idx, rates_total, seriesArrays);

   if(!InpUseBOSValidation)
   {
      if(!isHigh)
      {
         if(!(h[anew_chk] > h[aold_chk])) return;
      }
      else
      {
         if(!(l[anew_chk] < l[aold_chk])) return;
      }
   }
   else
   {
      if(!isHigh)
      {
         double H12 = MaxHighBetweenNS(h, older_idx, newer_idx, rates_total, seriesArrays);
         int nextL = FindNextSwingAfter_NS(false, h, l, newer_idx+1, i_end, p, rates_total, seriesArrays);
         int limit = (nextL >= 0 ? (nextL - 1) : i_end);
         if(!ExistsBreakBefore_NS(true, h, l, H12, newer_idx+1, limit, rates_total, seriesArrays))
            return;
      }
      else
      {
         double L12 = MinLowBetweenNS(l, older_idx, newer_idx, rates_total, seriesArrays);
         int nextH = FindNextSwingAfter_NS(true, h, l, newer_idx+1, i_end, p, rates_total, seriesArrays);
         int limit = (nextH >= 0 ? (nextH - 1) : i_end);
         if(!ExistsBreakBefore_NS(false, h, l, L12, newer_idx+1, limit, rates_total, seriesArrays))
            return;
      }
   }

   if(AngleBased)
   {
      int anew = MapNS2Arr(newer_idx, rates_total, seriesArrays);
      double atr_val = 0.0;
      if(!GetATRAtArrIndex(st, anew, atr_val)) return;
      int bars = newer_idx - older_idx;
      if(!AnglePass_ByATR(older_px, newer_px, bars, atr_val)) return;
   }

   int aold = MapNS2Arr(older_idx, rates_total, seriesArrays);
   int anew = MapNS2Arr(newer_idx, rates_total, seriesArrays);

   // guard against degenerate anchors
   if(t[aold] == t[anew]) return;

   out.has = true;
   out.t1 = t[aold]; out.p1 = older_px;
   out.t2 = t[anew]; out.p2 = newer_px;
   out.swing_ns = newer_idx;
   out.swingTime = t[anew];
   out.idx_old_arr = aold;
   out.idx_new_arr = anew;
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
double LinePriceAt(datetime t, datetime t1, double p1, datetime t2, double p2)
{
   long dt = (long)(t2 - t1);
   if(dt == 0) return p2;
   double slope = (p2 - p1) / (double)dt;
   return p1 + slope * (double)((long)(t - t1));
}

datetime CandleCloseTime(const datetime &timeOpen)
{
   return (datetime)((long)timeOpen + (long)PeriodSeconds(_Period));
}

// “full OHLC” reduces to single extreme test
bool FullOHLC_AboveLine(const datetime &time[], const double &low[],
                        const int i, datetime t1,double p1, datetime t2,double p2)
{
   datetime tClose = CandleCloseTime(time[i]);
   double lp = LinePriceAt(tClose, t1, p1, t2, p2);
   double eps = _Point * 0.5;
   return (low[i] > lp + eps);
}

bool FullOHLC_BelowLine(const datetime &time[], const double &high[],
                        const int i, datetime t1,double p1, datetime t2,double p2)
{
   datetime tClose = CandleCloseTime(time[i]);
   double lp = LinePriceAt(tClose, t1, p1, t2, p2);
   double eps = _Point * 0.5;
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
   double   pEnd = LinePriceAt(tEnd, tl.t1, tl.p1, tl.t2, tl.p2);

   string nm = BrokenTLObjName(breakOnHighLine, time[breakBarIdx]);

   int s = MathMax(0, MathMin(4, LineStyle));
   DrawTrendlineObject(nm, tl.t1, tl.p1, tEnd, pEnd, LineColor, (ENUM_LINE_STYLE)s, LineWidth, false);
}

//------------------------- TL-break -> confirm zones -----------------
bool ZoneTouchesLineWick(const Zone &z,
                         const datetime &time[],
                         const double &high[], const double &low[],
                         const bool series,
                         datetime t1,double p1, datetime t2,double p2)
{
   int idx = z.baseStart;
   while(true)
   {
      double lp = LinePriceAt(time[idx], t1, p1, t2, p2);
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
                           datetime t1,double p1, datetime t2,double p2)
{
   if(breakTime <= 0 || swingTime <= 0) return;

   ZoneType toConfirm = breakOnHighLine ? Demand : Supply;

   datetime a = swingTime;
   datetime b = breakTime;
   if(b < a){ datetime tmp=a; a=b; b=tmp; }

   int extremeIdx = -1;
   double extremeDistal = (toConfirm==Demand ? DBL_MAX : -DBL_MAX);

   for(int i=0; i<ArraySize(st.zonesActive); ++i)
   {
      if(st.zonesActive[i].status != Potential) continue;
      if(st.zonesActive[i].type != toConfirm) continue;
      if(st.zonesActive[i].tStart > b) continue;
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

   for(int i=0; i<ArraySize(st.zonesActive); ++i)
   {
      if(st.zonesActive[i].status != Potential) continue;
      if(st.zonesActive[i].type != toConfirm) continue;
      if(st.zonesActive[i].tStart > b) continue;
      if(st.zonesActive[i].tBaseEnd < a) continue;

      if(ZoneTouchesLineWick(st.zonesActive[i], time, high, low, series, t1,p1,t2,p2))
      {
         st.zonesActive[i].status = Confirmed;
         st.zonesActive[i].tConfirmed    = breakTime;
         st.zonesActive[i].confirmReason = breakOnHighLine
                                        ? "TRENDLINE_BREAK (touch -> Demand)"
                                        : "TRENDLINE_BREAK (touch -> Supply)";
      }
   }

   if(extremeIdx >= 0 && st.zonesActive[extremeIdx].status == Potential)
   {
      st.zonesActive[extremeIdx].status = Confirmed;
      st.zonesActive[extremeIdx].tConfirmed    = breakTime;
      st.zonesActive[extremeIdx].confirmReason = breakOnHighLine
                                             ? "TRENDLINE_BREAK (extreme distal -> Demand)"
                                             : "TRENDLINE_BREAK (extreme distal -> Supply)";
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
                        ? FullOHLC_AboveLine(time, low,  i, tl.t1,tl.p1,tl.t2,tl.p2)
                        : FullOHLC_BelowLine(time, high, i, tl.t1,tl.p1,tl.t2,tl.p2);

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
                        ? FullOHLC_AboveLine(time, low,  i, tl.t1,tl.p1,tl.t2,tl.p2)
                        : FullOHLC_BelowLine(time, high, i, tl.t1,tl.p1,tl.t2,tl.p2);

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
                         tl.t1,tl.p1,tl.t2,tl.p2);

   return true;
}
