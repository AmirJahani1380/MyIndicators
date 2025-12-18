//+------------------------------------------------------------------+
//|                                                   AlfonsoZones   |
//|   Step 6 FIX: Full historical replay (oldest->newest)            |
//|   - Rebuilds zones + TL breaks candle-by-candle on chart load     |
//|   - Potential zones are NOT used for trend/takeout logic          |
//|   - Confirmed zones are "real" zones                              |
//|   - TL breaks require full OHLC across line (no touch)            |
//|   - TL break confirms: touched-base zones + extreme-distal zone   |
//|   - Takeout confirms: when a CONFIRMED zone breaks, the closest   |
//|     opposing POTENTIAL (by proximal distance) becomes Confirmed   |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots   1
#property indicator_buffers 1
#property indicator_type1   DRAW_NONE
#property indicator_label1  ""

//------------------------- Inputs -----------------------------------
// Zone engine
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

// Detection
input int    InpMaxZonesProcess        = 140;  // safety cap during rebuild

// Confirm by trendline break: move window after swing endpoint
input int    InpConfirmLookaheadBars   = 300; // (kept; not used for scanning anymore)

// Display toggles
input bool   InpShowPotential   = true;
input bool   InpShowConfirmed   = true;
input bool   InpShowEliminated  = true;

// Zone colors (border == fill)
input color  InpPotentialDemandColor = clrMintCream;
input color  InpPotentialSupplyColor = clrLavenderBlush;
input color  InpEliminatedColor      = clrOrangeRed;
input color  InpConfirmedColor       = clrMidnightBlue;

// Border widths
input int    InpWidthPotential   = 1;
input int    InpWidthConfirmed   = 2;
input int    InpWidthEliminated  = 1;

//----------------- Trendline inputs (your code) ---------------------
input int    SwingPeriod    = 3;
input int    CandleWindow   = 200;
input int    ATRPeriod      = 14;
input int    LineStyle      = 2;        // 0..4
input int    LineWidth      = 1;        // >=1
input color  LineColor      = clrSilver;
input bool   OnlySwingHigh  = false;
input bool   OnlySwingLow   = false;

// Angle filtering
input bool   AngleBased     = false;
input double MinAngle       = 0.01;     // inclusive
input double MaxAngle       = 1.0;      // inclusive

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
   datetime   tBaseEnd;     // time[baseEnd]
   datetime   tEnd;         // now unless broken, else breaker candle time
   datetime   tLegOut;      // time[legOut]

   string     name;         // unique object name
   string     tag;          // DBR/RBD/RBR/DBD
};

struct TLInfo
{
   bool     has;
   datetime t1, t2;
   double   p1, p2;
   int      swing_ns;     // newer swing idx in NS space
   datetime swingTime;    // time at newer swing
};

//------------------------- Storage ----------------------------------
double   g_dummyBuffer[];
datetime g_lastClosedTime = 0;

Zone zonesActive[]; // Potential + Confirmed
Zone zonesDead[];   // Eliminated history

// last processed TL-break times (to avoid reprocessing)
datetime g_high_lastBreak = 0;
datetime g_low_lastBreak  = 0;

// ATR handle for angle filtering (optional)
int g_atrHandle = INVALID_HANDLE;

//------------------------- Utilities --------------------------------
void DebugPrint(const string msg){ if(InpDebug) Print(msg); }

bool StartsWith(const string s, const string prefix)
{
   int plen = (int)StringLen(prefix);
   if(plen <= 0) return false;
   if((int)StringLen(s) < plen) return false;
   return (StringSubstr(s, 0, plen) == prefix);
}

