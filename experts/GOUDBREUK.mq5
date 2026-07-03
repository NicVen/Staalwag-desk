//+------------------------------------------------------------------+
//|                                                  GOUDBREUK v1.0  |
//|          XAUUSD Â· Fractal-ORB Breakout Expert Advisor            |
//|  Signal: ORB Range Break + Williams Fractal + Markov Regime Gate |
//|  Trade Mgr: Trail Â· BE Â· Partial TP Â· Session Filter             |
//|  Nico's Trading Desk â one of a kind                             |
//+------------------------------------------------------------------+
#property copyright "Nico's Trading Desk"
#property version   "1.00"
#property description "GOUDBREUK â XAUUSD Fractal-ORB Breakout with Markov Gate"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

enum PropFirm
{
   PF_AUTO,        // Auto-detect from account company/server
   PF_FUNDEDNEXT,  // FundedNext Stellar 2-step (8/5, d5, m10 static)
   PF_FTMO,        // FTMO 2-step (10/5, d5, m10 static)
   PF_GOATFUNDED,  // Goat Funded 2-step Std (8/6, d4, m10 static)
   PF_FUNDINGPIPS, // FundingPips 2-step Std (8/5, d5, m10 static)
   PF_THE5ERS,     // The5ers High Stakes (10/5, d5, m10 static)
   PF_E8,          // E8 Classic 2-step (8/4, d4, m8 TRAILING)
   PF_BLACKBULL,   // BlackBull = broker, no prop rules (conservative cap)
   PF_OFF,         // No prop engine â use the $ daily-loss limit only
   PF_CUSTOM       // Use the manual values below
};

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// INPUTS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

input group "âââ Account & Risk âââ"
input bool     InpAutoLot        = true;     // Auto lot (% risk)
input double   InpRiskPercent    = 1.0;      // Risk % per trade
input double   InpFixedLot       = 0.05;     // Fixed lot (if AutoLot off)
input double   InpDailyLossLimit = 300.0;    // Daily loss limit ($) â used only when PropFirm=PF_OFF
input double   InpMaxSpreadUSD   = 0.80;     // Max XAUUSD spread ($) to allow an entry

// ââ Prop Firm Profile ââââââââââââââââââââââââââââââââââââââââââââââ
input group "âââ Prop Firm Profile âââ"
input PropFirm InpPropFirm      = PF_AUTO; // Recognise firm -> auto-apply its risk rules
input int    InpPhase           = 1;       // Challenge phase: 1 or 2 (sets profit target)
input double InpInitialBalance  = 0.0;     // Challenge start balance (0 = use account balance)
input bool   InpStopAtTarget    = true;    // Stop opening new trades once phase target hit
input double InpDailyProfitCap  = 2.5;     // Halt for the day after +this% (consistency rule)
input double InpProfitTargetPct = 8.0;     // (PF_CUSTOM) Phase target %
input double InpMaxLossPctIn    = 10.0;    // (PF_CUSTOM) Hard overall max loss %
input double InpDailyLossPctIn  = 5.0;     // (PF_CUSTOM) Hard daily loss %
input bool   InpTrailingMaxDD   = false;   // (PF_CUSTOM) Max loss trails equity peak

// ââ Trade Safety âââââââââââââââââââââââââââââââââââââââââââââââââââ
input group "âââ Trade Safety âââ"
input bool   InpAutoTradeOn     = true;    // AUTO trade ON at startup
input bool   InpUseProfitLock   = true;    // Once trade is +$X, push SL so it can't lose
input double InpLockProfitUSD   = 5.0;     // No-loss lock trigger ($) â gold sized

// ââ News Filter (currency-aware) âââââââââââââââââââââââââââââââââââ
input bool   InpUseNewsFilter = true;  // Block entries around high-impact news (XAU/USD)
input int    InpNewsBeforeMin = 15;    // Block minutes BEFORE the event
input int    InpNewsAfterMin  = 15;    // Block minutes AFTER the event
input bool   InpNewsHighOnly  = true;  // High-impact only (false = high + medium)

input group "âââ ORB Settings âââ"
input int      InpORBHour        = 7;        // ORB candle start hour (server UTC)
input int      InpORBConfirm     = 3;        // Consolidation candles before ORB valid
input double   InpORBBuffer      = 5.0;      // Buffer above/below ORB level (points)

input group "âââ Fractal Settings âââ"
input int      InpFractalBars    = 2;        // Bars each side for fractal detection
input int      InpFractalLB      = 15;       // Bars to look back for valid fractal

input group "âââ Trend Filter âââ"
input int      InpEMAPeriod      = 50;       // EMA period for trend direction
input bool     InpUseEMAFilter   = true;     // Require price above/below EMA

input group "âââ Markov Regime âââ"
input bool     InpUseMarkov      = true;     // Enable Markov gate
input double   InpMarkovThr      = 1.5;      // Regime threshold % per bar
input double   InpMarkovPersist  = 0.75;     // Block if persistence > this
input int      InpMarkovLB       = 10;       // Lookback bars for regime
input int      InpMarkovHold     = 2;        // Min bars regime must hold

