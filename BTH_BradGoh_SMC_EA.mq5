//+------------------------------------------------------------------+
//|                                        BTH_BradGoh_SMC_EA.mq5    |
//|                                              Backtest the Hype   |
//|                                                                  |
//|  Brad Goh (The Trading Geek) - "How I Combine Liquidity Sweeps,  |
//|  Order Blocks and FVGs For SNIPER Entries", coded by             |
//|  Backtest the Hype. Spec v3 (+ review fixes v3.1).               |
//|                                                                  |
//|  ONE CONTROL: set "Test version" at the top to V1...V5 and run.  |
//|  Everything else is already set to the spec.                     |
//|                                                                  |
//|  THE FIVE VERSIONS (all 2R, 1R = $1,000)                         |
//|   V1  Limit order at the order block, stop beyond it.            |
//|   V2  Limit order at the FVG (order block if none) - his main.   |
//|   V3  Wait for a 1-minute structure shift inside the zone.       |
//|   V4  Wait for the touch candle to sweep liquidity, stop beyond  |
//|       that candle (our version of his advanced stop).            |
//|   V5  V2, only in the direction of the 1-hour trend.             |
//|                                                                  |
//|  HOW TO RUN                                                      |
//|   Strategy Tester: EURUSD, NAS100 or XAUUSD, M5,                 |
//|   "Every tick based on real ticks", 2021.01.01 - 2026.09.30,     |
//|   deposit 100000 USD. Pick the version, press Start.             |
//|                                                                  |
//|  HIS RULES (stated in the video)                                 |
//|   1. A break of structure sets the direction and the range.      |
//|   2. Wait for a liquidity sweep: price runs a swing / equal low  |
//|      (high) and rejects. No sweep, no trade.                     |
//|   3. Order block = full high-to-low of the origin candle.        |
//|   4. Fair value gap = 3-candle gap in the move, inside / near    |
//|      the OB. No FVG -> use the OB.                               |
//|   5. Wait for price to come back. Aggressive = enter on the      |
//|      touch. Conservative = wait for a lower-timeframe shift.     |
//|      Stop beyond the zone, target 2R.                            |
//|                                                                  |
//|  OUR DEFINITIONS (identical to the Pine script v1.1)             |
//|   - Swing = Backtest the Hype qualified swing: 2+ candle push,   |
//|     anchor candle, confirmed on a close past the anchor close.   |
//|     Swing price = extreme of the push.                           |
//|   - Direction flips only on a close beyond the protected low /   |
//|     high of the range.                                           |
//|   - Sweep = wick through a swing / equal low inside the range,   |
//|     close back within 3 candles. Equal = within 0.10 x ATR.      |
//|     A breached level is used up even if the sweep fails.         |
//|   - Displacement = within 12 candles, body >= 1 x ATR closing    |
//|     beyond the origin candle. Setup arms one candle later.       |
//|   - FVG overlaps the OB or starts within 0.5 x ATR of it,        |
//|     min 0.10 x ATR, largest wins. First touch only: a zone price |
//|     already came back to before the order exists is skipped.     |
//|   - Stop buffer 0.10 x ATR. Setup expires after 48 candles.      |
//|   - Fills only 07:00 London -> 11:30 New York (real DST).        |
//|     Max 2 filled trades a day, 1 open trade. Friday close-out    |
//|     16:50 New York. 2R measured from the real fill.              |
//|   - 1R = the money lost if the stop is hit, from the real fill   |
//|     and real lot size. Costs = real spread + commission + swap.  |
//|                                                                  |
//|  PROP-FIRM SIMULATION (one virtual $100,000 account)             |
//|   Risk 1% of the current balance. Phase 1 +8%, Phase 2 +5%,      |
//|   funded pays 80% at +5% and resets to $100k. Max loss 10%       |
//|   (equity, checked every minute). Daily 5% = protection: a trade |
//|   that could take the day past -5% is not taken. $500 per        |
//|   challenge. Our assumed rules, not a named firm's.              |
//+------------------------------------------------------------------+
#property copyright "Backtest the Hype"
#property link      "https://www.youtube.com/@backtestthehype"
#property version   "1.02"
#property description "Brad Goh (The Trading Geek): liquidity sweep + order block + FVG. Five test versions plus a prop-firm challenge simulation. Coded by Backtest the Hype."

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
enum ENUM_VERSION
  {
   VER_1 = 1, // V1  Order block touch
   VER_2 = 2, // V2  FVG touch (Brad's main)
   VER_3 = 3, // V3  Conservative (1-minute shift)
   VER_4 = 4, // V4  Advanced stop (entry candle)
   VER_5 = 5  // V5  FVG touch + 1-hour trend
  };

input group "===== TEST VERSION - change this one setting and run ====="
input ENUM_VERSION InpVersion      = VER_2;     // Test version

input group "Broker and risk"
input int          InpServerMinusNY = 7;        // Server time minus New York time (hours). Fusion = 7
input double       InpRiskUSD       = 1000.0;   // Risk per trade = 1R (1% of 100,000)
input double       InpMinStop       = 0;        // OUR CALL: skip trades with a stop smaller than this (price; 0 = auto: FX 1 pip, XAUUSD 0.30, NAS100 2.0)

input group "Advanced - spec v3 values (leave as they are)"
input double       InpRR        = 2.0;    // Target (R)
input int          InpMaxTrades = 2;      // Max filled trades per day
input int          InpReclaimN  = 3;      // Sweep: close back within (candles, breach = 1)
input int          InpDispN     = 12;     // Displacement within (candles after the sweep)
input double       InpDispK     = 1.0;    // Displacement body >= x ATR
input double       InpFvgMinK   = 0.10;   // FVG min size (x ATR)
input double       InpFvgNearK  = 0.5;    // FVG max distance from the OB (x ATR)
input double       InpEqK       = 0.10;   // Equal highs / lows tolerance (x ATR)
input double       InpBufK      = 0.10;   // Stop buffer (x ATR)
input int          InpExpireN   = 48;     // Setup expires after (5-minute candles)
input int          InpV3N       = 12;     // V3: 1-minute shift within (5-minute candles of the touch)
input int          InpWinStart  = 700;    // Entry window start (London time, HHMM)
input int          InpWinEnd    = 1130;   // Entry window end (New York time, HHMM)
input int          InpFriClose  = 1650;   // Friday close-out (New York time, HHMM)
input int          InpScanCap   = 4000;   // Range look-back cap (5-minute candles)
input datetime     InpFrom      = D'2021.01.01 00:00'; // Trades only from (the EA ignores the tester dates outside this)
input datetime     InpTo        = D'2026.10.01 00:00'; // ... until (exclusive)

input group "Prop-firm simulation"
input bool         InpProp         = true;     // Run the prop-firm simulation
input double       InpPropStart    = 100000.0; // Account size
input double       InpPropRiskPct  = 1.0;      // Risk per trade (% of current balance)
input double       InpPhase1Pct    = 8.0;      // Phase 1 target (%)
input double       InpPhase2Pct    = 5.0;      // Phase 2 target (%)
input double       InpMaxLossPct   = 10.0;     // Max loss (%) - blows the account
input double       InpDailyLossPct = 5.0;      // Daily loss protection (%) - stop for the day
input double       InpPayoutPct    = 5.0;      // Funded payout at (%)
input double       InpSplitPct     = 80.0;     // Profit split (%)
input double       InpFee          = 500.0;    // Price of one challenge

input group "Visuals & log"
input bool         InpDraw    = true;      // Draw zones, trades and the results panel
input bool         InpLogCSV  = true;      // Write trade + challenge logs (Common\Files)
input ulong        InpMagic   = 26102401;  // Magic number
input int          InpWarm5   = 3000;      // Warm-up history (5-minute candles)

//+------------------------------------------------------------------+
//| Colours (same palette as the other BTH EAs)                      |
//+------------------------------------------------------------------+
#define PFX "BTH_BG_"
#define RB  8192
#define RM  8191
color C_GREEN  = C'0,229,97';
color C_RED    = C'255,77,94';
color C_GREY   = C'126,145,138';
color C_WHITE  = C'238,244,240';
color C_AMBER  = C'245,185,66';
color C_PANEL  = C'11,20,16';
color C_RISK   = C'110,30,38';
color C_REWARD = C'20,84,48';
color C_ZONE   = C'52,60,58';
color C_FVG    = C'74,62,30';

