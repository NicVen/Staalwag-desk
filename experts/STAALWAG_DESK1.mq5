//+------------------------------------------------------------------+
//|                   STAALWAG DESK v2.1 SCALP                        |
//|   Multi-Pair Scalping EA — BlackBull $100 Live                    |
//|   M5 signal · 0.01 lot · 3 concurrent · 2% daily DD limit        |
//+------------------------------------------------------------------+
#property copyright "STAALWAG"
#property version   "2.10"
#property description "STAALWAG DESK — Scalping Edition"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//────────────────────────────────────────────────────────────────────
// INPUTS
//────────────────────────────────────────────────────────────────────
input group "═══ Pairs ═══"
input string InpPairs         = "EURUSD,GBPUSD,USDJPY,USDCHF,USDCAD,AUDUSD,NZDUSD,GBPJPY,EURJPY,EURGBP";
input int    InpMaxConcurrent = 3;     // Max 3 scalp positions

input group "═══ Account & Risk ═══"
input bool   InpAutoLot        = true;   // Auto-scales with balance growth
input double InpRiskPercent    = 1.0;    // 1% risk per trade — $1 on $100, $2 on $200
input double InpFixedLot       = 0.01;   // Fallback if AutoLot=false
input double InpMaxLot         = 0.02;   // Safety cap — raise manually as balance grows
input double InpDailyLossPct   = 2.0;    // $2 daily limit on $100 — 3 bad trades max
input double InpMaxDrawdownPct = 8.0;    // 8% DD hard stop

input group "═══ Signal Engine ═══"
input ENUM_TIMEFRAMES InpSignalTF   = PERIOD_M5;  // M5 scalping timeframe
input int    InpScoreThreshold      = 4;           // Lower bar — scalp setups less perfect
input bool   InpUseBiasFilter       = false;       // Off — M5 bias changes too fast
input int    InpEMAFast             = 9;
input int    InpEMASlow             = 21;
input double InpWickRatio           = 1.2;
input double InpSLBuffer            = 0.3;   // Tight buffer for scalp
input double InpMinSLATR            = 0.6;   // 0.6×ATR — scalp SL must be tight
input double InpRRRatio             = 1.5;   // 1.5:1 TP — quick exits
input double InpLevelProximity      = 0.5;
input double InpMaxSpreadPips       = 3.0;   // BlackBull ECN: 0-2 pip typical, allow 3

input group "═══ Markov Regime ═══"
input bool   InpUseMarkov     = false;  // Off for scalping — M5 regime too noisy
input double InpMarkovThr     = 0.3;
input double InpMarkovPersist = 0.80;
input int    InpMarkovLB      = 10;
input int    InpMarkovHold    = 3;

input group "═══ Trade Manager ═══"
input bool   InpUseTrail      = true;
input double InpTrailMult     = 1.0;   // Tight trail — lock in scalp profits fast
input bool   InpUseBreakEven  = true;
input double InpBEMult        = 0.8;   // Move BE earlier on scalp
input bool   InpUsePartialTP  = false; // Off — too small to split 0.01 lot
input double InpPartialRR     = 1.0;
input bool   InpExtendTP      = false; // Off — take the scalp, don't chase
input bool   InpProgressTrail = false;
input double InpTrailR2Mult   = 1.2;
input double InpTrailR3Mult   = 0.8;

input group "═══ Sessions ═══"
input bool   InpUseSession    = true;
input int    InpAsiaOpen      = 0;
input int    InpAsiaClose     = 7;
input int    InpLDNOpen       = 7;
input int    InpLDNClose      = 16;
input int    InpNYOpen        = 13;
input int    InpNYClose       = 21;

input group "═══ Display ═══"
input bool   InpShowDash      = true;
input int    InpDashX         = 20;
input int    InpDashY         = 30;
input int    InpTimerSec      = 1;    // 1s timer — faster scalp response

//────────────────────────────────────────────────────────────────────
// CONSTANTS
//────────────────────────────────────────────────────────────────────
#define PFX    "SWD_"
#define MAGIC  202604
#define W      560
#define ROW_H  28
#define HDR_H  36
#define SEC_H  26

//────────────────────────────────────────────────────────────────────
// PER-PAIR STATE
//────────────────────────────────────────────────────────────────────
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
};

