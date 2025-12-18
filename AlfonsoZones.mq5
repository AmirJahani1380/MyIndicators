//+------------------------------------------------------------------+
//|                                                   AlfonsoZones   |
//|   Step 5 (revised): Filled zones + proper confirmation            |
//|   - Filled rectangles (single OBJ_RECTANGLE per zone)             |
//|   - Zone color affects both border & fill                         |
//|   - Confirmed zones: potential zone that takes out opposing zone  |
//|     (checks leg-out move, not just one candle)                    |
//|   - Processes zones oldest->newest for correct confirmation       |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

#property indicator_plots   1
#property indicator_buffers 1
#property indicator_type1   DRAW_NONE
#property indicator_label1  ""

//------------------------- Inputs -----------------------------------
input int    InpLookbackBars      = 2000;
input bool   InpDebug             = true;
input string InpObjPrefix         = "SDZ_";

// Candle classification thresholds
input double InpBasingBodyPctMax  = 0.50;
input double InpERCBodyPctMin     = 0.60;
input double InpCloseNearPct      = 0.20;
input int    InpAvgRangeLen       = 20;
input double InpWideMult          = 1.50;

// Base rules
input int    InpBaseMinBars               = 1;
input int    InpBaseMaxBars               = 6;     // STRICT: >max => reject (no truncation)
input bool   InpAllowSingleCandleBase     = true;
input bool   InpBaseUseEngulfPierceHarami = true;

// Detection + confirmation
input int    InpScanPatternBars        = 800;  // scan last N closed bars for leg-outs
input int    InpMaxZonesProcess        = 120;  // cap new zones processed per bar
input int    InpConfirmLookaheadBars   = 30;   // leg-out "move": scan forward up to N candles to take out opposing zone

// Display
input bool   InpDrawZones        = true;
input bool   InpShowEliminated   = true;

// Colors (your defaults)
input color  InpPotentialDemandColor = clrMintCream;
input color  InpPotentialSupplyColor = clrLavenderBlush;
input color  InpEliminatedColor      = clrOrangeRed;
input color  InpConfirmedColor       = clrMidnightBlue;

// Border widths
input int    InpWidthPotential   = 1;
input int    InpWidthConfirmed   = 2;
input int    InpWidthEliminated  = 1;

//------------------------- Types ------------------------------------
enum ZoneType   { Demand = 0, Supply = 1 };
enum ZoneStatus { Potential = 0, Confirmed = 1, Eliminated = 2 };

struct Zone
{
   ZoneType   type;
   ZoneStatus status;

   int        legIn;
   int        baseStart;
   int        baseEnd;
   int        legOut;

   double     proximal;
   double     distal;

   datetime   tStart;       // time[baseStart]
   datetime   tEnd;         // now unless broken, else breaker candle time
   datetime   tLegOut;      // time[legOut] (used for sorting / confirmation)

   string     name;         // unique object name
   string     tag;          // DBR/RBD/RBR/DBD
};

//------------------------- Storage ----------------------------------
double   g_dummyBuffer[];
datetime g_lastClosedTime = 0;

Zone zonesActive[]; // Potential + Confirmed (not eliminated)
Zone zonesDead[];   // Eliminated history

//------------------------- Utilities --------------------------------
void DebugPrint(const string msg){ if(InpDebug) Print(msg); }

string MakeBasePrefix()
{
   return (InpObjPrefix + _Symbol + "_" + IntegerToString((int)_Period) + "_");
}

bool StartsWith(const string s, const string prefix)
{
   int plen = (int)StringLen(prefix);
   if(plen <= 0) return false;
   if((int)StringLen(s) < plen) return false;
   return (StringSubstr(s, 0, plen) == prefix);
}

void DeleteObjectsByPrefix(const string pfx)
{
   const long chart_id = 0;
   int total = ObjectsTotal(chart_id);
   for(int i = total - 1; i >= 0; --i)
   {
      string nm = ObjectName(chart_id, i);
      if(StartsWith(nm, pfx))
         ObjectDelete(chart_id, nm);
   }
}

