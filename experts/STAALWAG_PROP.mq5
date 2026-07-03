//+------------------------------------------------------------------+
//|                   STAALWAG PROP v1.0                              |
//|   Multi-pair prop-firm scalper (auto firm recognition)            |
//|   Rule-locked per firm: daily loss Â· static/trailing max Â· target |
//|   Scalp window: configurable local hours (default 18:00-22:00)    |
//|   Signal: Key Levels + Sweeps + OB/FVG + Markov + HTF Bias       |
//|   Trade Mgr: Trail Â· BE Â· Partial TP Â· Profit Lock Â· Min-Hold    |
//|   AUTO trade defaults ON. Risk-first, consistency-aware.          |
//+------------------------------------------------------------------+
#property copyright "STAALWAG"
#property version   "1.00"
#property description "STAALWAG PROP â multi-firm prop scalper"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// INPUTS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
input group "âââ Pairs âââ"
// Net-positive pairs only from the 2-week review. Bleeders + USDJPY churn +
// GBPJPY removed. EURUSD/USDCHF/EURCHF/AUDUSD = earners; EURAUD tiny positive.
input string InpPairs         = "EURUSD,USDCHF,EURCHF,AUDUSD,EURAUD";
input int    InpMaxConcurrent = 2;       // Max concurrent positions (keep low for prop DD)
input string InpSymbolSuffix  = "AUTO";  // Broker symbol suffix ("AUTO"=detect, or e.g. ".raw" / "m" / "" )

enum PropFirm
{
   PF_AUTO,        // Auto-detect from account company/server
   PF_FUNDEDNEXT,  // FundedNext Stellar 2-step (8/5, d5, m10 static)
   PF_FTMO,        // FTMO 2-step (10/5, d5, m10 static)
   PF_GOATFUNDED,  // Goat Funded 2-step Std (8/6, d4, m10 static)
   PF_FUNDINGPIPS, // FundingPips 2-step Std (8/5, d5, m10 static)
   PF_THE5ERS,     // The5ers High Stakes (10/5, d5, m10 static)
   PF_E8,          // E8 Classic 2-step (8/4, d4, m8 TRAILING)
   PF_LEVERAGED,   // Leveraged Turbo Trade 1-step (t6, d3, m6 TRAILING; +3 profit days, 20% consistency)
   PF_BLACKBULL,   // BlackBull = broker, no prop rules (conservative cap)
   PF_CUSTOM       // Use the manual values below
};

input group "âââ Prop Firm Profile âââ"
input PropFirm InpPropFirm      = PF_AUTO; // Recognise firm -> auto-apply its risk rules
input int    InpPhase           = 1;      // Challenge phase: 1 or 2 (sets profit target)
input double InpInitialBalance  = 0.0;    // Challenge start balance (0 = use account balance)
input bool   InpStopAtTarget    = true;   // Stop opening new trades once phase target hit
input double InpDailyProfitCap  = 2.5;    // Halt for the day after +this% of balance (0=off)
input double InpConsistencyPct  = 0.0;    // Firm consistency rule % (e.g 15/20/40). 0=off. Caps daily profit to this share of the profit target so no day dominates; auto-sets min profitable days.

input group "âââ Manual Rules (PF_CUSTOM only) âââ"
input double InpProfitTargetPct = 8.0;    // Phase target % (P1=8, P2=5 typical)
input double InpMaxLossPct      = 10.0;   // Hard overall max loss %
input double InpMaxLossGuardPct = 8.0;    // Internal kill before the wall
input double InpDailyLossPct    = 5.0;    // Hard daily loss %
input double InpDailyGuardPct   = 3.5;    // Internal daily halt before the wall
input bool   InpTrailingMaxDD   = false;  // Max loss trails equity peak (else static vs initial)

input group "âââ Account & Risk âââ"
input bool   InpAutoLot        = true;   // Auto lot â risk-based sizing off InpInitialBalance
input double InpRiskPercent    = 0.3;    // Risk % per trade â small, so 2-3 losses can't scrap the day
input double InpFixedLot       = 0.05;   // Fixed lot (if AutoLot=false)
input double InpMaxLot         = 1.00;   // Hard max lot â safety ceiling
input int    InpMaxTradesDay   = 8;      // Cap trades per day (overtrade guard)

input group "âââ Signal Engine (scalp) âââ"
input ENUM_TIMEFRAMES InpSignalTF   = PERIOD_M5;  // Scalp timeframe (M5)
input int    InpScoreThreshold      = 4;           // Min score (0-10) â lower = more trades
input bool   InpUseBiasFilter       = true;

input group "âââ Scalp Entries (frequency) âââ"
// These run alongside the key-level/sweep logic so quiet nights still trade.
input bool   InpUseMomentum   = true;   // Micro-breakout of recent swing in trend
input bool   InpUsePullback   = true;   // Pullback to fast MA in trend, then go
input int    InpBreakoutLB    = 6;      // Bars to define the recent swing hi/lo
input int    InpScalpFastMA   = 9;      // Fast MA (signal TF) for trend/pullback
input int    InpScalpSlowMA   = 21;     // Slow MA (signal TF) for trend
input double InpMomBodyATR    = 0.25;   // Min breakout candle body (ÃATR)
input int    InpEMAFast             = 20;
input int    InpEMASlow             = 50;
input double InpWickRatio           = 1.5;
input double InpSLBuffer            = 0.5;   // Buffer beyond swing â avoids wick hunts
input double InpMinSLATR            = 1.0;   // Min 1.0ÃATR scalp stop (tighter than swing EA)
input double InpRRRatio             = 1.5;   // Scalp RR â quick targets, decent expectancy
input double InpLevelProximity      = 0.4;
input double InpMaxSpreadPips       = 2.5;   // Allow a touch wider (gold/evening spreads)

input group "âââ Markov Regime âââ"
input bool   InpUseMarkov     = true;
input double InpMarkovThr     = 0.3;
input double InpMarkovPersist = 0.80;
input int    InpMarkovLB      = 10;
input int    InpMarkovHold    = 3;

input group "âââ Trade Manager âââ"
input int    InpMinHoldSeconds = 180;   // HFT guard: no EA-driven exits before this age (FTMO flags <2min)
input bool   InpUseProfitLock = true;   // Once trade is +$X, push SL so it can't lose
input double InpLockProfitUSD = 3.0;    // Floating profit ($) that arms the no-loss lock
input bool   InpUseTrail      = true;
input double InpTrailMult     = 1.5;
input bool   InpUseBreakEven  = true;
input double InpBEMult        = 0.7;     // Move to BE early (0.7R) â turn would-be losers into scratches

input group "âââ Per-Pair Auto-Disable âââ"
input bool   InpUsePairGate    = true;  // Auto-pause a pair that bleeds (resets next day)
input double InpPairMaxLossPct = 1.5;   // Pause pair after it loses this % of initial balance today
input int    InpPairStopStreak = 3;     // ...or after this many losers in a row on the pair
input bool   InpUsePartialTP  = true;
input double InpPartialRR     = 1.0;    // Bank half at 1R â lock small wins before reversals
input double InpPartialFrac   = 0.50;   // Close 50% at 1R â bank the win, runner covers the rest
input bool   InpExtendTP      = true;
input bool   InpProgressTrail = true;
input double InpTrailR2Mult   = 1.2;
input double InpTrailR3Mult   = 0.8;

input group "âââ News Filter (currency-aware) âââ"
input bool   InpUseNewsFilter = true;  // Block entries around high-impact news
input int    InpNewsBeforeMin = 15;    // Block this many minutes BEFORE the event
input int    InpNewsAfterMin  = 15;    // Block this many minutes AFTER the event
input bool   InpNewsHighOnly  = true;  // High-impact only (false = high + medium)

input group "âââ Scalp Session Window âââ"
input double InpSpikeATRmult    = 4.0;   // SPIKE GUARD: freeze a pair's entries when its candle range >= this x ATR (0=off). Blocks news/fixing-flow spikes the calendar can't see.
input int    InpSpikeCoolBars   = 3;     // SPIKE GUARD: bars to stay frozen after a spike
input bool   InpUseSession      = true;  // Restrict trading to the scalp window
input int    InpSessStartHour   = 18;    // Local window open hour (24h)
input int    InpSessEndHour     = 22;    // Local window close hour (24h)
input int    InpServerGMTOffset = 3;     // Broker/server GMT offset (most MT5 = GMT+3)
input int    InpLocalGMTOffset  = 12;    // Your local GMT offset (NZ = 12 std / 13 DST)
input bool   InpFridayCutoff    = true;  // Skip late-Friday entries

input group "âââ Display âââ"
input bool   InpShowDash      = true;
input bool   InpAutoTradeOn   = true;    // AUTO trade ON at startup (user wants always-on)
input int    InpDashX         = 20;
input int    InpDashY         = 30;
input int    InpTimerSec      = 2;

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// CONSTANTS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
#define PFX    "SWF_"
#define MAGIC  202606
#define ASIA_OPEN  0    // Asia session hours (server time) for key-level calc
#define ASIA_CLOSE 7
#define W      560
#define ROW_H  28
#define HDR_H  36
#define SEC_H  26

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// PER-PAIR STATE
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
struct PairState
{
   string symbol;
   // Indicator handles
   int    hATR, hEMAFH4, hEMASH4, hEMAFD1, hEMASD1;
   // Scaled params
   ENUM_TIMEFRAMES sTF, htf1, htf2;
   double trailMult, rrRatio, proxMult, mkThr;
   // Session flags
   bool   sessLDN, sessNY, sessAsia;
   string pairClass;
   // ATR
   double atr;
   // Markov
   double mkCnt[3][3];
   int    mkRegime, mkConfirmed, mkHeldCount;
   double mkPersistence, mkConviction;
   // Signal
   int    signal, score;
   double entryPrice, slPrice, tpPrice;
   bool   partialDone, beDone;
   datetime lastBar;
   // Key levels
   double PDH, PDL, PWH, PWL, AsiaH, AsiaL;
   double BullOBH, BullOBL, BearOBH, BearOBL;
   double BullFVGT, BullFVGB, BearFVGT, BearFVGB;
   // Streak
   int    consecBuy, consecSell, consecAny;
   datetime cdBuyUntil, cdSellUntil;
   // Stats
   int    wins, losses;
   // Per-pair auto-disable gate
   double dayPnL;       // realized P&L for this pair today
   bool   disabled;     // paused for the rest of the day
   datetime spikeUntil; // entries frozen until this time after a flow spike
};

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// GLOBALS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
CTrade        trade;
CPositionInfo pos;

PairState g_ps[];
int       g_nPairs = 0;
string    g_brokerSuffix = "";   // detected once in ParsePairs

// ââ News filter cache (per currency) ââ
string    g_newsCcy[8] = {"USD","EUR","GBP","JPY","CHF","CAD","AUD","NZD"};
bool      g_newsBlk[8];
datetime  g_newsCacheT = 0;

double   g_startEquity = 0.0;    // equity at start of current trading day
double   g_dailyPnL    = 0.0;
double   g_peakEquity  = 0.0;
datetime g_lastDay     = 0;
bool     g_eaStopped   = false;  // hard stop on max loss (permanent until reattach)
bool     g_dailyHalt   = false;  // no new trades rest of day (daily loss or profit cap)
bool     g_targetHit   = false;  // phase profit target reached
int      g_tradesToday = 0;      // trades opened today (overtrade guard)

// ââ Effective risk profile (set in OnInit from prop-firm recognition) ââ
double   g_initBal       = 6000.0;  // balance drawdowns are measured against
double   g_profitTgtPct  = 8.0;
double   g_maxLossPct    = 10.0;    // hard wall
double   g_maxGuardPct   = 8.0;     // internal kill
double   g_dailyLossPct  = 5.0;     // hard wall
double   g_dailyGuardPct = 3.5;     // internal halt
bool     g_trailMaxDD    = false;   // trailing vs static max loss
string   g_firmName      = "CUSTOM";