//────────────────────────────────────────────────────────────────────
// GLOBALS
//────────────────────────────────────────────────────────────────────
CTrade        trade;
CPositionInfo pos;

PairState g_ps[];
int       g_nPairs = 0;

double   g_startEquity = 0.0;
double   g_dailyPnL    = 0.0;
double   g_peakEquity  = 0.0;
datetime g_lastDay     = 0;
bool     g_eaStopped   = false;  // hard stop on max DD

int      g_dashX, g_dashY;
bool     g_minimized = false;
bool     g_autoTrade = false;
#define  GV_AUTO  "SWD_AutoTrade"

// For manual trade panel (pair selector)
int      g_pairIdx   = 0;
double   g_tradeLot  = 0.01;

// Open position row tracker (for dashboard cleanup)
ulong    g_openTickets[];
int      g_lastPosCount = -1;

//────────────────────────────────────────────────────────────────────
// INIT HELPERS
//────────────────────────────────────────────────────────────────────
void ParsePairs()
{
   string raw = InpPairs;
   StringTrimLeft(raw);
   StringTrimRight(raw);
   string parts[];
   int n = StringSplit(raw, ',', parts);
   ArrayResize(g_ps, n);
   g_nPairs = 0;
   for(int i = 0; i < n; i++)
   {
      string sym = parts[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      StringToUpper(sym);
      if(sym == "") continue;
      // Only forex — block commodities, crypto, indices
      if(StringFind(sym,"XAU")>=0 || StringFind(sym,"XAG")>=0 ||
         StringFind(sym,"OIL")>=0 || StringFind(sym,"BTC")>=0 ||
         StringFind(sym,"ETH")>=0 || StringFind(sym,"SPX")>=0 ||
         StringFind(sym,"NAS")>=0 || StringFind(sym,"DAX")>=0 ||
         StringFind(sym,"US30")>=0|| StringFind(sym,"NDX")>=0)
      {
         Print("DESK: skipping non-forex symbol ", sym);
         continue;
      }
      // Check symbol exists in broker
      if(!SymbolSelect(sym, true) && !SymbolSelect(sym+".", true))
      {
         // Try with broker suffix
         Print("DESK: symbol not found — ", sym, " (check broker name)");
      }
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
   if(tfMin<=15)      { g_ps[i].trailMult=InpTrailMult; g_ps[i].rrRatio=InpRRRatio; g_ps[i].proxMult=0.4; g_ps[i].mkThr=0.15; }
   else if(tfMin<=60) { g_ps[i].trailMult=InpTrailMult; g_ps[i].rrRatio=InpRRRatio; g_ps[i].proxMult=0.6; g_ps[i].mkThr=0.30; }
   else if(tfMin<=240){ g_ps[i].trailMult=InpTrailMult; g_ps[i].rrRatio=InpRRRatio; g_ps[i].proxMult=0.8; g_ps[i].mkThr=0.50; }
   else               { g_ps[i].trailMult=InpTrailMult; g_ps[i].rrRatio=InpRRRatio; g_ps[i].proxMult=1.0; g_ps[i].mkThr=0.80; }

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

//────────────────────────────────────────────────────────────────────
// INIT / DEINIT
//────────────────────────────────────────────────────────────────────
int OnInit()
{
   trade.SetExpertMagicNumber(MAGIC);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   ParsePairs();
   for(int i=0;i<g_nPairs;i++) InitPairHandles(i);

   g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_peakEquity  = g_startEquity;
   g_dashX       = InpDashX;
   g_dashY       = InpDashY;
   g_tradeLot    = InpAutoLot ? 0.01 : InpFixedLot;

   ArrayResize(g_openTickets, 0);

   // Restore auto-trade state across TF switches / re-attaches
   if(GlobalVariableCheck(GV_AUTO))
      g_autoTrade = (bool)GlobalVariableGet(GV_AUTO);

   if(InpShowDash) DrawDashboard();
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

//────────────────────────────────────────────────────────────────────
// TIMER
//────────────────────────────────────────────────────────────────────
void OnTimer()
{
   if(InpShowDash) UpdateDashboard();
}

//────────────────────────────────────────────────────────────────────
// TRADE TRANSACTION — track wins/losses per pair
//────────────────────────────────────────────────────────────────────
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeResult      &request,
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
               g_ps[i].cdBuyUntil = TimeCurrent() + 30*60; // 30min scalp cooldown
         }
         else
         {
            g_ps[i].consecSell++;
            g_ps[i].consecBuy = 0;
            if(g_ps[i].consecSell >= 3)
               g_ps[i].cdSellUntil = TimeCurrent() + 30*60; // 30min scalp cooldown
         }
      }
      break;
   }
}