void DeleteObjectExact(const string name)
{
   const long chart_id = 0;
   if(ObjectFind(chart_id, name) >= 0)
      ObjectDelete(chart_id, name);
}

//------------------------- Indexing helpers --------------------------
bool IsSeriesOrder(const datetime &time[], const int rates_total)
{
   if(rates_total < 2) return true;
   return (time[0] > time[rates_total - 1]); // series => newest at [0]
}

int IndexCurrentBar(const datetime &time[], const int rates_total)
{
   return IsSeriesOrder(time, rates_total) ? 0 : (rates_total - 1);
}

int IndexLastClosedBar(const datetime &time[], const int rates_total)
{
   return IsSeriesOrder(time, rates_total) ? 1 : (rates_total - 2);
}

bool ComputeWindow(const datetime &time[], const int rates_total, const int lookback,
                   int &winOldest, int &winNewest)
{
   if(rates_total < 2) return false;

   int lb = lookback;
   if(lb < 2) lb = 2;
   if(lb > rates_total) lb = rates_total;

   bool series = IsSeriesOrder(time, rates_total);
   if(series)
   {
      winNewest = 0;
      winOldest = lb - 1;               // [0..lb-1]
   }
   else
   {
      winNewest = rates_total - 1;
      winOldest = rates_total - lb;     // [rates_total-lb .. rates_total-1]
      if(winOldest < 0) winOldest = 0;
   }
   return true;
}

bool IndexInWindow(const int idx, const int winOldest, const int winNewest, const bool series)
{
   if(series) return (idx >= winNewest && idx <= winOldest);
   return (idx >= winOldest && idx <= winNewest);
}

int OlderIndex(const int idx, const int k, const bool series){ return (series ? (idx + k) : (idx - k)); }
int NewerIndex(const int idx, const int k, const bool series){ return (series ? (idx - k) : (idx + k)); }

//------------------------- Candle helpers ----------------------------
double CandleRange(const double &high[], const double &low[], const int i)
{
   double r = high[i] - low[i];
   return (r > 0.0 ? r : 0.0);
}

double CandleBody(const double &open[], const double &close[], const int i)
{
   return MathAbs(close[i] - open[i]);
}

double BodyPct(const double &open[], const double &high[], const double &low[], const double &close[], const int i)
{
   double r = CandleRange(high, low, i);
   if(r <= 0.0) return 0.0;
   return CandleBody(open, close, i) / r;
}

bool IsBull(const double &open[], const double &close[], const int i){ return close[i] > open[i]; }
bool IsBear(const double &open[], const double &close[], const int i){ return close[i] < open[i]; }

bool IsBasing(const double &open[], const double &high[], const double &low[], const double &close[], const int i)
{
   return (BodyPct(open, high, low, close, i) <= InpBasingBodyPctMax);
}

bool CloseNearHigh(const double &high[], const double &low[], const double &close[], const int i)
{
   double r = CandleRange(high, low, i);
   if(r <= 0.0) return false;
   return ((high[i] - close[i]) <= (r * InpCloseNearPct));
}

bool CloseNearLow(const double &high[], const double &low[], const double &close[], const int i)
{
   double r = CandleRange(high, low, i);
   if(r <= 0.0) return false;
   return ((close[i] - low[i]) <= (r * InpCloseNearPct));
}

double AvgRange(const double &high[], const double &low[], const int i,
                const int len, const bool series,
                const int winOldest, const int winNewest)
{
   int L = len; if(L < 1) L = 1;
   double sum = 0.0; int cnt = 0;

   for(int k = 0; k < L; ++k)
   {
      int idx = OlderIndex(i, k, series);
      if(!IndexInWindow(idx, winOldest, winNewest, series)) break;
      sum += CandleRange(high, low, idx);
      cnt++;
   }
   if(cnt <= 0) return CandleRange(high, low, i);
   return sum / (double)cnt;
}

bool IsWide(const double &high[], const double &low[], const int i,
            const bool series, const int winOldest, const int winNewest)
{
   double r = CandleRange(high, low, i);
   double avg = AvgRange(high, low, i, InpAvgRangeLen, series, winOldest, winNewest);
   return (avg > 0.0 && r >= avg * InpWideMult);
}