int      g_dashX, g_dashY;
bool     g_minimized = false;
bool     g_autoTrade = false;
#define  GV_AUTO  "SWF_AutoTrade"

// For manual trade panel (pair selector)
int      g_pairIdx   = 0;
double   g_tradeLot  = 0.01;

// Open position row tracker (for dashboard cleanup)
ulong    g_openTickets[];
int      g_lastPosCount = -1;

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// WATERMARK â STAALWAG emblem, faint, bottom-right of chart
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void DrawWatermark()
{
   string nm = PFX+"WM";
   if(ObjectFind(0,nm) < 0) ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
   ObjectSetString (0,nm,OBJPROP_TEXT,"STAALWAG");
   ObjectSetString (0,nm,OBJPROP_FONT,"Arial Bold");
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,16);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,(color)C'160,124,34');
   ObjectSetInteger(0,nm,OBJPROP_CORNER,CORNER_RIGHT_LOWER);
   ObjectSetInteger(0,nm,OBJPROP_ANCHOR,ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,20);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,18);
   ObjectSetInteger(0,nm,OBJPROP_BACK,false);
   ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// SYMBOL SUFFIX RESOLVER â handles broker/prop naming (EURUSD vs EURUSD.r etc)
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
bool SymbolReal(string s)
{
   // exists + tradeable if select works and it has a real point/tick size
   if(!SymbolSelect(s, true)) return false;
   return (SymbolInfoDouble(s, SYMBOL_POINT) > 0.0 &&
           SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE) > 0.0);
}

void DetectSuffix()
{
   if(InpSymbolSuffix != "AUTO") { g_brokerSuffix = InpSymbolSuffix; return; }
   // Derive the broker suffix from the chart symbol: strip a known 6-char base.
   string cs = _Symbol; StringToUpper(cs);
   string bases[] = {"EURUSD","GBPUSD","USDJPY","USDCHF","USDCAD","AUDUSD",
                     "NZDUSD","EURGBP","EURJPY","XAUUSD"};
   for(int b=0; b<ArraySize(bases); b++)
   {
      int p = StringFind(cs, bases[b]);
      if(p >= 0) { g_brokerSuffix = StringSubstr(_Symbol, p+6); return; }
   }
   g_brokerSuffix = "";
}

// Resolve a base symbol (e.g. "EURUSD") to the broker's real name. Returns "" if
// no variant exists, so the pair is skipped only when genuinely unavailable.
string ResolveSymbol(string base)
{
   // Library of suffixes seen across props/brokers (IC Markets, Eightcap, Purple,
   // ThinkMarkets, BlackBull, FTMO, FundedNext, FundingPips, Goat, E8, The5ers ...)
   string cands[] = {
      "",   ".",  ".r",  ".raw", ".pro", ".ecn", ".stp", ".std", ".i", ".a",
      ".c", ".e", ".m",  ".z",   ".x",   ".s",   ".sb",  ".sml", ".cnt", ".cent",
      ".v", ".p", ".roboforex", "m", "c", "z", "+", "-", "_", "#", "..", ".fx" };
   // Try the detected/forced suffix first.
   if(g_brokerSuffix != "" && SymbolReal(base + g_brokerSuffix)) return base + g_brokerSuffix;
   if(SymbolReal(base)) return base;
   for(int k=0; k<ArraySize(cands); k++)
      if(SymbolReal(base + cands[k])) return base + cands[k];
   return "";
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// NEWS FILTER â currency-aware (MT5 Economic Calendar)
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// Refreshes which CURRENCIES have a high-impact event inside the blackout
// window. Cached (30s) so the calendar isn't hammered every tick. Note: the
// MT5 calendar is empty in the Strategy Tester, so this never false-blocks
// backtests â it only acts on a live/demo terminal with calendar data.
void RefreshNewsCache(datetime now)
{
   if(!InpUseNewsFilter) { for(int i=0;i<8;i++) g_newsBlk[i]=false; return; }
   if(now - g_newsCacheT < 30) return;
   g_newsCacheT = now;

   datetime from = now - InpNewsAfterMin*60;
   datetime to   = now + InpNewsBeforeMin*60;
   for(int i=0;i<8;i++)
   {
      g_newsBlk[i] = false;
      MqlCalendarValue vals[];
      int cnt = CalendarValueHistory(vals, from, to, NULL, g_newsCcy[i]);
      for(int v=0; v<cnt; v++)
      {
         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[v].event_id, ev)) continue;
         if(InpNewsHighOnly && ev.importance < CALENDAR_IMPORTANCE_HIGH) continue;
         if(!InpNewsHighOnly && ev.importance < CALENDAR_IMPORTANCE_MODERATE) continue;
         g_newsBlk[i] = true; break;
      }
   }
}

int CcyIdx(string c){ for(int i=0;i<8;i++) if(g_newsCcy[i]==c) return i; return -1; }