//+------------------------------------------------------------------+
//| Data                                                             |
//+------------------------------------------------------------------+
struct SBar
  {
   datetime          t;
   double            o, h, l, c;
  };

//--- ring buffer of closed candles, addressed by an ever-growing index
struct SBuf
  {
   SBar              b[RB];
   long              n;
   void              Init() { n = 0; }
   void              Push(const SBar &x) { b[(int)(n & RM)] = x; n++; }
   long              Cur() { return n - 1; }
   double            O(long i) { return b[(int)(i & RM)].o; }
   double            H(long i) { return b[(int)(i & RM)].h; }
   double            L(long i) { return b[(int)(i & RM)].l; }
   double            C(long i) { return b[(int)(i & RM)].c; }
   datetime          T(long i) { return b[(int)(i & RM)].t; }
  };

//--- channel swing tracker
struct SSwing
  {
   int               run;
   bool              qual;
   bool              anc;
   double            ancOpen, ancClose;
   bool              hasExt;
   double            ext;
   long              extI;
   void              Reset() { run = 0; qual = false; anc = false; ancOpen = 0; ancClose = 0; hasExt = false; ext = 0; extI = -1; }
  };

//--- market structure: direction + protected range
struct SStruct
  {
   SSwing            hiT, loT;
   int               dir;
   bool              hasSh; double sh; long shI, shC; bool shB;
   bool              hasSl; double sl; long slI, slC; bool slB;
   double            pLo; long pLoI;
   double            pHi; long pHiI;
   long              bosI;
   void              Reset()
     {
      hiT.Reset(); loT.Reset(); dir = 0;
      hasSh = false; sh = 0; shI = -1; shC = -1; shB = true;
      hasSl = false; sl = 0; slI = -1; slC = -1; slB = true;
      pLo = 0; pLoI = -1; pHi = 0; pHiI = -1; bosI = -1;
     }
  };

struct STrade
  {
   bool              open;
   ulong             ticket;
   long              posid;
   int               dir;
   double            entry, sl, tp, lots;
   double            riskMoney;
   double            pRisk;       // what the prop account put on it
   double            worstR;
   datetime          tOpen;
   double            zLo, zHi;
   string            zType;
   string            why;
  };

struct SProp
  {
   int               phase;       // 1, 2, 3 = funded
   double            balance;
   double            dayStart;
   int               challenges;
   double            fees;
   int               payouts;
   double            payoutMoney;
   int               p1pass, p2pass;
   int               failP1, failP2, failFunded;
   int               guarded;     // trades skipped by the daily protection
   datetime          accStart;
   datetime          firstPayout;
   double            worstEq;
  };

SBuf    g5, gH;
SStruct st, stH;
CTrade  g_trade;
STrade  g_tr;
SProp   g_prop;
int     g_ver = 2;
string  g_verName = "";

//--- ATR(14), Wilder, same as TradingView ta.atr
double  g_atr = 0.0, g_atrPrev = 0.0, g_atrSum = 0.0;
int     g_atrN = 0;

//--- liquidity levels inside the current range
double  liq[];

//--- sweep sequence: 0 idle, 1 breached, 2 waiting for displacement, 3 arm on next close
int     sq = 0, qD = 0;
double  qLvl = 0, qX = 0, oH = 0, oL = 0;
long    qB = -1, qC = -1, oI = -1;

//--- armed setup
int     sDir = 0, sMode = 0;
double  sLim = 0, sStop = 0, sZTop = 0, sZBot = 0, sBuf = 0;
long    sArm = -1;
bool    sTouched = false;
long    sTouchI = -1;
double  sTX = 0;
bool    sUseOB = true;
SSwing  m1;
bool    m1Has = false;
double  m1Lvl = 0;
string  sZoneName = "";
datetime sZoneT1 = 0;
int     g_zoneN = 0;
int     g_htfDir = 0;

//--- orders and days
ulong    g_pendTicket = 0;
double   g_pendPrice = 0;
int      g_today = 0;
long     g_dayIdx = -1;
datetime g_last5 = 0, g_last1 = 0, g_lastH1 = 0;
bool     g_warm = false;
int      g_tradeNo = 0;

//--- statistics
int      s_T = 0, s_W = 0, s_BE = 0, s_skipped = 0, s_sweeps = 0, s_armed = 0, s_minStop = 0;
//--- OUR CALL (v1.02): minimum stop size, ~0.01% of price per market
double MinStop()
  {
   if(InpMinStop > 0) return InpMinStop;
   string s = _Symbol; StringToUpper(s);
   if(StringFind(s, "XAU") >= 0) return 0.30;
   if(StringFind(s, "NAS") >= 0 || StringFind(s, "US100") >= 0 || StringFind(s, "USTEC") >= 0) return 2.0;
   int d = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (d == 5 || d == 3) ? 10 * _Point : _Point;
  }
double   s_sumR = 0, s_gW = 0, s_gL = 0, s_runR = 0, s_peakR = 0, s_ddR = 0, s_sumPriceR = 0;
int      s_consec = 0, s_maxConsec = 0;
datetime s_first = 0, s_last = 0;
bool     s_dataWarn = false;
int      s_marginCut = 0, s_orderFail = 0;
uint     s_lastRet = 0;
datetime g_firstTick = 0;
bool     g_propOn = false;
string   s_dataWarnTxt = "";

int      g_tradeHandle = INVALID_HANDLE;
int      g_propHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Time: server -> New York / London (real daylight saving)         |
//+------------------------------------------------------------------+
datetime MakeT(int y, int mo, int d, int h, int mi)
  {
   MqlDateTime s;
   ZeroMemory(s);
   s.year = y; s.mon = mo; s.day = d; s.hour = h; s.min = mi; s.sec = 0;
   return StructToTime(s);
  }
int Dow(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.day_of_week; }
int MinOfDay(datetime t) { MqlDateTime s; TimeToStruct(t, s); return s.hour * 60 + s.min; }
int HHMM(int x) { return (x / 100) * 60 + x % 100; }

datetime NthSun(int y, int mo, int n)
  {
   datetime f = MakeT(y, mo, 1, 0, 0);
   int first = 1 + (7 - Dow(f)) % 7;
   return MakeT(y, mo, first + 7 * (n - 1), 0, 0);
  }
datetime LastSun(int y, int mo)
  {
   datetime nx = (mo == 12) ? MakeT(y + 1, 1, 1, 0, 0) : MakeT(y, mo + 1, 1, 0, 0);
   datetime last = nx - 86400;
   return last - Dow(last) * 86400;
  }
datetime NyT(datetime srv) { return srv - InpServerMinusNY * 3600; }
bool UsDst(datetime ny)
  {
   MqlDateTime s; TimeToStruct(ny, s);
   datetime a = NthSun(s.year, 3, 2) + 2 * 3600;
   datetime b = NthSun(s.year, 11, 1) + 2 * 3600;
   return ny >= a && ny < b;
  }
bool UkDst(datetime utc)
  {
   MqlDateTime s; TimeToStruct(utc, s);
   datetime a = LastSun(s.year, 3) + 3600;
   datetime b = LastSun(s.year, 10) + 3600;
   return utc >= a && utc < b;
  }
datetime LonT(datetime srv)
  {
   datetime ny = NyT(srv);
   datetime utc = ny + (UsDst(ny) ? 4 : 5) * 3600;
   return utc + (UkDst(utc) ? 3600 : 0);
  }
//--- can an order fill at this moment? 07:00 London -> 11:30 New York
bool InWin(datetime srv)
  {
   return MinOfDay(NyT(srv)) < HHMM(InpWinEnd) && MinOfDay(LonT(srv)) >= HHMM(InpWinStart);
  }
//--- inside the fixed test period?
bool InTest(datetime t) { return t >= InpFrom && t < InpTo; }

