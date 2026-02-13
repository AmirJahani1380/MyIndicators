
#include "AZ_Types.mqh"

struct AZState
{
   double   dummyBuffer[];
   datetime lastClosedTime;

   Zone zonesActive[];
   Zone zonesDead[];

   datetime high_lastBreak;
   datetime low_lastBreak;

   // TL signature lock
   datetime high_sig_t1, high_sig_t2;
   datetime low_sig_t1,  low_sig_t2;
   bool     high_sig_broken;
   bool     low_sig_broken;

   int atrHandle;
};