bool IsERC(const double &open[], const double &high[], const double &low[], const double &close[], const int i,
           const bool series, const int winOldest, const int winNewest)
{
   if(IsBasing(open, high, low, close, i)) return false;

   double bp = BodyPct(open, high, low, close, i);
   if(bp < InpERCBodyPctMin) return false;

   if(IsBull(open, close, i)) return CloseNearHigh(high, low, close, i);
   if(IsBear(open, close, i)) return CloseNearLow(high, low, close, i);
   return false;
}

bool IsFailedERC(const double &open[], const double &high[], const double &low[], const double &close[], const int i,
                 const bool series, const int winOldest, const int winNewest)
{
   if(!IsWide(high, low, i, series, winOldest, winNewest)) return false;
   return IsBasing(open, high, low, close, i);
}

bool IsImpulse(const double &open[], const double &high[], const double &low[], const double &close[], const int i,
               const bool series, const int winOldest, const int winNewest)
{
   return IsERC(open, high, low, close, i, series, winOldest, winNewest) ||
          IsFailedERC(open, high, low, close, i, series, winOldest, winNewest);
}

//------------------------- Base pattern helpers ----------------------
bool IsBullishEngulf(const double &open[], const double &close[], const int i, const int prev)
{
   if(!(close[i] > open[i])) return false;
   double prevHi = MathMax(open[prev], close[prev]);
   double prevLo = MathMin(open[prev], close[prev]);
   double curHi  = MathMax(open[i], close[i]);
   double curLo  = MathMin(open[i], close[i]);
   return (curHi > prevHi && curLo < prevLo);
}

bool IsBearishEngulf(const double &open[], const double &close[], const int i, const int prev)
{
   if(!(close[i] < open[i])) return false;
   double prevHi = MathMax(open[prev], close[prev]);
   double prevLo = MathMin(open[prev], close[prev]);
   double curHi  = MathMax(open[i], close[i]);
   double curLo  = MathMin(open[i], close[i]);
   return (curHi > prevHi && curLo < prevLo);
}

bool IsHarami(const double &open[], const double &close[], const int i, const int prev)
{
   double prevHi = MathMax(open[prev], close[prev]);
   double prevLo = MathMin(open[prev], close[prev]);
   double curHi  = MathMax(open[i], close[i]);
   double curLo  = MathMin(open[i], close[i]);
   return (curHi <= prevHi && curLo >= prevLo);
}

//------------------------- Strict base finder ------------------------
bool FindBaseStrictBeforeLegOut(const datetime &time[],
                                const double &open[], const double &high[], const double &low[], const double &close[],
                                const int legOut,
                                const bool series,
                                const int winOldest, const int winNewest,
                                int &baseStart, int &baseEnd,
                                double &proximal, double &distal,
                                ZoneType &zoneType)
{
   if(IsBull(open, close, legOut)) zoneType = Demand;
   else if(IsBear(open, close, legOut)) zoneType = Supply;
   else return false;

   int prev = OlderIndex(legOut, 1, series);
   if(!IndexInWindow(prev, winOldest, winNewest, series)) return false;

   // Count contiguous basing candles before legOut
   int count = 0;
   baseEnd = prev;
   int cur = prev;

   while(IndexInWindow(cur, winOldest, winNewest, series) && IsBasing(open, high, low, close, cur))
   {
      count++;
      if(count > InpBaseMaxBars) return false; // STRICT reject
      cur = OlderIndex(cur, 1, series);
   }

   if(count < InpBaseMinBars)
   {
      if(!InpBaseUseEngulfPierceHarami) return false;

      int prev2 = OlderIndex(prev, 1, series);
      if(!IndexInWindow(prev2, winOldest, winNewest, series)) return false;

      bool pat = IsBullishEngulf(open, close, prev, prev2) ||
                 IsBearishEngulf(open, close, prev, prev2) ||
                 IsHarami(open, close, prev, prev2);

      if(!pat) return false;
      if(2 < InpBaseMinBars || 2 > InpBaseMaxBars) return false;

      baseStart = prev2;
      baseEnd   = prev;
   }
   else
   {
      if(count == 1 && !InpAllowSingleCandleBase) return false;
      baseStart = OlderIndex(prev, (count - 1), series);
   }

   // compute prox/dist from base candles
   double lo = low[baseStart], hi = high[baseStart];
   double maxOC = MathMax(open[baseStart], close[baseStart]);
   double minOC = MathMin(open[baseStart], close[baseStart]);

   int idx = baseStart;
   while(true)
   {
      lo = MathMin(lo, low[idx]);
      hi = MathMax(hi, high[idx]);
      maxOC = MathMax(maxOC, MathMax(open[idx], close[idx]));
      minOC = MathMin(minOC, MathMin(open[idx], close[idx]));

      if(idx == baseEnd) break;
      idx = NewerIndex(idx, 1, series);
      if(!IndexInWindow(idx, winOldest, winNewest, series)) break;
   }

   if(zoneType == Demand){ distal = lo; proximal = maxOC; }
   else                 { distal = hi; proximal = minOC; }

   return true;
}

