//+------------------------------------------------------------------+
//|                                                   SDZones_Shell  |
//|   Step 3: Base detection (1..6 basing candles + optional patterns)|
//|   Keeps Step 1 TEST zone + Step 2 candle helpers + debug bases    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// Dummy plot to avoid "no indicator plot defined"
#property indicator_plots   1
#property indicator_buffers 1
#property indicator_type1   DRAW_NONE
#property indicator_label1  ""

//------------------------- Inputs -----------------------------------
input int    InpLookbackBars      = 2000;   // Only check within this window
input bool   InpDebug             = true;   // Print debug logs
input string InpObjPrefix         = "SDZ_"; // Objects prefix (cleanup safety)

// Step 2 thresholds
input double InpBasingBodyPctMax  = 0.50;   // basing if body/range <= 50%
input double InpERCBodyPctMin     = 0.60;   // ERC if body/range >= 60%
input double InpCloseNearPct      = 0.20;   // close near hi/lo if within 20% of range
input int    InpAvgRangeLen       = 20;     // for "wide" check
input double InpWideMult          = 1.50;   // wide if range >= avgRange * mult
input bool   InpMarkDebugBars     = false;  // optional on-chart markers
input int    InpMarkBarsCount     = 50;     // how many recent closed bars to mark

// Step 3 base rules
input int    InpBaseMinBars               = 1;   // base min candles
input int    InpBaseMaxBars               = 6;   // base max candles
input bool   InpAllowSingleCandleBase     = true;
input bool   InpBaseUseEngulfPierceHarami = true;

// Step 3 debug drawing
input int    InpScanLegOutBars    = 200;  // scan last N closed bars for impulses
input int    InpMaxDebugBases     = 20;   // max base rectangles drawn

//------------------------- Types ------------------------------------
enum ZoneType   { Demand = 0, Supply = 1 };
enum ZoneStatus { Potential = 0, Confirmed = 1, Eliminated = 2 };

struct Zone
{
   ZoneType   type;
   ZoneStatus status;

   int        baseStart;
   int        baseEnd;

   double     proximal;
   double     distal;

   datetime   tStart;
   datetime   tEnd;

   // Base name for the zone (we'll create 2 objects from it: _F and _B)
   string     name;
};

//------------------------- Storage ----------------------------------
Zone   zones[];
double g_dummyBuffer[];
datetime g_lastPrintedBarTime = 0; // to avoid log spam

//------------------------- Utilities --------------------------------
void DebugPrint(const string msg)
{
   if(InpDebug) Print(msg);
}

string MakeBasePrefix()
{
   // Prefix + Symbol + "_" + Period + "_" + uniqueId
   return (InpObjPrefix + _Symbol + "_" + IntegerToString((int)_Period) + "_");
}

bool StartsWith(const string s, const string prefix)
{
   int plen = (int)StringLen(prefix);
   if(plen <= 0) return false;
   if((int)StringLen(s) < plen) return false;
   return (StringSubstr(s, 0, plen) == prefix);
}

//------------------------- Indexing helpers --------------------------
// In OnCalculate, arrays may be "series" (newest at 0) or chronological (oldest at 0).
bool IsSeriesOrder(const datetime &time[], const int rates_total)
{
   if(rates_total < 2) return true;
   return (time[0] > time[rates_total - 1]);
}

int IndexCurrentBar(const datetime &time[], const int rates_total)
{
   return IsSeriesOrder(time, rates_total) ? 0 : (rates_total - 1);
}

int IndexLastClosedBar(const datetime &time[], const int rates_total)
{
   return IsSeriesOrder(time, rates_total) ? 1 : (rates_total - 2);
}

// Compute lookback window bounds [winOldest .. winNewest] in array index space.
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
      winOldest = lb - 1;                 // include [0 .. lb-1]
   }
   else
   {
      winNewest = rates_total - 1;
      winOldest = rates_total - lb;       // include [rates_total-lb .. rates_total-1]
      if(winOldest < 0) winOldest = 0;
   }
   return true;
}

bool IndexInWindow(const int idx, const int winOldest, const int winNewest, const bool series)
{
   if(series)
      return (idx >= winNewest && idx <= winOldest);
   else
      return (idx >= winOldest && idx <= winNewest);
}