input group "âââ Trade Manager âââ"
input double   InpRRRatio        = 2.5;      // Initial TP (R:R ratio)
input double   InpSLATRMult      = 2.0;      // SL = ATR Ã this
input double   InpMinSLATR       = 1.0;      // Minimum SL (ATRÃ)
input bool     InpUseBreakEven   = true;     // Enable break-even
input double   InpBEATRMult      = 1.0;      // Move BE at XÃATR profit
input bool     InpUsePartialTP   = true;     // Close 50% at initial TP
input bool     InpUseTrail       = true;     // Enable trailing stop
input double   InpTrailATRMult   = 2.0;      // Trail ATR multiplier (base)

input group "âââ Breakout Runner âââ"
input bool     InpExtendTP       = true;     // Strip TP after partial â let remainder run
input bool     InpProgressTrail  = true;     // Tighten trail as move extends
input double   InpTrailR2Mult    = 1.5;      // Trail ATR mult after 2R profit
input double   InpTrailR3Mult    = 1.0;      // Trail ATR mult after 3R profit (locks hard)

input group "âââ Sessions âââ"
input bool     InpUseSession     = true;     // Session filter
input int      InpSessOpen       = 7;        // Session start hour (UTC)
input int      InpSessClose      = 20;       // Session end hour (UTC)

input group "âââ Display âââ"
input bool     InpShowDash       = true;     // Show dashboard
input bool     InpShowORB        = true;     // Draw ORB lines on chart
input int      InpDashX          = 20;       // Dashboard X
input int      InpDashY          = 30;       // Dashboard Y

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// GLOBALS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

CTrade        trade;
CPositionInfo pos;

int  hATR  = INVALID_HANDLE;
int  hEMA  = INVALID_HANDLE;

// ATR/EMA state
double g_atr = 0.0;
double g_ema = 0.0;

// Risk / daily
double g_startEquity = 0.0;
double g_dailyPnL    = 0.0;
datetime g_lastDay   = 0;
datetime g_lastBar   = 0;

// ORB state
bool     g_orbValid       = false;   // first candle of day captured
bool     g_orbConfirmed   = false;   // consolidation candles satisfied
double   g_orbHigh        = 0.0;
double   g_orbLow         = 0.0;
int      g_orbConsoCount  = 0;
datetime g_orbDay         = 0;       // which calendar day ORB belongs to

// Fractal state
double g_lastBearFracH    = 0.0;     // most recent bearish fractal high (resistance)
double g_lastBullFracL    = 0.0;     // most recent bullish fractal low  (support)

// Markov state (0=Side 1=Bull 2=Bear â same as STAALWAG)
double g_mkCnt[3][3];
int    g_mkRegime      = 0;
double g_mkPersistence = 0.33;
double g_mkConviction  = 0.0;
int    g_mkHeldCount   = 0;
int    g_mkConfirmed   = 0;

// Signal / trade state
int    g_signal        = 0;    // 1=long -1=short 0=none
double g_entryPrice    = 0.0;
double g_slPrice       = 0.0;
double g_tpPrice       = 0.0;
bool   g_partialDone   = false;
bool   g_beDone        = false;

// Win/loss tracker
int    g_allWins   = 0;
int    g_allLosses = 0;

// Auto-trade toggle (off by default â must enable via dashboard or input)
bool   g_autoTrade = false;

// ââ Prop risk profile (set in OnInit) ââ
double g_initBal       = 6000.0;
double g_profitTgtPct  = 8.0;
double g_maxLossPct    = 10.0;
double g_maxGuardPct   = 8.0;
double g_dailyLossPct  = 5.0;
double g_dailyGuardPct = 3.5;
bool   g_trailMaxDD    = false;
bool   g_propOn        = true;
string g_firmName      = "CUSTOM";
double g_peakEquity    = 0.0;
bool   g_dailyHalt     = false;
bool   g_targetHit     = false;
bool   g_eaStopped     = false;

const string PFX = "GBK_";
const long   MAGIC = 202610;   // unique â was 202602 (clashed with STAALWAG_FX)

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
// PROP FIRM RECOGNITION
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
PropFirm DetectFirm()
{
   string co = AccountInfoString(ACCOUNT_COMPANY); StringToUpper(co);
   string sv = AccountInfoString(ACCOUNT_SERVER);  StringToUpper(sv);
   string s  = co + " " + sv;
   if(StringFind(s,"FUNDEDNEXT")>=0  || StringFind(s,"FUNDED NEXT")>=0) return PF_FUNDEDNEXT;
   if(StringFind(s,"FTMO")>=0)                                           return PF_FTMO;
   if(StringFind(s,"GOAT")>=0)                                           return PF_GOATFUNDED;
   if(StringFind(s,"FUNDINGPIPS")>=0 || StringFind(s,"FUNDING PIPS")>=0) return PF_FUNDINGPIPS;
   if(StringFind(s,"5ERS")>=0 || StringFind(s,"THE5")>=0 ||
      StringFind(s,"FIVEPERCENT")>=0)                                    return PF_THE5ERS;
   if(StringFind(s,"E8")>=0)                                             return PF_E8;
   if(StringFind(s,"BLACKBULL")>=0   || StringFind(s,"BLACK BULL")>=0)   return PF_BLACKBULL;
   return PF_FUNDEDNEXT;
}