//+------------------------------------------------------------------+
//| Small helpers                                                    |
//+------------------------------------------------------------------+
double NormP(double p)
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts > 0) p = MathRound(p / ts) * ts;
   return NormalizeDouble(p, _Digits);
  }

double NormLots(double lots)
  {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stp = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stp <= 0) stp = 0.01;
   lots = MathFloor(lots / stp) * stp;
   if(lots < mn) lots = mn;
   if(lots > mx) lots = mx;
   return NormalizeDouble(lots, 2);
  }

double LotsFor(double dist)
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(ts <= 0 || tv <= 0 || dist <= 0) return 0;
   double lots = InpRiskUSD / (dist / ts * tv);
   // margin guard: tiny stops need big lots; never ask for more than half the free margin.
   // R stays exact because it is measured from the lots that actually traded.
   double m1 = 0, px = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(px > 0 && OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, px, m1) && m1 > 0)
     {
      double cap = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.5 / m1;
      if(lots > cap)
        {
         s_marginCut++;
         double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(cap < mn) return 0;
         lots = cap;
        }
     }
   return NormLots(lots);
  }

string VerName(int v)
  {
   if(v == 1) return "V1 Order block touch";
   if(v == 2) return "V2 FVG touch (Brad's main)";
   if(v == 3) return "V3 Conservative (1-minute shift)";
   if(v == 4) return "V4 Advanced stop (entry candle)";
   return "V5 FVG touch + 1-hour trend";
  }

void LowestSince(SBuf &buf, long idx, double &m, long &mi)
  {
   long cur = buf.Cur();
   long n = cur - idx;
   if(n < 0) n = 0;
   if(n > InpScanCap) n = InpScanCap;
   if(n > RB - 2) n = RB - 2;
   m = buf.L(cur); mi = cur;
   for(long i = 0; i <= n; i++)
      if(buf.L(cur - i) < m) { m = buf.L(cur - i); mi = cur - i; }
  }

void HighestSince(SBuf &buf, long idx, double &m, long &mi)
  {
   long cur = buf.Cur();
   long n = cur - idx;
   if(n < 0) n = 0;
   if(n > InpScanCap) n = InpScanCap;
   if(n > RB - 2) n = RB - 2;
   m = buf.H(cur); mi = cur;
   for(long i = 0; i <= n; i++)
      if(buf.H(cur - i) > m) { m = buf.H(cur - i); mi = cur - i; }
  }

//+------------------------------------------------------------------+
//| Qualified swing. side 1 = swing HIGHS, side -1 = swing LOWS.     |
//| Returns true on the candle that confirms it.                     |
//+------------------------------------------------------------------+
bool SwingStep(SSwing &s, int side, double o, double h, double l, double c, long idx, double &px, long &pxI)
  {
   bool pushC = (side == 1) ? (c > o) : (c < o);
   bool oppC  = (side == 1) ? (c < o) : (c > o);
   double p   = (side == 1) ? h : l;
   bool res   = false;
   if(s.anc)
     {
      if((side == 1) ? (p > s.ext) : (p < s.ext)) { s.ext = p; s.extI = idx; }
      if((side == 1) ? (c > s.ancOpen) : (c < s.ancOpen))
        {
         // push resumed: no swing, the next opposite candle becomes the new anchor
         s.anc = false;
         s.qual = true;
        }
      else if(oppC && ((side == 1) ? (c < s.ancClose) : (c > s.ancClose)))
        {
         px = s.ext; pxI = s.extI; res = true;
         s.anc = false; s.qual = false; s.run = 0; s.hasExt = false;
        }
     }
   else
     {
      if(pushC)
        {
         if((s.run == 0 && !s.qual) || !s.hasExt || ((side == 1) ? (p > s.ext) : (p < s.ext)))
           { s.ext = p; s.extI = idx; s.hasExt = true; }
         s.run++;
         if(s.run >= 2) s.qual = true;
        }
      else if(oppC)
        {
         if(s.qual)
           {
            s.anc = true; s.ancOpen = o; s.ancClose = c;
            if((side == 1) ? (p > s.ext) : (p < s.ext)) { s.ext = p; s.extI = idx; }
           }
         else { s.run = 0; s.hasExt = false; }
        }
     }
   return res;
  }

//--- ev: 2 / -2 direction set or flipped, 1 / -1 break of structure in the same direction
int UpdateStruct(SStruct &s, SBuf &buf, bool &gotSL, double &newSL, bool &gotSH, double &newSH)
  {
   long cur = buf.Cur();
   double o = buf.O(cur), h = buf.H(cur), l = buf.L(cur), c = buf.C(cur);
   double px = 0; long pxI = -1;
   gotSL = false; gotSH = false;
   if(SwingStep(s.hiT, 1, o, h, l, c, cur, px, pxI))
     { s.hasSh = true; s.sh = px; s.shI = pxI; s.shC = cur; s.shB = false; gotSH = true; newSH = px; }
   if(SwingStep(s.loT, -1, o, h, l, c, cur, px, pxI))
     { s.hasSl = true; s.sl = px; s.slI = pxI; s.slC = cur; s.slB = false; gotSL = true; newSL = px; }

   int ev = 0;
   double m = 0; long mi = -1;
   if(s.dir == 1 && c < s.pLo)
     {
      HighestSince(buf, s.pLoI, m, mi);
      s.dir = -1; s.pHi = m; s.pHiI = mi; s.bosI = cur; s.slB = true; ev = -2;
     }
   else if(s.dir == -1 && c > s.pHi)
     {
      LowestSince(buf, s.pHiI, m, mi);
      s.dir = 1; s.pLo = m; s.pLoI = mi; s.bosI = cur; s.shB = true; ev = 2;
     }
   else if(s.dir != -1 && s.hasSh && !s.shB && (s.dir == 0 || s.shC > s.bosI) && c > s.sh)
     {
      LowestSince(buf, s.shI, m, mi);
      ev = (s.dir == 0) ? 2 : 1;
      s.dir = 1; s.pLo = m; s.pLoI = mi; s.bosI = cur; s.shB = true;
     }
   else if(s.dir != 1 && s.hasSl && !s.slB && (s.dir == 0 || s.slC > s.bosI) && c < s.sl)
     {
      HighestSince(buf, s.slI, m, mi);
      ev = (s.dir == 0) ? -2 : -1;
      s.dir = -1; s.pHi = m; s.pHiI = mi; s.bosI = cur; s.slB = true;
     }
   return ev;
  }

void AtrPush(long cur)
  {
   double h = g5.H(cur), l = g5.L(cur);
   double tr = h - l;
   if(cur > 0)
     {
      double pc = g5.C(cur - 1);
      tr = MathMax(tr, MathMax(MathAbs(h - pc), MathAbs(l - pc)));
     }
   g_atrPrev = g_atr;
   g_atrN++;
   if(g_atrN <= 14) { g_atrSum += tr; g_atr = g_atrSum / g_atrN; }
   else g_atr = (g_atr * 13.0 + tr) / 14.0;
   if(g_atrN == 1) g_atrPrev = g_atr;
  }

//--- the 1-hour direction from bars that have fully closed before this hour (V5)
void FeedH1(datetime t5)
  {
   datetime hourStart = t5 - (t5 % 3600);
   datetime upto = hourStart - 3600;              // open time of the last fully closed hour
   if(upto <= g_lastH1) return;
   MqlRates r[];
   datetime from = (g_lastH1 == 0) ? upto - 1500 * 3600 : g_lastH1 + 1;
   int n = CopyRates(_Symbol, PERIOD_H1, from, upto, r);
   for(int i = 0; i < n; i++)
     {
      if(r[i].time <= g_lastH1) continue;
      SBar b; b.t = r[i].time; b.o = r[i].open; b.h = r[i].high; b.l = r[i].low; b.c = r[i].close;
      gH.Push(b);
      bool a, d; double x, y;
      UpdateStruct(stH, gH, a, x, d, y);
      g_lastH1 = r[i].time;
     }
   g_htfDir = stH.dir;
  }