//────────────────────────────────────────────────────────────────────
// ON TICK — main loop
//────────────────────────────────────────────────────────────────────
void OnTick()
{
   CheckDailyReset();
   if(g_eaStopped) return;

   // Max drawdown check
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_peakEquity) g_peakEquity = eq;
   double ddPct = (g_peakEquity > 0) ? (g_peakEquity - eq) / g_peakEquity * 100.0 : 0;
   if(ddPct >= InpMaxDrawdownPct)
   {
      CloseAll();
      g_eaStopped = true;
      Alert("STAALWAG DESK: Max drawdown ", DoubleToString(InpMaxDrawdownPct,1), "% hit — EA stopped.");
      return;
   }

   if(IsDailyDDBreached())
   {
      CloseAll();
      return;
   }

   // Friday cutoff
   MqlDateTime tNow; TimeToStruct(TimeCurrent(), tNow);
   if(tNow.day_of_week == 5 && tNow.hour >= 13) return;

   // Count open positions
   int openCount = CountOpenPositions();

   // Pass 1 — compute signals on new bar
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

      // Refresh levels
      RefreshLevels(i);
      RefreshOBFVG(i);
      UpdateMarkov(i);

      bool htfBull=false, htfBear=false;
      GetHTFBias(i, htfBull, htfBear);

      g_ps[i].signal = 0;
      g_ps[i].score  = 0;

      if(InpUseSession && !IsInSession(i)) continue;
      if(HasOpenPosition(sym)) continue;

      RunSignal(i, htfBull, htfBear);

      // Cooldown check
      datetime now = TimeCurrent();
      if(g_ps[i].signal==1  && now < g_ps[i].cdBuyUntil)  g_ps[i].signal=0;
      if(g_ps[i].signal==-1 && now < g_ps[i].cdSellUntil) g_ps[i].signal=0;
   }

   // Pass 2 — auto-fire any pending signal (runs every tick so AUTO ON is instant)
   for(int i=0;i<g_nPairs;i++)
   {
      if(!g_autoTrade) break;
      if(g_ps[i].signal == 0 || g_ps[i].score < InpScoreThreshold) continue;
      if(HasOpenPosition(g_ps[i].symbol)) continue;
      if(openCount >= InpMaxConcurrent) break;

      double lot = CalcLot(i);
      if(g_ps[i].consecAny >= 3) lot *= 0.5;
      ExecuteTrade(i, g_ps[i].signal, lot);
      g_ps[i].signal = 0; // clear so it doesn't re-fire next tick
      openCount++;
   }

   if(InpShowDash) UpdateDashboard();
}