string MakeZonePrefix()
{
   return (InpObjPrefix + _Symbol + "_" + IntegerToString((int)_Period) + "_");
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

// Map non-series index (0 oldest..rates_total-1 newest) to actual array index
int MapNS2Arr(const int ns_i, const int rates_total, const bool seriesArrays)
{
   return (seriesArrays ? (rates_total - 1 - ns_i) : ns_i);
}

// Map array index to NS index
int MapArr2NS(const int arr_i, const int rates_total, const bool seriesArrays)
{
   return (seriesArrays ? (rates_total - 1 - arr_i) : arr_i);
}

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
   outZone.tBaseEnd  = time[baseEnd];
   outZone.tLegOut   = time[legOut];
   outZone.tEnd      = (datetime)(time[iCur] + PeriodSeconds(_Period)); // extend to "now" at this step

   outZone.tag       = tag;
   outZone.name      = MakeZonePrefix() + "ZONE_" + tag + "_" + IntegerToString((long)outZone.tLegOut);

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

// prune zones older than the window (to avoid drawing ancient zones)
void PruneZonesOutsideWindow(const datetime oldestAllowedTime)
{
   for(int i = ArraySize(zonesActive) - 1; i >= 0; --i)
   {
      if(zonesActive[i].tStart < oldestAllowedTime)
      {
         DeleteObjectExact(zonesActive[i].name);
         for(int j = i; j < ArraySize(zonesActive) - 1; ++j) zonesActive[j] = zonesActive[j + 1];
         ArrayResize(zonesActive, ArraySize(zonesActive) - 1);
      }
   }
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

//------------------------- Takeout responsibility --------------------
// When a CONFIRMED zone is eliminated, the responsible zone is the closest opposing zone by
// price distance using proximal line (closest to breaker price).
int FindResponsibleOpposingZone(const Zone &brokenZone,
                                const datetime breakTime,
                                const double breakerPrice)
{
   int bestIdx = -1;
   double bestDist = DBL_MAX;

   for(int i=0; i<ArraySize(zonesActive); ++i)
   {
      if(zonesActive[i].status == Eliminated) continue;
      if(zonesActive[i].type == brokenZone.type) continue; // opposing only
      if(zonesActive[i].tStart > breakTime) continue;      // must exist by break time

      // Direction sanity filter:
      if(brokenZone.type == Demand)
      {
         if(zonesActive[i].type != Supply) continue;
         if(zonesActive[i].proximal <= breakerPrice) continue;
      }
      else
      {
         if(zonesActive[i].type != Demand) continue;
         if(zonesActive[i].proximal >= breakerPrice) continue;
      }

      double d = MathAbs(zonesActive[i].proximal - breakerPrice);
      if(d < bestDist)
      {
         bestDist = d;
         bestIdx = i;
      }
   }

   return bestIdx;
}

//------------------------- Lifecycle update (Eliminate + credit) -----
void UpdateZoneLifecycleOnClose(Zone &z,
                                const datetime &time[],
                                const double &high[], const double &low[],
                                const int iCls, const int iCur)
{
   if(z.status == Eliminated)
      return;

   bool broken = false;
   double breakerPrice = 0.0;

   if(z.type == Demand)
   {
      if(low[iCls] < z.distal)
      {
         broken = true;
         breakerPrice = low[iCls];
      }
   }
   else
   {
      if(high[iCls] > z.distal)
      {
         broken = true;
         breakerPrice = high[iCls];
      }
   }

   if(broken)
   {
      ZoneStatus prevStatus = z.status;
      z.status = Eliminated;
      z.tEnd   = time[iCls];

      // Only CONFIRMED zones count for takeout/credit.
      if(prevStatus == Confirmed)
      {
         int respIdx = FindResponsibleOpposingZone(z, time[iCls], breakerPrice);
         if(respIdx >= 0)
         {
            if(zonesActive[respIdx].status == Potential)
            {
               zonesActive[respIdx].status = Confirmed;
               if(InpDebug)
               {
                  PrintFormat("CONFIRM_BY_TAKEOUT: %s confirmed because it broke confirmed %s at %s",
                              zonesActive[respIdx].name,
                              z.name,
                              TimeToString(time[iCls], TIME_DATE|TIME_MINUTES|TIME_SECONDS));
               }
            }
         }
      }
      return;
   }

   // Not broken -> extend to "now" at this step
   z.tEnd = (datetime)(time[iCur] + PeriodSeconds(_Period));
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

// Swing detection in NON-SERIES index space, mapped to actual arrays
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

bool GetATRAtArrIndex(const int arrIndex, double &atrVal)
{
   atrVal = 0.0;
   if(g_atrHandle == INVALID_HANDLE) return false;
   double buf[];
   if(CopyBuffer(g_atrHandle, 0, arrIndex, 1, buf) != 1) return false;
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

// Compute trendline endpoints at a given historical "end" (ns_end = last closed in NS space).
// No drawing here (used for historical replay and per-bar break checks).
void ComputeTrendlineAt(const datetime &t[],
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

   int p = MathMax(1, SwingPeriod);
   if(rates_total < (2*p + 1)) return;

   // mimic your rule: last closed is ns_end, so i_end excludes last p bars
   int i_end   = ns_end - p;
   int i_start = MathMax(p, ns_end - CandleWindow - p);
   if(i_end < i_start) return;

   int newest=-1, second=-1;
   double px_new=0.0, px_old=0.0;

   for(int i = i_end; i >= i_start; --i)
   {
      bool ok = isHigh ? IsSwingHigh_NS(h, i, p, rates_total, seriesArrays)
                       : IsSwingLow_NS(l, i, p, rates_total, seriesArrays);

      if(ok)
      {
         int ai = MapNS2Arr(i, rates_total, seriesArrays);
         double price = isHigh ? h[ai] : l[ai];
         ConsiderPoint(i, price, newest, px_new, second, px_old);
         if(newest >= 0 && second >= 0) break; // nearest pair is enough
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

   // Angle filter (optional)
   if(AngleBased)
   {
      int anew = MapNS2Arr(newer_idx, rates_total, seriesArrays);
      double atr_val = 0.0;
      if(!GetATRAtArrIndex(anew, atr_val)) return;
      int bars = newer_idx - older_idx;
      if(!AnglePass_ByATR(older_px, newer_px, bars, atr_val)) return;
   }

   int aold = MapNS2Arr(older_idx, rates_total, seriesArrays);
   int anew = MapNS2Arr(newer_idx, rates_total, seriesArrays);

   out.has = true;
   out.t1 = t[aold]; out.p1 = older_px;
   out.t2 = t[anew]; out.p2 = newer_px;
   out.swing_ns = newer_idx;
   out.swingTime = t[anew];
}

void DrawTrendlineObject(const string name,
                         datetime t1,double p1, datetime t2,double p2,
                         color clr, ENUM_LINE_STYLE style, int width)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);

   ObjectMove(0, name, 0, t1, p1);
   ObjectMove(0, name, 1, t2, p2);

   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_STYLE, (int)style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, MathMax(1, width));
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

// Draw current trendlines (only once per tick set; used for visualization)
void DrawCurrentTrendlines(const datetime &t[],
                           const double &h[],
                           const double &l[],
                           const int rates_total,
                           const bool seriesArrays,
                           const int iClsArr)
{
   int ns_end = MapArr2NS(iClsArr, rates_total, seriesArrays);

   TLInfo hi, lo;
   ComputeTrendlineAt(t, h, l, rates_total, seriesArrays, ns_end, true,  hi);
   ComputeTrendlineAt(t, h, l, rates_total, seriesArrays, ns_end, false, lo);

   int s = MathMax(0, MathMin(4, LineStyle));
   string nameHigh = ObjName(true);
   string nameLow  = ObjName(false);

   if((OnlySwingHigh || (!OnlySwingHigh && !OnlySwingLow) || (OnlySwingHigh && OnlySwingLow)) && hi.has)
      DrawTrendlineObject(nameHigh, hi.t1, hi.p1, hi.t2, hi.p2, LineColor, (ENUM_LINE_STYLE)s, LineWidth);
   else
      ObjectDelete(0, nameHigh);

   if((OnlySwingLow || (!OnlySwingHigh && !OnlySwingLow) || (OnlySwingHigh && OnlySwingLow)) && lo.has)
      DrawTrendlineObject(nameLow, lo.t1, lo.p1, lo.t2, lo.p2, LineColor, (ENUM_LINE_STYLE)s, LineWidth);
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

bool FullOHLC_AboveLine(const datetime &time[], const double &open[], const double &high[],
                        const double &low[], const double &close[],
                        const int i, datetime t1,double p1, datetime t2,double p2)
{
   double lp = LinePriceAt(time[i], t1, p1, t2, p2);
   double eps = _Point * 0.5;
   return (open[i]  > lp + eps &&
           high[i]  > lp + eps &&
           low[i]   > lp + eps &&
           close[i] > lp + eps);
}

bool FullOHLC_BelowLine(const datetime &time[], const double &open[], const double &high[],
                        const double &low[], const double &close[],
                        const int i, datetime t1,double p1, datetime t2,double p2)
{
   double lp = LinePriceAt(time[i], t1, p1, t2, p2);
   double eps = _Point * 0.5;
   return (open[i]  < lp - eps &&
           high[i]  < lp - eps &&
           low[i]   < lp - eps &&
           close[i] < lp - eps);
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

// breakOnHighLine=true => confirms Demand, else confirms Supply
void ConfirmZonesByTLBreak(bool breakOnHighLine,
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

   // pick candidates whose BASE interval intersects [a..b]
   for(int i=0; i<ArraySize(zonesActive); ++i)
   {
      if(zonesActive[i].status != Potential) continue;
      if(zonesActive[i].type != toConfirm) continue;

      // interval intersection
      if(zonesActive[i].tStart > b) continue;
      if(zonesActive[i].tBaseEnd < a) continue;

      if(toConfirm == Demand)
      {
         if(zonesActive[i].distal < extremeDistal)
         {
            extremeDistal = zonesActive[i].distal;
            extremeIdx = i;
         }
      }
      else
      {
         if(zonesActive[i].distal > extremeDistal)
         {
            extremeDistal = zonesActive[i].distal;
            extremeIdx = i;
         }
      }
   }

   // confirm all touched zones in interval
   for(int i=0; i<ArraySize(zonesActive); ++i)
   {
      if(zonesActive[i].status != Potential) continue;
      if(zonesActive[i].type != toConfirm) continue;
      if(zonesActive[i].tStart > b) continue;
      if(zonesActive[i].tBaseEnd < a) continue;

      if(ZoneTouchesLineWick(zonesActive[i], time, high, low, series, t1,p1,t2,p2))
      {
         zonesActive[i].status = Confirmed;
         if(InpDebug)
         {
            PrintFormat("CONFIRM_BY_TL_TOUCH: %s confirmed at break %s",
                        zonesActive[i].name,
                        TimeToString(breakTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS));
         }
      }
   }

   // confirm extreme-distal zone
   if(extremeIdx >= 0 && zonesActive[extremeIdx].status == Potential)
   {
      zonesActive[extremeIdx].status = Confirmed;
      if(InpDebug)
      {
         PrintFormat("CONFIRM_BY_TL_EXTREME: %s confirmed (distal extreme) at break %s",
                     zonesActive[extremeIdx].name,
                     TimeToString(breakTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS));
      }
   }
}

bool CheckAndProcessTLBreakAtBar(const bool breakOnHighLine,
                                const TLInfo &tl,
                                const datetime &time[],
                                const double &open[],
                                const double &high[],
                                const double &low[],
                                const double &close[],
                                const int barIdx,
                                const bool series,
                                datetime &lastBreakStore)
{
   if(!tl.has) return false;

   // must be after the newer swing endpoint
   if(time[barIdx] <= tl.swingTime) return false;

   // don't reprocess
   if(time[barIdx] <= lastBreakStore) return false;

   bool isBreak = false;
   if(breakOnHighLine)
      isBreak = FullOHLC_AboveLine(time, open, high, low, close, barIdx, tl.t1,tl.p1,tl.t2,tl.p2);
   else
      isBreak = FullOHLC_BelowLine(time, open, high, low, close, barIdx, tl.t1,tl.p1,tl.t2,tl.p2);

   if(!isBreak) return false;

   lastBreakStore = time[barIdx];

   ConfirmZonesByTLBreak(breakOnHighLine,
                         tl.swingTime, time[barIdx],
                         time, high, low, series,
                         tl.t1,tl.p1,tl.t2,tl.p2);

   return true;
}

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

   // OBJ_RECTANGLE often shows tooltip best
   ObjectSetString(chart_id, z.name, OBJPROP_TOOLTIP, desc);

   return true;
}

//------------------------- Historical rebuild (key fix) --------------
void ResetAllState()
{
   DeleteObjectsByPrefix(MakeZonePrefix());
   DeleteAllLines();

   ArrayResize(zonesActive, 0);
   ArrayResize(zonesDead, 0);

   g_lastClosedTime = 0;
   g_high_lastBreak = 0;
   g_low_lastBreak  = 0;
}

void RebuildFromHistory(const int rates_total,
                        const datetime &time[],
                        const double &open[],
                        const double &high[],
                        const double &low[],
                        const double &close[],
                        const bool series,
                        const int winOldest,
                        const int winNewest)
{
   ResetAllState();

   int iCurArr = IndexCurrentBar(time, rates_total);
   int iClsArr = IndexLastClosedBar(time, rates_total);

   // replay only inside the window
   int ns_winOldest = MapArr2NS(winOldest, rates_total, series);
   int ns_iCls      = MapArr2NS(iClsArr,  rates_total, series);

   // safety: avoid insane work
   int created = 0;

   // start a bit later so swing logic has room
   int warmup = MathMax(2*SwingPeriod + 2, InpAvgRangeLen + 2);
   int ns_start = MathMax(ns_winOldest, warmup);

   for(int ns = ns_start; ns <= ns_iCls; ++ns)
   {
      int iCls = MapNS2Arr(ns, rates_total, series);
      int iCur = iCls;

      // 1) Detect zone from THIS candle as legOut (no backward scanning; candle-by-candle)
      if(created < InpMaxZonesProcess)
      {
         Zone z;
         if(BuildZoneFromLegOut(time, open, high, low, close,
                                iCls, iCls, iCur, series, winOldest, winNewest,
                                z))
         {
            if(FindZoneByName(z.name, zonesActive) < 0 &&
               FindZoneByName(z.name, zonesDead)   < 0)
            {
               int n = ArraySize(zonesActive);
               ArrayResize(zonesActive, n + 1);
               zonesActive[n] = z;
               created++;
            }
         }
      }

      // 2) Update lifecycle on this close (eliminate + takeout credit)
      for(int i = ArraySize(zonesActive) - 1; i >= 0; --i)
         UpdateZoneLifecycleOnClose(zonesActive[i], time, high, low, iCls, iCur);

      SweepEliminatedFromActive();

      // 3) Compute trendlines at THIS historical point and process break on THIS candle
      TLInfo tlHigh, tlLow;
      ComputeTrendlineAt(time, high, low, rates_total, series, ns, true,  tlHigh);
      ComputeTrendlineAt(time, high, low, rates_total, series, ns, false, tlLow);

      // HIGH TL break up => confirm Demand
      if(!OnlySwingLow) // respect settings loosely
         CheckAndProcessTLBreakAtBar(true, tlHigh, time, open, high, low, close, iCls, series, g_high_lastBreak);

      // LOW TL break down => confirm Supply
      if(!OnlySwingHigh)
         CheckAndProcessTLBreakAtBar(false, tlLow, time, open, high, low, close, iCls, series, g_low_lastBreak);
   }

   // set last closed time to prevent double-processing
   g_lastClosedTime = time[iClsArr];

   // Draw zones once after rebuild
   for(int i=0; i<ArraySize(zonesActive); ++i) DrawZone(zonesActive[i]);
   for(int i=0; i<ArraySize(zonesDead);   ++i) DrawZone(zonesDead[i]);

   // Draw current trendlines for visibility
   DrawCurrentTrendlines(time, high, low, rates_total, series, iClsArr);
}

//------------------------- Indicator lifecycle -----------------------
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "AlfonsoZones (Step6 FIX Replay)");

   ArraySetAsSeries(g_dummyBuffer, true);
   SetIndexBuffer(0, g_dummyBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);

   ArrayResize(zonesActive, 0);
   ArrayResize(zonesDead, 0);

   g_lastClosedTime = 0;
   g_high_lastBreak = 0;
   g_low_lastBreak  = 0;

   DeleteAllLines();

   // ATR handle for optional angle filter
   g_atrHandle = iATR(_Symbol, _Period, MathMax(1, ATRPeriod));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteObjectsByPrefix(MakeZonePrefix());
   DeleteAllLines();

   if(g_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
   }
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
   if(rates_total < 10) return 0;
   g_dummyBuffer[0] = EMPTY_VALUE;

   const bool series = IsSeriesOrder(time, rates_total);

   int winOldest=0, winNewest=0;
   if(!ComputeWindow(time, rates_total, InpLookbackBars, winOldest, winNewest))
      return rates_total;

   int iCur = IndexCurrentBar(time, rates_total);
   int iCls = IndexLastClosedBar(time, rates_total);
   if(!IndexInWindow(iCls, winOldest, winNewest, series))
      return rates_total;

   // On first load / refresh: full replay from oldest->newest
   if(prev_calculated == 0)
   {
      RebuildFromHistory(rates_total, time, open, high, low, close, series, winOldest, winNewest);
      return rates_total;
   }

   // Normal live update (bar-by-bar)
   datetime oldestAllowed = time[winOldest];
   PruneZonesOutsideWindow(oldestAllowed);

   bool newClosedBar = (time[iCls] != g_lastClosedTime);
   if(newClosedBar)
   {
      g_lastClosedTime = time[iCls];

      // 1) Detect zone from THIS candle as legOut
      Zone z;
      if(BuildZoneFromLegOut(time, open, high, low, close,
                             iCls, iCls, iCur, series, winOldest, winNewest,
                             z))
      {
         if(z.tStart >= oldestAllowed &&
            FindZoneByName(z.name, zonesActive) < 0 &&
            FindZoneByName(z.name, zonesDead)   < 0)
         {
            int n = ArraySize(zonesActive);
            ArrayResize(zonesActive, n + 1);
            zonesActive[n] = z;
         }
      }

      // 2) Lifecycle update (eliminate + takeout credit)
      for(int i = ArraySize(zonesActive) - 1; i >= 0; --i)
         UpdateZoneLifecycleOnClose(zonesActive[i], time, high, low, iCls, iCur);

      SweepEliminatedFromActive();

      // 3) Compute current TLs and check break on THIS close candle
      int ns_end = MapArr2NS(iCls, rates_total, series);

      TLInfo tlHigh, tlLow;
      ComputeTrendlineAt(time, high, low, rates_total, series, ns_end, true,  tlHigh);
      ComputeTrendlineAt(time, high, low, rates_total, series, ns_end, false, tlLow);

      if(!OnlySwingLow)
         CheckAndProcessTLBreakAtBar(true, tlHigh, time, open, high, low, close, iCls, series, g_high_lastBreak);

      if(!OnlySwingHigh)
         CheckAndProcessTLBreakAtBar(false, tlLow, time, open, high, low, close, iCls, series, g_low_lastBreak);

      // Draw current TL objects for visibility
      DrawCurrentTrendlines(time, high, low, rates_total, series, iCls);

      // 4) Draw zones
      for(int i=0; i<ArraySize(zonesActive); ++i) DrawZone(zonesActive[i]);
      for(int i=0; i<ArraySize(zonesDead);   ++i) DrawZone(zonesDead[i]);
   }
   else
   {
      // Same bar ticks: just extend active zones visually
      for(int i=0; i<ArraySize(zonesActive); ++i)
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