//+------------------------------------------------------------------+
//| Drawing                                                          |
//+------------------------------------------------------------------+
void DrawBox(const string name, datetime t1, double p1, datetime t2, double p2, color c, bool fill)
  {
   if(!InpDraw) return;
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FILL, fill);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void DrawText(const string name, datetime t, double p, const string txt, color c)
  {
   if(!InpDraw) return;
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void PanelLabel(const string name, int x, int y, const string txt, color c, ENUM_ANCHOR_POINT anchor, int size)
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

void PanelBg(const string name, int x, int y, int w, int h)
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C_PANEL);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, C'52,66,60');
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

//+------------------------------------------------------------------+
//| PROP-FIRM SIMULATION                                             |
//+------------------------------------------------------------------+
string PhaseTxt(int ph) { return ph == 1 ? "Phase 1" : ph == 2 ? "Phase 2" : "Funded"; }

void PropInit(datetime t)
  {
   g_prop.phase = 1;
   g_prop.balance = InpPropStart;
   g_prop.dayStart = InpPropStart;
   g_prop.challenges = 1;
   g_prop.fees = InpFee;
   g_prop.payouts = 0;
   g_prop.payoutMoney = 0;
   g_prop.p1pass = 0; g_prop.p2pass = 0;
   g_prop.failP1 = 0; g_prop.failP2 = 0; g_prop.failFunded = 0;
   g_prop.guarded = 0;
   g_prop.accStart = t;
   g_prop.firstPayout = 0;
   g_prop.worstEq = 0;
  }

void PropLog(datetime t, const string outcome)
  {
   PrintFormat("PROP #%d | %s | %s -> %s | %s | balance %.2f | payouts %d worth %.2f | fees %.2f",
               g_prop.challenges, g_verName, TimeToString(g_prop.accStart, TIME_DATE),
               TimeToString(t, TIME_DATE), outcome, g_prop.balance, g_prop.payouts,
               g_prop.payoutMoney, g_prop.fees);
   if(!InpLogCSV || g_propHandle == INVALID_HANDLE) return;
   FileWrite(g_propHandle, g_verName, _Symbol, IntegerToString(g_prop.challenges),
             TimeToString(g_prop.accStart, TIME_DATE), TimeToString(t, TIME_DATE), outcome,
             DoubleToString(g_prop.balance, 2), IntegerToString(g_prop.payouts),
             DoubleToString(g_prop.payoutMoney, 2), DoubleToString(g_prop.fees, 2));
  }

void PropRestart(datetime t, const string why)
  {
   PropLog(t, why);
   if(g_prop.phase == 1) g_prop.failP1++;
   else if(g_prop.phase == 2) g_prop.failP2++;
   else g_prop.failFunded++;
   g_prop.phase = 1;
   g_prop.balance = InpPropStart;
   g_prop.dayStart = InpPropStart;
   g_prop.challenges++;
   g_prop.fees += InpFee;
   g_prop.accStart = t;
   g_tr.pRisk = 0;                       // the open trade died with the account
  }

void PropCheckTargets(datetime t)
  {
   double S = InpPropStart;
   if(g_prop.phase == 1)
     {
      if(g_prop.balance >= S * (1.0 + InpPhase1Pct / 100.0))
        {
         g_prop.p1pass++; PropLog(t, "PASSED Phase 1");
         g_prop.phase = 2; g_prop.balance = S; g_prop.dayStart = S;
        }
      return;
     }
   if(g_prop.phase == 2)
     {
      if(g_prop.balance >= S * (1.0 + InpPhase2Pct / 100.0))
        {
         g_prop.p2pass++; PropLog(t, "PASSED Phase 2 - FUNDED");
         g_prop.phase = 3; g_prop.balance = S; g_prop.dayStart = S;
        }
      return;
     }
   if(g_prop.balance >= S * (1.0 + InpPayoutPct / 100.0))
     {
      double cash = (g_prop.balance - S) * InpSplitPct / 100.0;
      g_prop.payoutMoney += cash;
      g_prop.payouts++;
      if(g_prop.firstPayout == 0) g_prop.firstPayout = t;
      PropLog(t, "PAYOUT " + DoubleToString(cash, 0));
      g_prop.balance = S; g_prop.dayStart = S;
     }
  }

//--- every closed minute: worst equity of the open trade, max-loss check
void PropMinute(const SBar &m)
  {
   if(!InpProp || !g_tr.open || g_tr.pRisk <= 0) return;
   double dist = MathAbs(g_tr.entry - g_tr.sl);
   if(dist <= 0 || m.t < g_tr.tOpen - 59) return;
   double adverse = (g_tr.dir > 0) ? m.l : m.h;
   double r = g_tr.dir * (adverse - g_tr.entry) / dist;
   if(r < -1.0) r = -1.0;                // the stop caps the loss (gaps aside)
   if(r < g_tr.worstR) g_tr.worstR = r;
   double eq = g_prop.balance + r * g_tr.pRisk;
   double pct = (eq - InpPropStart) / InpPropStart * 100.0;
   if(pct < g_prop.worstEq) g_prop.worstEq = pct;
   if(eq <= InpPropStart * (1.0 - InpMaxLossPct / 100.0) + 0.000001)
      PropRestart(m.t, "FAILED " + PhaseTxt(g_prop.phase) + " - max loss");
  }

//+------------------------------------------------------------------+
//| Orders                                                           |
//+------------------------------------------------------------------+
void DeletePending()
  {
   if(g_pendTicket > 0 && OrderSelect(g_pendTicket)) g_trade.OrderDelete(g_pendTicket);
   g_pendTicket = 0;
   g_pendPrice = 0;
  }

void KillSetup()
  {
   if(sDir != 0 && sZoneName != "" && InpDraw)
      ObjectSetInteger(0, sZoneName, OBJPROP_TIME, 1, TimeCurrent());
   sDir = 0;
   DeletePending();
  }

bool MyPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == (long)InpMagic)
         return true;
     }
   return false;
  }

//--- market order with a stop; the target is reset to 2R from the real fill afterwards
void EnterMarket(int dir, double stp, const string why)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) { s_skipped++; return; }
   if(dir > 0 ? stp >= bid : stp <= ask) { s_skipped++; return; }   // already through the stop
   double entry = dir > 0 ? ask : bid;
   double dist = MathAbs(entry - stp);
   if(dist < MinStop()) { s_minStop++; return; }
   double lots = LotsFor(dist);
   if(lots <= 0) { s_skipped++; return; }
   double tp = NormP(entry + dir * InpRR * dist);
   g_tr.why = why;
   bool ok = dir > 0 ? g_trade.Buy(lots, _Symbol, 0.0, stp, tp, "BTH " + why)
                     : g_trade.Sell(lots, _Symbol, 0.0, stp, tp, "BTH " + why);
   if(!ok) { s_skipped++; s_orderFail++; s_lastRet = g_trade.ResultRetcode(); }
  }

//--- resting limit order for V1 / V2 / V5
void PlaceLimit()
  {
   if(g_pendTicket > 0 && OrderSelect(g_pendTicket) && MathAbs(g_pendPrice - sLim) < _Point / 2) return;
   DeletePending();
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) return;
   // price already through the entry (a gap): fill now, like a limit order would
   if(sDir > 0 ? ask <= sLim : bid >= sLim)
     {
      if(sDir > 0 ? bid > sStop : ask < sStop) EnterMarket(sDir, sStop, g_verName + " gap fill");
      KillSetup();
      return;
     }
   double dist = MathAbs(sLim - sStop);
   if(dist < MinStop()) { s_minStop++; KillSetup(); return; }
   double lots = LotsFor(dist);
   if(lots <= 0) { s_skipped++; KillSetup(); return; }
   double tp = NormP(sLim + sDir * InpRR * dist);
   g_tr.why = sUseOB ? "OB limit" : "FVG limit";
   bool ok = sDir > 0 ? g_trade.BuyLimit(lots, sLim, _Symbol, sStop, tp, ORDER_TIME_GTC, 0, "BTH " + g_tr.why)
                      : g_trade.SellLimit(lots, sLim, _Symbol, sStop, tp, ORDER_TIME_GTC, 0, "BTH " + g_tr.why);
   if(ok) { g_pendTicket = g_trade.ResultOrder(); g_pendPrice = sLim; }
   else { s_skipped++; s_orderFail++; s_lastRet = g_trade.ResultRetcode(); }
  }