// Block a pair ONLY if one of its two currencies has the news event.
bool NewsBlockedSym(string sym)
{
   if(!InpUseNewsFilter) return false;
   int ib = CcyIdx(SymbolInfoString(sym, SYMBOL_CURRENCY_BASE));
   int iq = CcyIdx(SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT));
   if(ib >= 0 && g_newsBlk[ib]) return true;
   if(iq >= 0 && g_newsBlk[iq]) return true;
   return false;
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// INIT HELPERS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void ParsePairs()
{
   string raw = InpPairs;
   StringTrimLeft(raw);
   StringTrimRight(raw);
   string parts[];
   int n = StringSplit(raw, ',', parts);
   ArrayResize(g_ps, n);
   g_nPairs = 0;
   DetectSuffix();
   if(g_brokerSuffix != "") Print("SCALPER: broker suffix detected = '", g_brokerSuffix, "'");
   for(int i = 0; i < n; i++)
   {
      string sym = parts[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      StringToUpper(sym);
      if(sym == "") continue;
      // Major forex ONLY â block metals, crypto, indices, oil
      if(StringFind(sym,"XAU")>=0 || StringFind(sym,"XAG")>=0 ||
         StringFind(sym,"OIL")>=0 || StringFind(sym,"BTC")>=0 ||
         StringFind(sym,"ETH")>=0 || StringFind(sym,"SPX")>=0 ||
         StringFind(sym,"NAS")>=0 || StringFind(sym,"DAX")>=0 ||
         StringFind(sym,"US30")>=0|| StringFind(sym,"NDX")>=0)
      {
         Print("SCALPER: skipping non-forex symbol ", sym);
         continue;
      }
      // Resolve to the broker's real name across the suffix library
      string resolved = ResolveSymbol(sym);
      if(resolved == "")
      {
         Print("SCALPER: symbol not found on this broker â ", sym, " (skipped)");
         continue;
      }
      sym = resolved;
      g_ps[g_nPairs].symbol       = sym;
      g_ps[g_nPairs].hATR         = INVALID_HANDLE;
      g_ps[g_nPairs].hEMAFH4      = INVALID_HANDLE;
      g_ps[g_nPairs].hEMASH4      = INVALID_HANDLE;
      g_ps[g_nPairs].hEMAFD1      = INVALID_HANDLE;
      g_ps[g_nPairs].hEMASD1      = INVALID_HANDLE;
      g_ps[g_nPairs].signal       = 0;
      g_ps[g_nPairs].score        = 0;
      g_ps[g_nPairs].atr          = 0.0;
      g_ps[g_nPairs].partialDone  = false;
      g_ps[g_nPairs].beDone       = false;
      g_ps[g_nPairs].lastBar      = 0;
      g_ps[g_nPairs].mkRegime     = 0;
      g_ps[g_nPairs].mkConfirmed  = 0;
      g_ps[g_nPairs].mkHeldCount  = 0;
      g_ps[g_nPairs].mkPersistence= 0.33;
      g_ps[g_nPairs].mkConviction = 0.0;
      g_ps[g_nPairs].consecBuy    = 0;
      g_ps[g_nPairs].consecSell   = 0;
      g_ps[g_nPairs].consecAny    = 0;
      g_ps[g_nPairs].cdBuyUntil   = 0;
      g_ps[g_nPairs].cdSellUntil  = 0;
      g_ps[g_nPairs].wins         = 0;
      g_ps[g_nPairs].losses       = 0;
      g_ps[g_nPairs].dayPnL       = 0.0;
      g_ps[g_nPairs].disabled     = false;
      g_ps[g_nPairs].spikeUntil   = 0;
      ArrayInitialize(g_ps[g_nPairs].mkCnt, 0.0);
      ScalePair(g_nPairs);
      g_nPairs++;
   }
   ArrayResize(g_ps, g_nPairs);
   Print("DESK: loaded ", g_nPairs, " forex pairs");
}

void ScalePair(int i)
{
   string sym = g_ps[i].symbol;
   ENUM_TIMEFRAMES sTF = InpSignalTF == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : InpSignalTF;
   g_ps[i].sTF = sTF;

   if(sTF <= PERIOD_H1)  { g_ps[i].htf1=PERIOD_H4; g_ps[i].htf2=PERIOD_D1; }
   else if(sTF<=PERIOD_H4){g_ps[i].htf1=PERIOD_D1; g_ps[i].htf2=PERIOD_W1; }
   else                  { g_ps[i].htf1=PERIOD_W1; g_ps[i].htf2=PERIOD_MN1;}

   int tfMin = (int)(PeriodSeconds(sTF)/60);
   if(tfMin<=15)      { g_ps[i].trailMult=2.0; g_ps[i].rrRatio=1.5; g_ps[i].proxMult=0.4; g_ps[i].mkThr=0.15; }
   else if(tfMin<=60) { g_ps[i].trailMult=1.5; g_ps[i].rrRatio=2.0; g_ps[i].proxMult=0.6; g_ps[i].mkThr=0.30; }
   else if(tfMin<=240){ g_ps[i].trailMult=1.2; g_ps[i].rrRatio=2.5; g_ps[i].proxMult=0.8; g_ps[i].mkThr=0.50; }
   else               { g_ps[i].trailMult=1.0; g_ps[i].rrRatio=3.0; g_ps[i].proxMult=1.0; g_ps[i].mkThr=0.80; }

   bool hasJPY = StringFind(sym,"JPY")>=0;
   bool hasGBP = StringFind(sym,"GBP")>=0;
   bool hasAUD = StringFind(sym,"AUD")>=0;
   bool hasNZD = StringFind(sym,"NZD")>=0;

   if(hasGBP && hasJPY) { g_ps[i].trailMult*=1.4; g_ps[i].proxMult*=1.3; g_ps[i].mkThr*=1.8; }
   else if(hasGBP)      { g_ps[i].trailMult*=1.2; g_ps[i].proxMult*=1.2; g_ps[i].mkThr*=1.3; }
   else if(hasJPY)      { g_ps[i].mkThr*=1.5; g_ps[i].proxMult*=1.1; }
   else if(hasAUD||hasNZD){ g_ps[i].proxMult*=0.9; g_ps[i].mkThr*=1.1; }

   // Session detection
   bool hasCAD=StringFind(sym,"CAD")>=0, hasEUR=StringFind(sym,"EUR")>=0;
   g_ps[i].sessLDN=false; g_ps[i].sessNY=false; g_ps[i].sessAsia=false;
   if(hasJPY&&(hasAUD||hasNZD))   { g_ps[i].sessAsia=true;  g_ps[i].sessLDN=true;  g_ps[i].pairClass="ASIA CROSS"; }
   else if(hasJPY)                { g_ps[i].sessAsia=true;  g_ps[i].sessNY=true;   g_ps[i].pairClass="JPY";        }
   else if(hasAUD||hasNZD)        { g_ps[i].sessAsia=true;  g_ps[i].sessLDN=true;  g_ps[i].pairClass="OCEANIA";    }
   else if(hasCAD)                { g_ps[i].sessLDN=true;   g_ps[i].sessNY=true;   g_ps[i].pairClass="CAD";        }
   else if(hasGBP&&hasEUR)        { g_ps[i].sessLDN=true;   g_ps[i].pairClass="EUR/GBP";                           }
   else if(hasGBP)                { g_ps[i].sessLDN=true;   g_ps[i].sessNY=true;   g_ps[i].pairClass="GBP";        }
   else if(hasEUR)                { g_ps[i].sessLDN=true;   g_ps[i].sessNY=true;   g_ps[i].pairClass="EUR";        }
   else                           { g_ps[i].sessLDN=true;   g_ps[i].sessNY=true;   g_ps[i].pairClass="MAJOR";      }
}

bool InitPairHandles(int i)
{
   string sym = g_ps[i].symbol;
   ENUM_TIMEFRAMES sTF  = g_ps[i].sTF;
   ENUM_TIMEFRAMES htf1 = g_ps[i].htf1;
   ENUM_TIMEFRAMES htf2 = g_ps[i].htf2;

   g_ps[i].hATR    = iATR(sym, sTF,  14);
   g_ps[i].hEMAFH4 = iMA (sym, htf1, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   g_ps[i].hEMASH4 = iMA (sym, htf1, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   g_ps[i].hEMAFD1 = iMA (sym, htf2, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   g_ps[i].hEMASD1 = iMA (sym, htf2, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);

   if(g_ps[i].hATR==INVALID_HANDLE || g_ps[i].hEMAFH4==INVALID_HANDLE)
   { Print("DESK: indicator handle failed for ", sym); return false; }
   return true;
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// PROP FIRM RECOGNITION
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
PropFirm DetectFirm()
{
   string co = AccountInfoString(ACCOUNT_COMPANY); StringToUpper(co);
   string sv = AccountInfoString(ACCOUNT_SERVER);  StringToUpper(sv);
   string s  = co + " " + sv;
   if(StringFind(s,"FUNDEDNEXT")>=0  || StringFind(s,"FUNDED NEXT")>=0)  return PF_FUNDEDNEXT;
   if(StringFind(s,"FTMO")>=0)                                            return PF_FTMO;
   if(StringFind(s,"GOAT")>=0)                                            return PF_GOATFUNDED;
   if(StringFind(s,"FUNDINGPIPS")>=0 || StringFind(s,"FUNDING PIPS")>=0)  return PF_FUNDINGPIPS;
   if(StringFind(s,"5ERS")>=0  || StringFind(s,"THE5")>=0 ||
      StringFind(s,"FIVEPERCENT")>=0)                                     return PF_THE5ERS;
   if(StringFind(s,"E8")>=0)                                              return PF_E8;
   if(StringFind(s,"LEVERAGED")>=0)                                       return PF_LEVERAGED;
   if(StringFind(s,"BLACKBULL")>=0   || StringFind(s,"BLACK BULL")>=0)    return PF_BLACKBULL;
   return PF_FUNDEDNEXT;   // unknown -> safest of the strict prop rule sets
}

void SetupRiskProfile()
{
   g_initBal = (InpInitialBalance>0) ? InpInitialBalance
                                     : AccountInfoDouble(ACCOUNT_BALANCE);

   PropFirm pf  = InpPropFirm;
   bool detected = (pf==PF_AUTO);
   if(pf==PF_AUTO) pf = DetectFirm();

   double p1=8, p2=5;   // phase profit targets, set per firm below
   if(pf==PF_CUSTOM)
   {
      g_firmName="CUSTOM";
      p1=InpProfitTargetPct; p2=InpProfitTargetPct;
      g_maxLossPct=InpMaxLossPct;  g_maxGuardPct=InpMaxLossGuardPct;
      g_dailyLossPct=InpDailyLossPct; g_dailyGuardPct=InpDailyGuardPct;
      g_trailMaxDD=InpTrailingMaxDD;
   }
   else
   {
      // Per-firm 2-step rules (% of initial balance). Daily/Max differ by firm.
      g_trailMaxDD=false;
      switch(pf)
      {
         case PF_FTMO:        g_firmName="FTMO";        p1=10; p2=5; g_maxLossPct=10; g_dailyLossPct=5; break;
         case PF_GOATFUNDED:  g_firmName="GoatFunded";  p1=8;  p2=6; g_maxLossPct=10; g_dailyLossPct=4; break;
         case PF_FUNDINGPIPS: g_firmName="FundingPips"; p1=8;  p2=5; g_maxLossPct=10; g_dailyLossPct=5; break;
         case PF_THE5ERS:     g_firmName="The5ers";     p1=10; p2=5; g_maxLossPct=10; g_dailyLossPct=5; break;
         case PF_E8:          g_firmName="E8";          p1=8;  p2=4; g_maxLossPct=8;  g_dailyLossPct=4; g_trailMaxDD=true; break;
         // Leveraged Turbo Trade = 1-step: same target both phases. 6% trailing max, 3% daily.
         // Eval extras NOT enforceable as risk walls: min 3 profitable days (0.5%+) & 20% consistency.
         case PF_LEVERAGED:   g_firmName="Leveraged";   p1=6;  p2=6; g_maxLossPct=6;  g_dailyLossPct=3; g_trailMaxDD=true; break;
         case PF_BLACKBULL:   g_firmName="BlackBull(brk)";p1=0;p2=0; g_maxLossPct=10; g_dailyLossPct=5; break; // broker: self-imposed cap, no target
         default:             g_firmName="FundedNext";  p1=8;  p2=5; g_maxLossPct=10; g_dailyLossPct=5; break;
      }
      g_maxGuardPct   = g_maxLossPct  * 0.8;
      g_dailyGuardPct = g_dailyLossPct* 0.7;
   }
   g_profitTgtPct = (InpPhase>=2) ? p2 : p1;   // 0 => no target stop (broker)
   if(detected) g_firmName += " (auto)";
   PrintFormat("RISK PROFILE: %s | phase %d | initBal $%.2f | daily %.1f%% (guard %.1f%%) | "
               "max %.1f%% (guard %.1f%%) | target %.1f%% | trailDD=%s",
      g_firmName,InpPhase,g_initBal,g_dailyLossPct,g_dailyGuardPct,
      g_maxLossPct,g_maxGuardPct,g_profitTgtPct,(g_trailMaxDD?"yes":"no"));
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// INIT / DEINIT
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
int OnInit()
{
   trade.SetExpertMagicNumber(MAGIC);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   ParsePairs();
   for(int i=0;i<g_nPairs;i++) InitPairHandles(i);

   SetupRiskProfile();   // recognise prop firm -> apply its risk rules

   g_startEquity = OwnEquity();   // own-equity baseline (self-contained P&L)
   g_peakEquity  = g_startEquity;
   g_dashX       = InpDashX;
   g_dashY       = InpDashY;
   g_tradeLot    = InpAutoLot ? 0.05 : InpFixedLot;
   g_lastDay     = StringToTime(TimeToString(TimeCurrent(),TIME_DATE));

   ArrayResize(g_openTickets, 0);

   // AUTO trade defaults ON (user wants always-on). GV restores state across
   // TF switches / re-attaches so a manual toggle survives a reload.
   if(GlobalVariableCheck(GV_AUTO))
      g_autoTrade = (bool)GlobalVariableGet(GV_AUTO);
   else
   {
      g_autoTrade = InpAutoTradeOn;
      GlobalVariableSet(GV_AUTO,(double)g_autoTrade);
   }

   if(InpShowDash) DrawDashboard();
   DrawWatermark();
   EventSetTimer(InpTimerSec);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
   for(int i=0;i<g_nPairs;i++)
   {
      IndicatorRelease(g_ps[i].hATR);
      IndicatorRelease(g_ps[i].hEMAFH4);
      IndicatorRelease(g_ps[i].hEMASH4);
      IndicatorRelease(g_ps[i].hEMAFD1);
      IndicatorRelease(g_ps[i].hEMASD1);
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// TIMER
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void OnTimer()
{
   if(InpShowDash) UpdateDashboard();
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// TRADE TRANSACTION â track wins/losses per pair
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MAGIC) return;

   long entry  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;

   string sym    = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   long   dType  = HistoryDealGetInteger(trans.deal, DEAL_TYPE);

   for(int i=0;i<g_nPairs;i++)
   {
      if(g_ps[i].symbol != sym) continue;
      if(profit > 0)
      {
         g_ps[i].wins++;
         g_ps[i].consecAny  = 0;
         if(dType==DEAL_TYPE_BUY)  g_ps[i].consecSell = 0;
         else                      g_ps[i].consecBuy  = 0;
      }
      else
      {
         g_ps[i].losses++;
         g_ps[i].consecAny++;
         if(dType==DEAL_TYPE_BUY)
         {
            g_ps[i].consecBuy++;
            g_ps[i].consecSell = 0;
            if(g_ps[i].consecBuy >= 3)
               g_ps[i].cdBuyUntil = TimeCurrent() + 4*3600;
         }
         else
         {
            g_ps[i].consecSell++;
            g_ps[i].consecBuy = 0;
            if(g_ps[i].consecSell >= 3)
               g_ps[i].cdSellUntil = TimeCurrent() + 4*3600;
         }
      }
      // Per-pair auto-disable gate: pause this pair for the day if it bleeds
      // past the $ cap or strings together too many losers.
      g_ps[i].dayPnL += profit;
      if(InpUsePairGate && !g_ps[i].disabled &&
         (g_ps[i].dayPnL <= -(g_initBal*InpPairMaxLossPct/100.0) ||
          g_ps[i].consecAny >= InpPairStopStreak))
      {
         g_ps[i].disabled = true;
         PrintFormat("PAIR GATE: %s paused for the day (dayPnL %.2f, streak %d)",
                     sym, g_ps[i].dayPnL, g_ps[i].consecAny);
      }
      break;
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// ON TICK â main loop
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void OnTick()
{
   CheckDailyReset();
   if(g_eaStopped) return;

   double eq  = OwnEquity();    // this EA's own equity, not the raw account
   double bal = OwnBalance();   // this EA's own balance (baseline + own realized)
   if(eq > g_peakEquity) g_peakEquity = eq;

   // ââ Max loss (per recognised firm). Static vs initial, or trailing peak. ââ
   // Kill at the internal guard so a slip/spread spike can't punch the wall.
   double maxLossFloor = g_trailMaxDD
                         ? g_peakEquity   * (1.0 - g_maxGuardPct/100.0)
                         : g_initBal      * (1.0 - g_maxGuardPct/100.0);
   if(eq <= maxLossFloor)
   {
      CloseAll();
      g_eaStopped = true;
      Alert(g_firmName, ": max-loss guard ", DoubleToString(g_maxGuardPct,1),
            "% hit (floor $", DoubleToString(maxLossFloor,2), ") â EA stopped.");
      return;
   }

   // ââ Daily loss (per firm). Guard sits under the hard wall. Measured from
   // equity at start of the trading day. On breach: flatten + halt for the day.
   if(!g_dailyHalt && IsDailyDDBreached())
   {
      CloseAll();
      g_dailyHalt = true;
      Alert(g_firmName, ": daily-loss guard hit â flat for the day.");
   }

   // ââ Phase profit target ââ
   if(g_profitTgtPct > 0)
   {
      double targetEq = g_initBal * (1.0 + g_profitTgtPct/100.0);
      if(InpStopAtTarget && eq >= targetEq) g_targetHit = true;
   }

   // ââ Daily profit cap (consistency rule): stop adding once up enough ââ
   // Bank the day once up enough, so no single day runs away. Two sources,
   // whichever is tighter (smaller $) wins:
   //   1. InpDailyProfitCap = fixed % of balance        (0 = off)
   //   2. InpConsistencyPct = firm consistency rule      (0 = off)
   //      Caps the day at consistency% of the profit-target $, keeping the
   //      biggest day under that share of total profit and auto-implying the
   //      minimum number of profitable days.
   double dayCapUsd = DailyProfitCapUsd();
   if(dayCapUsd > 0 && !g_dailyHalt && (eq - g_startEquity) >= dayCapUsd)
      g_dailyHalt = true;

   g_dailyPnL = eq - g_startEquity;

   // Friday late cutoff (avoid weekend gap risk)
   MqlDateTime tNow; TimeToStruct(TimeCurrent(), tNow);
   if(InpFridayCutoff && tNow.day_of_week == 5 && LocalHour() >= InpSessEndHour) return;

   RefreshNewsCache(TimeCurrent());   // update per-currency news blackout

   // Count open positions
   int openCount = CountOpenPositions();

   // Pass 1 â compute signals on new bar
   for(int i=0;i<g_nPairs;i++)
   {
      string sym = g_ps[i].symbol;

      // Manage any open trades on this pair first
      ManagePairTrades(i);

      // Spread filter
      double spreadPts  = (double)SymbolInfoInteger(sym, SYMBOL_SPREAD);
      double pointSize  = SymbolInfoDouble(sym, SYMBOL_POINT);
      int    digits     = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double pipSize    = (digits==3||digits==5) ? pointSize*10 : pointSize;
      double spreadPips = spreadPts * pointSize / pipSize;
      if(spreadPips > InpMaxSpreadPips) continue;

      // New bar check
      datetime curBar = iTime(sym, g_ps[i].sTF, 0);
      if(curBar == g_ps[i].lastBar) continue;
      g_ps[i].lastBar = curBar;

      // Refresh ATR
      double atrBuf[1];
      if(CopyBuffer(g_ps[i].hATR, 0, 1, 1, atrBuf) < 1) continue;
      g_ps[i].atr = atrBuf[0];

      UpdateSpikeGuard(i);   // detect flow shocks per pair (runs even out of session)

      // Refresh levels
      RefreshLevels(i);
      RefreshOBFVG(i);
      UpdateMarkov(i);

      bool htfBull=false, htfBear=false;
      GetHTFBias(i, htfBull, htfBear);

      g_ps[i].signal = 0;
      g_ps[i].score  = 0;

      if(InpUseSession && !IsInSession(i)) continue;
      if(SpikeFrozen(i)) continue;   // flow-spike cooldown: no new entries for this pair
      if(HasOpenPosition(sym)) continue;

      RunSignal(i, htfBull, htfBear);

      // Cooldown check
      datetime now = TimeCurrent();
      if(g_ps[i].signal==1  && now < g_ps[i].cdBuyUntil)  g_ps[i].signal=0;
      if(g_ps[i].signal==-1 && now < g_ps[i].cdSellUntil) g_ps[i].signal=0;
   }

   // Pass 2 â auto-fire any pending signal (runs every tick so AUTO ON is instant)
   for(int i=0;i<g_nPairs;i++)
   {
      if(!g_autoTrade) break;
      if(g_dailyHalt || g_targetHit) break;          // daily loss/profit cap or phase done
      if(g_tradesToday >= InpMaxTradesDay) break;     // overtrade guard
      if(g_ps[i].disabled) continue;                 // pair auto-paused for the day
      if(g_ps[i].signal == 0 || g_ps[i].score < InpScoreThreshold) continue;
      if(NewsBlockedSym(g_ps[i].symbol)) continue;   // block only pairs hit by the news
      if(HasOpenPosition(g_ps[i].symbol)) continue;
      if(openCount >= InpMaxConcurrent) break;

      double lot = CalcLot(i);
      if(g_ps[i].consecAny >= 3) lot *= 0.5;          // de-risk after a losing streak
      ExecuteTrade(i, g_ps[i].signal, lot);
      g_ps[i].signal = 0; // clear so it doesn't re-fire next tick
      openCount++;
      g_tradesToday++;
   }
   // Dashboard refresh is timer-driven only (OnTimer) â drawing every tick
   // caused the flicker.
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// SIGNAL ENGINE (per-pair)
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void RunSignal(int i, bool htfBull, bool htfBear)
{
   string sym  = g_ps[i].symbol;
   ENUM_TIMEFRAMES sTF = g_ps[i].sTF;
   double atr  = g_ps[i].atr;
   if(atr <= 0) return;

   int bars = iBars(sym, sTF);
   if(bars < InpScalpSlowMA+5) return;

   double close1 = iClose(sym,sTF,1), open1 = iOpen(sym,sTF,1);
   double high1  = iHigh(sym,sTF,1),  low1  = iLow(sym,sTF,1);
   double close2 = iClose(sym,sTF,2), open2 = iOpen(sym,sTF,2);
   double high2  = iHigh(sym,sTF,2),  low2  = iLow(sym,sTF,2);

   double proximity = atr * g_ps[i].proxMult;
   double body1      = MathAbs(close1-open1);
   double upperWick1 = high1 - MathMax(close1,open1);
   double lowerWick1 = MathMin(close1,open1) - low1;
   double range1     = high1 - low1;
   bool isBull1 = close1 >= open1;
   bool isBear1 = close1 <= open1;

   bool nearPDH = g_ps[i].PDH>0 && high1>=g_ps[i].PDH-proximity && low1<=g_ps[i].PDH+proximity;
   bool nearPDL = g_ps[i].PDL>0 && low1<=g_ps[i].PDL+proximity  && high1>=g_ps[i].PDL-proximity;
   bool nearPWH = g_ps[i].PWH>0 && high1>=g_ps[i].PWH-proximity && low1<=g_ps[i].PWH+proximity;
   bool nearPWL = g_ps[i].PWL>0 && low1<=g_ps[i].PWL+proximity  && high1>=g_ps[i].PWL-proximity;
   bool nearAH  = g_ps[i].AsiaH>0 && high1>=g_ps[i].AsiaH-proximity && low1<=g_ps[i].AsiaH+proximity;
   bool nearAL  = g_ps[i].AsiaL>0 && low1<=g_ps[i].AsiaL+proximity  && high1>=g_ps[i].AsiaL-proximity;
   bool nearBullOB = g_ps[i].BullOBH>0 && close1>=g_ps[i].BullOBL-atr*0.3 && close1<=g_ps[i].BullOBH+atr*0.5;
   bool nearBearOB = g_ps[i].BearOBH>0 && close1<=g_ps[i].BearOBH+atr*0.3 && close1>=g_ps[i].BearOBL-atr*0.5;
   bool nearBullFVG= g_ps[i].BullFVGT>0&& close1>=g_ps[i].BullFVGB-atr*0.3 && close1<=g_ps[i].BullFVGT+atr*0.5;
   bool nearBearFVG= g_ps[i].BearFVGT>0&& close1<=g_ps[i].BearFVGT+atr*0.3 && close1>=g_ps[i].BearFVGB-atr*0.5;

   bool bullWick = lowerWick1 >= body1*InpWickRatio || lowerWick1 >= atr*0.3;
   bool bearWick = upperWick1 >= body1*InpWickRatio || upperWick1 >= atr*0.3;

   bool confirmBull = isBull1 && range1>0 && (close1-low1)/range1>=0.4;
   bool confirmBear = isBear1 && range1>0 && (high1-close1)/range1>=0.4;

   bool longPDL  = (bullWick&&nearPDL&&isBull1)||(low2<g_ps[i].PDL&&close1>g_ps[i].PDL);  longPDL  = longPDL  && confirmBull;
   bool shortPDH = (bearWick&&nearPDH&&isBear1)||(high2>g_ps[i].PDH&&close1<g_ps[i].PDH); shortPDH = shortPDH && confirmBear;
   bool longAL   = (bullWick&&nearAL&&isBull1)||(low2<g_ps[i].AsiaL&&close1>g_ps[i].AsiaL); longAL = longAL && confirmBull;
   bool shortAH  = (bearWick&&nearAH&&isBear1)||(high2>g_ps[i].AsiaH&&close1<g_ps[i].AsiaH);shortAH= shortAH && confirmBear;
   bool longPWL  = (bullWick&&nearPWL&&isBull1)||(low2<g_ps[i].PWL&&close1>g_ps[i].PWL);   longPWL = longPWL && confirmBull;
   bool shortPWH = (bearWick&&nearPWH&&isBear1)||(high2>g_ps[i].PWH&&close1<g_ps[i].PWH);  shortPWH= shortPWH&& confirmBear;

   bool sweepBullPDL = g_ps[i].PDL>0  && low2<g_ps[i].PDL   && close1>g_ps[i].PDL   && isBull1;
   bool sweepBearPDH = g_ps[i].PDH>0  && high2>g_ps[i].PDH  && close1<g_ps[i].PDH   && isBear1;
   bool sweepBullAL  = g_ps[i].AsiaL>0&& low2<g_ps[i].AsiaL && close1>g_ps[i].AsiaL && isBull1;
   bool sweepBearAH  = g_ps[i].AsiaH>0&& high2>g_ps[i].AsiaH&& close1<g_ps[i].AsiaH && isBear1;

   // ââ Scalp momentum + pullback paths (always available, trend-filtered) ââ
   // Recent swing hi/lo over bars 2..(2+LB) for micro-breakout.
   double hiN=-DBL_MAX, loN=DBL_MAX;
   for(int b=2;b<2+InpBreakoutLB;b++)
   {
      double hb=iHigh(sym,sTF,b), lb=iLow(sym,sTF,b);
      if(hb>hiN) hiN=hb;
      if(lb<loN) loN=lb;
   }
   // Fast/slow SMA on the signal TF (inline â no extra handles).
   double sumF=0, sumS=0;
   for(int b=1;b<=InpScalpFastMA;b++) sumF+=iClose(sym,sTF,b);
   for(int b=1;b<=InpScalpSlowMA;b++) sumS+=iClose(sym,sTF,b);
   double maF = sumF/InpScalpFastMA;
   double maS = sumS/InpScalpSlowMA;
   bool trendUp = maF>maS, trendDn=maF<maS;

   bool momLong  = InpUseMomentum && close1>hiN && isBull1 && trendUp && body1>=atr*InpMomBodyATR;
   bool momShort = InpUseMomentum && close1<loN && isBear1 && trendDn && body1>=atr*InpMomBodyATR;
   bool pbLong   = InpUsePullback && trendUp && low1<=maF && close1>maF && isBull1 && confirmBull;
   bool pbShort  = InpUsePullback && trendDn && high1>=maF && close1<maF && isBear1 && confirmBear;

   bool anyLong  = longPDL||longAL||longPWL||sweepBullPDL||sweepBullAL||momLong||pbLong;
   bool anyShort = shortPDH||shortAH||shortPWH||sweepBearPDH||sweepBearAH||momShort||pbShort;
   if(!anyLong && !anyShort) return;
   // Never both directions in the same bar â pick the key-level/sweep bias,
   // else the trend.
   if(anyLong && anyShort)
   {
      if(trendUp) anyShort=false; else anyLong=false;
   }

   bool mkBlockLong  = InpUseMarkov && g_ps[i].mkConfirmed==2 && g_ps[i].mkPersistence>InpMarkovPersist;
   bool mkBlockShort = InpUseMarkov && g_ps[i].mkConfirmed==1 && g_ps[i].mkPersistence>InpMarkovPersist;
   if(anyLong  && mkBlockLong)  anyLong  = false;
   if(anyShort && mkBlockShort) anyShort = false;
   if(!anyLong && !anyShort) return;

   bool cfPDX  = anyLong ? nearPDL : nearPDH;
   bool cfWeek = anyLong ? nearPWL : nearPWH;
   bool cfAsia = anyLong ? nearAL  : nearAH;
   bool cfOB   = anyLong ? nearBullOB : nearBearOB;
   bool cfFVG  = anyLong ? nearBullFVG: nearBearFVG;

   int conf=0;
   if(cfPDX)conf++; if(cfWeek)conf++; if(cfAsia)conf++;
   if(cfOB) conf++; if(cfFVG) conf++;
   conf = MathMin(conf, 5);

   bool biasAligned = InpUseBiasFilter && ((anyLong&&htfBull)||(anyShort&&htfBear));
   bool mkAligned   = (anyLong&&g_ps[i].mkConfirmed==1)||(anyShort&&g_ps[i].mkConfirmed==2);
   bool isSweep     = sweepBullPDL||sweepBullAL||sweepBearPDH||sweepBearAH;
   bool inSess      = IsInSession(i);

   bool isMom = (anyLong&&momLong)||(anyShort&&momShort);
   bool isPB  = (anyLong&&pbLong) ||(anyShort&&pbShort);

   int score = 2;
   if(biasAligned) score+=2;
   if(mkAligned)   score+=1;
   if(isSweep)     score+=1;
   if(isMom)       score+=2;   // trend-aligned breakout
   if(isPB)        score+=2;   // trend pullback continuation
   score += MathMin(conf,4);
   if(inSess)      score+=1;
   score = MathMin(score,10);

   g_ps[i].signal = anyLong ? 1 : -1;
   g_ps[i].score  = score;

   double minSLDist = g_ps[i].atr * InpMinSLATR;
   if(anyLong)
   {
      double slRaw = low1 - atr * InpSLBuffer;
      g_ps[i].entryPrice = SymbolInfoDouble(sym, SYMBOL_ASK);
      g_ps[i].slPrice    = MathMin(slRaw, g_ps[i].entryPrice - minSLDist);
      g_ps[i].tpPrice    = g_ps[i].entryPrice + (g_ps[i].entryPrice - g_ps[i].slPrice) * g_ps[i].rrRatio;
   }
   else
   {
      double slRaw = high1 + atr * InpSLBuffer;
      g_ps[i].entryPrice = SymbolInfoDouble(sym, SYMBOL_BID);
      g_ps[i].slPrice    = MathMax(slRaw, g_ps[i].entryPrice + minSLDist);
      g_ps[i].tpPrice    = g_ps[i].entryPrice - (g_ps[i].slPrice - g_ps[i].entryPrice) * g_ps[i].rrRatio;
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// EXECUTE TRADE
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void ExecuteTrade(int i, int direction, double lot)
{
   string sym = g_ps[i].symbol;
   lot = NormLot(sym, lot);

   // ATR fallback â fetch fresh if zero (pair not yet processed by signal engine)
   if(g_ps[i].atr <= 0 && g_ps[i].hATR != INVALID_HANDLE)
   {
      double buf[1];
      if(CopyBuffer(g_ps[i].hATR, 0, 1, 1, buf) >= 1) g_ps[i].atr = buf[0];
   }
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   if(g_ps[i].atr <= 0) g_ps[i].atr = ask * 0.005; // 0.5% price fallback

   if(direction == 1)
   {
      double entry = ask;
      // Only reuse stored levels if they sit on the correct side for a BUY
      // (a stale SELL signal would put TP below entry -> broker rejects).
      double sl = (g_ps[i].slPrice > 0 && g_ps[i].slPrice < entry)
                  ? g_ps[i].slPrice : entry - g_ps[i].atr*(InpSLBuffer+InpMinSLATR);
      sl = MathMin(sl, entry - g_ps[i].atr*InpMinSLATR);
      double tp = (g_ps[i].tpPrice > entry)
                  ? g_ps[i].tpPrice : entry + (entry-sl)*g_ps[i].rrRatio;
      if(sl >= entry){ Print("ExecuteTrade BUY: invalid SL ",sl," >= entry ",entry," â skipping"); return; }
      if(trade.Buy(lot, sym, entry, sl, tp, StringFormat("SWD LONG %s Sc:%d", sym, g_ps[i].score)))
         { g_ps[i].partialDone=false; g_ps[i].beDone=false; }
      else
         Print("ExecuteTrade BUY failed ",sym," ret=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
   }
   else
   {
      double entry = bid;
      double sl = (g_ps[i].slPrice > entry)
                  ? g_ps[i].slPrice : entry + g_ps[i].atr*(InpSLBuffer+InpMinSLATR);
      sl = MathMax(sl, entry + g_ps[i].atr*InpMinSLATR);
      double tp = (g_ps[i].tpPrice > 0 && g_ps[i].tpPrice < entry)
                  ? g_ps[i].tpPrice : entry - (sl-entry)*g_ps[i].rrRatio;
      if(sl <= entry){ Print("ExecuteTrade SELL: invalid SL ",sl," <= entry ",entry," â skipping"); return; }
      if(trade.Sell(lot, sym, entry, sl, tp, StringFormat("SWD SHORT %s Sc:%d", sym, g_ps[i].score)))
         { g_ps[i].partialDone=false; g_ps[i].beDone=false; }
      else
         Print("ExecuteTrade SELL failed ",sym," ret=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// TRADE MANAGER (per-pair)
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void ManagePairTrades(int i)
{
   string sym = g_ps[i].symbol;
   double atr = g_ps[i].atr;
   if(atr<=0) return;

   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);

   for(int j=PositionsTotal()-1;j>=0;j--)
   {
      if(!pos.SelectByIndex(j)) continue;
      if(pos.Magic()  != MAGIC)  continue;
      if(pos.Symbol() != sym)    continue;

      // HFT guard: leave the trade fully alone until it ages past the min-hold.
      // The entry SL/TP still protect it; we just don't BE/lock/trail/partial it
      // into a sub-2-minute exit that firms (esp. FTMO) flag as HFT.
      if((long)(TimeCurrent() - pos.Time()) < InpMinHoldSeconds) continue;

      double openP  = pos.PriceOpen();
      double curSL  = pos.StopLoss();
      double curTP  = pos.TakeProfit();
      double lots   = pos.Volume();
      ulong  ticket = pos.Ticket();
      double slDist = MathAbs(openP - curSL);
      double oneR   = slDist > 0 ? slDist : atr;

      double curP   = pos.PositionType()==POSITION_TYPE_BUY ? bid : ask;
      double pnlR   = (oneR>0) ? MathAbs(curP-openP)/oneR : 0;

      // ââ No-loss lock: once floating profit >= $X, shove SL past entry so the
      // trade can no longer close at a loss (covers spread). Runs before trail. ââ
      if(InpUseProfitLock)
      {
         double netP = pos.Profit()+pos.Swap()+pos.Commission();
         if(netP >= InpLockProfitUSD)
         {
            int    dg  = (int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
            double buf = (double)SymbolInfoInteger(sym,SYMBOL_SPREAD)*SymbolInfoDouble(sym,SYMBOL_POINT);
            if(pos.PositionType()==POSITION_TYPE_BUY)
            {
               double lockSL = NormalizeDouble(openP+buf, dg);
               if(lockSL>curSL && lockSL<bid) trade.PositionModify(ticket,lockSL,curTP);
            }
            else
            {
               double lockSL = NormalizeDouble(openP-buf, dg);
               if((curSL==0 || lockSL<curSL) && lockSL>ask) trade.PositionModify(ticket,lockSL,curTP);
            }
         }
      }

      double activeMult = g_ps[i].trailMult;
      if(InpProgressTrail)
      {
         if(pnlR>=3.0)      activeMult=InpTrailR3Mult;
         else if(pnlR>=2.0) activeMult=InpTrailR2Mult;
      }

      if(pos.PositionType()==POSITION_TYPE_BUY)
      {
         double p1R = openP + oneR * InpPartialRR;
         double pBE = openP + oneR * InpBEMult;

         if(InpUsePartialTP && !g_ps[i].partialDone && curP >= p1R)
         {
            double cl = NormLot(sym, lots*InpPartialFrac);
            if(cl>=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN))
            { trade.PositionClosePartial(ticket,cl); g_ps[i].partialDone=true;
              if(InpExtendTP) trade.PositionModify(ticket,curSL,0); }
         }
         if(InpUseBreakEven && !g_ps[i].beDone && curP >= pBE)
         {
            double newSL = openP + (double)SymbolInfoInteger(sym,SYMBOL_SPREAD)*SymbolInfoDouble(sym,SYMBOL_POINT);
            double newTP = (InpExtendTP&&g_ps[i].partialDone)?0:curTP;
            if(newSL>curSL){trade.PositionModify(ticket,newSL,newTP);g_ps[i].beDone=true;}
         }
         if(InpUseTrail)
         {
            double newSL = NormalizeDouble(bid - atr*activeMult, (int)SymbolInfoInteger(sym,SYMBOL_DIGITS));
            double newTP = (InpExtendTP&&g_ps[i].partialDone)?0:curTP;
            if(newSL>curSL && newSL<bid) trade.PositionModify(ticket,newSL,newTP);
         }
      }
      else
      {
         double p1R = openP - oneR * InpPartialRR;
         double pBE = openP - oneR * InpBEMult;

         if(InpUsePartialTP && !g_ps[i].partialDone && curP <= p1R)
         {
            double cl = NormLot(sym, lots*InpPartialFrac);
            if(cl>=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN))
            { trade.PositionClosePartial(ticket,cl); g_ps[i].partialDone=true;
              if(InpExtendTP) trade.PositionModify(ticket,curSL,0); }
         }
         if(InpUseBreakEven && !g_ps[i].beDone && curP <= pBE)
         {
            double newSL = openP - (double)SymbolInfoInteger(sym,SYMBOL_SPREAD)*SymbolInfoDouble(sym,SYMBOL_POINT);
            double newTP = (InpExtendTP&&g_ps[i].partialDone)?0:curTP;
            if(newSL<curSL){trade.PositionModify(ticket,newSL,newTP);g_ps[i].beDone=true;}
         }
         if(InpUseTrail)
         {
            double newSL = NormalizeDouble(ask + atr*activeMult, (int)SymbolInfoInteger(sym,SYMBOL_DIGITS));
            double newTP = (InpExtendTP&&g_ps[i].partialDone)?0:curTP;
            if(newSL<curSL && newSL>ask) trade.PositionModify(ticket,newSL,newTP);
         }
      }
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// MARKOV
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void UpdateMarkov(int i)
{
   string sym = g_ps[i].symbol;
   int bars = iBars(sym, g_ps[i].sTF);
   if(bars < InpMarkovLB+5) return;

   double cNow  = iClose(sym, g_ps[i].sTF, 1);
   double cPrev = iClose(sym, g_ps[i].sTF, 1+InpMarkovLB);
   if(cPrev<=0) return;

   double logR = MathLog(cNow/cPrev);
   double thr  = g_ps[i].mkThr/100.0;
   int newR = (logR>thr)?1:(logR<-thr)?2:0;

   g_ps[i].mkCnt[g_ps[i].mkRegime][newR] += 1.0;
   g_ps[i].mkRegime = newR;

   if(newR==g_ps[i].mkConfirmed) g_ps[i].mkHeldCount++;
   else { g_ps[i].mkHeldCount=1; if(g_ps[i].mkHeldCount>=InpMarkovHold) g_ps[i].mkConfirmed=newR; }
   if(g_ps[i].mkHeldCount>=InpMarkovHold) g_ps[i].mkConfirmed=newR;

   double P[3][3];
   for(int r=0;r<3;r++)
   {
      double s=g_ps[i].mkCnt[r][0]+g_ps[i].mkCnt[r][1]+g_ps[i].mkCnt[r][2];
      for(int c=0;c<3;c++) P[r][c]=(s>0)?g_ps[i].mkCnt[r][c]/s:1.0/3.0;
   }
   g_ps[i].mkPersistence = P[g_ps[i].mkConfirmed][g_ps[i].mkConfirmed];
   g_ps[i].mkConviction  = P[g_ps[i].mkConfirmed][1]-P[g_ps[i].mkConfirmed][2];
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// HTF BIAS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void GetHTFBias(int i, bool &bull, bool &bear)
{
   string sym = g_ps[i].symbol;
   double efH4[1],esH4[1],efD1[1],esD1[1];
   if(CopyBuffer(g_ps[i].hEMAFH4,0,1,1,efH4)<1) return;
   if(CopyBuffer(g_ps[i].hEMASH4,0,1,1,esH4)<1) return;
   if(CopyBuffer(g_ps[i].hEMAFD1,0,1,1,efD1)<1) return;
   if(CopyBuffer(g_ps[i].hEMASD1,0,1,1,esD1)<1) return;

   double cH4 = iClose(sym,g_ps[i].htf1,1);
   double cD1 = iClose(sym,g_ps[i].htf2,1);

   bool h4Bull = cH4>efH4[0]&&cH4>esH4[0];
   bool h4Bear = cH4<efH4[0]&&cH4<esH4[0];
   bool d1Bull = cD1>efD1[0]&&cD1>esD1[0];
   bool d1Bear = cD1<efD1[0]&&cD1<esD1[0];

   bull = (h4Bull||d1Bull)&&!h4Bear&&!d1Bear;
   bear = (h4Bear||d1Bear)&&!h4Bull&&!d1Bull;
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// KEY LEVELS & OB/FVG
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void RefreshLevels(int i)
{
   string sym = g_ps[i].symbol;
   g_ps[i].PDH = iHigh(sym,PERIOD_D1,1);
   g_ps[i].PDL = iLow (sym,PERIOD_D1,1);
   g_ps[i].PWH = iHigh(sym,PERIOD_W1,1);
   g_ps[i].PWL = iLow (sym,PERIOD_W1,1);

   double aH=0,aL=DBL_MAX;
   MqlDateTime td;
   for(int b=1;b<=200;b++)
   {
      datetime t=iTime(sym,PERIOD_H1,b);
      TimeToStruct(t,td);
      if(td.hour>=ASIA_OPEN && td.hour<ASIA_CLOSE)
      {
         double h=iHigh(sym,PERIOD_H1,b),l=iLow(sym,PERIOD_H1,b);
         if(h>aH)aH=h; if(l<aL)aL=l;
      }
      if(td.hour>=ASIA_CLOSE && td.day_of_week>=1) break;
   }
   if(aH>0) g_ps[i].AsiaH=aH;
   if(aL<DBL_MAX) g_ps[i].AsiaL=aL;
}

void RefreshOBFVG(int i)
{
   string sym = g_ps[i].symbol;
   ENUM_TIMEFRAMES sTF = g_ps[i].sTF;
   double fvgFrac = (g_ps[i].atr>0)?0.3:0.0003;

   for(int b=3;b<=20;b++)
   {
      double c0=iClose(sym,sTF,b),o0=iOpen(sym,sTF,b),c1=iClose(sym,sTF,b-2);
      if(c0<o0&&c1>iHigh(sym,sTF,b)){g_ps[i].BullOBH=MathMax(o0,c0);g_ps[i].BullOBL=MathMin(o0,c0);break;}
   }
   for(int b=3;b<=20;b++)
   {
      double c0=iClose(sym,sTF,b),o0=iOpen(sym,sTF,b),c1=iClose(sym,sTF,b-2);
      if(c0>o0&&c1<iLow(sym,sTF,b)) {g_ps[i].BearOBH=MathMax(o0,c0);g_ps[i].BearOBL=MathMin(o0,c0);break;}
   }
   for(int b=2;b<=30;b++)
   {
      double l0=iLow(sym,sTF,b),h2=iHigh(sym,sTF,b+2);
      if(l0>h2&&(l0-h2)>=g_ps[i].atr*fvgFrac){g_ps[i].BullFVGT=l0;g_ps[i].BullFVGB=h2;break;}
   }
   for(int b=2;b<=30;b++)
   {
      double h0=iHigh(sym,sTF,b),l2=iLow(sym,sTF,b+2);
      if(h0<l2&&(l2-h0)>=g_ps[i].atr*fvgFrac){g_ps[i].BearFVGT=l2;g_ps[i].BearFVGB=h0;break;}
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// SESSION CHECK
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// Convert server time to local hour, then test the scalp window.
// localHour = serverHour - serverGMT + localGMT (wrapped to 0..23).
int LocalHour()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   int h = t.hour - InpServerGMTOffset + InpLocalGMTOffset;
   h = ((h % 24) + 24) % 24;
   return h;
}

bool IsInSession(int i)
{
   if(!InpUseSession) return true;
   int h = LocalHour();
   // Handle windows that cross midnight (e.g. 22 -> 02)
   if(InpSessStartHour <= InpSessEndHour)
      return (h >= InpSessStartHour && h < InpSessEndHour);
   return (h >= InpSessStartHour || h < InpSessEndHour);
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// DAILY RESET / DD
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void CheckDailyReset()
{
   // Server date rollover = FundedNext daily reset (their clock is server-side).
   datetime curDay = StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(curDay != g_lastDay)
   {
      g_lastDay     = curDay;
      g_startEquity = OwnEquity();   // day-start baseline = this EA's own equity
      g_dailyPnL    = 0.0;
      g_dailyHalt   = false;   // re-arm for the new day
      g_tradesToday = 0;
      for(int i=0;i<g_nPairs;i++)
      {
         g_ps[i].consecBuy=0; g_ps[i].consecSell=0; g_ps[i].consecAny=0;
         g_ps[i].cdBuyUntil=0; g_ps[i].cdSellUntil=0;
         g_ps[i].dayPnL=0.0;  g_ps[i].disabled=false;   // re-arm pair gate
      }
   }
   g_dailyPnL = OwnEquity() - g_startEquity;
}

// FundedNext daily loss = % of INITIAL balance, measured from day-start equity.
// We trip at the internal guard (InpDailyGuardPct) which sits under the 5% wall.
bool IsDailyDDBreached()
{
   double limit = g_initBal * g_dailyGuardPct / 100.0;
   return (g_startEquity - OwnEquity()) >= limit;
}

//------------------------------------------------------------------
// OWN-ACCOUNT P&L  (self-contained: only this EA's MAGIC trades).
// PROP manages and measures ONLY what it makes itself, never the raw
// account balance/equity. So it can share an account with other EAs
// during testing without their profit/loss tripping its guards.
// In production (1 EA per account) own == account, identical behaviour.
//   OwnBalance = starting baseline + this EA's realized P&L
//   OwnEquity  = OwnBalance + this EA's open floating P&L
//------------------------------------------------------------------
double OwnFloating()
{
   double p = 0.0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(pos.SelectByIndex(i) && pos.Magic() == MAGIC)
         p += pos.Profit() + pos.Swap() + pos.Commission();
   return p;
}

double OwnRealizedAll()
{
   if(!HistorySelect(0, TimeCurrent())) return 0.0;
   double p = 0.0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if((long)HistoryDealGetInteger(t, DEAL_MAGIC) != MAGIC) continue;
      p += HistoryDealGetDouble(t, DEAL_PROFIT)
         + HistoryDealGetDouble(t, DEAL_SWAP)
         + HistoryDealGetDouble(t, DEAL_COMMISSION);
   }
   return p;
}

double OwnBalance() { return g_initBal + OwnRealizedAll(); }
double OwnEquity()  { return OwnBalance() + OwnFloating(); }

//------------------------------------------------------------------
// Daily profit cap in $ (the smaller of the fixed cap and the firm
// consistency cap). 0 = no cap. The consistency cap = consistency% of
// the phase profit-target $, so the largest single day stays under that
// share of total profit -> firm consistency rule auto-satisfied, and the
// minimum number of profitable days falls out of it (target / cap).
//------------------------------------------------------------------
double DailyProfitCapUsd()
{
   double cap = 0.0;   // 0 = unlimited
   if(InpDailyProfitCap > 0)
      cap = g_initBal * InpDailyProfitCap / 100.0;
   if(InpConsistencyPct > 0 && g_profitTgtPct > 0)
   {
      double targetUsd = g_initBal * g_profitTgtPct / 100.0;
      double consUsd   = targetUsd * InpConsistencyPct / 100.0;
      cap = (cap > 0) ? MathMin(cap, consUsd) : consUsd;
   }
   return cap;
}

// Min profitable days implied by the consistency cap (ceil of target/cap).
int ConsistencyMinDays()
{
   if(InpConsistencyPct <= 0) return 0;
   return (int)MathCeil(100.0 / InpConsistencyPct);
}

//------------------------------------------------------------------
// SPIKE GUARD (per pair). Abnormal candle (range >= InpSpikeATRmult x
// the pair's ATR) = flow shock (news/fixing/illiquidity), not tradeable
// structure, and the calendar news filter cannot see it. Freezes that
// pair's new entries for InpSpikeCoolBars bars so neither the shock nor
// its violent retrace is read as a signal. Other pairs are unaffected.
//------------------------------------------------------------------
void UpdateSpikeGuard(int i)
{
   if(InpSpikeATRmult <= 0 || g_ps[i].atr <= 0) return;
   string sym = g_ps[i].symbol;
   ENUM_TIMEFRAMES tf = g_ps[i].sTF;
   double big = InpSpikeATRmult * g_ps[i].atr;
   double r0  = iHigh(sym,tf,0) - iLow(sym,tf,0);
   double r1  = iHigh(sym,tf,1) - iLow(sym,tf,1);
   if(r0 >= big || r1 >= big)
      g_ps[i].spikeUntil = TimeCurrent()
                         + (datetime)(MathMax(1,InpSpikeCoolBars)*PeriodSeconds(tf));
}

bool SpikeFrozen(int i) { return (TimeCurrent() < g_ps[i].spikeUntil); }

//------------------------------------------------------------------
// ENTRY GATE (per pair). Single risk check both AUTO and the manual
// dashboard buttons must pass before a new trade opens on a pair, so
// panel trading stays honest to the prop rules. Account-wide stops
// plus the pair's own news/spike/disable state are all enforced.
//------------------------------------------------------------------
bool EntryBlockedPair(int i, string &why)
{
   if(g_eaStopped)                  { why="EA STOPPED (max-loss)"; return true; }
   if(g_dailyHalt)                  { why="DAILY CAP HALT";        return true; }
   if(g_targetHit)                  { why="TARGET REACHED";        return true; }
   if(g_ps[i].disabled)             { why="PAIR DISABLED (day)";   return true; }
   if(NewsBlockedSym(g_ps[i].symbol)){ why="NEWS BLACKOUT";        return true; }
   if(SpikeFrozen(i))               { why="SPIKE FROZEN";          return true; }
   return false;
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// POSITION HELPERS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
bool HasOpenPosition(string sym)
{
   for(int i=0;i<PositionsTotal();i++)
      if(pos.SelectByIndex(i)&&pos.Magic()==MAGIC&&pos.Symbol()==sym) return true;
   return false;
}

int CountOpenPositions()
{
   int n=0;
   for(int i=0;i<PositionsTotal();i++)
      if(pos.SelectByIndex(i)&&pos.Magic()==MAGIC) n++;
   return n;
}

void CloseAll()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(pos.SelectByIndex(i)&&pos.Magic()==MAGIC) trade.PositionClose(pos.Ticket());
}

void CloseSymbol(string sym)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(pos.SelectByIndex(i)&&pos.Magic()==MAGIC&&pos.Symbol()==sym) trade.PositionClose(pos.Ticket());
}

void CloseByFilter(int filter) // 1=profit only, -1=loss only, 0=all
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!pos.SelectByIndex(i)||pos.Magic()!=MAGIC) continue;
      double pnl=pos.Profit()+pos.Swap()+pos.Commission();
      if(filter==0||(filter==1&&pnl>0)||(filter==-1&&pnl<0))
         trade.PositionClose(pos.Ticket());
   }
}

void CloseTicketPartial(ulong ticket, double frac)
{
   if(!pos.SelectByTicket(ticket)) return;
   double lots=NormLot(pos.Symbol(), pos.Volume()*frac);
   if(lots>=SymbolInfoDouble(pos.Symbol(),SYMBOL_VOLUME_MIN))
      trade.PositionClosePartial(ticket,lots);
}

double CalcLot(int i)
{
   if(!InpAutoLot) return MathMin(InpFixedLot, InpMaxLot);
   string sym  = g_ps[i].symbol;
   double slD  = MathAbs(g_ps[i].entryPrice - g_ps[i].slPrice);
   if(slD<=0) slD = g_ps[i].atr * InpMinSLATR;
   if(slD<=0) slD = SymbolInfoDouble(sym,SYMBOL_ASK) * 0.003;
   double tv   = SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   double ts   = SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   if(tv<=0||ts<=0) return NormLot(sym,InpMaxLot);
   // Size off the SMALLER of initial vs current balance â never risk more
   // after a drawdown, and keep lots stable for the consistency rule.
   double sizingBase = MathMin(g_initBal, OwnBalance());
   double risk = sizingBase * InpRiskPercent / 100.0;
   double lots = risk / (slD/ts * tv);
   lots = MathMin(lots, InpMaxLot);  // hard ceiling
   return NormLot(sym,lots);
}

double NormLot(string sym, double lots)
{
   double minL=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double maxL=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   lots=MathFloor(lots/step)*step;
   return NormalizeDouble(MathMax(minL,MathMin(maxL,lots)),2);
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// CHART EVENT
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_DRAG && sparam==PFX+"BG_HDR")
   {
      g_dashX=(int)ObjectGetInteger(0,PFX+"BG_HDR",OBJPROP_XDISTANCE);
      g_dashY=(int)ObjectGetInteger(0,PFX+"BG_HDR",OBJPROP_YDISTANCE);
      DrawDashboard(); return;
   }
   if(id!=CHARTEVENT_OBJECT_CLICK) return;

   // Minimize
   if(sparam==PFX+"BTN_MIN")
   {
      g_minimized=!g_minimized;
      ObjectsDeleteAll(0,PFX);   // one-time clean slate on layout switch
      if(g_minimized) DrawMinimized(); else DrawDashboard();
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false); return;
   }

   // Auto trade toggle
   if(sparam==PFX+"BTN_AUTO")
   {
      g_autoTrade=!g_autoTrade;
      GlobalVariableSet(GV_AUTO,(double)g_autoTrade);
      UpdateDashboard();
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false); return;
   }

   // Pair selector
   if(sparam==PFX+"BTN_PAIR_L")
   { g_pairIdx=(g_pairIdx-1+g_nPairs)%g_nPairs; UpdateDashboard(); ObjectSetInteger(0,sparam,OBJPROP_STATE,false); return; }
   if(sparam==PFX+"BTN_PAIR_R")
   { g_pairIdx=(g_pairIdx+1)%g_nPairs; UpdateDashboard(); ObjectSetInteger(0,sparam,OBJPROP_STATE,false); return; }

   // Lot
   if(sparam==PFX+"BTN_LOT_UP")
   { g_tradeLot=NormalizeDouble(g_tradeLot+0.01,2); if(g_tradeLot>5.0)g_tradeLot=5.0; UpdateDashboard(); ObjectSetInteger(0,sparam,OBJPROP_STATE,false); return; }
   if(sparam==PFX+"BTN_LOT_DN")
   { g_tradeLot=NormalizeDouble(g_tradeLot-0.01,2); if(g_tradeLot<0.01)g_tradeLot=0.01; UpdateDashboard(); ObjectSetInteger(0,sparam,OBJPROP_STATE,false); return; }

   // Manual BUY/SELL on selected pair
   if(sparam==PFX+"BTN_BUY" && g_nPairs>0)
   {
      int idx=g_pairIdx%g_nPairs; string why;
      if(EntryBlockedPair(idx,why)) Alert("STAALWAG PROP: manual BUY ",g_ps[idx].symbol," blocked - ",why);
      else ExecuteTrade(idx,1,g_tradeLot);
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false); return;
   }
   if(sparam==PFX+"BTN_SELL" && g_nPairs>0)
   {
      int idx=g_pairIdx%g_nPairs; string why;
      if(EntryBlockedPair(idx,why)) Alert("STAALWAG PROP: manual SELL ",g_ps[idx].symbol," blocked - ",why);
      else ExecuteTrade(idx,-1,g_tradeLot);
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false); return;
   }

   // Account actions
   if(sparam==PFX+"BTN_CLOSE_PROFIT"){CloseByFilter(1); ObjectSetInteger(0,sparam,OBJPROP_STATE,false); return;}
   if(sparam==PFX+"BTN_CLOSE_LOSS")  {CloseByFilter(-1);ObjectSetInteger(0,sparam,OBJPROP_STATE,false); return;}
   if(sparam==PFX+"BTN_CLOSE_ALL")   {CloseAll();        ObjectSetInteger(0,sparam,OBJPROP_STATE,false); return;}

   // Per-position buttons
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!pos.SelectByIndex(i)||pos.Magic()!=MAGIC) continue;
      string tk=(string)pos.Ticket();
      if(sparam==PFX+"BTN_C25_"+tk){CloseTicketPartial(pos.Ticket(),0.25);ObjectSetInteger(0,sparam,OBJPROP_STATE,false);return;}
      if(sparam==PFX+"BTN_C50_"+tk){CloseTicketPartial(pos.Ticket(),0.50);ObjectSetInteger(0,sparam,OBJPROP_STATE,false);return;}
      if(sparam==PFX+"BTN_CXX_"+tk){trade.PositionClose(pos.Ticket());    ObjectSetInteger(0,sparam,OBJPROP_STATE,false);return;}
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// DASHBOARD DRAW
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
struct PosRow { string symbol,dir; double lots,openPrice,sl,tp,pnl; ulong ticket; };

void DrawDashboard()
{
   // No full ObjectsDeleteAll here â objects are reused by name (CreatePanel/
   // SetLabel/CreateButton recreate only if missing), so repeated draws don't
   // flicker. Only the dynamic position rows (per-ticket) are cleared, since
   // their count/names change as trades open and close.
   ObjectsDeleteAll(0,PFX+"POS_");
   ObjectsDeleteAll(0,PFX+"BTN_C25_");
   ObjectsDeleteAll(0,PFX+"BTN_C50_");
   ObjectsDeleteAll(0,PFX+"BTN_CXX_");

   double bal=OwnBalance();   // own balance (this EA's realized P&L only)
   double eq =OwnEquity();    // own equity  (own balance + own floating)
   double freeM=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double mLevel=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   int n=PositionsTotal();
   PosRow rows[]; ArrayResize(rows,0);
   double totalPnL=0;
   for(int i=0;i<n;i++)
   {
      if(!pos.SelectByIndex(i)||pos.Magic()!=MAGIC) continue;
      PosRow r;
      r.symbol=pos.Symbol(); r.dir=(pos.PositionType()==POSITION_TYPE_BUY)?"BUY":"SELL";
      r.lots=pos.Volume(); r.openPrice=pos.PriceOpen(); r.sl=pos.StopLoss(); r.tp=pos.TakeProfit();
      r.pnl=pos.Profit()+pos.Swap()+pos.Commission(); r.ticket=pos.Ticket();
      int sz=ArraySize(rows); ArrayResize(rows,sz+1); rows[sz]=r;
      totalPnL+=r.pnl;
   }
   int nRows=ArraySize(rows);

   int x=g_dashX, y=g_dashY;

   // Header
   CreatePanel(PFX+"BG_HDR",x,y,W,HDR_H,C'18,22,30',230);
   ObjectSetInteger(0,PFX+"BG_HDR",OBJPROP_SELECTABLE,true);
   SetLabel(PFX+"T_TITLE","STAALWAG PROP",x+10,y+7,C'212,160,23',13,"Arial Bold");
   // Status dot: green = trading, red = daily limit / max-loss stop, grey = idle
   color dotClr = (g_dailyHalt || g_eaStopped) ? C'220,60,60'
                : (g_autoTrade && !g_targetHit) ? C'60,210,90'
                : C'150,150,150';
   SetLabel(PFX+"T_DOT","\x25CF",x+230,y+9,dotClr,12,"Arial");
   SetLabel(PFX+"T_PAIRS",StringFormat("%dp | %d open",g_nPairs,nRows),x+W-150,y+9,clrWhite,10,"Courier New");
   CreateButton(PFX+"BTN_MIN",g_minimized?" ^ ":" v ",x+W-36,y+6,30,24,C'22,27,34',C'212,160,23');

   int row=y+HDR_H+2;

   // Account stats
   color dpnlC=g_dailyPnL>=0?C'80,220,80':C'220,80,80';
   color eqC=eq>=bal?C'80,220,80':C'220,80,80';
   // Prop metrics vs the recognised firm's baseline (g_initBal)
   double ddRef          = g_trailMaxDD ? g_peakEquity : g_initBal;
   double overallLossPct = (eq < ddRef) ? (ddRef - eq)/ddRef*100.0 : 0;
   double dailyLossPct   = (g_startEquity - eq) > 0
                           ? (g_startEquity - eq)/g_initBal*100.0 : 0;
   double profitPct      = (eq - g_initBal)/g_initBal*100.0;

   CreatePanel(PFX+"BG_ACCT",x,row,W,72,C'14,18,26',200);
   SetLabel(PFX+"T_BAL", StringFormat("BAL  $%.2f",bal), x+10,row+5, clrWhite,10,"Courier New");
   SetLabel(PFX+"T_EQ",  StringFormat("EQ   $%.2f",eq),  x+10,row+22,eqC,      10,"Courier New");
   string firmStr=g_firmName;
   if(InpConsistencyPct>0)
      firmStr+=StringFormat("  C%.0f%% %dd",InpConsistencyPct,ConsistencyMinDays());
   SetLabel(PFX+"T_FIRM",firmStr,x+155,row+24,C'150,170,210',8,"Courier New");
   color tgtC=(g_profitTgtPct>0 && profitPct>=g_profitTgtPct)?C'80,220,80':C'212,160,23';
   string tgtStr=(g_profitTgtPct>0)?StringFormat("PROFIT %+.1f%% / %.0f%%",profitPct,g_profitTgtPct)
                                    :StringFormat("PROFIT %+.1f%% (no tgt)",profitPct);
   SetLabel(PFX+"T_DPNL",StringFormat("DAY  %+.2f",g_dailyPnL),x+290,row+5, dpnlC,10,"Courier New");
   SetLabel(PFX+"T_TGT", tgtStr,x+290,row+22,tgtC,9,"Courier New");
   color ddC=dailyLossPct>=g_dailyGuardPct?C'220,80,80':C'180,180,180';
   SetLabel(PFX+"T_DD",  StringFormat("DAY DD %.1f%%/%.0f%%  TOT %.1f%%/%.0f%%",dailyLossPct,g_dailyLossPct,overallLossPct,g_maxLossPct),x+10,row+44,ddC,9,"Courier New");
   string mlStr=mLevel>0?StringFormat("MARGIN %.0f%%",mLevel):"MARGIN â";
   color mlC=mLevel>0&&mLevel<150?C'220,80,80':mLevel<300?clrOrange:C'180,180,180';
   SetLabel(PFX+"T_ML",mlStr,x+290,row+44,mlC,9,"Courier New");
   row+=76;

   // Signals section
   CreatePanel(PFX+"BG_SIGHDR",x,row,W,SEC_H,C'22,28,38',220);
   // Status: why the EA may not be firing right now
   string st="SIGNALS"; color stC=clrWhite;
   if(g_eaStopped)        { st="STOPPED (max loss)"; stC=C'220,80,80'; }
   else if(g_targetHit)   { st="TARGET HIT";         stC=C'80,220,80'; }
   else if(g_dailyHalt)   { st="HALTED (day cap)";   stC=clrOrange;    }
   else if(g_nPairs>0 && !IsInSession(0)) { st=StringFormat("OUT OF WINDOW (now %02d:00 loc)",LocalHour()); stC=C'150,150,150'; }
   else                   { st=StringFormat("LIVE  %d/%d trades",g_tradesToday,InpMaxTradesDay); }
   SetLabel(PFX+"T_SIGHDR",st,x+8,row+5,stC,10,"Courier New");
   string autoTxt=g_autoTrade?"AUTO ON":"AUTO OFF";
   color  autoClr=g_autoTrade?C'60,200,80':C'180,180,180';
   CreateButton(PFX+"BTN_AUTO",autoTxt,x+W-104,row+2,100,22,g_autoTrade?C'15,45,20':C'30,30,40',autoClr);
   row+=SEC_H+2;

   // Signal rows (one per pair)
   for(int i=0;i<g_nPairs;i++)
   {
      color bgC=(i%2==0)?C'16,20,28':C'18,23,32';
      CreatePanel(PFX+"SIG_BG"+IntegerToString(i),x,row,W,26,bgC,200);

      // Symbol
      SetLabel(PFX+"SIG_SYM"+IntegerToString(i),PadR(g_ps[i].symbol,8),x+8,row+5,clrWhite,9,"Courier New");

      // Signal indicator
      string sigTxt="  â  ";
      color  sigClr=C'100,100,100';
      if(g_ps[i].signal==1)  {sigTxt=" BUY "; sigClr=C'60,200,80';}
      if(g_ps[i].signal==-1) {sigTxt="SELL "; sigClr=C'220,70,70';}
      SetLabel(PFX+"SIG_DIR"+IntegerToString(i),sigTxt,x+100,row+5,sigClr,9,"Courier New");

      // Score
      string scTxt=g_ps[i].score>0?StringFormat("Sc:%d",g_ps[i].score):"     ";
      color scClr=g_ps[i].score>=InpScoreThreshold?clrWhite:C'120,120,120';
      SetLabel(PFX+"SIG_SC"+IntegerToString(i),scTxt,x+158,row+5,scClr,9,"Courier New");

      // Open position for this pair
      bool hasTrade=HasOpenPosition(g_ps[i].symbol);
      string posStr=hasTrade?"[OPEN]":"      ";
      color posClr=hasTrade?C'212,160,23':C'80,80,80';
      SetLabel(PFX+"SIG_POS"+IntegerToString(i),posStr,x+220,row+5,posClr,9,"Courier New");

      // Cooldown indicator
      datetime now=TimeCurrent();
      bool cdActive=(now<g_ps[i].cdBuyUntil||now<g_ps[i].cdSellUntil);
      string cdTxt=g_ps[i].disabled?" [OFF]":(SpikeFrozen(i)?" [SPK]":(cdActive?" [CD]":"      "));
      color cdClr=g_ps[i].disabled?C'220,70,70':(SpikeFrozen(i)?clrOrange:C'220,140,40');
      SetLabel(PFX+"SIG_CD"+IntegerToString(i),cdTxt,x+290,row+5,cdClr,9,"Courier New");

      // Win/loss
      int tot=g_ps[i].wins+g_ps[i].losses;
      string wlTxt=tot>0?StringFormat("W%d L%d",g_ps[i].wins,g_ps[i].losses):"W0 L0";
      color wlClr=g_ps[i].wins>g_ps[i].losses?C'80,180,80':g_ps[i].losses>g_ps[i].wins?C'180,80,80':C'140,140,140';
      SetLabel(PFX+"SIG_WL"+IntegerToString(i),wlTxt,x+W-80,row+5,wlClr,9,"Courier New");

      row+=28;
   }
   row+=4;

   // Open positions header
   CreatePanel(PFX+"BG_POSHDR",x,row,W,SEC_H,C'22,28,38',220);
   color tpnlC=totalPnL>=0?C'80,220,80':C'220,80,80';
   SetLabel(PFX+"T_POSTTL",StringFormat("OPEN POSITIONS  (%d)",nRows),x+8,row+5,clrWhite,10,"Courier New");
   SetLabel(PFX+"T_TPNL",StringFormat("TOTAL  %+.2f",totalPnL),x+360,row+5,tpnlC,10,"Courier New");
   row+=SEC_H+2;

   if(nRows==0)
   {
      CreatePanel(PFX+"POS_EMPTY",x,row,W,ROW_H,C'16,20,28',180);
      SetLabel(PFX+"T_EMPTY","  No open positions",x+8,row+5,C'180,180,180',10,"Courier New");
      row+=ROW_H+2;
   }
   else
   {
      for(int i=0;i<nRows;i++)
      {
         string tk=(string)rows[i].ticket;
         color bgC2=(i%2==0)?C'16,20,28':C'20,25,34';
         color dirC=rows[i].dir=="BUY"?C'60,200,80':C'220,70,70';
         color pnlC=rows[i].pnl>=0?C'60,200,80':C'220,70,70';
         CreatePanel(PFX+"POS_BG"+tk,x,row,W-100,ROW_H,bgC2,200);
         SetLabel(PFX+"POS_SYM"+tk,PadR(rows[i].symbol,8),x+8, row+5,clrWhite, 10,"Courier New");
         SetLabel(PFX+"POS_DIR"+tk,rows[i].dir,             x+100,row+5,dirC,   10,"Courier New");
         SetLabel(PFX+"POS_LOT"+tk,StringFormat("%.2f",rows[i].lots),x+152,row+5,clrWhite,10,"Courier New");
         SetLabel(PFX+"POS_PX"+tk, StringFormat("@%.5g",rows[i].openPrice),x+210,row+5,C'180,180,180',9,"Courier New");
         color slC=rows[i].sl>0?C'220,90,90':C'160,160,160';
         color tpC=rows[i].tp>0?C'90,220,90':C'160,160,160';
         SetLabel(PFX+"POS_SL"+tk,rows[i].sl>0?StringFormat("SL%.5g",rows[i].sl):"SL â",x+282,row+5,slC,9,"Courier New");
         SetLabel(PFX+"POS_TP"+tk,rows[i].tp>0?StringFormat("TP%.5g",rows[i].tp):"TP â",x+358,row+5,tpC,9,"Courier New");
         SetLabel(PFX+"POS_PNL"+tk,StringFormat("%+.2f",rows[i].pnl),x+W-128,row+5,pnlC,10,"Courier New");
         CreateButton(PFX+"BTN_C25_"+tk,"25%",x+W-96,row+1,30,ROW_H-2,C'28,35,45',clrWhite);
         CreateButton(PFX+"BTN_C50_"+tk,"50%",x+W-64,row+1,30,ROW_H-2,C'28,35,45',clrWhite);
         CreateButton(PFX+"BTN_CXX_"+tk," X ",x+W-32,row+1,30,ROW_H-2,C'80,20,20',C'220,80,80');
         row+=ROW_H+1;
      }
   }
   row+=4;

   // New trade row
   CreatePanel(PFX+"BG_TRADE",x,row,W,SEC_H,C'22,28,38',220);
   SetLabel(PFX+"T_TRADEHDR","MANUAL TRADE",x+8,row+5,clrWhite,10,"Courier New");
   row+=SEC_H+2;

   CreatePanel(PFX+"BG_TRADE2",x,row,W,36,C'16,20,28',200);
   string selPair=g_nPairs>0?g_ps[g_pairIdx%g_nPairs].symbol:"EURUSD";
   CreateButton(PFX+"BTN_PAIR_L","<",x+6,  row+4,22,26,C'28,35,48',clrWhite);
   CreateButton(PFX+"BTN_PAIR_M",PadC(selPair,8),x+30,row+4,96,26,C'22,30,45',clrWhite);
   CreateButton(PFX+"BTN_PAIR_R",">",x+128,row+4,22,26,C'28,35,48',clrWhite);
   SetLabel(PFX+"T_LOT_LBL","LOT",x+162,row+8,C'180,180,180',9,"Courier New");
   CreateButton(PFX+"BTN_LOT_DN","-", x+190,row+4,22,26,C'28,35,48',clrWhite);
   CreateButton(PFX+"BTN_LOT_DSP",StringFormat("%.2f",g_tradeLot),x+214,row+4,52,26,C'18,24,34',clrWhite);
   CreateButton(PFX+"BTN_LOT_UP","+", x+268,row+4,22,26,C'28,35,48',clrWhite);
   CreateButton(PFX+"BTN_BUY", "BUY", x+304,row+4,118,26,C'20,70,30',C'60,220,80');
   CreateButton(PFX+"BTN_SELL","SELL",x+426,row+4,118,26,C'70,20,20',C'220,60,60');
   row+=40;

   // Account actions
   CreatePanel(PFX+"BG_ACTS",x,row,W,34,C'14,18,26',200);
   CreateButton(PFX+"BTN_CLOSE_PROFIT","CLOSE PROFIT",x+6,  row+4,172,26,C'15,45,20',C'60,200,80');
   CreateButton(PFX+"BTN_CLOSE_LOSS",  "CLOSE LOSS",  x+182,row+4,150,26,C'45,15,15',C'200,60,60');
   CreateButton(PFX+"BTN_CLOSE_ALL",   "CLOSE ALL",   x+336,row+4,218,26,C'60,15,15',clrOrangeRed);
   row+=38;

   // Footer bar
   CreatePanel(PFX+"BG_FOOT",x,row,W,4,C'212,160,23',255);

   ChartRedraw(0);
}

void UpdateDashboard()
{
   if(g_minimized){DrawMinimized();return;}
   DrawDashboard();
}

void DrawMinimized()
{
   double eq=OwnEquity();
   g_dailyPnL=eq-g_startEquity;
   color dpC=g_dailyPnL>=0?C'80,220,80':C'220,80,80';
   CreatePanel(PFX+"BG_HDR",g_dashX,g_dashY,W,HDR_H,C'18,22,30',230);
   SetLabel(PFX+"T_TITLE",StringFormat("STAALWAG PROP  |  EQ $%.2f  DAY %+.2f  |  %d open",
            eq,g_dailyPnL,CountOpenPositions()),g_dashX+8,g_dashY+9,dpC,10,"Courier New");
   CreateButton(PFX+"BTN_MIN"," ^ ",g_dashX+W-36,g_dashY+6,30,24,C'22,27,34',C'212,160,23');
   ChartRedraw(0);
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// OBJECT HELPERS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void CreatePanel(string name,int x,int y,int w,int h,color bg,uchar alpha)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   // Force fully opaque â solid dashboard background, no chart bleed-through.
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,ColorToARGB(bg,255));
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}

void SetLabel(string name,string text,int x,int y,color clr,int sz=10,string font="Courier New")
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,font);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,sz);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}

void CreateButton(string name,string text,int x,int y,int w,int h,color bg,color clr=clrWhite)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial Bold");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}

string PadR(string s,int n)
{
   while(StringLen(s)<n) s+=" ";
   return StringSubstr(s,0,n);
}

string PadC(string s,int n)
{
   int sp=n-StringLen(s);
   int l=sp/2, r=sp-l;
   string res="";
   for(int i=0;i<l;i++) res+=" ";
   res+=s;
   for(int i=0;i<r;i++) res+=" ";
   return res;
}

