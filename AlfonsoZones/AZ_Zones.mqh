
#include "AZ_State.mqh"
#include "AZ_Core.mqh"

//------------------------- Base pattern helpers ----------------------
// Bullish engulf: cur bullish, prev bearish, open[cur] <= high[prev], close[cur] > high[prev]
// Bearish engulf: cur bearish, prev bullish, open[cur] >= low[prev],  close[cur] < low[prev]
bool IsBullishEngulf(const double &open[], const double &high[], const double &close[], const int cur, const int prev)
{
   double eps = _Point * 0.5;
   if(!(close[cur] > open[cur])) return false;
   if(!(close[prev] < open[prev])) return false;
   if(!(open[cur] <= high[prev] + eps)) return false;
   if(!(close[cur] >  high[prev] + eps)) return false;
   return true;
}

bool IsBearishEngulf(const double &open[], const double &low[], const double &close[], const int cur, const int prev)
{
   double eps = _Point * 0.5;
   if(!(close[cur] < open[cur])) return false;
   if(!(close[prev] > open[prev])) return false;
   if(!(open[cur] >= low[prev] - eps)) return false;
   if(!(close[cur] <  low[prev] - eps)) return false;
   return true;
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
      if(count > InpBaseMaxBars) return false;
      cur = OlderIndex(cur, 1, series);
   }

   if(count < InpBaseMinBars)
   {
      if(!InpBaseUseEngulfPierceHarami) return false;

      int prev2 = OlderIndex(prev, 1, series);
      if(!IndexInWindow(prev2, winOldest, winNewest, series)) return false;

      bool bullEng = IsBullishEngulf(open, high, close, prev, prev2);
      bool bearEng = IsBearishEngulf(open, low,  close, prev, prev2);
      bool harami  = IsHarami(open, close, prev, prev2);

      if(!(bullEng || bearEng || harami)) return false;

      // If engulfing is used as the “base”, use ONLY the engulfed candle (prev2)
      if(bullEng || bearEng)
      {
         if(1 < InpBaseMinBars || 1 > InpBaseMaxBars) return false;
         baseStart = prev2;
         baseEnd   = prev2;
      }
      else
      {
         // Harami keeps 2-candle base
         if(2 < InpBaseMinBars || 2 > InpBaseMaxBars) return false;
         baseStart = prev2;
         baseEnd   = prev;
      }
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
   outZone.tEnd      = (datetime)(time[iCur] + PeriodSeconds(_Period));

   outZone.tag       = tag;
   outZone.name      = MakeZonePrefix() + "ZONE_" + tag + "_" + IntegerToString((long)outZone.tLegOut);

   outZone.tConfirmed    = 0;
   outZone.confirmReason = "";

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

void MoveToDead(AZState &st, const Zone &z)
{
   int n = ArraySize(st.zonesDead);
   ArrayResize(st.zonesDead, n + 1);
   st.zonesDead[n] = z;
}

void PruneZonesOutsideWindow(AZState &st, const datetime oldestAllowedTime)
{
   for(int i = ArraySize(st.zonesActive) - 1; i >= 0; --i)
   {
      if(st.zonesActive[i].tStart < oldestAllowedTime)
      {
         DeleteObjectExact(st.zonesActive[i].name);
         for(int j = i; j < ArraySize(st.zonesActive) - 1; ++j) st.zonesActive[j] = st.zonesActive[j + 1];
         ArrayResize(st.zonesActive, ArraySize(st.zonesActive) - 1);
      }
   }
   for(int i = ArraySize(st.zonesDead) - 1; i >= 0; --i)
   {
      if(st.zonesDead[i].tStart < oldestAllowedTime)
      {
         DeleteObjectExact(st.zonesDead[i].name);
         for(int j = i; j < ArraySize(st.zonesDead) - 1; ++j) st.zonesDead[j] = st.zonesDead[j + 1];
         ArrayResize(st.zonesDead, ArraySize(st.zonesDead) - 1);
      }
   }
}

//------------------------- Takeout responsibility --------------------
int FindResponsibleOpposingZone(AZState &st,
                                const Zone &brokenZone,
                                const datetime breakTime,
                                const double breakerPrice)
{
   int bestIdx = -1;
   double bestDist = DBL_MAX;

   for(int i=0; i<ArraySize(st.zonesActive); ++i)
   {
      if(st.zonesActive[i].status == Eliminated) continue;
      if(st.zonesActive[i].type == brokenZone.type) continue;
      if(st.zonesActive[i].tStart > breakTime) continue;

      if(brokenZone.type == Demand)
      {
         if(st.zonesActive[i].type != Supply) continue;
         if(st.zonesActive[i].proximal <= breakerPrice) continue;
      }
      else
      {
         if(st.zonesActive[i].type != Demand) continue;
         if(st.zonesActive[i].proximal >= breakerPrice) continue;
      }

      double d = MathAbs(st.zonesActive[i].proximal - breakerPrice);
      if(d < bestDist)
      {
         bestDist = d;
         bestIdx = i;
      }
   }

   return bestIdx;
}

//------------------------- lifecycle processing ----------------------
void ProcessZonesOnClose(AZState &st,
                         const datetime &time[],
                         const double &high[], const double &low[],
                         const int iCls, const int iCur,
                         const bool series)
{
   for(int i = ArraySize(st.zonesActive) - 1; i >= 0; --i)
   {
      if(st.zonesActive[i].status == Eliminated)
         continue;

      bool broken = false;
      double breakerPrice = 0.0;

      if(st.zonesActive[i].type == Demand)
      {
         if(low[iCls] < st.zonesActive[i].distal)
         {
            broken = true;
            breakerPrice = low[iCls];
         }
      }
      else
      {
         if(high[iCls] > st.zonesActive[i].distal)
         {
            broken = true;
            breakerPrice = high[iCls];
         }
      }

      if(broken)
      {
         if(st.zonesActive[i].status == Confirmed)
         {
            st.zonesActive[i].status = Eliminated;
            st.zonesActive[i].tEnd   = time[iCls];

            Zone brokenCopy = st.zonesActive[i];
            int respIdx = FindResponsibleOpposingZone(st, brokenCopy, time[iCls], breakerPrice);

            if(respIdx >= 0 && st.zonesActive[respIdx].status == Potential)
            {
               st.zonesActive[respIdx].status = Confirmed;
               st.zonesActive[respIdx].tConfirmed    = time[iCls];
               st.zonesActive[respIdx].confirmReason = "TAKEOUT (broke confirmed " + brokenCopy.tag + ")";
            }

            MoveToDead(st, st.zonesActive[i]);
            DeleteObjectExact(st.zonesActive[i].name);

            for(int j = i; j < ArraySize(st.zonesActive) - 1; ++j)
               st.zonesActive[j] = st.zonesActive[j + 1];
            ArrayResize(st.zonesActive, ArraySize(st.zonesActive) - 1);
         }
         else
         {
            DeleteObjectExact(st.zonesActive[i].name);
            for(int j = i; j < ArraySize(st.zonesActive) - 1; ++j)
               st.zonesActive[j] = st.zonesActive[j + 1];
            ArrayResize(st.zonesActive, ArraySize(st.zonesActive) - 1);
         }
         continue;
      }

      st.zonesActive[i].tEnd = (datetime)(time[iCur] + PeriodSeconds(_Period));
   }
}