//--- a position just appeared: record it, reset the target to 2R from the real fill
void OnFill()
  {
   g_tr.open = true;
   g_tr.ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   g_tr.posid = PositionGetInteger(POSITION_IDENTIFIER);
   g_tr.dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   g_tr.entry = PositionGetDouble(POSITION_PRICE_OPEN);
   g_tr.sl = PositionGetDouble(POSITION_SL);
   g_tr.lots = PositionGetDouble(POSITION_VOLUME);
   g_tr.tOpen = (datetime)PositionGetInteger(POSITION_TIME);
   g_tr.worstR = 0;
   g_tr.zLo = sZBot; g_tr.zHi = sZTop; g_tr.zType = sUseOB ? "OB" : "FVG";
   double dist = MathAbs(g_tr.entry - g_tr.sl);
   g_tr.tp = NormP(g_tr.entry + g_tr.dir * InpRR * dist);
   g_trade.PositionModify(g_tr.ticket, g_tr.sl, g_tr.tp);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   g_tr.riskMoney = (ts > 0 && tv > 0) ? dist / ts * tv * g_tr.lots : InpRiskUSD;
   if(g_tr.riskMoney <= 0) g_tr.riskMoney = InpRiskUSD;
   g_today++;
   g_pendTicket = 0;
   sDir = 0;                                     // the setup is used up

   // prop account: 1% of balance, unless it could take the day past -5%
   g_tr.pRisk = 0;
   if(InpProp)
     {
      double risk = g_prop.balance * InpPropRiskPct / 100.0;
      double dayLoss = MathMax(0.0, g_prop.dayStart - g_prop.balance);
      if(dayLoss + risk > InpPropStart * InpDailyLossPct / 100.0 + 0.000001) g_prop.guarded++;
      else g_tr.pRisk = risk;
     }
  }

//--- the position is gone: count it
void Settle(datetime t)
  {
   double money = 0, exitPx = 0;
   string reason = "closed";
   if(HistorySelectByPosition(g_tr.posid))
     {
      int deals = HistoryDealsTotal();
      for(int d = 0; d < deals; d++)
        {
         ulong tk = HistoryDealGetTicket(d);
         if(tk == 0) continue;
         money += HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP)
                + HistoryDealGetDouble(tk, DEAL_COMMISSION);
         if(HistoryDealGetInteger(tk, DEAL_ENTRY) == DEAL_ENTRY_OUT)
           {
            exitPx = HistoryDealGetDouble(tk, DEAL_PRICE);
            long rs = HistoryDealGetInteger(tk, DEAL_REASON);
            reason = rs == DEAL_REASON_SL ? "stop" : rs == DEAL_REASON_TP ? "target" : "Friday close";
            t = (datetime)HistoryDealGetInteger(tk, DEAL_TIME);
           }
        }
     }
   double R = money / g_tr.riskMoney;
   double dist = MathAbs(g_tr.entry - g_tr.sl);
   double priceR = (dist > 0 && exitPx > 0) ? g_tr.dir * (exitPx - g_tr.entry) / dist : 0;

   s_T++;
   if(MathAbs(R) < 0.01) { s_BE++; s_consec = 0; }
   else if(R > 0) { s_W++; s_gW += R; s_consec = 0; }
   else { s_gL += -R; s_consec++; if(s_consec > s_maxConsec) s_maxConsec = s_consec; }
   s_sumR += R; s_sumPriceR += priceR;
   s_runR += R;
   if(s_runR > s_peakR) s_peakR = s_runR;
   if(s_peakR - s_runR > s_ddR) s_ddR = s_peakR - s_runR;
   if(s_first == 0) s_first = g_tr.tOpen;
   s_last = t;

   // prop account takes its share
   string propBefore = PhaseTxt(g_prop.phase);
   if(InpProp && g_tr.pRisk > 0)
     {
      g_prop.balance += R * g_tr.pRisk;
      if(g_prop.balance <= InpPropStart * (1.0 - InpMaxLossPct / 100.0) + 0.000001)
         PropRestart(t, "FAILED " + PhaseTxt(g_prop.phase) + " - max loss");
      else
         PropCheckTargets(t);
     }

   g_tradeNo++;
   if(InpLogCSV && g_tradeHandle != INVALID_HANDLE)
      FileWrite(g_tradeHandle, IntegerToString(g_tradeNo), g_verName, _Symbol,
                TimeToString(g_tr.tOpen, TIME_DATE | TIME_MINUTES), g_tr.dir > 0 ? "BUY" : "SELL",
                g_tr.zType, g_tr.why,
                DoubleToString(g_tr.entry, _Digits), DoubleToString(g_tr.sl, _Digits),
                DoubleToString(g_tr.tp, _Digits), TimeToString(t, TIME_DATE | TIME_MINUTES),
                reason, DoubleToString(exitPx, _Digits), DoubleToString(g_tr.lots, 2),
                DoubleToString(money, 2), DoubleToString(R, 3), DoubleToString(priceR, 3),
                DoubleToString(g_tr.worstR, 3),
                DoubleToString(g_tr.zLo, _Digits), DoubleToString(g_tr.zHi, _Digits),
                propBefore, DoubleToString(g_tr.pRisk, 2),
                PhaseTxt(g_prop.phase), DoubleToString(g_prop.balance, 2),
                IntegerToString(g_prop.challenges), IntegerToString(g_prop.payouts));

   if(InpDraw)
     {
      string tag = PFX + "t" + IntegerToString(g_tradeNo);
      DrawBox(tag + "rk", g_tr.tOpen, g_tr.entry, t, g_tr.sl, C_RISK, true);
      DrawBox(tag + "rw", g_tr.tOpen, g_tr.entry, t, g_tr.tp, C_REWARD, true);
      DrawText(tag + "r", t, g_tr.dir > 0 ? MathMax(exitPx, g_tr.tp) : MathMin(exitPx, g_tr.tp),
               (R >= 0 ? "+" : "") + DoubleToString(R, 2) + "R", R > 0 ? C_GREEN : C_RED);
     }
   g_tr.open = false;
  }