void SetupRiskProfile()
{
   g_initBal = (InpInitialBalance>0) ? InpInitialBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_propOn  = true;

   PropFirm pf = InpPropFirm;
   bool detected = (pf==PF_AUTO);
   if(pf==PF_AUTO) pf = DetectFirm();

   double p1=8, p2=5;
   if(pf==PF_OFF)
   {
      g_propOn=false; g_firmName="OFF ($limit)";
      g_profitTgtPct=0; g_maxLossPct=100; g_dailyLossPct=100;
      g_maxGuardPct=100; g_dailyGuardPct=100; g_trailMaxDD=false;
      Print("RISK PROFILE: prop engine OFF â using $", DoubleToString(InpDailyLossLimit,0), " daily limit");
      return;
   }
   if(pf==PF_CUSTOM)
   {
      g_firmName="CUSTOM"; p1=InpProfitTargetPct; p2=InpProfitTargetPct;
      g_maxLossPct=InpMaxLossPctIn; g_dailyLossPct=InpDailyLossPctIn; g_trailMaxDD=InpTrailingMaxDD;
      g_maxGuardPct=g_maxLossPct*0.8; g_dailyGuardPct=g_dailyLossPct*0.7;
   }
   else
   {
      g_trailMaxDD=false;
      switch(pf)
      {
         case PF_FTMO:        g_firmName="FTMO";        p1=10; p2=5; g_maxLossPct=10; g_dailyLossPct=5; break;
         case PF_GOATFUNDED:  g_firmName="GoatFunded";  p1=8;  p2=6; g_maxLossPct=10; g_dailyLossPct=4; break;
         case PF_FUNDINGPIPS: g_firmName="FundingPips"; p1=8;  p2=5; g_maxLossPct=10; g_dailyLossPct=5; break;
         case PF_THE5ERS:     g_firmName="The5ers";     p1=10; p2=5; g_maxLossPct=10; g_dailyLossPct=5; break;
         case PF_E8:          g_firmName="E8";          p1=8;  p2=4; g_maxLossPct=8;  g_dailyLossPct=4; g_trailMaxDD=true; break;
         case PF_BLACKBULL:   g_firmName="BlackBull(brk)";p1=0;p2=0; g_maxLossPct=10; g_dailyLossPct=5; break;
         default:             g_firmName="FundedNext";  p1=8;  p2=5; g_maxLossPct=10; g_dailyLossPct=5; break;
      }
      g_maxGuardPct=g_maxLossPct*0.8; g_dailyGuardPct=g_dailyLossPct*0.7;
   }
   g_profitTgtPct = (InpPhase>=2) ? p2 : p1;
   if(detected) g_firmName += " (auto)";
   PrintFormat("RISK PROFILE: %s | phase %d | initBal $%.2f | daily %.1f%% (guard %.1f%%) | "
               "max %.1f%% (guard %.1f%%) | target %.1f%% | trailDD=%s",
      g_firmName,InpPhase,g_initBal,g_dailyLossPct,g_dailyGuardPct,
      g_maxLossPct,g_maxGuardPct,g_profitTgtPct,(g_trailMaxDD?"yes":"no"));
}

bool     g_newsBlocked = false;
datetime g_newsCacheT  = 0;
bool NewsBlocked()
{
   if(!InpUseNewsFilter) return false;
   datetime now = TimeCurrent();
   if(now - g_newsCacheT >= 30)
   {
      g_newsCacheT = now; g_newsBlocked = false;
      string ccy[2] = {SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE),
                       SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT)};
      datetime from = now - InpNewsAfterMin*60, to = now + InpNewsBeforeMin*60;
      for(int c=0; c<2 && !g_newsBlocked; c++)
      {
         MqlCalendarValue vals[];
         int cnt = CalendarValueHistory(vals, from, to, NULL, ccy[c]);
         for(int v=0; v<cnt; v++)
         {
            MqlCalendarEvent ev;
            if(!CalendarEventById(vals[v].event_id, ev)) continue;
            if(InpNewsHighOnly && ev.importance < CALENDAR_IMPORTANCE_HIGH) continue;
            if(!InpNewsHighOnly && ev.importance < CALENDAR_IMPORTANCE_MODERATE) continue;
            g_newsBlocked = true; break;
         }
      }
   }
   return g_newsBlocked;
}

void CloseAllGBK()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t)
         && PositionGetInteger(POSITION_MAGIC) == MAGIC
         && PositionGetString(POSITION_SYMBOL) == _Symbol)
         trade.PositionClose(t);
   }
}

