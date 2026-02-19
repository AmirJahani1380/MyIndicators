

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

   datetime   tStart;
   datetime   tBaseEnd;
   datetime   tEnd;
   datetime   tLegOut;

   string     name;
   string     tag;

   datetime   tConfirmed;
   string     confirmReason;
};

struct TLInfo
{
   bool     has;
   datetime t1, t2;
   double   p1, p2;

   // Anchor points in "natural" candle index space (NS):
   // NS increases from oldest -> newest and is stable regardless of series arrays.
   // Used for index-based trendline price math (immune to weekend time gaps).
   int      ns1;   // older swing point (NS index)
   int      ns2;   // newer swing point (NS index)

   int      swing_ns;
   datetime swingTime;

   int      idx_old_arr;
   int      idx_new_arr;
};