//+------------------------------------------------------------------+
//| One closed 5-minute candle (same order of steps as the Pine)     |
//+------------------------------------------------------------------+
void Process5(const SBar &x, bool live)
  {
   g5.Push(x);
   long cur = g5.Cur();
   AtrPush(cur);
   FeedH1(x.t);

   // B. structure
   bool prevHasSL = st.hasSl, prevHasSH = st.hasSh;
   double prevSL = st.sl, prevSH = st.sh;
   bool gotSL, gotSH;
   double newSL = 0, newSH = 0;
   int ev = UpdateStruct(st, g5, gotSL, newSL, gotSH, newSH);
   int dir = st.dir;
   if(ev != 0) ArrayResize(liq, 0);
   if(MathAbs(ev) == 2) sq = 0;

   datetime tClose = x.t + 300;
   bool flat = !g_tr.open;
   bool canTrade = live && flat && g_today < InpMaxTrades && InWin(tClose) && InTest(tClose);

   // C. armed setup: invalidation, expiry, V4 trigger, V3 timeout
   if(sDir != 0)
     {
      bool kill = false;
      double zStop = (sDir == 1) ? sZBot - sBuf : sZTop + sBuf;
      if(sDir != dir) kill = true;
      else if(g_ver == 5 && g_htfDir != sDir) kill = true;
      else if((sDir == 1) ? (x.c < zStop) : (x.c > zStop)) kill = true;
      else if(cur - sArm >= InpExpireN) kill = true;
      else if(MinOfDay(NyT(tClose)) >= HHMM(InpWinEnd)) kill = true;
      else if(sMode == 4 && flat && cur > sArm)
        {
         bool touch = (sDir == 1) ? (x.l <= sZTop) : (x.h >= sZBot);
         if(touch)
           {
            bool swept = (sDir == 1) ? (prevHasSL && x.l < prevSL && x.c > prevSL)
                                     : (prevHasSH && x.h > prevSH && x.c < prevSH);
            if(swept && canTrade)
               EnterMarket(sDir, NormP((sDir == 1) ? x.l - sBuf : x.h + sBuf), "V4 entry candle");
            kill = true;
           }
        }
      else if(sMode == 3 && sTouched && cur - sTouchI >= InpV3N) kill = true;
      if(kill) KillSetup();
     }

   // D. sweep -> displacement -> arm
   if(sq != 0 && qD != dir) sq = 0;
   bool isBull = x.c > x.o, isBear = x.c < x.o;
   bool armNow = false;
   if(sq == 3) { armNow = true; sq = 0; }
   else if(sq == 2)
     {
      bool dispOK = ((qD == 1) ? (isBull && x.c > oH) : (isBear && x.c < oL))
                    && MathAbs(x.c - x.o) >= InpDispK * g_atrPrev;
      if(dispOK) sq = 3;
      else
        {
         qX = (qD == 1) ? MathMin(qX, x.l) : MathMax(qX, x.h);
         if((qD == 1) ? isBear : isBull) { oH = x.h; oL = x.l; oI = cur; }
         if(cur - qC >= InpDispN) sq = 0;
        }
     }
   else if(sq == 1)
     {
      qX = (qD == 1) ? MathMin(qX, x.l) : MathMax(qX, x.h);
      if((qD == 1) ? isBear : isBull) { oH = x.h; oL = x.l; oI = cur; }
      if((qD == 1) ? (x.c > qLvl) : (x.c < qLvl))
        {
         sq = 2; qC = cur;
         if(live) { s_sweeps++; DrawText(PFX + "sw" + IntegerToString(cur), x.t, qX, "sweep", C_AMBER); }
        }
      else if(cur - qB >= InpReclaimN - 1) sq = 0;
     }

   // a new sweep of liquidity inside the range
   if(sq == 0 && dir != 0 && ArraySize(liq) > 0)
     {
      bool found = false;
      double deep = 0;
      for(int k = ArraySize(liq) - 1; k >= 0; k--)
        {
         double lv = liq[k];
         if((dir == 1) ? (x.l < lv) : (x.h > lv))
           {
            if(!found) { deep = lv; found = true; }
            else deep = (dir == 1) ? MathMin(deep, lv) : MathMax(deep, lv);
            ArrayRemove(liq, k, 1);
           }
        }
      if(found)
        {
         sq = 1; qD = dir; qLvl = deep; qB = cur;
         qX = (dir == 1) ? x.l : x.h;
         oH = x.h; oL = x.l; oI = cur;
         if((dir == 1) ? (x.c > deep) : (x.c < deep))
           {
            sq = 2; qC = cur;
            if(live) { s_sweeps++; DrawText(PFX + "sw" + IntegerToString(cur), x.t, qX, "sweep", C_AMBER); }
           }
        }
     }

   // a new swing inside the range = liquidity (equal ones merged)
   bool add = false;
   double nl = 0;
   if(dir == 1 && gotSL && newSL > st.pLo && cur > st.bosI) { add = true; nl = newSL; }
   else if(dir == -1 && gotSH && newSH < st.pHi && cur > st.bosI) { add = true; nl = newSH; }
   if(add)
     {
      bool merged = false;
      for(int k = 0; k < ArraySize(liq); k++)
         if(MathAbs(liq[k] - nl) <= InpEqK * g_atr)
           {
            liq[k] = (dir == 1) ? MathMin(liq[k], nl) : MathMax(liq[k], nl);
            merged = true;
            break;
           }
      if(!merged) { int z = ArraySize(liq); ArrayResize(liq, z + 1); liq[z] = nl; }
     }

   if(armNow) Arm(cur, x, live);

   if(sDir != 0 && InpDraw && sZoneName != "")
      ObjectSetInteger(0, sZoneName, OBJPROP_TIME, 1, x.t + 600);

   // E. resting limit order for V1 / V2 / V5
   if(live)
     {
      bool okLim = sDir != 0 && sMode == 1 && !g_tr.open && g_today < InpMaxTrades && InWin(tClose) && InTest(tClose);
      if(okLim) PlaceLimit();
      else DeletePending();
     }
  }

void Arm(long cur, const SBar &x, bool live)
  {
   double aAtr = g_atr;
   double buf = InpBufK * aAtr;
   bool hasF = false;
   double fTop = 0, fBot = 0, fSize = 0;
   long fI = -1;
   long span = cur - oI;
   if(span >= 2)
      for(long k = 0; k <= span - 2; k++)
        {
         if(qD == 1 && g5.H(cur - k - 2) < g5.L(cur - k))
           {
            double bot = g5.H(cur - k - 2), top = g5.L(cur - k);
            bool hit = false;                     // already revisited = not a first touch
            for(long m = 0; m < k; m++) if(g5.L(cur - m) <= top) { hit = true; break; }
            if(!hit && top - bot >= InpFvgMinK * aAtr && bot <= oH + InpFvgNearK * aAtr && top > oL && top - bot > fSize)
              { hasF = true; fTop = top; fBot = bot; fSize = top - bot; fI = cur - k - 2; }
           }
         if(qD == -1 && g5.L(cur - k - 2) > g5.H(cur - k))
           {
            double top = g5.L(cur - k - 2), bot = g5.H(cur - k);
            bool hit = false;
            for(long m = 0; m < k; m++) if(g5.H(cur - m) >= bot) { hit = true; break; }
            if(!hit && top - bot >= InpFvgMinK * aAtr && top >= oL - InpFvgNearK * aAtr && bot < oH && top - bot > fSize)
              { hasF = true; fTop = top; fBot = bot; fSize = top - bot; fI = cur - k - 2; }
           }
        }
   bool useOB = (g_ver == 1) || !hasF;
   double zTop = useOB ? oH : fTop;
   double zBot = useOB ? oL : fBot;
   double lim = NormP((qD == 1) ? zTop : zBot);
   double stp = NormP((qD == 1) ? zBot - buf : zTop + buf);
   bool obHit = useOB && ((qD == 1) ? (x.l <= oH) : (x.h >= oL));
   bool valid = !obHit && ((qD == 1) ? (x.c > stp) : (x.c < stp)) && MathAbs(lim - stp) > _Point
                && (g_ver != 5 || g_htfDir == qD);
   if(!valid) return;

   if(sDir != 0) KillSetup();                   // a newer setup replaces the old one
   if(live) s_armed++;
   sDir = qD;
   sMode = (g_ver == 3) ? 3 : (g_ver == 4) ? 4 : 1;
   sLim = lim; sStop = stp; sZTop = zTop; sZBot = zBot; sBuf = buf;
   sArm = cur; sTouched = false; sTouchI = -1; sUseOB = useOB;
   g_zoneN++;
   sZoneName = PFX + "z" + IntegerToString(g_zoneN);
   sZoneT1 = g5.T(useOB ? oI : fI);
   if(live) DrawBox(sZoneName, sZoneT1, zTop, x.t + 600, zBot, useOB ? C_ZONE : C_FVG, true);
   else sZoneName = "";
  }