//────────────────────────────────────────────────────────────────────
// SIGNAL ENGINE (per-pair)
//────────────────────────────────────────────────────────────────────
void RunSignal(int i, bool htfBull, bool htfBear)
{
   string sym  = g_ps[i].symbol;
   ENUM_TIMEFRAMES sTF = g_ps[i].sTF;
   double atr  = g_ps[i].atr;
   if(atr <= 0) return;

   int bars = iBars(sym, sTF);
   if(bars < 10) return;

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

   bool anyLong  = longPDL||longAL||longPWL||sweepBullPDL||sweepBullAL;
   bool anyShort = shortPDH||shortAH||shortPWH||sweepBearPDH||sweepBearAH;
   if(!anyLong && !anyShort) return;

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

   int score = 2;
   if(biasAligned) score+=2;
   if(mkAligned)   score+=1;
   if(isSweep)     score+=1;
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

//────────────────────────────────────────────────────────────────────
// EXECUTE TRADE
//────────────────────────────────────────────────────────────────────
void ExecuteTrade(int i, int direction, double lot)
{
   string sym = g_ps[i].symbol;
   lot = NormLot(sym, lot);

   // ATR fallback — fetch fresh if zero (pair not yet processed by signal engine)
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
      double sl    = g_ps[i].slPrice > 0 ? g_ps[i].slPrice : entry - g_ps[i].atr*(InpSLBuffer+InpMinSLATR);
      sl    = MathMin(sl, entry - g_ps[i].atr*InpMinSLATR);
      double tp    = g_ps[i].tpPrice > 0 ? g_ps[i].tpPrice : entry+(entry-sl)*g_ps[i].rrRatio;
      if(sl >= entry){ Print("ExecuteTrade BUY: invalid SL ",sl," >= entry ",entry," — skipping"); return; }
      if(trade.Buy(lot, sym, entry, sl, tp,
            StringFormat("SWD LONG %s Sc:%d", sym, g_ps[i].score)))
      { g_ps[i].partialDone=false; g_ps[i].beDone=false; }
   }
   else
   {
      double entry = bid;
      double sl    = g_ps[i].slPrice > 0 ? g_ps[i].slPrice : entry + g_ps[i].atr*(InpSLBuffer+InpMinSLATR);
      sl    = MathMax(sl, entry + g_ps[i].atr*InpMinSLATR);
      double tp    = g_ps[i].tpPrice > 0 ? g_ps[i].tpPrice : entry-(sl-entry)*g_ps[i].rrRatio;
      if(sl <= entry){ Print("ExecuteTrade SELL: invalid SL ",sl," <= entry ",entry," — skipping"); return; }
      if(trade.Sell(lot, sym, entry, sl, tp,
            StringFormat("SWD SHORT %s Sc:%d", sym, g_ps[i].score)))
      { g_ps[i].partialDone=false; g_ps[i].beDone=false; }
   }
}

//────────────────────────────────────────────────────────────────────
// TRADE MANAGER (per-pair)
//────────────────────────────────────────────────────────────────────
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

      double openP  = pos.PriceOpen();
      double curSL  = pos.StopLoss();
      double curTP  = pos.TakeProfit();
      double lots   = pos.Volume();
      ulong  ticket = pos.Ticket();
      double slDist = MathAbs(openP - curSL);
      double oneR   = slDist > 0 ? slDist : atr;

      double curP   = pos.PositionType()==POSITION_TYPE_BUY ? bid : ask;
      double pnlR   = (oneR>0) ? MathAbs(curP-openP)/oneR : 0;

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
            double cl = NormLot(sym, lots*0.5);
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
            double cl = NormLot(sym, lots*0.5);
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

//────────────────────────────────────────────────────────────────────
// MARKOV
//────────────────────────────────────────────────────────────────────
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

//────────────────────────────────────────────────────────────────────
// HTF BIAS
//────────────────────────────────────────────────────────────────────
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

//────────────────────────────────────────────────────────────────────
// KEY LEVELS & OB/FVG
//────────────────────────────────────────────────────────────────────
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
      if(td.hour>=InpAsiaOpen && td.hour<InpAsiaClose)
      {
         double h=iHigh(sym,PERIOD_H1,b),l=iLow(sym,PERIOD_H1,b);
         if(h>aH)aH=h; if(l<aL)aL=l;
      }
      if(td.hour>=InpAsiaClose && td.day_of_week>=1) break;
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

//────────────────────────────────────────────────────────────────────
// SESSION CHECK
//────────────────────────────────────────────────────────────────────
bool IsInSession(int i)
{
   if(!InpUseSession) return true;
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   int h=t.hour;
   bool inAsia = g_ps[i].sessAsia && (h>=InpAsiaOpen && h<InpAsiaClose);
   bool inLDN  = g_ps[i].sessLDN  && (h>=InpLDNOpen  && h<InpLDNClose);
   bool inNY   = g_ps[i].sessNY   && (h>=InpNYOpen   && h<InpNYClose);
   return inAsia||inLDN||inNY;
}

//────────────────────────────────────────────────────────────────────
// DAILY RESET / DD
//────────────────────────────────────────────────────────────────────
void CheckDailyReset()
{
   datetime curDay = StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(curDay != g_lastDay)
   {
      g_lastDay     = curDay;
      g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dailyPnL    = 0.0;
      for(int i=0;i<g_nPairs;i++)
      {
         g_ps[i].consecBuy=0; g_ps[i].consecSell=0; g_ps[i].consecAny=0;
         g_ps[i].cdBuyUntil=0; g_ps[i].cdSellUntil=0;
      }
   }
   g_dailyPnL = AccountInfoDouble(ACCOUNT_EQUITY) - g_startEquity;
}