//------------------------- Zone build --------------------------------
bool FindFirstBreakerAfterLegOut(const datetime &time[],
                                 const double &high[], const double &low[],
                                 const int legOut, const int iCls,
                                 const bool series,
                                 const int winOldest, const int winNewest,
                                 const ZoneType zt,
                                 const double distal,
                                 int &breakerIdx)
{
   breakerIdx = -1;

   int idx = NewerIndex(legOut, 1, series);
   while(IndexInWindow(idx, winOldest, winNewest, series))
   {
      // stop past newest closed candle
      if(series)
      {
         if(idx < iCls) break;
      }
      else
      {
         if(idx > iCls) break;
      }

      if(zt == Demand)
      {
         if(low[idx] < distal){ breakerIdx = idx; return true; }
      }
      else
      {
         if(high[idx] > distal){ breakerIdx = idx; return true; }
      }

      if(idx == iCls) break;
      idx = NewerIndex(idx, 1, series);
   }
   return false;
}

bool BuildZoneFromLegOut(const datetime &time[],
                         const double &open[], const double &high[], const double &low[], const double &close[],
                         const int legOut,
                         const int iCls, const int iCur,
                         const bool series,
                         const int winOldest, const int winNewest,
                         Zone &outZone)
{
   if(!IsImpulse(open, high, low, close, legOut, series, winOldest, winNewest))
      return false;

   int baseStart=-1, baseEnd=-1;
   double prox=0, dist=0;
   ZoneType zt=Demand;

   if(!FindBaseStrictBeforeLegOut(time, open, high, low, close,
                                  legOut, series, winOldest, winNewest,
                                  baseStart, baseEnd, prox, dist, zt))
      return false;

   int legIn = OlderIndex(baseStart, 1, series);
   if(!IndexInWindow(legIn, winOldest, winNewest, series))
      return false;

   if(!IsImpulse(open, high, low, close, legIn, series, winOldest, winNewest))
      return false;

   bool inBull  = IsBull(open, close, legIn);
   bool outBull = IsBull(open, close, legOut);

   string tag="";
   if(!inBull && outBull) tag="DBR";
   else if(inBull && !outBull) tag="RBD";
   else if(inBull && outBull) tag="RBR";
   else if(!inBull && !outBull) tag="DBD";
   else return false;

   outZone.type      = zt;
   outZone.status    = Potential;

   outZone.legIn     = legIn;
   outZone.baseStart = baseStart;
   outZone.baseEnd   = baseEnd;
   outZone.legOut    = legOut;

   outZone.proximal  = prox;
   outZone.distal    = dist;

   outZone.tStart    = time[baseStart];
   outZone.tLegOut   = time[legOut];
   outZone.tEnd      = (datetime)(time[iCur] + PeriodSeconds(_Period)); // default extend to now

   outZone.tag       = tag;
   outZone.name      = MakeBasePrefix() + "ZONE_" + tag + "_" + IntegerToString((long)outZone.tLegOut);

   // End at breaker if already broken in history
   int breakerIdx=-1;
   if(FindFirstBreakerAfterLegOut(time, high, low, legOut, iCls, series, winOldest, winNewest, zt, dist, breakerIdx))
   {
      outZone.status = Eliminated;
      outZone.tEnd   = time[breakerIdx];
   }

   return true;
}