//+------------------------------------------------------------------+
//| One closed 1-minute candle: prop equity check + V3 trigger       |
//+------------------------------------------------------------------+
void Process1(const SBar &m)
  {
   PropMinute(m);
   if(sDir == 0 || sMode != 3 || g_tr.open) return;
   if(m.t < g5.T(sArm) + 300) return;           // only candles after the arming candle
   double zStop = (sDir == 1) ? sZBot - sBuf : sZTop + sBuf;
   if(!sTouched && ((sDir == 1) ? (m.l <= sZTop) : (m.h >= sZBot)))
     {
      sTouched = true;
      sTouchI = g5.Cur() + 1;
      sTX = (sDir == 1) ? m.l : m.h;
      m1.Reset();
      m1Has = false;
     }
   if(!sTouched) return;
   sTX = (sDir == 1) ? MathMin(sTX, m.l) : MathMax(sTX, m.h);
   if(m1Has && ((sDir == 1) ? (m.c > m1Lvl) : (m.c < m1Lvl)))
     {
      double stp = NormP((sDir == 1) ? sTX - sBuf : sTX + sBuf);
      if(g_today < InpMaxTrades && InWin(m.t + 60) && InTest(m.t + 60)) EnterMarket(sDir, stp, "V3 1m shift");
      KillSetup();
      return;
     }
   if((sDir == 1) ? (m.c < zStop) : (m.c > zStop)) { KillSetup(); return; }
   double px = 0; long pxI = -1;
   if(SwingStep(m1, sDir, m.o, m.h, m.l, m.c, 0, px, pxI)) { m1Has = true; m1Lvl = px; }
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
void ShowPanel()
  {
   if(!InpDraw) return;
   const int W = 410, rowH = 18, rows = 15;
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int x0 = MathMax(10, chartW - W - 20), y0 = 24;
   PanelBg(PFX + "bg", x0, y0, W, rows * rowH + 12);

   double wr = s_T > 0 ? 100.0 * s_W / s_T : 0.0;
   string pf = s_gL > 0 ? DoubleToString(s_gW / s_gL, 2) : "-";
   string span = s_first > 0 ? TimeToString(s_first, TIME_DATE) + "  to  " + TimeToString(s_last, TIME_DATE) : "-";

   string L[15], V[15];
   color LC[15], VC[15];
   for(int i = 0; i < rows; i++) { LC[i] = C_WHITE; VC[i] = C_WHITE; }
   L[0] = "BTH | Brad Goh SMC";            V[0] = _Symbol + " | M5";          LC[0] = C_GREEN; VC[0] = C_GREEN;
   L[1] = "Test version";                   V[1] = g_verName;                  VC[1] = C_AMBER;
   L[2] = "Window | 1R | target";           V[2] = "07:00 London - 11:30 NY | " + DoubleToString(InpRiskUSD, 0) + " | " + DoubleToString(InpRR, 1) + "R"; VC[2] = C_AMBER;
   L[3] = "TESTED HISTORY";                 V[3] = span;                        LC[3] = C_GREEN;
   L[4] = "Sweeps | setups armed";          V[4] = IntegerToString(s_sweeps) + " | " + IntegerToString(s_armed);
   L[5] = "Trades";                         V[5] = IntegerToString(s_T) + (s_BE > 0 ? "  (" + IntegerToString(s_BE) + " break-even)" : "");
   L[6] = "Win rate";                       V[6] = DoubleToString(wr, 1) + "%";
   L[7] = "Total (R, after costs)";         V[7] = DoubleToString(s_sumR, 2) + "R";  VC[7] = s_sumR >= 0 ? C_GREEN : C_RED;
   L[8] = "Average per trade";              V[8] = s_T > 0 ? DoubleToString(s_sumR / s_T, 3) + "R" : "-";
   L[9] = "Profit factor";                  V[9] = pf;
   L[10] = "Max drawdown (R)";              V[10] = DoubleToString(s_ddR, 2) + "R";
   L[11] = "Worst losing streak";           V[11] = IntegerToString(s_maxConsec);
   L[12] = "Total before costs (R)";        V[12] = DoubleToString(s_sumPriceR, 2) + "R";
   L[13] = "Fills | costs";                 V[13] = "real ticks | spread + commission + swap"; LC[13] = C_GREY; VC[13] = C_GREY;
   L[14] = "coded by Backtest the Hype";    V[14] = s_dataWarn ? s_dataWarnTxt : "spec v3.1"; LC[14] = C_GREY; VC[14] = s_dataWarn ? C_AMBER : C_GREY;
   for(int i = 0; i < rows; i++)
     {
      int y = y0 + 7 + i * rowH;
      int sz = i >= 13 ? 8 : 9;
      PanelLabel(PFX + "l" + IntegerToString(i), x0 + 10, y, L[i], LC[i], ANCHOR_LEFT_UPPER, sz);
      PanelLabel(PFX + "v" + IntegerToString(i), x0 + W - 10, y, V[i], VC[i], ANCHOR_RIGHT_UPPER, sz);
     }
   if(InpProp) ShowPropPanel(x0, y0 + rows * rowH + 24, W, rowH);
   ChartRedraw(0);
  }

void ShowPropPanel(int x0, int y0, int W, int rowH)
  {
   const int rows = 9;
   PanelBg(PFX + "pbg", x0, y0, W, rows * rowH + 12);
   string L[9], V[9];
   color LC[9], VC[9];
   for(int i = 0; i < rows; i++) { LC[i] = C_WHITE; VC[i] = C_WHITE; }
   double net = g_prop.payoutMoney - g_prop.fees;
   L[0] = "PROP FIRM CHALLENGE";
   V[0] = DoubleToString(InpPropStart / 1000.0, 0) + "k | " + DoubleToString(InpPropRiskPct, 1) + "% risk | "
        + DoubleToString(InpPhase1Pct, 0) + "% / " + DoubleToString(InpPhase2Pct, 0) + "% | max " + DoubleToString(InpMaxLossPct, 0) + "%";
   LC[0] = C_GREEN;
   L[1] = "Paid  -  spent  =  net";
   V[1] = DoubleToString(g_prop.payoutMoney, 0) + "  -  " + DoubleToString(g_prop.fees, 0) + "  =  " + DoubleToString(net, 0);
   VC[1] = net > 0 ? C_GREEN : (net < 0 ? C_RED : C_WHITE);
   L[2] = "Challenges bought";             V[2] = IntegerToString(g_prop.challenges);
   L[3] = "Phase 1 / Phase 2 passed";      V[3] = IntegerToString(g_prop.p1pass) + " / " + IntegerToString(g_prop.p2pass);
   L[4] = "Payouts taken";                 V[4] = IntegerToString(g_prop.payouts); VC[4] = g_prop.payouts > 0 ? C_GREEN : C_WHITE;
   L[5] = "Where it died (P1 / P2 / funded)"; V[5] = IntegerToString(g_prop.failP1) + " / " + IntegerToString(g_prop.failP2) + " / " + IntegerToString(g_prop.failFunded);
   L[6] = "Now";                           V[6] = PhaseTxt(g_prop.phase) + " | balance " + DoubleToString(g_prop.balance, 0);
   L[7] = "Trades skipped by daily 5% guard"; V[7] = IntegerToString(g_prop.guarded);
   L[8] = "Max loss on equity, payouts on closed money"; V[8] = "our rules, not a named firm"; LC[8] = C_GREY; VC[8] = C_GREY;
   for(int i = 0; i < rows; i++)
     {
      int y = y0 + 7 + i * rowH;
      int sz = i == 8 ? 8 : 9;
      PanelLabel(PFX + "pl" + IntegerToString(i), x0 + 10, y, L[i], LC[i], ANCHOR_LEFT_UPPER, sz);
      PanelLabel(PFX + "pv" + IntegerToString(i), x0 + W - 10, y, V[i], VC[i], ANCHOR_RIGHT_UPPER, sz);
     }
  }

void Out(int h, const string txt)
  {
   Print(txt);
   if(h != INVALID_HANDLE) FileWriteString(h, txt + "\r\n");
  }

void PrintSummary()
  {
   int h = INVALID_HANDLE;
   if(InpLogCSV)
      h = FileOpen("BTH_BradGoh_summary_" + _Symbol + "_V" + IntegerToString(g_ver) + ".txt",
                   FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   double wr = s_T > 0 ? 100.0 * s_W / s_T : 0.0;
   Out(h, "=====================================================");
   Out(h, "BTH Brad Goh SMC v1.02  |  " + g_verName + "  |  " + _Symbol + "  |  M5");
   Out(h, "Tester ran " + TimeToString(g_firstTick, TIME_DATE) + " -> " + TimeToString(TimeCurrent(), TIME_DATE)
          + "   |   trades counted " + TimeToString(InpFrom, TIME_DATE) + " -> " + TimeToString(InpTo - 1, TIME_DATE));
   if(g_firstTick > InpFrom + 7 * 86400 || TimeCurrent() < InpTo - 7 * 86400)
     {
      s_dataWarn = true;
      s_dataWarnTxt += " | TESTER DATES DO NOT COVER THE TEST PERIOD - set 2021.01.01 to 2026.09.30";
     }
   Out(h, "Trades " + IntegerToString(s_T) + "   win rate " + DoubleToString(wr, 1) + "%   total "
          + DoubleToString(s_sumR, 2) + "R (before costs " + DoubleToString(s_sumPriceR, 2) + "R)   profit factor "
          + (s_gL > 0 ? DoubleToString(s_gW / s_gL, 2) : "-"));
   Out(h, "Max drawdown " + DoubleToString(s_ddR, 2) + "R   worst losing streak " + IntegerToString(s_maxConsec));
   Out(h, "Sweeps " + IntegerToString(s_sweeps) + "   setups armed " + IntegerToString(s_armed)
          + "   orders skipped " + IntegerToString(s_skipped) + "   order errors " + IntegerToString(s_orderFail)
          + (s_orderFail > 0 ? " (last code " + IntegerToString((int)s_lastRet) + ")" : "")
          + "   lots cut for margin " + IntegerToString(s_marginCut)
          + "   skipped by min stop " + IntegerToString(s_minStop) + " (min " + DoubleToString(MinStop(), _Digits) + ")");
   if(InpProp)
      Out(h, "PROP: challenges " + IntegerToString(g_prop.challenges) + "  P1 " + IntegerToString(g_prop.p1pass)
             + "  P2 " + IntegerToString(g_prop.p2pass) + "  payouts " + IntegerToString(g_prop.payouts)
             + "  paid " + DoubleToString(g_prop.payoutMoney, 0) + "  spent " + DoubleToString(g_prop.fees, 0)
             + "  NET " + DoubleToString(g_prop.payoutMoney - g_prop.fees, 0)
             + "  worst equity " + DoubleToString(g_prop.worstEq, 1) + "%   skipped by daily guard " + IntegerToString(g_prop.guarded));
   if(s_dataWarn) Out(h, "WARNING:" + s_dataWarnTxt);
   Out(h, "=====================================================");
   if(h != INVALID_HANDLE) FileClose(h);
  }

//+------------------------------------------------------------------+
//| CSV                                                              |
//+------------------------------------------------------------------+
void CsvInit()
  {
   if(!InpLogCSV) return;
   string tag = _Symbol + "_V" + IntegerToString(g_ver);
   g_tradeHandle = FileOpen("BTH_BradGoh_trades_" + tag + ".csv", FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
   if(g_tradeHandle != INVALID_HANDLE)
      FileWrite(g_tradeHandle, "no", "version", "symbol", "open_time", "side", "zone", "entry_type",
                "entry", "stop", "target", "close_time", "exit_reason", "exit_price", "lots",
                "money", "R", "R_before_costs", "worst_R", "zone_low", "zone_high",
                "prop_phase_before", "prop_risk", "prop_phase_after", "prop_balance_after",
                "prop_challenge_no", "prop_payouts");
   g_propHandle = FileOpen("BTH_BradGoh_challenges_" + tag + ".csv", FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
   if(g_propHandle != INVALID_HANDLE)
      FileWrite(g_propHandle, "version", "symbol", "challenge_no", "started", "ended", "outcome",
                "balance", "payouts_so_far", "payout_money", "fees_so_far");
  }

void CheckData()
  {
   datetime fd = (datetime)SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_FIRSTDATE);
   long bars = SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_BARS_COUNT);
   if(bars < 1000 || (fd > 0 && fd > TimeCurrent() - 30 * 86400))
     {
      s_dataWarn = true;
      s_dataWarnTxt = " thin 1-minute data";
      Print("BTH data warning: 1-minute history looks thin - V3 and the prop equity check need it");
     }
  }

//+------------------------------------------------------------------+
//| Warm-up: feed history before the test starts (no trading)        |
//+------------------------------------------------------------------+
void WarmUp()
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M5, 1, InpWarm5, r);
   for(int i = 0; i < n; i++)
     {
      SBar b; b.t = r[i].time; b.o = r[i].open; b.h = r[i].high; b.l = r[i].low; b.c = r[i].close;
      Process5(b, false);
      g_last5 = b.t;
     }
   sDir = 0;
   sq = 0;
   g_last1 = iTime(_Symbol, PERIOD_M1, 1);
   PrintFormat("BTH warm-up: %d five-minute candles, direction now %d, 1-hour direction %d", n, st.dir, g_htfDir);
  }