bool IsDailyDDBreached() { return g_dailyPnL <= -(AccountInfoDouble(ACCOUNT_BALANCE)*InpDailyLossPct/100.0); }

//────────────────────────────────────────────────────────────────────
// POSITION HELPERS
//────────────────────────────────────────────────────────────────────
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
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
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

//────────────────────────────────────────────────────────────────────
// CHART EVENT
//────────────────────────────────────────────────────────────────────
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
      int idx=g_pairIdx%g_nPairs;
      ExecuteTrade(idx,1,g_tradeLot);
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false); return;
   }
   if(sparam==PFX+"BTN_SELL" && g_nPairs>0)
   {
      int idx=g_pairIdx%g_nPairs;
      ExecuteTrade(idx,-1,g_tradeLot);
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

//────────────────────────────────────────────────────────────────────
// DASHBOARD DRAW
//────────────────────────────────────────────────────────────────────
struct PosRow { string symbol,dir; double lots,openPrice,sl,tp,pnl; ulong ticket; };

void DrawDashboard()
{
   ObjectsDeleteAll(0,PFX);

   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq =AccountInfoDouble(ACCOUNT_EQUITY);
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
   SetLabel(PFX+"T_TITLE","STAALWAG DESK v2",x+10,y+7,C'212,160,23',13,"Arial Bold");
   SetLabel(PFX+"T_PAIRS",StringFormat("%d pairs | %d open",g_nPairs,nRows),x+210,y+9,clrWhite,10,"Courier New");
   CreateButton(PFX+"BTN_MIN",g_minimized?" ^ ":" v ",x+W-36,y+6,30,24,C'22,27,34',C'212,160,23');

   int row=y+HDR_H+2;

   // Account stats
   color dpnlC=g_dailyPnL>=0?C'80,220,80':C'220,80,80';
   color eqC=eq>=bal?C'80,220,80':C'220,80,80';
   double ddPct=g_peakEquity>0?(g_peakEquity-eq)/g_peakEquity*100.0:0;
   double dailyPct=g_startEquity>0?MathAbs(g_dailyPnL)/g_startEquity*100.0:0;

   CreatePanel(PFX+"BG_ACCT",x,row,W,72,C'14,18,26',200);
   SetLabel(PFX+"T_BAL", StringFormat("BAL  $%.2f",bal), x+10,row+5, clrWhite,10,"Courier New");
   SetLabel(PFX+"T_EQ",  StringFormat("EQ   $%.2f",eq),  x+10,row+22,eqC,      10,"Courier New");
   SetLabel(PFX+"T_DPNL",StringFormat("DAY  %+.2f (%.1f%%)",g_dailyPnL,dailyPct),x+290,row+5, dpnlC,10,"Courier New");
   SetLabel(PFX+"T_FREE",StringFormat("FREE $%.2f",freeM),x+290,row+22,clrWhite,10,"Courier New");
   color ddC=ddPct>=InpMaxDrawdownPct*0.7?C'220,80,80':C'180,180,180';
   SetLabel(PFX+"T_DD",  StringFormat("DD %.1f%% / %.0f%% MAX",ddPct,InpMaxDrawdownPct),x+10,row+44,ddC,9,"Courier New");
   string mlStr=mLevel>0?StringFormat("MARGIN %.0f%%",mLevel):"MARGIN —";
   color mlC=mLevel>0&&mLevel<150?C'220,80,80':mLevel<300?clrOrange:C'180,180,180';
   SetLabel(PFX+"T_ML",mlStr,x+290,row+44,mlC,9,"Courier New");
   row+=76;

   // Signals section
   CreatePanel(PFX+"BG_SIGHDR",x,row,W,SEC_H,C'22,28,38',220);
   SetLabel(PFX+"T_SIGHDR","SIGNALS",x+8,row+5,clrWhite,10,"Courier New");
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
      string sigTxt="  —  ";
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
      string cdTxt=cdActive?" [CD]":"      ";
      SetLabel(PFX+"SIG_CD"+IntegerToString(i),cdTxt,x+290,row+5,C'220,140,40',9,"Courier New");

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
         SetLabel(PFX+"POS_SL"+tk,rows[i].sl>0?StringFormat("SL%.5g",rows[i].sl):"SL —",x+300,row+5,slC,9,"Courier New");
         SetLabel(PFX+"POS_TP"+tk,rows[i].tp>0?StringFormat("TP%.5g",rows[i].tp):"TP —",x+385,row+5,tpC,9,"Courier New");
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
   if(g_minimized){ DrawMinimized(); return; }

   // Rebuild structure only when position count changes
   int curPosCount = CountOpenPositions();
   if(curPosCount != g_lastPosCount)
   {
      g_lastPosCount = curPosCount;
      DrawDashboard();
      return;
   }

   // Patch dynamic labels in-place — no delete, no flicker
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double freeM= AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double mLevel=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double ddPct = g_peakEquity>0?(g_peakEquity-eq)/g_peakEquity*100.0:0;
   double dailyPct=g_startEquity>0?MathAbs(g_dailyPnL)/g_startEquity*100.0:0;

   color eqC   = eq>=bal?C'80,220,80':C'220,80,80';
   color dpnlC = g_dailyPnL>=0?C'80,220,80':C'220,80,80';
   color ddC   = ddPct>=InpMaxDrawdownPct*0.7?C'220,80,80':C'180,180,180';
   color mlC   = mLevel>0&&mLevel<150?C'220,80,80':mLevel<300?clrOrange:C'180,180,180';

   // Account row
   ObjectSetString (0,PFX+"T_BAL", OBJPROP_TEXT, StringFormat("BAL  $%.2f",bal));
   ObjectSetString (0,PFX+"T_EQ",  OBJPROP_TEXT, StringFormat("EQ   $%.2f",eq));
   ObjectSetInteger(0,PFX+"T_EQ",  OBJPROP_COLOR,(long)eqC);
   ObjectSetString (0,PFX+"T_DPNL",OBJPROP_TEXT, StringFormat("DAY  %+.2f (%.1f%%)",g_dailyPnL,dailyPct));
   ObjectSetInteger(0,PFX+"T_DPNL",OBJPROP_COLOR,(long)dpnlC);
   ObjectSetString (0,PFX+"T_FREE",OBJPROP_TEXT, StringFormat("FREE $%.2f",freeM));
   ObjectSetString (0,PFX+"T_DD",  OBJPROP_TEXT, StringFormat("DD %.1f%% / %.0f%% MAX",ddPct,InpMaxDrawdownPct));
   ObjectSetInteger(0,PFX+"T_DD",  OBJPROP_COLOR,(long)ddC);
   string mlStr=mLevel>0?StringFormat("MARGIN %.0f%%",mLevel):"MARGIN —";
   ObjectSetString (0,PFX+"T_ML",  OBJPROP_TEXT, mlStr);
   ObjectSetInteger(0,PFX+"T_ML",  OBJPROP_COLOR,(long)mlC);

   // Header pair count
   int n=PositionsTotal(); int nMagic=0;
   for(int i=0;i<n;i++) if(pos.SelectByIndex(i)&&pos.Magic()==MAGIC) nMagic++;
   ObjectSetString(0,PFX+"T_PAIRS",OBJPROP_TEXT,StringFormat("%d pairs | %d open",g_nPairs,nMagic));

   // AUTO button
   string autoTxt=g_autoTrade?"AUTO ON":"AUTO OFF";
   color  autoClr=g_autoTrade?C'60,200,80':C'180,180,180';
   color  autoBg =g_autoTrade?C'15,45,20':C'30,30,40';
   ObjectSetString (0,PFX+"BTN_AUTO",OBJPROP_TEXT,   autoTxt);
   ObjectSetInteger(0,PFX+"BTN_AUTO",OBJPROP_COLOR,  (long)autoClr);
   ObjectSetInteger(0,PFX+"BTN_AUTO",OBJPROP_BGCOLOR,(long)autoBg);

   // Signal rows
   datetime now=TimeCurrent();
   for(int i=0;i<g_nPairs;i++)
   {
      string si=IntegerToString(i);
      string sigTxt="  —  "; color sigClr=C'100,100,100';
      if(g_ps[i].signal==1)  {sigTxt=" BUY "; sigClr=C'60,200,80';}
      if(g_ps[i].signal==-1) {sigTxt="SELL "; sigClr=C'220,70,70';}
      ObjectSetString (0,PFX+"SIG_DIR"+si,OBJPROP_TEXT, sigTxt);
      ObjectSetInteger(0,PFX+"SIG_DIR"+si,OBJPROP_COLOR,(long)sigClr);

      string scTxt=g_ps[i].score>0?StringFormat("Sc:%d",g_ps[i].score):"     ";
      color  scClr=g_ps[i].score>=InpScoreThreshold?clrWhite:C'120,120,120';
      ObjectSetString (0,PFX+"SIG_SC"+si,OBJPROP_TEXT, scTxt);
      ObjectSetInteger(0,PFX+"SIG_SC"+si,OBJPROP_COLOR,(long)scClr);

      bool hasTrade=HasOpenPosition(g_ps[i].symbol);
      ObjectSetString (0,PFX+"SIG_POS"+si,OBJPROP_TEXT, hasTrade?"[OPEN]":"      ");
      ObjectSetInteger(0,PFX+"SIG_POS"+si,OBJPROP_COLOR,(long)(hasTrade?C'212,160,23':C'80,80,80'));

      bool cdActive=(now<g_ps[i].cdBuyUntil||now<g_ps[i].cdSellUntil);
      ObjectSetString(0,PFX+"SIG_CD"+si,OBJPROP_TEXT,cdActive?" [CD]":"      ");

      int tot=g_ps[i].wins+g_ps[i].losses;
      string wlTxt=tot>0?StringFormat("W%d L%d",g_ps[i].wins,g_ps[i].losses):"W0 L0";
      color wlClr=g_ps[i].wins>g_ps[i].losses?C'80,180,80':g_ps[i].losses>g_ps[i].wins?C'180,80,80':C'140,140,140';
      ObjectSetString (0,PFX+"SIG_WL"+si,OBJPROP_TEXT, wlTxt);
      ObjectSetInteger(0,PFX+"SIG_WL"+si,OBJPROP_COLOR,(long)wlClr);
   }

   // Open position P&L (rows already exist, just update numbers)
   double totalPnL=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(!pos.SelectByIndex(i)||pos.Magic()!=MAGIC) continue;
      string tk=(string)pos.Ticket();
      double pnl=pos.Profit()+pos.Swap()+pos.Commission();
      totalPnL+=pnl;
      color pnlC=pnl>=0?C'60,200,80':C'220,70,70';
      ObjectSetString (0,PFX+"POS_PNL"+tk,OBJPROP_TEXT, StringFormat("%+.2f",pnl));
      ObjectSetInteger(0,PFX+"POS_PNL"+tk,OBJPROP_COLOR,(long)pnlC);
   }
   color tpnlC=totalPnL>=0?C'80,220,80':C'220,80,80';
   ObjectSetString (0,PFX+"T_TPNL",OBJPROP_TEXT, StringFormat("TOTAL  %+.2f",totalPnL));
   ObjectSetInteger(0,PFX+"T_TPNL",OBJPROP_COLOR,(long)tpnlC);

   ChartRedraw(0);
}

void DrawMinimized()
{
   ObjectsDeleteAll(0,PFX);
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   g_dailyPnL=eq-g_startEquity;
   color dpC=g_dailyPnL>=0?C'80,220,80':C'220,80,80';
   CreatePanel(PFX+"BG_HDR",g_dashX,g_dashY,W,HDR_H,C'18,22,30',230);
   SetLabel(PFX+"T_TITLE",StringFormat("STAALWAG DESK  |  EQ $%.2f  DAY %+.2f  |  %d open",
            eq,g_dailyPnL,CountOpenPositions()),g_dashX+8,g_dashY+9,dpC,10,"Courier New");
   CreateButton(PFX+"BTN_MIN"," ^ ",g_dashX+W-36,g_dashY+6,30,24,C'22,27,34',C'212,160,23');
   ChartRedraw(0);
}

//────────────────────────────────────────────────────────────────────
// OBJECT HELPERS
//────────────────────────────────────────────────────────────────────
void CreatePanel(string name,int x,int y,int w,int h,color bg,uchar alpha)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,ColorToARGB(bg,alpha));
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