//------------------------- Zone list helpers -------------------------
int FindZoneByName(const string &name, const Zone &arr[])
{
   int n = ArraySize(arr);
   for(int i = 0; i < n; ++i)
      if(arr[i].name == name)
         return i;
   return -1;
}

void MoveToDead(const Zone &z)
{
   int n = ArraySize(zonesDead);
   ArrayResize(zonesDead, n + 1);
   zonesDead[n] = z;
}

bool CandleTakesOutZone(const double &high[], const double &low[], const int candleIndex, const Zone &target)
{
   if(target.status == Eliminated) return false;
   if(target.type == Supply) return (high[candleIndex] > target.distal);
   return (low[candleIndex] < target.distal); // Demand
}

//------------------------- Confirmation (fixed) ----------------------
// Confirm new zone if its LEG-OUT MOVE (legOut .. legOut+N) takes out an older opposing active zone.
// We must process zones chronologically for this to work (done below).
void ApplyConfirmationOnNewZone(Zone &newZ,
                                const datetime &time[],
                                const double &high[],
                                const double &low[],
                                const bool series,
                                const int winOldest, const int winNewest,
                                const int iCls)
{
   if(newZ.status == Eliminated) return;

   datetime newBaseTime = newZ.tStart;

   for(int i = 0; i < ArraySize(zonesActive); ++i)
   {
      if(zonesActive[i].status == Eliminated) continue;
      if(zonesActive[i].type == newZ.type)    continue; // must be opposing
      if(zonesActive[i].tStart >= newBaseTime) continue; // must pre-exist before base

      // Scan forward from legOut for up to InpConfirmLookaheadBars closed candles
      bool tookOut = false;
      int takeIdx = -1;

      for(int k = 0; k <= InpConfirmLookaheadBars; ++k)
      {
         int idx = NewerIndex(newZ.legOut, k, series);
         if(!IndexInWindow(idx, winOldest, winNewest, series)) break;

         // only consider up to newest closed candle
         if(series)
         {
            if(idx < iCls) break;
         }
         else
         {
            if(idx > iCls) break;
         }

         if(CandleTakesOutZone(high, low, idx, zonesActive[i]))
         {
            tookOut = true;
            takeIdx = idx;
            break;
         }
      }

      if(tookOut && takeIdx >= 0)
      {
         // eliminate opposing zone at the takeout candle
         zonesActive[i].status = Eliminated;
         zonesActive[i].tEnd   = time[takeIdx];

         // confirm new zone
         newZ.status = Confirmed;

         if(InpDebug)
         {
            PrintFormat("CONFIRMED: %s (%s) took out %s (%s) at %s",
                        newZ.name, newZ.tag,
                        zonesActive[i].name, zonesActive[i].tag,
                        TimeToString(time[takeIdx], TIME_DATE|TIME_MINUTES|TIME_SECONDS));
         }
         // keep scanning: one move could take out multiple opposing zones
      }
   }
}

void SweepEliminatedFromActive()
{
   for(int i = ArraySize(zonesActive) - 1; i >= 0; --i)
   {
      if(zonesActive[i].status == Eliminated)
      {
         MoveToDead(zonesActive[i]);
         for(int j = i; j < ArraySize(zonesActive) - 1; ++j)
            zonesActive[j] = zonesActive[j + 1];
         ArrayResize(zonesActive, ArraySize(zonesActive) - 1);
      }
   }
}