//+------------------------------------------------------------------+
//| Standard event handlers                                          |
//+------------------------------------------------------------------+
int OnInit()
  {
   // where the CSV logs land on disk - printed so you never have to hunt for it
   PrintFormat("LOG FILES ARE HERE -> %s", TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files");
   g_ver = (int)InpVersion;
   g_verName = VerName(g_ver);
   if(InpRiskUSD <= 0 || InpRR <= 0 || InpMaxTrades < 1) return INIT_PARAMETERS_INCORRECT;

   g5.Init(); gH.Init();
   st.Reset(); stH.Reset(); m1.Reset();
   ArrayResize(liq, 0);
   g_tr.open = false;
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetDeviationInPoints(50);
   PropInit(TimeCurrent());
   CsvInit();
   Print("BTH Brad Goh SMC | ", g_verName, " | ", _Symbol, " | server minus New York = ", InpServerMinusNY, "h");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ShowPanel();
   PrintSummary();
   if(InpProp) PropLog(TimeCurrent(), "STILL RUNNING " + PhaseTxt(g_prop.phase));
   if(g_tradeHandle != INVALID_HANDLE) { FileClose(g_tradeHandle); g_tradeHandle = INVALID_HANDLE; }
   if(g_propHandle != INVALID_HANDLE) { FileClose(g_propHandle); g_propHandle = INVALID_HANDLE; }
   if(!MQLInfoInteger(MQL_TESTER)) ObjectsDeleteAll(0, PFX);
  }

double OnTester() { return s_sumR; }

void OnTick()
  {
   datetime now = TimeCurrent();
   if(!g_warm)
     {
      WarmUp();
      CheckData();
      g_warm = true;
      g_firstTick = now;
     }
   if(!g_propOn && now >= InpFrom) { PropInit(now); g_propOn = true; }
   if(now >= InpTo && g_pendTicket > 0) DeletePending();

   // 1. fills and closes
   bool has = MyPosition();
   if(has && !g_tr.open) OnFill();
   else if(!has && g_tr.open) Settle(now);

   // 2. new broker day
   long day = (long)now / 86400;
   if(day != g_dayIdx)
     {
      g_dayIdx = day;
      g_today = 0;
      g_prop.dayStart = g_prop.balance;
      ShowPanel();
     }

   // 3. Friday close-out (16:50 New York)
   if(g_tr.open && Dow(NyT(now)) == 5 && MinOfDay(NyT(now)) >= HHMM(InpFriClose))
      g_trade.PositionClose(g_tr.ticket);

   // 4. closed 1-minute candles (V3 + prop equity), then closed 5-minute candles
   datetime o1 = iTime(_Symbol, PERIOD_M1, 0);
   if(o1 > 0 && o1 > g_last1 + 60)
     {
      MqlRates r[];
      int n = CopyRates(_Symbol, PERIOD_M1, g_last1 + 1, o1 - 1, r);
      for(int i = 0; i < n; i++)
        {
         if(r[i].time <= g_last1 || r[i].time >= o1) continue;
         SBar b; b.t = r[i].time; b.o = r[i].open; b.h = r[i].high; b.l = r[i].low; b.c = r[i].close;
         Process1(b);
         g_last1 = b.t;
        }
      if(n <= 0) g_last1 = o1 - 60;
     }
   datetime o5 = iTime(_Symbol, PERIOD_M5, 0);
   if(o5 > 0 && o5 > g_last5 + 300)
     {
      MqlRates r[];
      int n = CopyRates(_Symbol, PERIOD_M5, g_last5 + 1, o5 - 1, r);
      for(int i = 0; i < n; i++)
        {
         if(r[i].time <= g_last5 || r[i].time >= o5) continue;
         SBar b; b.t = r[i].time; b.o = r[i].open; b.h = r[i].high; b.l = r[i].low; b.c = r[i].close;
         Process5(b, true);
         g_last5 = b.t;
        }
      if(n <= 0) g_last5 = o5 - 300;
     }
  }
//+------------------------------------------------------------------+
