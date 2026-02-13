

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

string MakeBrokenTLPfx()
{
   return (InpObjPrefix + "BRKTL_" + _Symbol + "_" + IntegerToString((int)_Period) + "_");
}

string BrokenTLObjName(const bool breakOnHighLine, const datetime breakTime)
{
   return MakeBrokenTLPfx() + (breakOnHighLine ? "BEAR_" : "BULL_") + IntegerToString((long)breakTime);
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
      winOldest = lb - 1;
   }
   else
   {
      winNewest = rates_total - 1;
      winOldest = rates_total - lb;
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

int MapNS2Arr(const int ns_i, const int rates_total, const bool seriesArrays)
{
   return (seriesArrays ? (rates_total - 1 - ns_i) : ns_i);
}

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