// prune zones that are older than the current lookback window (so we never show before window)
void PruneZonesOutsideWindow(const datetime oldestAllowedTime)
{
   // Active
   for(int i = ArraySize(zonesActive) - 1; i >= 0; --i)
   {
      if(zonesActive[i].tStart < oldestAllowedTime)
      {
         DeleteObjectExact(zonesActive[i].name);
         for(int j = i; j < ArraySize(zonesActive) - 1; ++j) zonesActive[j] = zonesActive[j + 1];
         ArrayResize(zonesActive, ArraySize(zonesActive) - 1);
      }
   }
   // Dead
   for(int i = ArraySize(zonesDead) - 1; i >= 0; --i)
   {
      if(zonesDead[i].tStart < oldestAllowedTime)
      {
         DeleteObjectExact(zonesDead[i].name);
         for(int j = i; j < ArraySize(zonesDead) - 1; ++j) zonesDead[j] = zonesDead[j + 1];
         ArrayResize(zonesDead, ArraySize(zonesDead) - 1);
      }
   }
}

//------------------------- Lifecycle update --------------------------
void UpdateZoneLifecycleOnNewClose(Zone &z,
                                   const datetime &time[],
                                   const double &high[], const double &low[],
                                   const int iCls, const int iCur)
{
   if(z.status == Eliminated)
      return;

   // break check at newest closed candle
   if(z.type == Demand)
   {
      if(low[iCls] < z.distal)
      {
         z.status = Eliminated;
         z.tEnd   = time[iCls];
         return;
      }
   }
   else
   {
      if(high[iCls] > z.distal)
      {
         z.status = Eliminated;
         z.tEnd   = time[iCls];
         return;
      }
   }

   // extend to now
   z.tEnd = (datetime)(time[iCur] + PeriodSeconds(_Period));
}