// Get an "older" index offset by k bars from idx
int OlderIndex(const int idx, const int k, const bool series)
{
   return (series ? (idx + k) : (idx - k));
}

//------------------------- Zone API ---------------------------------
int ZoneAdd(Zone &z)
{
   int n = ArraySize(zones);
   ArrayResize(zones, n + 1);
   zones[n] = z;
   return n;
}

bool RectCreateOrUpdate(const string objName,
                        const datetime t1, const double p1,
                        const datetime t2, const double p2,
                        const color col,
                        const bool fill,
                        const string description_text)
{
   const long chart_id = 0;

   double top = MathMax(p1, p2);
   double bot = MathMin(p1, p2);

   if(MathAbs(top - bot) < (_Point * 2.0))
      top = bot + (_Point * 10.0);

   datetime tt1 = t1;
   datetime tt2 = t2;
   if(tt2 <= tt1)
      tt2 = tt1 + (datetime)PeriodSeconds(_Period);

   if(ObjectFind(chart_id, objName) < 0)
   {
      if(!ObjectCreate(chart_id, objName, OBJ_RECTANGLE, 0, tt1, top, tt2, bot))
      {
         if(InpDebug) PrintFormat("ObjectCreate failed for '%s'. Error=%d", objName, GetLastError());
         return false;
      }
   }
   else
   {
      ObjectMove(chart_id, objName, 0, tt1, top);
      ObjectMove(chart_id, objName, 1, tt2, bot);
   }

   ObjectSetInteger(chart_id, objName, OBJPROP_COLOR, (long)col);
   ObjectSetInteger(chart_id, objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(chart_id, objName, OBJPROP_WIDTH, 1);

   ObjectSetInteger(chart_id, objName, OBJPROP_BACK, true);
   ObjectSetInteger(chart_id, objName, OBJPROP_FILL, fill);

   ObjectSetInteger(chart_id, objName, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(chart_id, objName, OBJPROP_SELECTED, false);

   ObjectSetString(chart_id, objName, OBJPROP_TEXT, description_text);

   return true;
}

bool ZoneObjectCreateOrUpdate(const Zone &z)
{
   string nameFill   = z.name + "_F";
   string nameBorder = z.name + "_B";

   color base_col = (z.type == Demand ? clrLime : clrTomato);
   color fill_col = (color)ColorToARGB(base_col, 40);

   string ts   = TimeToString(z.tStart, TIME_DATE | TIME_MINUTES | TIME_SECONDS);
   string desc = "Candle time: " + ts;

   bool ok1 = RectCreateOrUpdate(nameFill,   z.tStart, z.proximal, z.tEnd, z.distal, fill_col, true,  desc);
   bool ok2 = RectCreateOrUpdate(nameBorder, z.tStart, z.proximal, z.tEnd, z.distal, base_col, false, desc);

   return (ok1 && ok2);
}

void DeleteObjectsByPrefix(const string pfx)
{
   const long chart_id = 0;
   int total = ObjectsTotal(chart_id);
   for(int i = total - 1; i >= 0; --i)
   {
      string name = ObjectName(chart_id, i);
      if(StartsWith(name, pfx))
         ObjectDelete(chart_id, name);
   }
}

void ZonesClearAll()
{
   ArrayResize(zones, 0);
   DeleteObjectsByPrefix(MakeBasePrefix());
}

//------------------------- Step 2: Candle helpers --------------------
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

bool IsBull(const double &open[], const double &close[], const int i) { return close[i] > open[i]; }
bool IsBear(const double &open[], const double &close[], const int i) { return close[i] < open[i]; }

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
   int L = len;
   if(L < 1) L = 1;

   double sum = 0.0;
   int    cnt = 0;

   for(int k = 0; k < L; ++k)
   {
      int idx = OlderIndex(i, k, series);
      if(!IndexInWindow(idx, winOldest, winNewest, series))
         break;

      sum += CandleRange(high, low, idx);
      cnt++;
   }

   if(cnt <= 0)
      return CandleRange(high, low, i);

   return sum / (double)cnt;
}

bool IsWide(const double &high[], const double &low[], const int i,
            const bool series, const int winOldest, const int winNewest)
{
   double r   = CandleRange(high, low, i);
   double avg = AvgRange(high, low, i, InpAvgRangeLen, series, winOldest, winNewest);
   return (avg > 0.0 && r >= avg * InpWideMult);
}

bool IsERC(const double &open[], const double &high[], const double &low[], const double &close[], const int i,
           const bool series, const int winOldest, const int winNewest)
{
   if(IsBasing(open, high, low, close, i))
      return false;

   double bp = BodyPct(open, high, low, close, i);
   if(bp < InpERCBodyPctMin)
      return false;

   if(IsBull(open, close, i))
      return CloseNearHigh(high, low, close, i);
   if(IsBear(open, close, i))
      return CloseNearLow(high, low, close, i);

   return false;
}

bool IsFailedERC(const double &open[], const double &high[], const double &low[], const double &close[], const int i,
                 const bool series, const int winOldest, const int winNewest)
{
   if(!IsWide(high, low, i, series, winOldest, winNewest))
      return false;
   return IsBasing(open, high, low, close, i);
}

//------------------------- Step 3: Patterns --------------------------
// These are "base helpers" only (not trade signals), so we keep them strict/simple.

bool IsBullishEngulf(const double &open[], const double &close[], const int i, const int prev)
{
   // Current bull body fully engulfs previous body
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
   // Current body inside previous body
   double prevHi = MathMax(open[prev], close[prev]);
   double prevLo = MathMin(open[prev], close[prev]);
   double curHi  = MathMax(open[i], close[i]);
   double curLo  = MathMin(open[i], close[i]);
   return (curHi <= prevHi && curLo >= prevLo);
}

bool IsPiercing(const double &open[], const double &close[], const double &high[], const double &low[], const int i, const int prev)
{
   // Typical piercing: prev bear, current bull; current opens below prev low and closes above midpoint of prev body
   if(!(close[prev] < open[prev])) return false; // prev bear
   if(!(close[i] > open[i]))       return false; // current bull

   double prevBodyMid = (open[prev] + close[prev]) * 0.5;
   bool openedBelow   = (open[i] < low[prev]);
   bool closedAboveMid= (close[i] > prevBodyMid);
   bool closedBelowPrevOpen = (close[i] < open[prev]); // classic piercing closes below prev open

   return (openedBelow && closedAboveMid && closedBelowPrevOpen);
}

bool IsDarkCloud(const double &open[], const double &close[], const double &high[], const double &low[], const int i, const int prev)
{
   // Dark cloud cover: prev bull, current bear; current opens above prev high and closes below midpoint of prev body
   if(!(close[prev] > open[prev])) return false; // prev bull
   if(!(close[i] < open[i]))       return false; // current bear

   double prevBodyMid = (open[prev] + close[prev]) * 0.5;
   bool openedAbove   = (open[i] > high[prev]);
   bool closedBelowMid= (close[i] < prevBodyMid);
   bool closedAbovePrevOpen = (close[i] > open[prev]); // classic dark cloud closes above prev open

   return (openedAbove && closedBelowMid && closedAbovePrevOpen);
}

//------------------------- Step 3: Base Finder -----------------------
bool FindBaseBeforeLegOut(const datetime &time[],
                          const double &open[], const double &high[], const double &low[], const double &close[],
                          const int legOutIndex,
                          const bool series,
                          const int winOldest, const int winNewest,
                          int &baseStart, int &baseEnd,
                          double &proximal, double &distal,
                          ZoneType &baseType,
                          string &reason)
{
   reason = "";

   // Determine base type from leg-out direction (temporary for base debug):
   // bull impulse => demand base; bear impulse => supply base
   if(IsBull(open, close, legOutIndex)) baseType = Demand;
   else if(IsBear(open, close, legOutIndex)) baseType = Supply;
   else return false;

   int prev = OlderIndex(legOutIndex, 1, series); // candle immediately before leg-out
   if(!IndexInWindow(prev, winOldest, winNewest, series))
      return false;

   // 1) Primary path: contiguous basing candles right before the leg-out
   int count = 0;
   int cur = prev;
   baseEnd = prev; // most recent candle in the base (closest to leg-out)
   baseStart = prev;

   while(IndexInWindow(cur, winOldest, winNewest, series))
   {
      if(!IsBasing(open, high, low, close, cur))
         break;

      count++;
      baseStart = cur;

      if(count >= InpBaseMaxBars)
         break;

      cur = OlderIndex(cur, 1, series); // move older
   }

   if(count >= InpBaseMinBars)
   {
      if(count == 1 && !InpAllowSingleCandleBase)
      {
         // reject single-candle bases if disabled
         return false;
      }

      // Compute proximal/distal from base candles
      double lo = low[baseStart], hi = high[baseStart];
      double maxOC = MathMax(open[baseStart], close[baseStart]);
      double minOC = MathMin(open[baseStart], close[baseStart]);

      // iterate from baseStart .. baseEnd in index terms (careful with order)
      // We'll walk forward in "newer direction" to include all candles up to baseEnd
      int idx = baseStart;
      while(true)
      {
         lo = MathMin(lo, low[idx]);
         hi = MathMax(hi, high[idx]);

         maxOC = MathMax(maxOC, MathMax(open[idx], close[idx]));
         minOC = MathMin(minOC, MathMin(open[idx], close[idx]));

         if(idx == baseEnd) break;
         idx = OlderIndex(idx, -1, series); // go newer by one
         if(!IndexInWindow(idx, winOldest, winNewest, series))
            break;
      }

      if(baseType == Demand)
      {
         distal = lo;
         proximal = maxOC;
      }
      else
      {
         distal = hi;
         proximal = minOC;
      }

      reason = StringFormat("BASING_%d", count);
      return true;
   }

   // 2) Fallback: allow a 2-candle "pattern base" immediately before leg-out
   if(!InpBaseUseEngulfPierceHarami)
      return false;

   int prev2 = OlderIndex(prev, 1, series);
   if(!IndexInWindow(prev2, winOldest, winNewest, series))
      return false;

   bool pat = false;
   string patName = "";

   // Pattern is between prev (latest before legout) and prev2 (older)
   if(IsBullishEngulf(open, close, prev, prev2)) { pat=true; patName="BULL_ENG"; }
   else if(IsBearishEngulf(open, close, prev, prev2)) { pat=true; patName="BEAR_ENG"; }
   else if(IsPiercing(open, close, high, low, prev, prev2)) { pat=true; patName="PIERCING"; }
   else if(IsDarkCloud(open, close, high, low, prev, prev2)) { pat=true; patName="DARKCLOUD"; }
   else if(IsHarami(open, close, prev, prev2)) { pat=true; patName="HARAMI"; }

   if(!pat)
      return false;

   // Pattern base = 2 candles: [prev2 .. prev]
   baseStart = prev2;
   baseEnd   = prev;

   // Enforce size constraints
   if(2 < InpBaseMinBars || 2 > InpBaseMaxBars)
      return false;

   // Compute proximal/distal over these two candles
   double lo2 = MathMin(low[baseStart], low[baseEnd]);
   double hi2 = MathMax(high[baseStart], high[baseEnd]);
   double maxOC2 = MathMax(MathMax(open[baseStart], close[baseStart]), MathMax(open[baseEnd], close[baseEnd]));
   double minOC2 = MathMin(MathMin(open[baseStart], close[baseStart]), MathMin(open[baseEnd], close[baseEnd]));

   if(baseType == Demand)
   {
      distal = lo2;
      proximal = maxOC2;
   }
   else
   {
      distal = hi2;
      proximal = minOC2;
   }

   reason = patName;
   return true;
}

//------------------------- Debug marker helpers ----------------------
string MakeDbgName(const datetime t)
{
   return MakeBasePrefix() + "DBG_" + IntegerToString((long)t);
}

void DebugMarkerSetOrDelete(const datetime &time[], const double &high[], const double &low[],
                            const int idx, const string text)
{
   const long chart_id = 0;
   string name = MakeDbgName(time[idx]);

   if(text == "")
   {
      if(ObjectFind(chart_id, name) >= 0)
         ObjectDelete(chart_id, name);
      return;
   }

   double y = high[idx] + (CandleRange(high, low, idx) * 0.15);
   if(y <= high[idx]) y = high[idx] + (_Point * 20.0);

   if(ObjectFind(chart_id, name) < 0)
   {
      if(!ObjectCreate(chart_id, name, OBJ_TEXT, 0, time[idx], y))
         return;
   }
   else
   {
      ObjectMove(chart_id, name, 0, time[idx], y);
   }

   ObjectSetString(chart_id, name, OBJPROP_TEXT, text);
   ObjectSetInteger(chart_id, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(chart_id, name, OBJPROP_BACK, true);
   ObjectSetInteger(chart_id, name, OBJPROP_SELECTABLE, false);
}

//------------------------- Indicator lifecycle -----------------------
int OnInit()
{
   DebugPrint("SDZones Step3: OnInit()");
   IndicatorSetString(INDICATOR_SHORTNAME, "SDZones (Step3 Base Finder)");

   ArraySetAsSeries(g_dummyBuffer, true);
   SetIndexBuffer(0, g_dummyBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DebugPrint("SDZones Step3: OnDeinit()");
   ZonesClearAll();
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
   if(rates_total < 2)
      return 0;

   g_dummyBuffer[0] = EMPTY_VALUE;

   const bool series = IsSeriesOrder(time, rates_total);

   int winOldest = 0, winNewest = 0;
   if(!ComputeWindow(time, rates_total, InpLookbackBars, winOldest, winNewest))
      return rates_total;

   int iCur = IndexCurrentBar(time, rates_total);
   int iCls = IndexLastClosedBar(time, rates_total);

   // Enforce window strictly
   if(!IndexInWindow(iCls, winOldest, winNewest, series))
   {
      ZonesClearAll();
      if(InpDebug)
         PrintFormat("Last closed bar index %d OUTSIDE window. Window=[%d..%d] series=%s",
                     iCls, winOldest, winNewest, (series ? "true" : "false"));
      return rates_total;
   }

   // Print/compute once per new closed candle
   bool newClosedCandle = (time[iCls] != g_lastPrintedBarTime);
   if(newClosedCandle)
      g_lastPrintedBarTime = time[iCls];

   // ---------- Step 2 debug harness (last closed candle) ----------
   if(InpDebug && newClosedCandle)
   {
      double r  = CandleRange(high, low, iCls);
      double b  = CandleBody(open, close, iCls);
      double bp = BodyPct(open, high, low, close, iCls);

      bool basing = IsBasing(open, high, low, close, iCls);
      bool wide   = IsWide(high, low, iCls, series, winOldest, winNewest);
      bool cnH    = CloseNearHigh(high, low, close, iCls);
      bool cnL    = CloseNearLow(high, low, close, iCls);

      bool erc    = IsERC(open, high, low, close, iCls, series, winOldest, winNewest);
      bool ferc   = IsFailedERC(open, high, low, close, iCls, series, winOldest, winNewest);

      PrintFormat("Step2 lastClosed idx=%d time=%s range=%.5f body=%.5f bodyPct=%.3f "
                  "Bull=%s Bear=%s Basing=%s Wide=%s CloseNearH=%s CloseNearL=%s ERC=%s FailedERC=%s",
                  iCls,
                  TimeToString(time[iCls], TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                  r, b, bp,
                  (IsBull(open, close, iCls) ? "true":"false"),
                  (IsBear(open, close, iCls) ? "true":"false"),
                  (basing ? "true":"false"),
                  (wide   ? "true":"false"),
                  (cnH    ? "true":"false"),
                  (cnL    ? "true":"false"),
                  (erc    ? "true":"false"),
                  (ferc   ? "true":"false"));
   }

   // Optional: mark last N closed bars with B/E/F
   if(InpMarkDebugBars && newClosedCandle)
   {
      int N = InpMarkBarsCount;
      if(N < 1) N = 1;

      for(int k = 0; k < N; ++k)
      {
         int idx = OlderIndex(iCls, k, series);
         if(!IndexInWindow(idx, winOldest, winNewest, series))
            break;

         string tag = "";
         if(IsERC(open, high, low, close, idx, series, winOldest, winNewest))
            tag = "E";
         else if(IsFailedERC(open, high, low, close, idx, series, winOldest, winNewest))
            tag = "F";
         else if(IsBasing(open, high, low, close, idx))
            tag = "B";

         DebugMarkerSetOrDelete(time, high, low, idx, tag);
      }
   }
   else if(!InpMarkDebugBars && newClosedCandle)
   {
      // delete DBG_ objects only
      DeleteObjectsByPrefix(MakeBasePrefix() + "DBG_");
   }

   // ---------- Step 3: draw debug bases for impulses ----------
   if(newClosedCandle)
   {
      // Clear old base debug objects each bar so we only show the most recent set
      DeleteObjectsByPrefix(MakeBasePrefix() + "BASE_");

      int scan = InpScanLegOutBars;
      if(scan < 5) scan = 5;

      int drawn = 0;
      for(int k = 0; k < scan && drawn < InpMaxDebugBases; ++k)
      {
         int leg = OlderIndex(iCls, k, series);
         if(!IndexInWindow(leg, winOldest, winNewest, series))
            break;

         bool impulse = IsERC(open, high, low, close, leg, series, winOldest, winNewest) ||
                        IsFailedERC(open, high, low, close, leg, series, winOldest, winNewest);

         if(!impulse)
            continue;

         int baseStart = -1, baseEnd = -1;
         double prox=0, dist=0;
         ZoneType bt = Demand;
         string reason = "";

         if(!FindBaseBeforeLegOut(time, open, high, low, close,
                                  leg, series, winOldest, winNewest,
                                  baseStart, baseEnd, prox, dist, bt, reason))
            continue;

         Zone z;
         z.type = bt;
         z.status = Potential; // debug only
         z.baseStart = baseStart;
         z.baseEnd   = baseEnd;
         z.proximal  = prox;
         z.distal    = dist;

         // left edge = baseStart time (older), right edge = extend to now for visibility
         z.tStart = time[baseStart];
         z.tEnd   = (datetime)(time[iCur] + PeriodSeconds(_Period));

         // Name unique by leg-out time
         long legT = (long)time[leg];
         z.name = MakeBasePrefix() + "BASE_" + IntegerToString(legT);

         // Put useful info into description text by temporarily overriding tStart text via ZoneObjectCreateOrUpdate
         // (ZoneObjectCreateOrUpdate writes "Candle time: z.tStart", so for base debug we want base start time.
         // We'll keep that, and also log details in Experts.)
         if(InpDebug)
         {
            PrintFormat("BASE found: leg=%s (%s) base=[%s..%s] bars=%d type=%s reason=%s prox=%.5f dist=%.5f",
                        TimeToString(time[leg], TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                        (IsBull(open, close, leg) ? "bull" : (IsBear(open, close, leg) ? "bear" : "doji")),
                        TimeToString(time[baseStart], TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                        TimeToString(time[baseEnd],   TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                        (int)(MathAbs(baseStart - baseEnd) + 1),
                        (bt==Demand ? "Demand" : "Supply"),
                        reason,
                        prox, dist);
         }

         ZoneObjectCreateOrUpdate(z);
         drawn++;
      }
   }

   // ---------- Step 1 TEST zone (still fake) ----------
   Zone test;
   test.type      = Demand;
   test.status    = Potential;
   test.baseStart = iCls;
   test.baseEnd   = iCls;

   test.distal   = low[iCls];
   test.proximal = MathMin(open[iCls], close[iCls]);
   if(MathAbs(test.proximal - test.distal) < (_Point * 2.0))
      test.proximal = test.distal + (_Point * 10.0);

   test.tStart = time[iCls];
   test.tEnd   = (datetime)(time[iCur] + PeriodSeconds(_Period));
   test.name   = MakeBasePrefix() + "TEST";

   if(ArraySize(zones) == 0)
      ZoneAdd(test);
   else
      zones[0] = test;

   ZoneObjectCreateOrUpdate(zones[0]);

   return rates_total;
}
//+------------------------------------------------------------------+