bool IsDailyDDBreached()
{
   if(!g_propOn) return g_dailyPnL <= -MathAbs(InpDailyLossLimit);
   double limit = g_initBal * g_dailyGuardPct / 100.0;
   return (g_startEquity - AccountInfoDouble(ACCOUNT_EQUITY)) >= limit;
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// INIT / DEINIT
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

int OnInit()
{
   // ââ Chart isolation guards ââââââââââââââââââââââââââââââââââââââââ
   // Refuse to run on wrong symbol â prevents cross-chart interference
   // with any other EA running on a different pair/symbol
   if(_Symbol != "XAUUSD" && _Symbol != "XAUUSD." && _Symbol != "GOLD" &&
      StringFind(_Symbol, "XAU") < 0)
   {
      Alert("GOUDBREUK: Wrong symbol '", _Symbol, "'. Attach to XAUUSD chart only.");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Refuse to run on wrong timeframe â H1 only
   if(Period() != PERIOD_H1)
   {
      Alert("GOUDBREUK: Wrong timeframe. Attach to H1 chart only.");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Unique magic number 202602 isolates every trade/position/deal
   // from any other EA running on the same or different charts
   trade.SetExpertMagicNumber(MAGIC);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   hATR = iATR(_Symbol, PERIOD_H1, 14);
   hEMA = iMA(_Symbol, PERIOD_H1, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(hATR == INVALID_HANDLE || hEMA == INVALID_HANDLE)
   {
      Alert("GOUDBREUK: Indicator init failed");
      return INIT_FAILED;
   }

   ArrayInitialize(g_mkCnt, 0.0);
   g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   SetupRiskProfile();           // recognise prop firm -> apply risk rules
   g_autoTrade = InpAutoTradeOn; // AUTO defaults ON

   if(InpShowDash) DrawDashboard();
   DrawWatermark();

   EventSetTimer(1);
   Print("GOUDBREUK v1.0 armed â XAUUSD H1 Fractal-ORB + Markov");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// TICK â bar-by-bar execution
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

void OnTick()
{
   // ââ Prop risk kill-switch (runs every tick) ââ
   if(g_eaStopped) return;
   CheckDailyReset();
   double eqT = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eqT > g_peakEquity) g_peakEquity = eqT;
   if(g_propOn)
   {
      double floorEq = g_trailMaxDD ? g_peakEquity*(1.0-g_maxGuardPct/100.0)
                                    : g_initBal   *(1.0-g_maxGuardPct/100.0);
      if(eqT <= floorEq)
      { CloseAllGBK(); g_eaStopped=true; Alert(g_firmName,": max-loss guard hit â EA stopped."); return; }
      if(!g_dailyHalt && IsDailyDDBreached())
      { CloseAllGBK(); g_dailyHalt=true; Alert(g_firmName,": daily-loss guard hit â flat for the day."); }
      if(g_profitTgtPct > 0 && InpStopAtTarget && eqT >= g_initBal*(1.0+g_profitTgtPct/100.0)) g_targetHit=true;
      if(!g_dailyHalt && (eqT - g_startEquity) >= g_initBal*InpDailyProfitCap/100.0) g_dailyHalt=true;
   }
   else if(IsDailyDDBreached())
   { CloseAllGBK(); g_dailyHalt=true; }

   datetime currentBar = iTime(_Symbol, PERIOD_H1, 0);
   if(currentBar == g_lastBar)
   {
      ManageTrades();
      return;
   }
   g_lastBar = currentBar;

   // Refresh ATR + EMA
   double atrBuf[], emaBuf[];
   ArraySetAsSeries(atrBuf, true);
   ArraySetAsSeries(emaBuf, true);
   if(CopyBuffer(hATR, 0, 1, 1, atrBuf) < 1) return;
   if(CopyBuffer(hEMA, 0, 1, 1, emaBuf) < 1) return;
   g_atr = atrBuf[0];
   g_ema = emaBuf[0];

   // Daily reset
   CheckDailyReset();

   // Markov
   UpdateMarkov();

   // ORB
   UpdateORB();

   // Fractals
   ScanFractals();

   // Signal engine
   g_signal = 0;
   if(g_orbConfirmed && !HasPosition()) EvaluateBreakout();

   // Auto-trade (blocked when halted / target hit / news window)
   if(g_signal != 0 && g_autoTrade && !HasPosition()
      && !g_dailyHalt && !g_targetHit && !NewsBlocked()) ExecuteTrade();

   // Dashboard
   if(InpShowDash) RefreshDashboard();
   if(InpShowORB)  DrawORBLines();
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// ORB â Open Range Breakout tracking
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

void UpdateORB()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

   if(today != g_orbDay)
   {
      // New calendar day â reset
      g_orbDay        = today;
      g_orbValid      = false;
      g_orbConfirmed  = false;
      g_orbConsoCount = 0;
      g_orbHigh       = 0.0;
      g_orbLow        = 0.0;
   }

   if(!g_orbValid)
   {
      // Look for the ORB candle: first completed H1 bar at/after InpORBHour today
      for(int i = 1; i <= 48; i++)
      {
         datetime barTime = iTime(_Symbol, PERIOD_H1, i);
         MqlDateTime bd;
         TimeToStruct(barTime, bd);
         datetime barDay = StringToTime(StringFormat("%04d.%02d.%02d", bd.year, bd.mon, bd.day));
         if(barDay != today) break;   // past today

         if(bd.hour == InpORBHour)
         {
            g_orbHigh  = iHigh(_Symbol, PERIOD_H1, i);
            g_orbLow   = iLow(_Symbol, PERIOD_H1,  i);
            g_orbValid = true;
            break;
         }
      }
      return;
   }

   if(!g_orbConfirmed)
   {
      // Count how many completed bars stay fully inside the ORB range
      double h1 = iHigh(_Symbol, PERIOD_H1, 1);
      double l1 = iLow(_Symbol,  PERIOD_H1, 1);
      if(h1 <= g_orbHigh && l1 >= g_orbLow)
         g_orbConsoCount++;

      if(g_orbConsoCount >= InpORBConfirm)
      {
         g_orbConfirmed = true;
         Print("GOUDBREUK: ORB confirmed H:", g_orbHigh, " L:", g_orbLow,
               " after ", g_orbConsoCount, " consolidation bars");
      }
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// FRACTALS â Williams-style (N bars each side)
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

void ScanFractals()
{
   int n = InpFractalBars;
   int lb = InpFractalLB;

   for(int i = n + 1; i <= lb; i++)
   {
      // Bearish fractal = high[i] surrounded by lower highs â resistance level
      bool bearFrac = true;
      double midH = iHigh(_Symbol, PERIOD_H1, i);
      for(int j = 1; j <= n; j++)
      {
         if(iHigh(_Symbol, PERIOD_H1, i - j) >= midH ||
            iHigh(_Symbol, PERIOD_H1, i + j) >= midH)
         { bearFrac = false; break; }
      }
      if(bearFrac) { g_lastBearFracH = midH; break; }
   }

   for(int i = n + 1; i <= lb; i++)
   {
      // Bullish fractal = low[i] surrounded by higher lows â support level
      bool bullFrac = true;
      double midL = iLow(_Symbol, PERIOD_H1, i);
      for(int j = 1; j <= n; j++)
      {
         if(iLow(_Symbol, PERIOD_H1, i - j) <= midL ||
            iLow(_Symbol, PERIOD_H1, i + j) <= midL)
         { bullFrac = false; break; }
      }
      if(bullFrac) { g_lastBullFracL = midL; break; }
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// MARKOV â 3x3 transition matrix (0=Side 1=Bull 2=Bear)
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

void UpdateMarkov()
{
   int bars = iBars(_Symbol, PERIOD_H1);
   if(bars < InpMarkovLB + 5) return;

   double closeNow  = iClose(_Symbol, PERIOD_H1, 1);
   double closePrev = iClose(_Symbol, PERIOD_H1, 1 + InpMarkovLB);
   double thr = InpMarkovThr / 100.0;
   double ret = (closePrev > 0) ? (closeNow - closePrev) / closePrev : 0;

   int newRegime = (ret > thr) ? 1 : (ret < -thr) ? 2 : 0;
   g_mkCnt[g_mkRegime][newRegime] += 1.0;
   g_mkRegime = newRegime;

   // Debounce
   if(newRegime == g_mkConfirmed)
      g_mkHeldCount++;
   else
   {
      g_mkHeldCount = 1;
      if(g_mkHeldCount >= InpMarkovHold)
         g_mkConfirmed = newRegime;
   }
   if(g_mkHeldCount >= InpMarkovHold)
      g_mkConfirmed = newRegime;

   // Transition matrix stats
   double P[3][3];
   for(int r = 0; r < 3; r++)
      for(int c = 0; c < 3; c++)
      {
         double rowSum = g_mkCnt[r][0] + g_mkCnt[r][1] + g_mkCnt[r][2];
         P[r][c] = (rowSum > 0) ? g_mkCnt[r][c] / rowSum : 1.0/3.0;
      }
   g_mkPersistence = P[g_mkConfirmed][g_mkConfirmed];
   g_mkConviction  = P[g_mkConfirmed][1] - P[g_mkConfirmed][2];
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// SIGNAL ENGINE â Fractal-ORB breakout evaluation
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

void EvaluateBreakout()
{
   if(!IsInSession()) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if((ask - bid) > InpMaxSpreadUSD) return;   // skip wide-spread fills (news/rollover)
   double buf = InpORBBuffer * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   bool aboveORB = ask > g_orbHigh + buf;
   bool belowORB = bid < g_orbLow  - buf;

   if(!aboveORB && !belowORB) return;

   // EMA trend filter
   bool emaUp   = !InpUseEMAFilter || (ask > g_ema);
   bool emaDown = !InpUseEMAFilter || (bid < g_ema);

   // Fractal confirmation â price must break a fractal in the same direction
   bool fracBuy  = aboveORB && g_lastBearFracH > 0 && ask > g_lastBearFracH;
   bool fracSell = belowORB && g_lastBullFracL > 0 && bid < g_lastBullFracL;

   bool wantLong  = fracBuy  && emaUp;
   bool wantShort = fracSell && emaDown;

   // Markov gate â block counter-regime trades
   if(InpUseMarkov)
   {
      bool blockLong  = (g_mkConfirmed == 2 && g_mkPersistence > InpMarkovPersist);
      bool blockShort = (g_mkConfirmed == 1 && g_mkPersistence > InpMarkovPersist);
      if(wantLong  && blockLong)  wantLong  = false;
      if(wantShort && blockShort) wantShort = false;
   }

   if(!wantLong && !wantShort) return;

   // Compute entry / SL / TP
   double minSL = g_atr * InpMinSLATR;
   if(wantLong)
   {
      double slRaw  = g_orbLow - g_atr * InpSLATRMult;
      g_entryPrice  = ask;
      g_slPrice     = MathMin(slRaw, ask - minSL);
      g_tpPrice     = ask + (ask - g_slPrice) * InpRRRatio;
      g_signal      = 1;
   }
   else
   {
      double slRaw  = g_orbHigh + g_atr * InpSLATRMult;
      g_entryPrice  = bid;
      g_slPrice     = MathMax(slRaw, bid + minSL);
      g_tpPrice     = bid - (g_slPrice - bid) * InpRRRatio;
      g_signal      = -1;
   }

   g_partialDone = false;
   g_beDone      = false;

   string mk = g_mkConfirmed == 1 ? "BULL" : g_mkConfirmed == 2 ? "BEAR" : "SIDE";
   string dir = g_signal == 1 ? "BUY" : "SELL";
   Print(StringFormat("GOUDBREUK SIGNAL %s | Entry:%.2f SL:%.2f TP:%.2f | ORB H:%.2f L:%.2f | Frac:%.2f | Regime:%s %.0f%%",
         dir, g_entryPrice, g_slPrice, g_tpPrice,
         g_orbHigh, g_orbLow,
         g_signal == 1 ? g_lastBearFracH : g_lastBullFracL,
         mk, g_mkPersistence * 100));
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// EXECUTE TRADE
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

void ExecuteTrade()
{
   if(g_signal == 0) return;
   if(HasPosition()) return;

   // Daily loss guard â prop engine handles this when on; $ limit only for PF_OFF
   if(g_dailyHalt || g_targetHit) return;
   if(!g_propOn && g_dailyPnL <= -InpDailyLossLimit)
   {
      Print("GOUDBREUK: Daily loss limit hit â blocked");
      return;
   }

   double lots = InpAutoLot ? CalcLots(g_entryPrice, g_slPrice) : InpFixedLot;
   if(lots <= 0) return;

   bool ok = false;
   if(g_signal == 1)
      ok = trade.Buy(lots, _Symbol, g_entryPrice, g_slPrice, g_tpPrice, "GOUDBREUK");
   else
      ok = trade.Sell(lots, _Symbol, g_entryPrice, g_slPrice, g_tpPrice, "GOUDBREUK");

   if(ok)
   {
      Print("GOUDBREUK TRADE OPEN â ", g_signal == 1 ? "BUY" : "SELL",
            " lots:", lots, " SL:", g_slPrice, " TP:", g_tpPrice);
      g_signal = 0;
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// TRADE MANAGEMENT â BE, partial close, trail
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

void ManageTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MAGIC) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double open     = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL    = PositionGetDouble(POSITION_SL);
      double curTP    = PositionGetDouble(POSITION_TP);
      double curP     = PositionGetDouble(POSITION_PRICE_CURRENT);
      double lots     = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE pType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double riskDist = MathAbs(open - curSL);
      if(riskDist <= 0) riskDist = g_atr * InpSLATRMult;

      // No-loss lock: once floating profit >= $X, push SL past entry (covers
      // spread) so the trade can no longer close red. Extra floor for breaks
      // that pop but never reach the 1R break-even point.
      if(InpUseProfitLock)
      {
         double netP = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(netP >= InpLockProfitUSD)
         {
            int    dg  = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
            double bidL= SymbolInfoDouble(_Symbol,SYMBOL_BID);
            double askL= SymbolInfoDouble(_Symbol,SYMBOL_ASK);
            double bufL= askL - bidL;
            if(pType == POSITION_TYPE_BUY)
            {
               double lockSL = NormalizeDouble(open+bufL, dg);
               if(lockSL>curSL && lockSL<bidL) trade.PositionModify(ticket,lockSL,curTP);
            }
            else
            {
               double lockSL = NormalizeDouble(open-bufL, dg);
               if((curSL==0 || lockSL<curSL) && lockSL>askL) trade.PositionModify(ticket,lockSL,curTP);
            }
         }
      }

      // Progressive trail multiplier â tightens as move extends to lock bigger profits
      double pnlR = (pType == POSITION_TYPE_BUY)
                    ? (curP - open) / riskDist
                    : (open - curP) / riskDist;

      double trailMult = InpTrailATRMult;
      if(InpProgressTrail)
      {
         if(pnlR >= 3.0) trailMult = InpTrailR3Mult;
         else if(pnlR >= 2.0) trailMult = InpTrailR2Mult;
      }

      if(pType == POSITION_TYPE_BUY)
      {
         // Partial close at initial TP (1R default)
         if(InpUsePartialTP && !g_partialDone && pnlR >= 1.0)
         {
            double closeLots = NormalizeDouble(lots * 0.5,
                               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(closeLots >= minLot)
               trade.PositionClosePartial(ticket, closeLots);
            g_partialDone = true;

            // Strip fixed TP â remainder runs free, trail is the only exit
            if(InpExtendTP)
               trade.PositionModify(ticket, curSL, 0);

            Print("GOUDBREUK: Partial closed 50% at ", DoubleToString(pnlR, 2),
                  "R. Remainder running free â trail active.");
         }

         // Break-even
         if(InpUseBreakEven && !g_beDone && pnlR >= InpBEATRMult && curSL < open)
         {
            trade.PositionModify(ticket, open, (InpExtendTP && g_partialDone) ? 0 : curTP);
            g_beDone = true;
         }

         // Progressive trailing stop
         if(InpUseTrail && pnlR >= 1.0)
         {
            double newSL = curP - g_atr * trailMult;
            double newTP = (InpExtendTP && g_partialDone) ? 0 : curTP;
            if(newSL > curSL && newSL > open)
            {
               trade.PositionModify(ticket, newSL, newTP);
               if(InpProgressTrail && pnlR >= 2.0)
                  Print("GOUDBREUK: Trail tightened to ", DoubleToString(trailMult, 1),
                        "ÃATR at ", DoubleToString(pnlR, 1), "R");
            }
         }
      }
      else // SELL
      {
         if(InpUsePartialTP && !g_partialDone && pnlR >= 1.0)
         {
            double closeLots = NormalizeDouble(lots * 0.5,
                               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(closeLots >= minLot)
               trade.PositionClosePartial(ticket, closeLots);
            g_partialDone = true;

            if(InpExtendTP)
               trade.PositionModify(ticket, curSL, 0);

            Print("GOUDBREUK: Partial closed 50% at ", DoubleToString(pnlR, 2),
                  "R. Remainder running free â trail active.");
         }

         if(InpUseBreakEven && !g_beDone && pnlR >= InpBEATRMult && curSL > open)
         {
            trade.PositionModify(ticket, open, (InpExtendTP && g_partialDone) ? 0 : curTP);
            g_beDone = true;
         }

         if(InpUseTrail && pnlR >= 1.0)
         {
            double newSL = curP + g_atr * trailMult;
            double newTP = (InpExtendTP && g_partialDone) ? 0 : curTP;
            if(newSL < curSL && newSL < open)
            {
               trade.PositionModify(ticket, newSL, newTP);
               if(InpProgressTrail && pnlR >= 2.0)
                  Print("GOUDBREUK: Trail tightened to ", DoubleToString(trailMult, 1),
                        "ÃATR at ", DoubleToString(pnlR, 1), "R");
            }
         }
      }
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// HELPERS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

double CalcLots(double entry, double sl)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt  = balance * InpRiskPercent / 100.0;
   double slDist   = MathAbs(entry - sl);
   if(slDist <= 0) return 0;

   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotVal   = (slDist / tickSize) * tickVal;
   if(lotVal <= 0) return 0;

   double lots     = riskAmt / lotVal;
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathMax(minLot, MathMin(maxLot, MathRound(lots / stepLot) * stepLot));
   return lots;
}

bool IsInSession()
{
   if(!InpUseSession) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   return (dt.hour >= InpSessOpen && dt.hour < InpSessClose);
}

bool HasPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t)
         && PositionGetInteger(POSITION_MAGIC) == MAGIC
         && PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
   }
   return false;
}

void CheckDailyReset()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != g_lastDay)
   {
      g_lastDay    = today;
      g_dailyPnL   = 0.0;
      g_startEquity= AccountInfoDouble(ACCOUNT_EQUITY);
      g_dailyHalt  = false;   // re-arm for the new day
   }
   g_dailyPnL = AccountInfoDouble(ACCOUNT_EQUITY) - g_startEquity;
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// TRADE EVENTS â win/loss tracking
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&    req,
                        const MqlTradeResult&     res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(HistoryDealSelect(trans.deal))
   {
      long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
      if(magic != MAGIC) return;
      string sym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
      if(sym != _Symbol) return;   // own chart only
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      if(profit > 0) g_allWins++;
      else if(profit < 0) g_allLosses++;
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// DASHBOARD
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

void SetLabel(string name, string text, int x, int y,
              color clr = clrSilver, int fontSize = 8, string font = "Consolas")
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fontSize);
   ObjectSetString (0, name, OBJPROP_FONT,       font);
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
}

void DrawDashboard()
{
   int x = InpDashX, y = InpDashY;
   SetLabel(PFX+"HDR", "â GOUDBREUK v1.0 â", x, y, clrGold, 10);
   color dotClr=(g_dailyHalt||g_eaStopped)?C'220,60,60':(g_autoTrade&&!g_targetHit)?C'60,210,90':C'150,150,150';
   SetLabel(PFX+"DOT", "\x25CF", x+155, y, dotClr, 11, "Arial");
   y += 18;
   SetLabel(PFX+"SEP", "ââââââââââââââââââââââââââââââââ", x, y, clrDimGray, 7);
}

void RefreshDashboard()
{
   int x = InpDashX, y = InpDashY + 30;

   // Status dot in header â green=trading, red=daily limit/stop, grey=idle
   color dotC=(g_dailyHalt||g_eaStopped)?C'220,60,60':(g_autoTrade&&!g_targetHit)?C'60,210,90':C'150,150,150';
   SetLabel(PFX+"DOT", "\x25CF", InpDashX+178, InpDashY, dotC, 11, "Arial");

   // Regime line
   string mk    = g_mkConfirmed == 1 ? "BULL" : g_mkConfirmed == 2 ? "BEAR" : "SIDE";
   color  mkClr = g_mkConfirmed == 1 ? clrLimeGreen : g_mkConfirmed == 2 ? clrCrimson : clrSilver;
   SetLabel(PFX+"MK", StringFormat("REGIME  %-4s  PERSIST %.0f%%  CONV %+.2f",
            mk, g_mkPersistence*100, g_mkConviction), x, y, mkClr, 8);
   y += 15;

   // ORB line
   color orbClr = g_orbConfirmed ? clrAqua : (g_orbValid ? clrYellow : clrDimGray);
   string orbSt = g_orbConfirmed ? "CONFIRMED" : (g_orbValid ? StringFormat("CONSOLIDATING %d/%d", g_orbConsoCount, InpORBConfirm) : "WAITING");
   SetLabel(PFX+"ORB", StringFormat("ORB  %-20s  H:%.2f  L:%.2f", orbSt, g_orbHigh, g_orbLow),
            x, y, orbClr, 8);
   y += 15;

   // Fractal line
   SetLabel(PFX+"FRC", StringFormat("FRAC  ResH:%.2f  SupL:%.2f", g_lastBearFracH, g_lastBullFracL),
            x, y, clrMediumOrchid, 8);
   y += 15;

   // Signal line
   string sigTxt = g_signal == 1 ? "â² BUY SIGNAL" : g_signal == -1 ? "â¼ SELL SIGNAL" : "ââ NO SIGNAL";
   color  sigClr = g_signal == 1 ? clrLimeGreen : g_signal == -1 ? clrCrimson : clrDimGray;
   SetLabel(PFX+"SIG", sigTxt, x, y, sigClr, 9);
   y += 15;

   // Auto-trade toggle
   string atTxt = g_autoTrade ? "AUTO-TRADE  ON  [click to disable]" : "AUTO-TRADE  OFF [click to enable]";
   color  atClr = g_autoTrade ? clrLimeGreen : clrOrangeRed;
   SetLabel(PFX+"AT", atTxt, x, y, atClr, 8);
   y += 15;

   // Prop firm + risk status
   double eqN = AccountInfoDouble(ACCOUNT_EQUITY);
   string st  = g_eaStopped ? "STOPPED maxloss" : g_targetHit ? "TARGET HIT" :
                g_dailyHalt ? "HALTED day-cap"  : "LIVE";
   string fLine;
   color  fClr;
   if(g_propOn)
   {
      double dLoss = (g_startEquity-eqN)>0 ? (g_startEquity-eqN)/g_initBal*100.0 : 0;
      double tRef  = g_trailMaxDD ? g_peakEquity : g_initBal;
      double tLoss = (eqN<tRef) ? (tRef-eqN)/tRef*100.0 : 0;
      fLine = StringFormat("%s  %s  D%.1f/%.0f T%.1f/%.0f",
              g_firmName, st, dLoss,g_dailyLossPct, tLoss,g_maxLossPct);
      fClr  = (dLoss>=g_dailyGuardPct||tLoss>=g_maxGuardPct) ? clrCrimson : clrGold;
   }
   else
   {
      fLine = StringFormat("%s  %s  $lim %.0f", g_firmName, st, InpDailyLossLimit);
      fClr  = clrGold;
   }
   SetLabel(PFX+"FIRM", fLine, x, y, fClr, 8);
   y += 15;

   // Daily PnL
   color pnlClr = g_dailyPnL >= 0 ? clrLimeGreen : clrCrimson;
   SetLabel(PFX+"PNL", StringFormat("DAY PnL  $%.2f   W:%d  L:%d",
            g_dailyPnL, g_allWins, g_allLosses), x, y, pnlClr, 8);
   y += 15;

   // ATR
   SetLabel(PFX+"ATR", StringFormat("ATR(14)  %.2f   EMA(%d)  %.2f",
            g_atr, InpEMAPeriod, g_ema), x, y, clrDarkGray, 8);

   ChartRedraw();
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// ORB CHART LINES
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

void DrawORBLines()
{
   if(!g_orbValid) return;

   string nameH = PFX + "ORB_H";
   string nameL = PFX + "ORB_L";

   color lineClr = g_orbConfirmed ? clrAqua : clrYellow;

   for(int i = 0; i < 2; i++)
   {
      string nm    = (i == 0) ? nameH : nameL;
      double price = (i == 0) ? g_orbHigh : g_orbLow;

      if(ObjectFind(0, nm) < 0)
         ObjectCreate(0, nm, OBJ_HLINE, 0, 0, price);
      ObjectSetDouble (0, nm, OBJPROP_PRICE, price);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, lineClr);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
   }
   ChartRedraw();
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// CHART EVENTS â auto-trade toggle via label click
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == PFX+"AT")
   {
      g_autoTrade = !g_autoTrade;
      Print("GOUDBREUK: AutoTrade ", g_autoTrade ? "ENABLED" : "DISABLED");
      RefreshDashboard();
   }
}

void OnTimer()
{
   CheckDailyReset();
   if(InpShowDash) RefreshDashboard();
}