//------------------------- Drawing (single filled rectangle) ---------
color ZoneColorFor(const Zone &z)
{
   if(z.status == Eliminated) return InpEliminatedColor;
   if(z.status == Confirmed)  return InpConfirmedColor;

   // Potential by type
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
   if(!InpShowEliminated && z.status == Eliminated)
   {
      DeleteObjectExact(z.name);
      return true;
   }

   const long chart_id = 0;

   // create or update the rectangle
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
   ObjectSetInteger(chart_id, z.name, OBJPROP_FILL, true);     // filled rectangle
   ObjectSetInteger(chart_id, z.name, OBJPROP_BACK, true);

   // description includes exact candle time for base start + legout
   string desc =
      z.tag + " | " +
      (z.type==Demand ? "Demand" : "Supply") + " | " +
      (z.status==Potential ? "Potential" : (z.status==Confirmed ? "Confirmed" : "Eliminated")) +
      " | base: " + TimeToString(z.tStart, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +
      " | legOut: " + TimeToString(z.tLegOut, TIME_DATE|TIME_MINUTES|TIME_SECONDS) +
      " | end: "  + TimeToString(z.tEnd, TIME_DATE|TIME_MINUTES|TIME_SECONDS);

   ObjectSetString(chart_id, z.name, OBJPROP_TEXT, desc);

   return true;
}

//------------------------- Sorting new zones by time (oldest->newest)
void SortZonesByLegOutTimeAsc(Zone &arr[])
{
   int n = ArraySize(arr);
   for(int i = 1; i < n; ++i)
   {
      Zone key = arr[i];
      int j = i - 1;
      while(j >= 0 && arr[j].tLegOut > key.tLegOut)
      {
         arr[j + 1] = arr[j];
         j--;
      }
      arr[j + 1] = key;
   }
}

//------------------------- Indicator lifecycle -----------------------
int OnInit()
{
   DebugPrint("AlfonsoZones: OnInit()");
   IndicatorSetString(INDICATOR_SHORTNAME, "AlfonsoZones (Step5)");

   ArraySetAsSeries(g_dummyBuffer, true);
   SetIndexBuffer(0, g_dummyBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);

   ArrayResize(zonesActive, 0);
   ArrayResize(zonesDead, 0);
   g_lastClosedTime = 0;

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DebugPrint("AlfonsoZones: OnDeinit()");
   DeleteObjectsByPrefix(MakeBasePrefix());
}

//------------------------- Main calculation --------------------------
int OnCalculate(
   const int rates_total,
   const int prev_calculated,
   const datetime &time[],
   const double &open[],
   const double &high[],
   const double &low[],
   const double &close[],
   const long &tick_volume[],
   const long &volume[],
   const int &spread[]
)
{
   if(rates_total < 2) return 0;
   g_dummyBuffer[0] = EMPTY_VALUE;

   const bool series = IsSeriesOrder(time, rates_total);

   int winOldest=0, winNewest=0;
   if(!ComputeWindow(time, rates_total, InpLookbackBars, winOldest, winNewest))
      return rates_total;

   int iCur = IndexCurrentBar(time, rates_total);
   int iCls = IndexLastClosedBar(time, rates_total);
   if(!IndexInWindow(iCls, winOldest, winNewest, series))
      return rates_total;

   // enforce "don't draw before window"
   datetime oldestAllowed = time[winOldest];
   PruneZonesOutsideWindow(oldestAllowed);

   bool newClosedBar = (time[iCls] != g_lastClosedTime);
   if(newClosedBar) g_lastClosedTime = time[iCls];

   if(newClosedBar)
   {
      // 1) Update existing active zones (break/extend) using newly closed candle
      for(int i = ArraySize(zonesActive) - 1; i >= 0; --i)
         UpdateZoneLifecycleOnNewClose(zonesActive[i], time, high, low, iCls, iCur);

      // Move newly eliminated to dead
      SweepEliminatedFromActive();

      // 2) Detect new zones from scan window
      if(InpDrawZones)
      {
         int scan = InpScanPatternBars; if(scan < 10) scan = 10;

         Zone newFound[];
         ArrayResize(newFound, 0);

         for(int k = 0; k < scan && ArraySize(newFound) < InpMaxZonesProcess; ++k)
         {
            int legOut = OlderIndex(iCls, k, series);
            if(!IndexInWindow(legOut, winOldest, winNewest, series))
               break;

            Zone z;
            if(!BuildZoneFromLegOut(time, open, high, low, close,
                                    legOut, iCls, iCur, series, winOldest, winNewest,
                                    z))
               continue;

            // ignore zones older than window (extra safety)
            if(z.tStart < oldestAllowed)
               continue;

            // skip if already known
            if(FindZoneByName(z.name, zonesActive) >= 0) continue;
            if(FindZoneByName(z.name, zonesDead)   >= 0) continue;

            int n = ArraySize(newFound);
            ArrayResize(newFound, n + 1);
            newFound[n] = z;
         }

         // IMPORTANT FIX: process zones oldest->newest so confirmation works
         SortZonesByLegOutTimeAsc(newFound);

         // 3) For each new zone in chronological order:
         //    - confirm it if its leg-out move takes out opposing active zones
         //    - add it to active/dead
         for(int i = 0; i < ArraySize(newFound); ++i)
         {
            // confirm only if it's not already eliminated
            ApplyConfirmationOnNewZone(newFound[i], time, high, low, series, winOldest, winNewest, iCls);

            if(newFound[i].status == Eliminated)
            {
               MoveToDead(newFound[i]);
            }
            else
            {
               int n = ArraySize(zonesActive);
               ArrayResize(zonesActive, n + 1);
               zonesActive[n] = newFound[i];
            }

            // opposing zones may have been eliminated by confirmation
            SweepEliminatedFromActive();
         }
      }

      // 4) Draw/update zones
      for(int i = 0; i < ArraySize(zonesActive); ++i)
         DrawZone(zonesActive[i]);

      if(InpShowEliminated)
      {
         for(int i = 0; i < ArraySize(zonesDead); ++i)
            DrawZone(zonesDead[i]);
      }
      else
      {
         for(int i = 0; i < ArraySize(zonesDead); ++i)
            DeleteObjectExact(zonesDead[i].name);
      }
   }
   else
   {
      // same-bar ticks: extend active zones visually to now (cheap updates)
      for(int i = 0; i < ArraySize(zonesActive); ++i)
      {
         if(zonesActive[i].status != Eliminated)
         {
            zonesActive[i].tEnd = (datetime)(time[iCur] + PeriodSeconds(_Period));
            DrawZone(zonesActive[i]);
         }
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+
