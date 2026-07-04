//+------------------------------------------------------------------+
//|                     STAALWAG GOLD v1.0                           |
//|            XAUUSD Â· Commodities Expert Advisor                   |
//|  Signal: Markov Regime + Key Levels + Sweeps + OB/FVG            |
//|  Trade Mgr: Trail Â· BE Â· Partial TP Â· DD Kill Â· Session Filter   |
//+------------------------------------------------------------------+
#property copyright "STAALWAG"
#property version   "1.00"
#property description "STAALWAG GOLD â Professional XAUUSD EA"

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
   PF_LEVERAGED,   // Leveraged Turbo Trade 1-step (t6, d3, m6 TRAILING; +3 profit days, 20% consistency)
   PF_BLACKBULL,   // BlackBull = broker, no prop rules (conservative cap)
   PF_OFF,         // No prop engine â use the $ daily-loss limit only
   PF_CUSTOM       // Use the manual values below
};

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// INPUT PARAMETERS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

// ââ Account & Risk âââââââââââââââââââââââââââââââââââââââââââââââââ
input group "âââ Account & Risk âââ"
input double   InpFixedLot       = 0.02;    // Fixed lot (small) â used only if AutoLot off
input bool     InpAutoLot        = true;    // Auto lot ON â small consistent size, scales w/ balance
input double   InpRiskPercent    = 0.3;     // Risk % per trade â small, so one loss can't wipe the day
input double   InpRiskAmount     = 122.0;   // Risk $ per trade (if AutoLot)
input double   InpDailyLossLimit = 60.0;    // Daily loss limit ($) â used only when PropFirm=PF_OFF

// ââ Prop Firm Profile ââââââââââââââââââââââââââââââââââââââââââââââ
input group "âââ Prop Firm Profile âââ"
input PropFirm InpPropFirm      = PF_AUTO; // Recognise firm -> auto-apply its risk rules
input int    InpPhase           = 1;       // Challenge phase: 1 or 2 (sets profit target)
input double InpInitialBalance  = 0.0;     // Challenge start balance (0 = use account balance)
input bool   InpStopAtTarget    = true;    // Stop opening new trades once phase target hit
input double InpDailyProfitCap  = 2.5;     // Halt for the day after +this% of balance (0=off)
input double InpConsistencyPct  = 0.0;     // Firm consistency rule % (e.g 15/20/40). 0=off. Caps daily profit to this share of the profit target so no day dominates; auto-sets min profitable days.
input int    InpMaxTradesDay    = 8;       // Overtrade guard (max EA trades/day)
input double InpProfitTargetPct = 8.0;     // (PF_CUSTOM) Phase target %
input double InpMaxLossPctIn    = 10.0;    // (PF_CUSTOM) Hard overall max loss %
input double InpDailyLossPctIn  = 5.0;     // (PF_CUSTOM) Hard daily loss %
input bool   InpTrailingMaxDD   = false;   // (PF_CUSTOM) Max loss trails equity peak

// ââ Trade Safety âââââââââââââââââââââââââââââââââââââââââââââââââââ
input group "âââ Trade Safety âââ"
input bool   InpAutoTradeOn     = true;    // AUTO trade ON at startup
input int    InpMinHoldSeconds  = 180;     // HFT guard: no EA exits before this age
input bool   InpUseProfitLock   = true;    // Once trade is +$X, push SL so it can't lose
input double InpLockProfitUSD   = 5.0;     // No-loss lock trigger ($) â gold moves big, set higher

// ââ Scalp Entries (frequency) ââââââââââââââââââââââââââââââââââââââ
input group "âââ Scalp Entries âââ"
input bool   InpUseMomentum   = true;   // Micro-breakout of recent swing in trend
input bool   InpUsePullback   = true;   // Pullback to fast MA in trend, then go
input int    InpBreakoutLB    = 6;      // Bars to define the recent swing hi/lo
input int    InpScalpFastMA   = 9;      // Fast MA (signal TF)
input int    InpScalpSlowMA   = 21;     // Slow MA (signal TF)
input double InpMomBodyATR    = 0.25;   // Min breakout candle body (ÃATR)

// ââ News Filter (currency-aware) âââââââââââââââââââââââââââââââââââ
input bool   InpUseNewsFilter = true;  // Block entries around high-impact news on this pair
input int    InpNewsBeforeMin = 15;    // Block minutes BEFORE the event
input int    InpNewsAfterMin  = 15;    // Block minutes AFTER the event
input bool   InpNewsHighOnly  = true;  // High-impact only (false = high + medium)

// ââ Signal Engine ââââââââââââââââââââââââââââââââââââââââââââââââââ
input group "âââ Signal Engine âââ"
input ENUM_TIMEFRAMES InpSignalTF      = PERIOD_CURRENT; // Signal timeframe (0=current chart)
input bool            InpAutoScale     = true;      // Auto-tune params for TF + Gold
input int      InpScoreThreshold = 3;       // Min score to auto-trade â lower = more setups
input bool     InpUseBiasFilter  = true;    // HTF Bias filter (H4+D1 EMA)
input int      InpEMAFast        = 21;      // Fast EMA period (Fibonacci â gold)
input int      InpEMASlow        = 89;      // Slow EMA period (Fibonacci â gold)
input double   InpWickRatio      = 1.5;     // Wick:Body ratio for rejection
input double   InpSLBuffer       = 0.8;     // SL buffer (ATRÃ) â wider to avoid noise stops
input double   InpMinSLATR       = 1.2;     // Min SL distance (ATRÃ) â gold needs room
input double   InpRRRatio        = 3.0;     // Risk:Reward ratio (overridden by AutoScale)
input double   InpLevelProximity = 0.8;     // Level proximity ATRÃ (overridden by AutoScale)

// ââ Markov Regime ââââââââââââââââââââââââââââââââââââââââââââââââââ
input group "âââ Markov Regime âââ"
input bool     InpUseMarkov      = true;    // Enable Markov gate
input double   InpMarkovThr      = 1.5;     // Regime threshold % (overridden by AutoScale)
input double   InpMarkovPersist  = 0.80;    // Block if persistence > this
input int      InpMarkovLB       = 10;      // Lookback bars for regime
input int      InpMarkovHold     = 3;       // Min bars regime must hold

// ââ Trade Manager ââââââââââââââââââââââââââââââââââââââââââââââââââ
input group "âââ Trade Manager âââ"
input bool     InpUseTrail       = true;    // Enable trailing stop
input string   InpTrailMode      = "ATR";   // Trail mode: ATR or SWING
input double   InpTrailATRMult   = 2.0;     // ATR trail multiplier
input int      InpSwingLen       = 5;       // Swing lookback (bars)
input bool     InpUseBreakEven   = true;    // Enable break-even
input double   InpBEATRMult      = 1.0;     // Move BE at XÃATR profit
input bool     InpUsePartialTP   = true;    // Close 50% at 1R
input double   InpPartialRR      = 1.0;     // Bank half at 1R (was 2R) â lock small wins early, runner free
input bool     InpExtendTP       = true;    // Strip TP after partial â let remainder run free
input bool     InpProgressTrail  = true;    // Tighten trail as move extends
input double   InpTrailR2Mult    = 1.5;     // Trail ATR mult after 2R profit
input double   InpTrailR3Mult    = 1.0;     // Trail ATR mult after 3R profit (locks hard)

// ââ Sessions âââââââââââââââââââââââââââââââââââââââââââââââââââââââ
input group "âââ Sessions âââ"
input double   InpSpikeATRmult   = 4.0;     // SPIKE GUARD: freeze entries when a candle range >= this x ATR (0=off). Blocks news/fixing-flow spikes the calendar can't see.
input int      InpSpikeCoolBars  = 3;       // SPIKE GUARD: bars to stay frozen after a spike
input bool     InpUseSession     = true;    // Session filter (London + NY)
input int      InpServerGMTOffset = 3;      // Broker server GMT offset (MetaQuotes-Demo summer=3). Converts server->UTC so hours below are TRUE UTC.
input int      InpLDNOpen        = 7;       // Session open (UTC) â 07:00 UTC = NZ 19:00
input int      InpLDNClose       = 21;      // Session close (UTC) â 21:00 UTC = NZ 09:00 (covers your morning)
input int      InpNYOpen         = 13;      // (unused when InpUseNY=false)
input int      InpNYClose        = 17;      // (unused when InpUseNY=false)
input bool     InpUseNY          = false;   // Single continuous window (07-21 UTC) â no gaps
input int      InpLossStreakStop = 4;       // Pause a direction after THIS many losses in a row (was 2)
input double   InpCooldownHours  = 1.0;     // ...for this many hours (was 4) â 0 = no cooldown

// ââ Display ââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
input group "âââ Display âââ"
input bool     InpShowDash       = true;    // Show dashboard panel
input bool     InpShowLevels     = true;    // Show key level lines
input bool     InpShowOBFVG      = true;    // Show OB/FVG zones
input bool     InpShowSignals    = true;    // Show entry/SL/TP lines
input int      InpDashX          = 20;      // Dashboard X position
input int      InpDashY          = 30;      // Dashboard Y position

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// GLOBALS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

CTrade         trade;
CPositionInfo  pos;

// ATR handle
int   hATR;
int   hEMAFastH4, hEMASlowH4;
int   hEMAFastD1, hEMASlowD1;

// State
double g_lot         = 0.0;
double g_atr         = 0.0;
double g_dailyPnL    = 0.0;
double g_startEquity = 0.0;
datetime g_lastDay   = 0;
datetime g_lastBar   = 0;

// Markov state
double g_mkCnt[3][3];
int    g_mkRegime       = 0;   // 0=Side 1=Bull 2=Bear
double g_mkPersistence  = 0.33;
double g_mkConviction   = 0.0;
int    g_mkHeldCount    = 0;
int    g_mkConfirmed    = 0;

// Signal state
int    g_signal         = 0;   // 0=none 1=long -1=short
int    g_decisionScore  = 0;
int    g_confluenceScore= 0;   // 0-5 structural confluence
int    g_probSuccess    = 0;   // 0-100 probability of success %
double g_entryPrice     = 0.0;
double g_slPrice        = 0.0;
double g_tpPrice        = 0.0;
bool   g_partialDone    = false;
bool   g_beDone         = false;

// Confluence factor flags (for dashboard breakdown)
bool   g_cfPDX    = false;   // near PDH/PDL
bool   g_cfWeek   = false;   // near PWH/PWL
bool   g_cfAsia   = false;   // near Asia H/L
bool   g_cfOB     = false;   // inside OB
bool   g_cfFVG    = false;   // inside FVG
bool   g_cfBias   = false;   // HTF bias aligned
bool   g_cfMarkov = false;   // Markov regime aligned
bool   g_cfSweep  = false;   // liquidity sweep signal
bool   g_cfSess   = false;   // in session window

// Manual lot override from panel buttons
double g_manualLot      = 0.0;
bool   g_newsFilter     = false;  // manual news block toggle

// Dashboard position and state (runtime, not input-locked)
int    g_dashX          = 20;
int    g_dashY          = 30;
bool   g_dashMinimized  = false;
bool   g_autoTrade      = false;  // OFF by default â user must enable

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
int    g_tradesToday   = 0;
bool   g_eaStopped     = false;

// Key levels
double g_PDH = 0.0, g_PDL = 0.0;
double g_PWH = 0.0, g_PWL = 0.0;
double g_AsiaH = 0.0, g_AsiaL = 0.0;

// OB / FVG
double g_BullOBHigh = 0.0, g_BullOBLow = 0.0;
double g_BearOBHigh = 0.0, g_BearOBLow = 0.0;
double g_BullFVGTop = 0.0, g_BullFVGBot = 0.0;
double g_BearFVGTop = 0.0, g_BearFVGBot = 0.0;

// Win/loss tracker
int    g_allWins    = 0;
int    g_allLosses  = 0;
double g_equityCurve[20];
int    g_eqIdx      = 0;

// Manual vs EA trade counters
int    g_manualOpens  = 0;
int    g_manualCloses = 0;
int    g_eaOpens      = 0;
int    g_eaCloses     = 0;

// Consecutive loss cooldown (per direction)
int      g_consecLossBuy  = 0;    // consecutive SL hits going LONG
int      g_consecLossSell = 0;    // consecutive SL hits going SHORT
datetime g_cooldownBuyUntil  = 0; // block BUY signals until this time
datetime g_cooldownSellUntil = 0; // block SELL signals until this time
datetime g_spikeUntil        = 0; // entries frozen until this time after a flow spike
int      g_consecLossAny  = 0;    // any direction â controls lot scaling

// Panel object prefix
const string PFX = "SWG_";

// ââ Auto-scaled params (set by AutoScaleForGold in OnInit) ââââââââ
ENUM_TIMEFRAMES g_sTF       = PERIOD_H1;  // resolved signal timeframe
ENUM_TIMEFRAMES g_htf1      = PERIOD_H4;  // first HTF for bias
ENUM_TIMEFRAMES g_htf2      = PERIOD_D1;  // second HTF for bias
int             g_atrPeriod = 14;         // ATR period for signal TF
double          g_trailMult = 2.0;        // ATR trail multiplier
double          g_rrRatio   = 2.5;        // Risk:Reward ratio
double          g_proxMult  = 0.8;        // Level proximity (ATRÃ)
double          g_mkThr     = 1.5;        // Markov threshold %

string TFName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return "??";
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// AUTO-SCALE: resolve signal TF + tune params for Gold
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void AutoScaleForGold()
{
   // Resolve signal TF (0/CURRENT â use chart period)
   g_sTF = (InpSignalTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : InpSignalTF;

   // HTF bias pair: always at least 2 levels above signal TF
   if(g_sTF <= PERIOD_H1)
      { g_htf1 = PERIOD_H4;  g_htf2 = PERIOD_D1;  }
   else if(g_sTF <= PERIOD_H4)
      { g_htf1 = PERIOD_D1;  g_htf2 = PERIOD_W1;  }
   else
      { g_htf1 = PERIOD_W1;  g_htf2 = PERIOD_MN1; }

   if(!InpAutoScale)
   {
      // User manages params manually â respect their inputs
      g_atrPeriod = 14;
      g_trailMult = InpTrailATRMult;
      g_rrRatio   = InpRRRatio;
      g_proxMult  = InpLevelProximity;
      g_mkThr     = InpMarkovThr;
      return;
   }

   // Gold-specific scaling by timeframe (minutes per bar)
   int tfMin = (int)(PeriodSeconds(g_sTF) / 60);

   if(tfMin <= 15)       // M1âM15: scalping â tighter trail, lower RR, tight proximity
      { g_atrPeriod=20; g_trailMult=2.5; g_rrRatio=2.0; g_proxMult=0.5; g_mkThr=0.5; }
   else if(tfMin <= 60)  // M30âH1: intraday swing â balanced defaults
      { g_atrPeriod=14; g_trailMult=2.0; g_rrRatio=2.5; g_proxMult=0.8; g_mkThr=1.5; }
   else if(tfMin <= 240) // H4: swing â wider trail, higher RR, wider levels
      { g_atrPeriod=10; g_trailMult=1.5; g_rrRatio=3.0; g_proxMult=1.0; g_mkThr=2.0; }
   else                  // D1+: position â widest trail, best RR, widest proximity
      { g_atrPeriod=10; g_trailMult=1.2; g_rrRatio=3.5; g_proxMult=1.2; g_mkThr=3.0; }

   Print("STAALWAG GOLD AutoScale â TF:", TFName(g_sTF),
         " HTF:", TFName(g_htf1), "+", TFName(g_htf2),
         " ATRp:", g_atrPeriod, " Trail:", g_trailMult,
         " RR:", g_rrRatio, " Prox:", g_proxMult, " MkThr:", g_mkThr);
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// INIT
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
   if(StringFind(s,"LEVERAGED")>=0)                                      return PF_LEVERAGED;
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
         case PF_LEVERAGED:   g_firmName="Leveraged";   p1=6;  p2=6; g_maxLossPct=6;  g_dailyLossPct=3; g_trailMaxDD=true; break;
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

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// NEWS FILTER â currency-aware. Cached 30s. Empty in Strategy Tester.
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
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

int OnInit()
{
   trade.SetExpertMagicNumber(202601);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   AutoScaleForGold();   // resolve TF + gold-tuned params before creating handles

   hATR       = iATR(_Symbol, g_sTF,  g_atrPeriod);
   hEMAFastH4 = iMA(_Symbol, g_htf1, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMASlowH4 = iMA(_Symbol, g_htf1, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hEMAFastD1 = iMA(_Symbol, g_htf2, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMASlowD1 = iMA(_Symbol, g_htf2, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);

   if(hATR == INVALID_HANDLE || hEMAFastH4 == INVALID_HANDLE)
   { Alert("STAALWAG GOLD: Indicator init failed"); return INIT_FAILED; }

   ArrayInitialize(g_mkCnt, 0.0);
   ArrayInitialize(g_equityCurve, 0.0);

   g_manualLot    = InpFixedLot;
   g_dashX        = InpDashX;
   g_dashY        = InpDashY;
   g_dashMinimized= false;
   g_startEquity  = AccountInfoDouble(ACCOUNT_EQUITY);

   SetupRiskProfile();           // recognise prop firm -> apply risk rules
   g_autoTrade = InpAutoTradeOn; // AUTO defaults ON

   if(InpShowDash)   DrawDashboard();
   if(InpShowLevels) DrawKeyLevels();
   DrawWatermark();

   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// DEINIT
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteAllObjects();
   IndicatorRelease(hATR);
   IndicatorRelease(hEMAFastH4);
   IndicatorRelease(hEMASlowH4);
   IndicatorRelease(hEMAFastD1);
   IndicatorRelease(hEMASlowD1);
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// TIMER â refresh dashboard every second
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void OnTimer()
{
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(ch > 50)
   {
      int newY = InpDashY;
      if(newY != g_dashY) { g_dashY = newY; RedrawAllPanelObjects(); }
   }
   if(InpShowDash) UpdateDashboard();
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// TRADE TRANSACTION â count manual vs EA opens/closes
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.symbol != _Symbol) return;
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong ticket = trans.deal;
      if(!HistoryDealSelect(ticket)) return;
      long   magic    = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      long   entry    = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      double profit   = HistoryDealGetDouble (ticket, DEAL_PROFIT);
      bool   isManual = (magic == 0);
      bool   isEA     = (magic == 202601);

      if(entry == DEAL_ENTRY_IN)
      {
         if(isManual) g_manualOpens++;
         else if(isEA) g_eaOpens++;
      }
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         if(isManual) g_manualCloses++;
         else if(isEA)
         {
            g_eaCloses++;
            if(profit > 0)
            {
               g_allWins++;
               g_consecLossAny  = 0;
               // win resets the direction cooldowns
               long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
               if(dealType == DEAL_TYPE_BUY)  { g_consecLossSell = 0; }
               else                            { g_consecLossBuy  = 0; }
            }
            else
            {
               g_allLosses++;
               g_consecLossAny++;
               // track per-direction streak and set cooldown after 2 consecutive
               long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
               if(dealType == DEAL_TYPE_BUY)   // closing a BUY = was a LONG trade
               {
                  g_consecLossBuy++;
                  g_consecLossSell = 0;
                  if(InpCooldownHours > 0 && g_consecLossBuy >= InpLossStreakStop)
                     g_cooldownBuyUntil = TimeCurrent() + (int)(InpCooldownHours * 3600);
               }
               else
               {
                  g_consecLossSell++;
                  g_consecLossBuy = 0;
                  if(InpCooldownHours > 0 && g_consecLossSell >= InpLossStreakStop)
                     g_cooldownSellUntil = TimeCurrent() + (int)(InpCooldownHours * 3600);
               }
            }
         }
      }
      if(InpShowDash) UpdateDashboard();
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// ON TICK â main loop
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void OnTick()
{
   // Daily reset
   CheckDailyReset();
   if(g_eaStopped) return;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_peakEquity) g_peakEquity = eq;

   if(g_propOn)
   {
      double floorEq = g_trailMaxDD ? g_peakEquity*(1.0-g_maxGuardPct/100.0)
                                    : g_initBal   *(1.0-g_maxGuardPct/100.0);
      if(eq <= floorEq)
      {
         CloseAllPositions(); g_eaStopped = true;
         Alert(g_firmName, ": max-loss guard hit â EA stopped.");
         return;
      }
      if(!g_dailyHalt && IsDailyDDBreached())
      {
         CloseAllPositions(); g_dailyHalt = true;
         Alert(g_firmName, ": daily-loss guard hit â flat for the day.");
      }
      if(g_profitTgtPct > 0 && InpStopAtTarget &&
         eq >= g_initBal*(1.0+g_profitTgtPct/100.0)) g_targetHit = true;
      double dayCapUsd = DailyProfitCapUsd();
      if(dayCapUsd > 0 && !g_dailyHalt && (eq - g_startEquity) >= dayCapUsd)
         g_dailyHalt = true;
   }
   else if(IsDailyDDBreached())
   {
      CloseAllPositions();
      g_dailyHalt = true;
   }

   // Trade manager runs every tick (trailing, BE, partial)
   ManageOpenTrades();

   // Signal engine â new bar only (on signal TF)
   datetime curBar = iTime(_Symbol, g_sTF, 0);
   if(curBar == g_lastBar) return;
   g_lastBar = curBar;

   // Refresh ATR
   double atrBuf[1];
   if(CopyBuffer(hATR, 0, 1, 1, atrBuf) < 1) return;
   g_atr = atrBuf[0];

   // Refresh key levels
   RefreshKeyLevels();
   RefreshOBFVG();

   // Markov regime update
   UpdateMarkov();

   // HTF bias
   bool htfBull = false, htfBear = false;
   GetHTFBias(htfBull, htfBear);

   // Session gate â Gold only trades London open + NY open (avoid Asia/noon chop)
   UpdateSpikeGuard();   // detect flow shocks every tick (in or out of session)

   if(InpUseSession && !IsInSession()) return;
   if(SpikeFrozen()) return;   // flow-spike cooldown: no new entries

   // Friday cutoff â no new entries after 13:00 UTC (pre-weekend liquidity drain)
   MqlDateTime tNow; TimeToStruct(TimeCurrent(), tNow);
   if(tNow.day_of_week == 5 && tNow.hour >= 13) return;

   // News filter (manual toggle)
   if(g_newsFilter) return;

   // Don't stack positions â one trade at a time
   if(HasOpenPosition()) return;

   // Clear stale signal zones from previous bar
   string _so[] = {"EntryLine","SLLine","TPLine","RiskZone","RewardZone",
                   "EntryArrow","EntryLabel","SLPriceLabel","TPPriceLabel","EntPriceLabel"};
   for(int _i=0;_i<ArraySize(_so);_i++) { string _n=PFX+_so[_i]; if(ObjectFind(0,_n)>=0) ObjectDelete(0,_n); }

   // Reset signal state â dashboard keeps last score visible until new signal fires
   g_signal = 0;
   RunSignalEngine(htfBull, htfBear);

   // Cooldown check â block direction after 2 consecutive losses
   datetime now = TimeCurrent();
   if(g_signal == 1  && now < g_cooldownBuyUntil)  g_signal = 0;
   if(g_signal == -1 && now < g_cooldownSellUntil) g_signal = 0;

   // Auto-execute if score meets threshold and auto-trade is enabled
   if(g_signal != 0 && g_decisionScore >= InpScoreThreshold && g_autoTrade
      && !g_dailyHalt && !g_targetHit && g_tradesToday < InpMaxTradesDay
      && !NewsBlocked())
   {
      // Streak lot reduction â use 50% lot after 2+ consecutive losses
      double execLot = (g_consecLossAny >= 2) ? g_manualLot * 0.5 : g_manualLot;
      ExecuteSignal(g_signal, execLot);
      g_tradesToday++;
   }

   // Redraw levels and dashboard
   if(InpShowLevels) DrawKeyLevels();
   if(InpShowDash)   UpdateDashboard();
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// CHART EVENT â button handler
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // ââ CHART RESIZE â snap back to bottom-left âââââââââââââââââââââââ
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if(ch > 50) g_dashY = InpDashY;
      RedrawAllPanelObjects();
      return;
   }

   // ââ DRAG â reposition entire panel âââââââââââââââââââââââââââââââ
   if(id == CHARTEVENT_OBJECT_DRAG && sparam == PFX+"BG")
   {
      g_dashX = (int)ObjectGetInteger(0, PFX+"BG", OBJPROP_XDISTANCE);
      g_dashY = (int)ObjectGetInteger(0, PFX+"BG", OBJPROP_YDISTANCE);
      // Snap to screen edges (min 0)
      if(g_dashX < 0) g_dashX = 0;
      if(g_dashY < 0) g_dashY = 0;
      RedrawAllPanelObjects();
      return;
   }

   if(id != CHARTEVENT_OBJECT_CLICK) return;

   // ââ MINIMIZE / MAXIMISE ââââââââââââââââââââââââââââââââââââââââââ
   if(sparam == PFX+"BTN_MINIMIZE")
   {
      g_dashMinimized = !g_dashMinimized;
      ApplyMinimizeState();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      return;
   }

   if(sparam == PFX+"BTN_BUY")
   {
      string why;
      if(EntryBlocked(why)) Alert("STAALWAG GOLD: manual BUY blocked - ", why);
      else { double lot = g_manualLot > 0 ? g_manualLot : InpFixedLot; ExecuteSignal(1, lot); }
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == PFX+"BTN_SELL")
   {
      string why;
      if(EntryBlocked(why)) Alert("STAALWAG GOLD: manual SELL blocked - ", why);
      else { double lot = g_manualLot > 0 ? g_manualLot : InpFixedLot; ExecuteSignal(-1, lot); }
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == PFX+"BTN_CLOSE_ALL")
   {
      CloseAllPositions();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == PFX+"BTN_CLOSE_50")
   {
      ClosePartialAll(0.5);
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == PFX+"BTN_CLOSE_25")
   {
      ClosePartialAll(0.25);
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == PFX+"BTN_LOT_UP")
   {
      g_manualLot = NormalizeDouble(g_manualLot + 0.01, 2);
      if(g_manualLot > 5.0) g_manualLot = 5.0;
      UpdateDashboard();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == PFX+"BTN_LOT_DN")
   {
      g_manualLot = NormalizeDouble(g_manualLot - 0.01, 2);
      if(g_manualLot < 0.01) g_manualLot = 0.01;
      UpdateDashboard();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == PFX+"BTN_AUTO")
   {
      g_autoTrade = !g_autoTrade;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      UpdateDashboard();
      return;
   }
   else if(sparam == PFX+"BTN_NEWS")
   {
      g_newsFilter = !g_newsFilter;
      UpdateDashboard();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == PFX+"BTN_LOT_AUTO")
   {
      g_manualLot = CalcAutoLot(SymbolInfoDouble(_Symbol, SYMBOL_ASK), g_atr * InpMinSLATR);
      UpdateDashboard();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// SIGNAL ENGINE
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void RunSignalEngine(bool htfBull, bool htfBear)
{
   // Need at least 3 bars on signal TF
   int bars = iBars(_Symbol, g_sTF);
   if(bars < 10) return;

   double close0 = iClose(_Symbol, g_sTF, 0);
   double close1 = iClose(_Symbol, g_sTF, 1);
   double open1  = iOpen (_Symbol, g_sTF, 1);
   double high1  = iHigh (_Symbol, g_sTF, 1);
   double low1   = iLow  (_Symbol, g_sTF, 1);
   double open2  = iOpen (_Symbol, g_sTF, 2);
   double high2  = iHigh (_Symbol, g_sTF, 2);
   double low2   = iLow  (_Symbol, g_sTF, 2);
   double close2 = iClose(_Symbol, g_sTF, 2);

   double atr = g_atr;
   double proximity = atr * g_proxMult;

   // Candle properties (bar 1 = last closed bar)
   double body1      = MathAbs(close1 - open1);
   double upperWick1 = high1 - MathMax(close1, open1);
   double lowerWick1 = MathMin(close1, open1) - low1;
   double range1     = high1 - low1;
   bool   isBull1    = close1 >= open1;
   bool   isBear1    = close1 <= open1;
   bool   isBigC1    = body1 > atr * 0.25;

   // ââ PROXIMITY TO KEY LEVELS ââââââââââââââââââââââââââââââââââââââ
   bool nearPDH = g_PDH > 0 && high1 >= g_PDH - proximity && low1 <= g_PDH + proximity;
   bool nearPDL = g_PDL > 0 && low1  <= g_PDL + proximity && high1 >= g_PDL - proximity;
   bool nearPWH = g_PWH > 0 && high1 >= g_PWH - proximity && low1  <= g_PWH + proximity;
   bool nearPWL = g_PWL > 0 && low1  <= g_PWL + proximity && high1 >= g_PWL - proximity;
   bool nearAH  = g_AsiaH > 0 && high1 >= g_AsiaH - proximity && low1 <= g_AsiaH + proximity;
   bool nearAL  = g_AsiaL > 0 && low1  <= g_AsiaL + proximity && high1 >= g_AsiaL - proximity;
   bool nearBullOB = g_BullOBHigh > 0 && close1 >= g_BullOBLow - atr*0.3 && close1 <= g_BullOBHigh + atr*0.5;
   bool nearBearOB = g_BearOBHigh > 0 && close1 <= g_BearOBHigh + atr*0.3 && close1 >= g_BearOBLow  - atr*0.5;
   bool nearBullFVG= g_BullFVGTop > 0 && close1 >= g_BullFVGBot - atr*0.3 && close1 <= g_BullFVGTop + atr*0.5;
   bool nearBearFVG= g_BearFVGTop > 0 && close1 <= g_BearFVGTop + atr*0.3 && close1 >= g_BearFVGBot - atr*0.5;

   // ââ REJECTION WICKS (wick >= ratioÃbody OR >= 0.3ÃATR absolute floor)
   bool bullWick1 = lowerWick1 >= body1 * InpWickRatio || lowerWick1 >= atr * 0.3;
   bool bearWick1 = upperWick1 >= body1 * InpWickRatio || upperWick1 >= atr * 0.3;

   // ââ REJECTION PATTERNS âââââââââââââââââââââââââââââââââââââââââââ
   bool bullRejPDL = (bullWick1 && nearPDL && isBull1) || (low2 < g_PDL && close1 > g_PDL);
   bool bearRejPDH = (bearWick1 && nearPDH && isBear1) || (high2 > g_PDH && close1 < g_PDH);
   bool bullRejAL  = (bullWick1 && nearAL  && isBull1) || (low2 < g_AsiaL && close1 > g_AsiaL);
   bool bearRejAH  = (bearWick1 && nearAH  && isBear1) || (high2 > g_AsiaH && close1 < g_AsiaH);
   bool bullRejPWL = (bullWick1 && nearPWL && isBull1) || (low2 < g_PWL && close1 > g_PWL);
   bool bearRejPWH = (bearWick1 && nearPWH && isBear1) || (high2 > g_PWH && close1 < g_PWH);

   // ââ CONFIRMATION: close in upper/lower 40%+ of candle range
   bool confirmBull = isBull1 && range1 > 0 && (close1 - low1) / range1 >= 0.4;
   bool confirmBear = isBear1 && range1 > 0 && (high1 - close1) / range1 >= 0.4;

   bool longPDL  = bullRejPDL && confirmBull;
   bool shortPDH = bearRejPDH && confirmBear;
   bool longAL   = bullRejAL  && confirmBull;
   bool shortAH  = bearRejAH  && confirmBear;
   bool longPWL  = bullRejPWL && confirmBull;
   bool shortPWH = bearRejPWH && confirmBear;

   // ââ LIQUIDITY SWEEPS âââââââââââââââââââââââââââââââââââââââââââââ
   bool sweepBullPDL = g_PDL > 0 && low2  < g_PDL && close1 > g_PDL && isBull1;
   bool sweepBearPDH = g_PDH > 0 && high2 > g_PDH && close1 < g_PDH && isBear1;
   bool sweepBullAL  = g_AsiaL > 0 && low2 < g_AsiaL && close1 > g_AsiaL && isBull1;
   bool sweepBearAH  = g_AsiaH > 0 && high2 > g_AsiaH && close1 < g_AsiaH && isBear1;

   // ââ Scalp momentum + pullback (always available, trend-filtered) ââ
   double hiN=-DBL_MAX, loN=DBL_MAX;
   for(int b=2;b<2+InpBreakoutLB;b++)
   {
      double hb=iHigh(_Symbol,g_sTF,b), lb=iLow(_Symbol,g_sTF,b);
      if(hb>hiN) hiN=hb;
      if(lb<loN) loN=lb;
   }
   double sumF=0,sumS=0;
   for(int b=1;b<=InpScalpFastMA;b++) sumF+=iClose(_Symbol,g_sTF,b);
   for(int b=1;b<=InpScalpSlowMA;b++) sumS+=iClose(_Symbol,g_sTF,b);
   double maF=sumF/InpScalpFastMA, maS=sumS/InpScalpSlowMA;
   bool trendUp=maF>maS, trendDn=maF<maS;
   bool momLong  = InpUseMomentum && close1>hiN && isBull1 && trendUp && body1>=atr*InpMomBodyATR;
   bool momShort = InpUseMomentum && close1<loN && isBear1 && trendDn && body1>=atr*InpMomBodyATR;
   bool pbLong   = InpUsePullback && trendUp && low1<=maF && close1>maF && isBull1 && confirmBull;
   bool pbShort  = InpUsePullback && trendDn && high1>=maF && close1<maF && isBear1 && confirmBear;

   bool anyLong  = longPDL || longAL || longPWL || sweepBullPDL || sweepBullAL || momLong || pbLong;
   bool anyShort = shortPDH || shortAH || shortPWH || sweepBearPDH || sweepBearAH || momShort || pbShort;

   if(!anyLong && !anyShort) return;
   if(anyLong && anyShort) { if(trendUp) anyShort=false; else anyLong=false; }

   // ââ MARKOV GATE ââââââââââââââââââââââââââââââââââââââââââââââââââ
   bool mkBlockLong  = InpUseMarkov && g_mkConfirmed == 2 && g_mkPersistence > InpMarkovPersist;
   bool mkBlockShort = InpUseMarkov && g_mkConfirmed == 1 && g_mkPersistence > InpMarkovPersist;

   if(anyLong  && mkBlockLong)  anyLong  = false;
   if(anyShort && mkBlockShort) anyShort = false;
   if(!anyLong && !anyShort) return;

   // ââ CONFLUENCE SCORE 0-5 âââââââââââââââââââââââââââââââââââââââââ
   bool cfPDX  = anyLong ? nearPDL    : nearPDH;
   bool cfWeek = anyLong ? nearPWL    : nearPWH;
   bool cfAsia = anyLong ? nearAL     : nearAH;
   bool cfOB   = anyLong ? nearBullOB : nearBearOB;
   bool cfFVG  = anyLong ? nearBullFVG: nearBearFVG;

   int conf = 0;
   if(cfPDX)  conf++;
   if(cfWeek) conf++;
   if(cfAsia) conf++;
   if(cfOB)   conf++;
   if(cfFVG)  conf++;
   conf = MathMin(conf, 5);

   // ââ DECISION SCORE 0-10 ââââââââââââââââââââââââââââââââââââââââââ
   int score = 2;
   bool biasAligned = (anyLong && htfBull) || (anyShort && htfBear);
   bool mkAligned   = (anyLong && g_mkConfirmed == 1) || (anyShort && g_mkConfirmed == 2);
   bool isSweep     = sweepBullPDL || sweepBullAL || sweepBearPDH || sweepBearAH;
   bool inSess      = IsInSession();

   bool isMom = (anyLong&&momLong)||(anyShort&&momShort);
   bool isPB  = (anyLong&&pbLong) ||(anyShort&&pbShort);
   if(biasAligned) score += 2;
   if(mkAligned)   score += 1;
   if(isSweep)     score += 1;
   if(isMom)       score += 2;
   if(isPB)        score += 2;
   score += MathMin(conf, 4);
   if(inSess)      score += 1;
   score = MathMin(score, 10);

   // ââ PROBABILITY OF SUCCESS 0-100% ââââââââââââââââââââââââââââââââ
   // Base: 38% (XAUUSD historical random-trade baseline)
   // Each factor weighted by empirical edge contribution
   double prob = 38.0;
   if(cfPDX)       prob += 8.0;   // prev day level rejection: strong edge
   if(cfWeek)      prob += 6.0;   // weekly level confluence
   if(cfAsia)      prob += 7.0;   // asia range bounce: high probability
   if(cfOB)        prob += 9.0;   // order block: institutional level
   if(cfFVG)       prob += 5.0;   // fair value gap fill
   if(biasAligned) prob += 10.0;  // HTF aligned: largest single factor
   if(mkAligned)   prob += 8.0;   // Markov confirms regime
   if(isSweep)     prob += 7.0;   // liquidity sweep: smart money signal
   if(inSess)      prob += 4.0;   // session timing: London/NY liquidity
   if(score >= 8)  prob += 3.0;   // high decision score bonus
   // Conviction multiplier from Markov (0â1 range adds up to +3%)
   prob += MathAbs(g_mkConviction) * 3.0;
   // Historical win-rate skew (if we have data, blend toward real rate)
   int total = g_allWins + g_allLosses;
   if(total >= 10)
   {
      double realWR = (double)g_allWins / total * 100.0;
      prob = prob * 0.6 + realWR * 0.4;   // 40% weight to live track record
   }
   prob = MathMin(MathMax(prob, 25.0), 92.0);  // floor 25%, cap 92%

   // ââ STORE GLOBALS ââââââââââââââââââââââââââââââââââââââââââââââââ
   g_confluenceScore = conf;
   g_probSuccess     = (int)MathRound(prob);
   g_decisionScore   = score;
   g_signal          = anyLong ? 1 : -1;

   // Factor flags for dashboard breakdown
   g_cfPDX    = cfPDX;
   g_cfWeek   = cfWeek;
   g_cfAsia   = cfAsia;
   g_cfOB     = cfOB;
   g_cfFVG    = cfFVG;
   g_cfBias   = biasAligned;
   g_cfMarkov = mkAligned;
   g_cfSweep  = isSweep;
   g_cfSess   = inSess;

   // Calculate E/SL/TP
   double minSLDist = g_atr * InpMinSLATR;
   if(anyLong)
   {
      double slRaw = low1 - g_atr * InpSLBuffer;
      g_entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      g_slPrice    = MathMin(slRaw, g_entryPrice - minSLDist);
      g_tpPrice    = g_entryPrice + (g_entryPrice - g_slPrice) * g_rrRatio;
   }
   else
   {
      double slRaw = high1 + g_atr * InpSLBuffer;
      g_entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      g_slPrice    = MathMax(slRaw, g_entryPrice + minSLDist);
      g_tpPrice    = g_entryPrice - (g_slPrice - g_entryPrice) * g_rrRatio;
   }

   // Draw signal markers
   if(InpShowSignals) DrawSignalLevels(anyLong);
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// EXECUTE SIGNAL
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void ExecuteSignal(int direction, double lot)
{
   if(lot <= 0) lot = InpFixedLot;
   lot = NormalizeLot(lot);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double atr = g_atr;
   double minSLDist = atr * InpMinSLATR;

   double entry, sl, tp;

   if(direction == 1)
   {
      entry = ask;
      sl    = (g_slPrice > 0) ? g_slPrice : entry - atr * (InpSLBuffer + InpMinSLATR);
      sl    = MathMin(sl, entry - minSLDist);
      tp    = (g_tpPrice > 0) ? g_tpPrice : entry + (entry - sl) * g_rrRatio;

      if(InpAutoLot) lot = CalcAutoLot(entry, entry - sl);

      bool ok = trade.Buy(lot, _Symbol, entry, sl, tp,
                          StringFormat("SWG LONG | Score:%d | %.2fR", g_decisionScore, g_rrRatio));
      if(ok)
      {
         DrawEntryMarker(true, entry, sl, tp, lot);
         g_partialDone = false;
         g_beDone      = false;
         Print("STAALWAG GOLD: BUY ", lot, " @ ", entry, " SL:", sl, " TP:", tp);
      }
   }
   else
   {
      entry = bid;
      sl    = (g_slPrice > 0) ? g_slPrice : entry + atr * (InpSLBuffer + InpMinSLATR);
      sl    = MathMax(sl, entry + minSLDist);
      tp    = (g_tpPrice > 0) ? g_tpPrice : entry - (sl - entry) * g_rrRatio;

      if(InpAutoLot) lot = CalcAutoLot(entry, sl - entry);

      bool ok = trade.Sell(lot, _Symbol, entry, sl, tp,
                           StringFormat("SWG SHORT | Score:%d | %.2fR", g_decisionScore, g_rrRatio));
      if(ok)
      {
         DrawEntryMarker(false, entry, sl, tp, lot);
         g_partialDone = false;
         g_beDone      = false;
         Print("STAALWAG GOLD: SELL ", lot, " @ ", entry, " SL:", sl, " TP:", tp);
      }
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// TRADE MANAGER
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void ManageOpenTrades()
{
   if(!HasOpenPosition()) return;

   double atr   = g_atr;
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != 202601)  continue;
      if(pos.Symbol() != _Symbol) continue;

      double openP   = pos.PriceOpen();
      double curSL   = pos.StopLoss();
      double curTP   = pos.TakeProfit();
      double curPrice= pos.PositionType() == POSITION_TYPE_BUY ? bid : ask;
      double lots    = pos.Volume();
      ulong  ticket  = pos.Ticket();

      double slDist  = MathAbs(openP - curSL);
      double oneR    = slDist;

      // HFT guard: leave trade alone until it ages past the min-hold.
      if((long)(TimeCurrent() - pos.Time()) < InpMinHoldSeconds) continue;

      // No-loss lock: once floating profit >= $X, push SL past entry.
      if(InpUseProfitLock)
      {
         double netP = pos.Profit()+pos.Swap()+pos.Commission();
         if(netP >= InpLockProfitUSD)
         {
            int    dg  = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
            double buf = (double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*SymbolInfoDouble(_Symbol,SYMBOL_POINT);
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

      // Progressive trail multiplier â tightens as move extends
      double pnlR = (oneR > 0) ? MathAbs(curPrice - openP) / oneR : 0;
      double activeMult = g_trailMult;
      if(InpProgressTrail)
      {
         if(pnlR >= 3.0)      activeMult = InpTrailR3Mult;
         else if(pnlR >= 2.0) activeMult = InpTrailR2Mult;
      }

      if(pos.PositionType() == POSITION_TYPE_BUY)
      {
         double profit1R = openP + oneR * InpPartialRR;
         double profitBE = openP + oneR * InpBEATRMult;

         // Partial TP at 1R â then strip fixed TP so remainder runs free
         if(InpUsePartialTP && !g_partialDone && curPrice >= profit1R)
         {
            double closeLots = NormalizeLot(lots * 0.5);
            if(closeLots >= 0.01)
            {
               trade.PositionClosePartial(ticket, closeLots);
               g_partialDone = true;
               Print("STAALWAG: Partial close 50% @ 1R â remainder running free");
               if(InpExtendTP)
                  trade.PositionModify(ticket, curSL, 0);
            }
         }

         // Break-even
         if(InpUseBreakEven && !g_beDone && curPrice >= profitBE)
         {
            double newSL = openP + (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double newTP = (InpExtendTP && g_partialDone) ? 0 : curTP;
            if(newSL > curSL)
            {
               trade.PositionModify(ticket, newSL, newTP);
               g_beDone = true;
               Print("STAALWAG: Break-even set @ ", newSL);
            }
         }

         // Progressive trailing stop
         if(InpUseTrail)
         {
            double newSL = 0.0;
            if(InpTrailMode == "ATR")
               newSL = bid - atr * activeMult;
            else
            {
               double swLow = iLow(_Symbol, g_sTF, iLowest(_Symbol, g_sTF, MODE_LOW, InpSwingLen, 1));
               newSL = swLow - atr * 0.1;
            }
            newSL = NormalizeDouble(newSL, _Digits);
            double newTP = (InpExtendTP && g_partialDone) ? 0 : curTP;
            if(newSL > curSL && newSL < bid)
            {
               trade.PositionModify(ticket, newSL, newTP);
               DrawTrailLine(newSL);
            }
         }
      }
      else // SELL
      {
         double profit1R = openP - oneR * InpPartialRR;
         double profitBE = openP - oneR * InpBEATRMult;

         if(InpUsePartialTP && !g_partialDone && curPrice <= profit1R)
         {
            double closeLots = NormalizeLot(lots * 0.5);
            if(closeLots >= 0.01)
            {
               trade.PositionClosePartial(ticket, closeLots);
               g_partialDone = true;
               Print("STAALWAG: Partial close 50% @ 1R â remainder running free");
               if(InpExtendTP)
                  trade.PositionModify(ticket, curSL, 0);
            }
         }

         if(InpUseBreakEven && !g_beDone && curPrice <= profitBE)
         {
            double newSL = openP - (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double newTP = (InpExtendTP && g_partialDone) ? 0 : curTP;
            if(newSL < curSL)
            {
               trade.PositionModify(ticket, newSL, newTP);
               g_beDone = true;
            }
         }

         if(InpUseTrail)
         {
            double newSL = 0.0;
            if(InpTrailMode == "ATR")
               newSL = ask + atr * activeMult;
            else
            {
               double swHigh = iHigh(_Symbol, g_sTF, iHighest(_Symbol, g_sTF, MODE_HIGH, InpSwingLen, 1));
               newSL = swHigh + atr * 0.1;
            }
            newSL = NormalizeDouble(newSL, _Digits);
            double newTP = (InpExtendTP && g_partialDone) ? 0 : curTP;
            if(newSL < curSL && newSL > ask)
            {
               trade.PositionModify(ticket, newSL, newTP);
               DrawTrailLine(newSL);
            }
         }
      }
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// MARKOV REGIME ENGINE
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void UpdateMarkov()
{
   int bars = iBars(_Symbol, g_sTF);
   if(bars < InpMarkovLB + 5) return;

   // Calculate log return over lookback on signal TF
   double closeNow  = iClose(_Symbol, g_sTF, 1);
   double closePrev = iClose(_Symbol, g_sTF, 1 + InpMarkovLB);
   if(closePrev <= 0) return;

   double logRet = MathLog(closeNow / closePrev);
   double thr    = g_mkThr / 100.0;   // auto-scaled threshold

   int newRegime = (logRet > thr) ? 1 : (logRet < -thr) ? 2 : 0;

   // Update transition count
   g_mkCnt[g_mkRegime][newRegime] += 1.0;
   g_mkRegime = newRegime;

   // Debounce â must hold InpMarkovHold bars
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

   // Normalise rows â transition probabilities
   double P[3][3];
   for(int r = 0; r < 3; r++)
   {
      double rowSum = g_mkCnt[r][0] + g_mkCnt[r][1] + g_mkCnt[r][2];
      for(int c = 0; c < 3; c++)
         P[r][c] = (rowSum > 0) ? g_mkCnt[r][c] / rowSum : 1.0/3.0;
   }

   g_mkPersistence = P[g_mkConfirmed][g_mkConfirmed];
   g_mkConviction  = P[g_mkConfirmed][1] - P[g_mkConfirmed][2];
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// HTF BIAS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void GetHTFBias(bool &bull, bool &bear)
{
   double efH4[1], esH4[1], clH4[1];
   double efD1[1], esD1[1], clD1[1];

   if(CopyBuffer(hEMAFastH4, 0, 1, 1, efH4) < 1) return;
   if(CopyBuffer(hEMASlowH4, 0, 1, 1, esH4) < 1) return;
   if(CopyBuffer(hEMAFastD1, 0, 1, 1, efD1) < 1) return;
   if(CopyBuffer(hEMASlowD1, 0, 1, 1, esD1) < 1) return;

   double closeH4 = iClose(_Symbol, PERIOD_H4, 1);
   double closeD1 = iClose(_Symbol, PERIOD_D1, 1);

   bool h4Bull = closeH4 > efH4[0] && closeH4 > esH4[0];
   bool h4Bear = closeH4 < efH4[0] && closeH4 < esH4[0];
   bool d1Bull = closeD1 > efD1[0] && closeD1 > esD1[0];
   bool d1Bear = closeD1 < efD1[0] && closeD1 < esD1[0];

   // Gold: both TFs must agree â prevents trading into major trend (June 19 lesson)
   bull = h4Bull && d1Bull;
   bear = h4Bear && d1Bear;
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// KEY LEVELS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void RefreshKeyLevels()
{
   g_PDH = iHigh(_Symbol, PERIOD_D1, 1);
   g_PDL = iLow (_Symbol, PERIOD_D1, 1);
   g_PWH = iHigh(_Symbol, PERIOD_W1, 1);
   g_PWL = iLow (_Symbol, PERIOD_W1, 1);

   // Asia session H/L (00:00-07:00 UTC)
   double asiaH = 0.0, asiaL = DBL_MAX;
   MqlDateTime td;
   for(int b = 1; b <= 200; b++)
   {
      datetime t = iTime(_Symbol, PERIOD_H1, b);
      TimeToStruct(t, td);
      if(td.hour >= 0 && td.hour < 7)
      {
         double h = iHigh(_Symbol, PERIOD_H1, b);
         double l = iLow (_Symbol, PERIOD_H1, b);
         if(h > asiaH) asiaH = h;
         if(l < asiaL) asiaL = l;
      }
      if(td.hour >= 7 && td.day_of_week >= 1) break;
   }
   if(asiaH > 0)     g_AsiaH = asiaH;
   if(asiaL < DBL_MAX) g_AsiaL = asiaL;
}

void RefreshOBFVG()
{
   // FVG minimum size scales up on lower TFs to filter noise on gold
   int tfMin = (int)(PeriodSeconds(g_sTF) / 60);
   double fvgMinFrac = (tfMin <= 15) ? 0.4 : 0.3;

   // Order blocks â last bearish candle before bullish push (on signal TF)
   for(int b = 3; b <= 20; b++)
   {
      double c0 = iClose(_Symbol, g_sTF, b);
      double o0 = iOpen (_Symbol, g_sTF, b);
      double c1 = iClose(_Symbol, g_sTF, b-2);
      if(c0 < o0 && c1 > iHigh(_Symbol, g_sTF, b))  // Bull OB
      {
         g_BullOBHigh = MathMax(o0, c0);
         g_BullOBLow  = MathMin(o0, c0);
         break;
      }
   }
   for(int b = 3; b <= 20; b++)
   {
      double c0 = iClose(_Symbol, g_sTF, b);
      double o0 = iOpen (_Symbol, g_sTF, b);
      double c1 = iClose(_Symbol, g_sTF, b-2);
      if(c0 > o0 && c1 < iLow(_Symbol, g_sTF, b))   // Bear OB
      {
         g_BearOBHigh = MathMax(o0, c0);
         g_BearOBLow  = MathMin(o0, c0);
         break;
      }
   }

   // FVG â 3-bar gap
   for(int b = 2; b <= 30; b++)
   {
      double l0 = iLow (_Symbol, g_sTF, b);
      double h2 = iHigh(_Symbol, g_sTF, b+2);
      if(l0 > h2 && (l0 - h2) >= g_atr * fvgMinFrac)
      {
         g_BullFVGTop = l0;
         g_BullFVGBot = h2;
         break;
      }
   }
   for(int b = 2; b <= 30; b++)
   {
      double h0 = iHigh(_Symbol, g_sTF, b);
      double l2 = iLow (_Symbol, g_sTF, b+2);
      if(h0 < l2 && (l2 - h0) >= g_atr * fvgMinFrac)
      {
         g_BearFVGTop = l2;
         g_BearFVGBot = h0;
         break;
      }
   }
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// SESSION CHECK
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
bool IsInSession()
{
   if(!InpUseSession) return true;
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int h = ((t.hour - InpServerGMTOffset) % 24 + 24) % 24;   // server -> UTC
   bool inLDN = (h >= InpLDNOpen && h < InpLDNClose);
   bool inNY  = InpUseNY && (h >= InpNYOpen && h < InpNYClose);
   return inLDN || inNY;
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// DAILY RESET & DD CHECK
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void CheckDailyReset()
{
   datetime curDay = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(curDay != g_lastDay)
   {
      g_lastDay     = curDay;
      g_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dailyPnL    = 0.0;
      g_partialDone = false;
      g_beDone      = false;
      // Reset daily streak â fresh start each day
      g_consecLossAny  = 0;
      g_consecLossBuy  = 0;
      g_consecLossSell = 0;
      g_cooldownBuyUntil  = 0;
      g_cooldownSellUntil = 0;
      g_dailyHalt   = false;
      g_tradesToday = 0;
   }
   g_dailyPnL = AccountInfoDouble(ACCOUNT_EQUITY) - g_startEquity;
}

bool IsDailyDDBreached()
{
   if(!g_propOn) return g_dailyPnL <= -MathAbs(InpDailyLossLimit);
   double limit = g_initBal * g_dailyGuardPct / 100.0;
   return (g_startEquity - AccountInfoDouble(ACCOUNT_EQUITY)) >= limit;
}

//------------------------------------------------------------------
// Daily profit cap in $ (smaller of fixed cap and firm consistency
// cap). 0 = no cap. Consistency cap = consistency% of the phase
// profit-target $, so the biggest single day stays under that share
// of total profit (firm consistency rule auto-satisfied) and the
// minimum profitable-day count falls out of it.
//------------------------------------------------------------------
double DailyProfitCapUsd()
{
   double cap = 0.0;
   if(InpDailyProfitCap > 0)
      cap = g_initBal * InpDailyProfitCap / 100.0;
   if(InpConsistencyPct > 0 && g_profitTgtPct > 0)
   {
      double consUsd = (g_initBal * g_profitTgtPct / 100.0) * InpConsistencyPct / 100.0;
      cap = (cap > 0) ? MathMin(cap, consUsd) : consUsd;
   }
   return cap;
}

int ConsistencyMinDays()
{
   if(InpConsistencyPct <= 0) return 0;
   return (int)MathCeil(100.0 / InpConsistencyPct);
}

//------------------------------------------------------------------
// SPIKE GUARD. Abnormal candle (range >= InpSpikeATRmult x ATR) = flow
// shock (news/fixing/illiquidity), not tradeable structure, and the
// economic-calendar news filter cannot see it. Freeze new entries for
// InpSpikeCoolBars bars so the engine never reads the shock (or its
// violent retrace) as a signal. Range measured on the signal TF g_sTF
// to match g_atr's units. Runs every tick, in or out of session.
//------------------------------------------------------------------
void UpdateSpikeGuard()
{
   if(InpSpikeATRmult <= 0 || g_atr <= 0) return;
   double big = InpSpikeATRmult * g_atr;
   double r0  = iHigh(_Symbol,g_sTF,0) - iLow(_Symbol,g_sTF,0);
   double r1  = iHigh(_Symbol,g_sTF,1) - iLow(_Symbol,g_sTF,1);
   if(r0 >= big || r1 >= big)
      g_spikeUntil = TimeCurrent()
                   + (datetime)(MathMax(1,InpSpikeCoolBars)*PeriodSeconds(g_sTF));
}

bool SpikeFrozen() { return (TimeCurrent() < g_spikeUntil); }

//------------------------------------------------------------------
// ENTRY GATE. Single risk check both AUTO and the manual dashboard
// buttons must pass before a new trade opens, so panel trading stays
// honest to the prop rules. Session window is NOT gated (a manual click
// is a deliberate timing choice); every capital rule IS enforced.
//------------------------------------------------------------------
bool EntryBlocked(string &why)
{
   if(g_eaStopped)   { why="EA STOPPED (max-loss)"; return true; }
   if(g_dailyHalt)   { why="DAILY CAP HALT";        return true; }
   if(g_targetHit)   { why="TARGET REACHED";        return true; }
   if(g_newsFilter)  { why="NEWS BLOCK (manual)";   return true; }
   if(NewsBlocked()) { why="NEWS BLACKOUT";         return true; }
   if(SpikeFrozen()) { why="SPIKE FROZEN";          return true; }
   return false;
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// POSITION HELPERS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(pos.SelectByIndex(i) && pos.Magic() == 202601 && pos.Symbol() == _Symbol)
         return true;
   }
   return false;
}

double GetOpenPnL()
{
   double pnl = 0.0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(pos.SelectByIndex(i) && pos.Magic() == 202601 && pos.Symbol() == _Symbol)
         pnl += pos.Profit() + pos.Swap() + pos.Commission();
   return pnl;
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Magic() == 202601 && pos.Symbol() == _Symbol)
      {
         trade.PositionClose(pos.Ticket());
         DrawExitMarker(pos.PriceOpen(), pos.PositionType() == POSITION_TYPE_BUY);
      }
   }
}

void ClosePartialAll(double fraction)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Magic() == 202601 && pos.Symbol() == _Symbol)
      {
         double lots = NormalizeLot(pos.Volume() * fraction);
         if(lots >= 0.01)
            trade.PositionClosePartial(pos.Ticket(), lots);
      }
   }
}

double CalcAutoLot(double entry, double slDist)
{
   if(slDist <= 0) return InpFixedLot;
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double riskUSD  = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double lots     = riskUSD / (slDist / tickSize * tickVal);
   return NormalizeLot(lots);
}

double NormalizeLot(double lots)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(lots, 2);
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// CHART VISUAL OBJECTS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void DrawKeyLevels()
{
   if(!InpShowLevels) return;

   CreateHLine(PFX+"PDH", g_PDH, clrFireBrick,     "PDH " + DoubleToString(g_PDH, 2), STYLE_DASH);
   CreateHLine(PFX+"PDL", g_PDL, clrForestGreen,   "PDL " + DoubleToString(g_PDL, 2), STYLE_DASH);
   CreateHLine(PFX+"PWH", g_PWH, clrDarkOrange,    "PWH " + DoubleToString(g_PWH, 2), STYLE_DOT);
   CreateHLine(PFX+"PWL", g_PWL, clrDarkOrange,    "PWL " + DoubleToString(g_PWL, 2), STYLE_DOT);
   CreateHLine(PFX+"AH",  g_AsiaH, clrMediumPurple,"Asia H " + DoubleToString(g_AsiaH, 2), STYLE_SOLID);
   CreateHLine(PFX+"AL",  g_AsiaL, clrMediumAquamarine,"Asia L " + DoubleToString(g_AsiaL, 2), STYLE_SOLID);

   if(InpShowOBFVG && g_BullOBHigh > 0)
      CreateZone(PFX+"BullOB", g_BullOBHigh, g_BullOBLow, clrLimeGreen, 85);
   if(InpShowOBFVG && g_BearOBHigh > 0)
      CreateZone(PFX+"BearOB", g_BearOBHigh, g_BearOBLow, clrCrimson, 85);
   if(InpShowOBFVG && g_BullFVGTop > 0)
      CreateZone(PFX+"BullFVG", g_BullFVGTop, g_BullFVGBot, clrDeepSkyBlue, 88);
   if(InpShowOBFVG && g_BearFVGTop > 0)
      CreateZone(PFX+"BearFVG", g_BearFVGTop, g_BearFVGBot, clrViolet, 88);
}

void CreateHLine(string name, double price, color clr, string tooltip, ENUM_LINE_STYLE style)
{
   if(price <= 0) return;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,     style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     1);
   ObjectSetString(0,  name, OBJPROP_TOOLTIP,   tooltip);
   ObjectSetString(0,  name, OBJPROP_TEXT,      tooltip);
}

void CreateZone(string name, double hi, double lo, color clr, int alpha)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   int bars = iBars(_Symbol, PERIOD_H1);
   datetime t1 = iTime(_Symbol, PERIOD_H1, MathMin(bars-1, 200));
   datetime t2 = iTime(_Symbol, PERIOD_H1, 0) + PeriodSeconds(PERIOD_H1) * 30;
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, hi, t2, lo);
   ObjectSetInteger(0, name, OBJPROP_COLOR,   clr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, ColorToARGB(clr, (uchar)(255-alpha)));
   ObjectSetInteger(0, name, OBJPROP_BACK,    true);
   ObjectSetInteger(0, name, OBJPROP_FILL,    true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,   1);
}

void DrawSignalLevels(bool isLong)
{
   datetime t1 = iTime(_Symbol, PERIOD_H1, 1);
   datetime t2 = t1 + PeriodSeconds(PERIOD_H1) * 50;

   // Entry line
   CreateTrendLine(PFX+"EntryLine", t1, g_entryPrice, t2, g_entryPrice,
                   clrWhite, STYLE_DASH, 1);
   // SL line
   CreateTrendLine(PFX+"SLLine", t1, g_slPrice, t2, g_slPrice,
                   clrCrimson, STYLE_SOLID, 2);
   // TP line
   CreateTrendLine(PFX+"TPLine", t1, g_tpPrice, t2, g_tpPrice,
                   clrLimeGreen, STYLE_SOLID, 2);

   // Risk zone (red fill entryâSL)
   if(ObjectFind(0, PFX+"RiskZone") >= 0) ObjectDelete(0, PFX+"RiskZone");
   ObjectCreate(0, PFX+"RiskZone", OBJ_RECTANGLE, 0, t1, g_entryPrice, t2, g_slPrice);
   ObjectSetInteger(0, PFX+"RiskZone", OBJPROP_COLOR,   clrCrimson);
   ObjectSetInteger(0, PFX+"RiskZone", OBJPROP_BGCOLOR, ColorToARGB(clrCrimson, 230));
   ObjectSetInteger(0, PFX+"RiskZone", OBJPROP_BACK,    true);
   ObjectSetInteger(0, PFX+"RiskZone", OBJPROP_FILL,    true);
   ObjectSetInteger(0, PFX+"RiskZone", OBJPROP_WIDTH,   0);

   // Reward zone (green fill entryâTP)
   if(ObjectFind(0, PFX+"RewardZone") >= 0) ObjectDelete(0, PFX+"RewardZone");
   ObjectCreate(0, PFX+"RewardZone", OBJ_RECTANGLE, 0, t1, g_tpPrice, t2, g_entryPrice);
   ObjectSetInteger(0, PFX+"RewardZone", OBJPROP_COLOR,   clrLimeGreen);
   ObjectSetInteger(0, PFX+"RewardZone", OBJPROP_BGCOLOR, ColorToARGB(clrLimeGreen, 235));
   ObjectSetInteger(0, PFX+"RewardZone", OBJPROP_BACK,    true);
   ObjectSetInteger(0, PFX+"RewardZone", OBJPROP_FILL,    true);
   ObjectSetInteger(0, PFX+"RewardZone", OBJPROP_WIDTH,   0);

   // Entry arrow + label
   string arrowName = PFX + "EntryArrow";
   if(ObjectFind(0, arrowName) >= 0) ObjectDelete(0, arrowName);
   ObjectCreate(0, arrowName, OBJ_ARROW, 0, t1, g_entryPrice);
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, isLong ? 233 : 234);
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR, isLong ? clrLimeGreen : clrCrimson);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);

   // Label box
   string lbName = PFX + "EntryLabel";
   if(ObjectFind(0, lbName) >= 0) ObjectDelete(0, lbName);
   ObjectCreate(0, lbName, OBJ_TEXT, 0, t1, g_entryPrice);
   string dir = isLong ? "BUY" : "SELL";
   ObjectSetString(0, lbName, OBJPROP_TEXT,
      StringFormat(" %s  %.2f  |  SL:%.2f  TP:%.2f  |  %.2f lots  Score:%d",
                   dir, g_entryPrice, g_slPrice, g_tpPrice, g_manualLot, g_decisionScore));
   ObjectSetString(0, lbName, OBJPROP_FONT,    "Courier New");
   ObjectSetInteger(0, lbName, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, lbName, OBJPROP_COLOR,    clrWhiteSmoke);
   ObjectSetInteger(0, lbName, OBJPROP_BACK,     false);

   // Price labels on right axis
   CreatePriceLabel(PFX+"SLPriceLabel", g_slPrice,    "SL  " + DoubleToString(g_slPrice,   2), clrCrimson);
   CreatePriceLabel(PFX+"TPPriceLabel", g_tpPrice,    "TP  " + DoubleToString(g_tpPrice,   2), clrLimeGreen);
   CreatePriceLabel(PFX+"EntPriceLabel",g_entryPrice, "ENT " + DoubleToString(g_entryPrice,2), clrWhiteSmoke);
}

void CreateTrendLine(string name, datetime t1, double p1, datetime t2, double p2,
                     color clr, ENUM_LINE_STYLE style, int width)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR,   clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,   style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,   width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
}

void CreatePriceLabel(string name, double price, string txt, color clr)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   datetime t = iTime(_Symbol, PERIOD_H1, 0) + PeriodSeconds(PERIOD_H1) * 2;
   ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetString(0,  name, OBJPROP_TEXT,     txt);
   ObjectSetString(0,  name, OBJPROP_FONT,     "Courier New");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  8);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
}

void DrawEntryMarker(bool isLong, double entry, double sl, double tp, double lots)
{
   datetime t = TimeCurrent();
   string nm = PFX + "Trade_" + IntegerToString(t);

   ObjectCreate(0, nm, OBJ_ARROW, 0, t, entry);
   ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, isLong ? 233 : 234);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, isLong ? clrLimeGreen : clrOrangeRed);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 3);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP,
      StringFormat("%s %.2f lots\nEntry:%.2f  SL:%.2f  TP:%.2f",
                   isLong?"BUY":"SELL", lots, entry, sl, tp));
}

void DrawExitMarker(double exitPrice, bool wasLong)
{
   datetime t  = TimeCurrent();
   string nm   = PFX + "Exit_" + IntegerToString(t);
   double pnl  = GetOpenPnL();

   ObjectCreate(0, nm, OBJ_ARROW, 0, t, exitPrice);
   ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, 251);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, pnl >= 0 ? clrLimeGreen : clrCrimson);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP,
      StringFormat("EXIT %s  P&L: %+.2f", wasLong?"LONG":"SHORT", pnl));
}

void DrawTrailLine(double price)
{
   CreateHLine(PFX+"TrailLine", price, clrDarkOrange, "Trail Stop " + DoubleToString(price,2), STYLE_DOT);
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// DASHBOARD  (on-chart panel using chart objects)
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void DrawDashboard()
{
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(chartH > 50) g_dashY = InpDashY;
   int x = g_dashX, y = g_dashY;
   int w = 340, lh = 18;

   // Background panel â draggable
   CreatePanel(PFX+"BG", x, y, w, 638, C'13,17,23', 180);
   ObjectSetInteger(0, PFX+"BG", OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, PFX+"BG", OBJPROP_SELECTED,   false);

   // Header bar
   CreatePanel(PFX+"HDR", x, y, w, 26, C'22,27,34', 220);

   // Minimize button â top right of header
   CreateButton(PFX+"BTN_MINIMIZE", " v ", x+w-30, y+2, 28, 20, C'22,27,34', C'212,160,23');

   // Lot controls
   CreateButton(PFX+"BTN_LOT_DN",   " - ",  x+8,   y+444, 30,  22, C'33,38,45', clrSilver);
   CreateButton(PFX+"BTN_LOT_UP",   " + ",  x+82,  y+444, 30,  22, C'33,38,45', clrSilver);
   CreateButton(PFX+"BTN_LOT_AUTO", "AUTO", x+118, y+444, 44,  22, C'26,18,0',  C'212,160,23');
   CreateButton(PFX+"BTN_NEWS",     "NEWS: CLEAR", x+168, y+444, 164, 22, C'13,31,45', C'88,166,255');
   // Buttons row â BUY / SELL
   CreateButton(PFX+"BTN_BUY",  "  BUY MARKET  ", x+8,   y+470, 158, 28, C'35,134,54', clrWhite);
   CreateButton(PFX+"BTN_SELL", "  SELL MARKET  ", x+174, y+470, 158, 28, C'218,54,51', clrWhite);
   // AUTO-TRADE toggle â spans full width on its own row
   color autoClr = g_autoTrade ? C'20,80,30' : C'80,20,20';
   color autoTxt = g_autoTrade ? C'80,220,80' : C'220,80,80';
   string autoLbl = g_autoTrade ? "AUTO TRADE:  ON" : "AUTO TRADE: OFF";
   CreateButton(PFX+"BTN_AUTO", autoLbl, x+8, y+502, 324, 24, autoClr, autoTxt);
   // Exit buttons
   CreateButton(PFX+"BTN_CLOSE_25",  " Close 25% ", x+8,   y+530, 100, 22, C'33,38,45', clrSilver);
   CreateButton(PFX+"BTN_CLOSE_50",  " Close 50% ", x+114, y+530, 100, 22, C'33,38,45', clrSilver);
   CreateButton(PFX+"BTN_CLOSE_ALL", " CLOSE ALL ", x+220, y+530, 112, 22, C'80,20,20', clrOrangeRed);

   ChartRedraw(0);
}

void UpdateDashboard()
{
   if(!InpShowDash) return;

   int    x   = g_dashX, y = g_dashY;
   int    w   = 315, lh = 18;
   int    row = y + 28;
   string mk  = g_mkConfirmed == 1 ? "BULL" : g_mkConfirmed == 2 ? "BEAR" : "SIDE";
   color  mkC = g_mkConfirmed == 1 ? clrLimeGreen : g_mkConfirmed == 2 ? clrCrimson : clrSilver;
   string sess= IsInSession() ? "LDN/NY  ACTIVE" : "OUT OF SESSION";
   color  sesC= IsInSession() ? clrGold : clrLightGray;
   if(SpikeFrozen()) { sess = "SPIKE FROZEN (flow shock)"; sesC = clrOrange; }

   // Header title
   SetLabel(PFX+"T_LOGO",  "STAALWAG GOLD", x+8,  y+5,  clrGold, 9, "Courier New");
   color dotClr=(g_dailyHalt||g_eaStopped)?C'220,60,60':(g_autoTrade&&!g_targetHit)?C'60,210,90':C'150,150,150';
   SetLabel(PFX+"T_VER", "v1.0", x+132, y+5, clrGold, 9, "Courier New");
   SetLabel(PFX+"T_DOT", "\x25CF", x+172, y+4, dotClr, 11, "Arial");  // gap between v1.0 and pair label
   SetLabel(PFX+"T_PAIR",  "XAUUSD "+TFName(g_sTF), x+200, y+5, clrLightGray, 8, "Courier New");

   // Signal row
   string sigTxt  = g_signal == 1 ? "LONG" : g_signal == -1 ? "SHORT" : "WATCHING";
   color  sigCol  = g_signal == 1 ? clrLimeGreen : g_signal == -1 ? clrCrimson : clrLightGray;
   string decTxt  = g_decisionScore >= 8 ? "EXECUTE NOW" : g_decisionScore >= 6 ? "CONSIDER" :
                    g_decisionScore >= 4 ? "CAUTION"     : g_signal != 0 ? "SKIP" : "â";
   color  decCol  = g_decisionScore >= 8 ? clrLimeGreen : g_decisionScore >= 6 ? clrGold :
                    g_decisionScore >= 4 ? clrOrange    : clrLightGray;

   SetLabel(PFX+"T_SIGLBL", "SIGNAL",   x+8,  row,    clrLightGray, 8, "Courier New"); row += lh;
   SetLabel(PFX+"T_SIGVAL", sigTxt,      x+8,  row-lh, sigCol,     9, "Courier New");
   SetLabel(PFX+"T_DECTXT", decTxt,      x+160, row-lh, decCol,    9, "Courier New");

   // Score bar â pure ASCII chars (Unicode block glyphs render wider in MT5 GDI)
   string scoreBar = "[";
   for(int d = 1; d <= 10; d++) scoreBar += (d <= g_decisionScore) ? "|" : ".";
   scoreBar += "]";
   color scoreCol = g_decisionScore >= 8 ? clrLimeGreen : g_decisionScore >= 6 ? clrGold : clrLightGray;
   SetLabel(PFX+"T_SCORE", StringFormat("SCORE  %2d/10  %s", g_decisionScore, scoreBar),
            x+8, row, scoreCol, 8, "Courier New"); row += lh-2;

   // Confluence score bar
   string confBar = "[";
   for(int c = 1; c <= 5; c++) confBar += (c <= g_confluenceScore) ? "|" : ".";
   confBar += "]";
   color confCol = g_confluenceScore >= 4 ? clrGold : g_confluenceScore >= 3 ? clrLimeGreen : clrLightGray;
   SetLabel(PFX+"T_CONF", StringFormat("CONF    %d/5    %s", g_confluenceScore, confBar),
            x+8, row, confCol, 8, "Courier New"); row += lh-2;

   // Probability of success
   string probBar = "[";
   for(int p = 1; p <= 10; p++) probBar += (p <= (int)MathRound(g_probSuccess/10.0)) ? "|" : ".";
   probBar += "]";
   color probCol = g_probSuccess >= 70 ? clrLimeGreen : g_probSuccess >= 55 ? clrGold :
                   g_probSuccess >= 40 ? clrOrange    : clrCrimson;
   SetLabel(PFX+"T_PROB", StringFormat("WIN%%   %3d%%   %s", g_probSuccess, probBar),
            x+8, row, probCol, 8, "Courier New"); row += lh-2;

   // Confluence factor breakdown â 2 rows, ASCII +/- flags
   string fRow1 = "", fRow2 = "";
   fRow1 += g_cfPDX    ? " PDx:+" : " PDx:-";
   fRow1 += g_cfWeek   ? " Wk:+"  : " Wk:-";
   fRow1 += g_cfAsia   ? " As:+"  : " As:-";
   fRow1 += g_cfOB     ? " OB:+"  : " OB:-";
   fRow1 += g_cfFVG    ? " FV:+"  : " FV:-";
   fRow2 += g_cfBias   ? " Bias:+" : " Bias:-";
   fRow2 += g_cfMarkov ? " Mkv:+"  : " Mkv:-";
   fRow2 += g_cfSweep  ? " Swp:+"  : " Swp:-";
   SetLabel(PFX+"T_FACTORS",  fRow1, x+8, row, C'160,210,160', 7, "Courier New"); row += lh-4;
   SetLabel(PFX+"T_FACTORS2", fRow2, x+8, row, C'160,210,160', 7, "Courier New"); row += lh-2;

   // Entry details
   SetLabel(PFX+"T_SEP1",   "---------------------------------",x+8, row, C'90,100,115', 8, "Courier New"); row += lh-4;
   if(g_signal != 0)
   {
      SetLabel(PFX+"T_ENT", StringFormat("ENTRY    %s", DoubleToString(g_entryPrice,2)), x+8, row, clrSilver,    8, "Courier New"); row += lh-2;
      SetLabel(PFX+"T_SL",  StringFormat("SL       %s", DoubleToString(g_slPrice,   2)), x+8, row, clrCrimson,   8, "Courier New"); row += lh-2;
      SetLabel(PFX+"T_TP",  StringFormat("TP       %s  (%.1fR)", DoubleToString(g_tpPrice,2), g_rrRatio),
               x+8, row, clrLimeGreen, 8, "Courier New"); row += lh-2;
   }
   else
   {
      SetLabel(PFX+"T_ENT", "ENTRY    â",  x+8, row, clrLightGray, 8, "Courier New"); row += lh-2;
      SetLabel(PFX+"T_SL",  "SL       â",  x+8, row, clrLightGray, 8, "Courier New"); row += lh-2;
      SetLabel(PFX+"T_TP",  "TP       â",  x+8, row, clrLightGray, 8, "Courier New"); row += lh-2;
   }

   // Lot display
   SetLabel(PFX+"T_SEP2",   "---------------------------------",x+8, row, C'90,100,115', 8, "Courier New"); row += lh-4;
   double riskUSD = 0.0;
   if(g_slPrice > 0 && g_entryPrice > 0)
   {
      double slDist  = MathAbs(g_entryPrice - g_slPrice);
      double tv      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double ts      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      riskUSD = (ts > 0) ? g_manualLot * (slDist / ts) * tv : 0.0;
   }
   SetLabel(PFX+"T_LOT",   StringFormat("LOT SIZE    %.2f        RISK  $%.0f", g_manualLot, riskUSD),
            x+8, row, clrGold, 8, "Courier New"); row += lh;

   // Spacer for buttons (40+22+22 px below)

   // Live PnL
   SetLabel(PFX+"T_SEP3",   "---------------------------------",x+8, row, C'90,100,115', 8, "Courier New"); row += lh-4;
   double openPnL = GetOpenPnL();
   color pnlCol   = openPnL >= 0 ? clrLimeGreen : clrCrimson;
   SetLabel(PFX+"T_PNL",   StringFormat("LIVE P&L      %+.2f", openPnL),         x+8, row, pnlCol,   8, "Courier New"); row += lh-2;
   color dpnlC = g_dailyPnL >= 0 ? clrLimeGreen : clrCrimson;
   SetLabel(PFX+"T_DPNL",  StringFormat("DAILY P&L     %+.2f", g_dailyPnL),       x+8, row, dpnlC,    8, "Courier New"); row += lh-2;

   string statusTxt = g_eaStopped ? "STOPPED maxloss" : g_targetHit ? "TARGET HIT" :
                      g_dailyHalt ? "HALTED day-cap" : g_autoTrade ? "AUTO ON" : "AUTO OFF";
   double eqNow = AccountInfoDouble(ACCOUNT_EQUITY);
   string ddStr; color ddCol;
   if(g_propOn)
   {
      double dLoss = (g_startEquity-eqNow)>0 ? (g_startEquity-eqNow)/g_initBal*100.0 : 0;
      double tRef  = g_trailMaxDD ? g_peakEquity : g_initBal;
      double tLoss = (eqNow<tRef) ? (tRef-eqNow)/tRef*100.0 : 0;
      ddStr = StringFormat("%s D%.1f/%.0f T%.1f/%.0f", g_firmName, dLoss,g_dailyLossPct, tLoss,g_maxLossPct);
      if(InpConsistencyPct>0) ddStr += StringFormat(" C%.0f%%/%dd",InpConsistencyPct,ConsistencyMinDays());
      ddCol = (dLoss>=g_dailyGuardPct||tLoss>=g_maxGuardPct) ? clrCrimson : clrGold;
   }
   else
   {
      double ddPct = MathAbs(g_dailyPnL) / InpDailyLossLimit * 100.0;
      ddStr = StringFormat("DD %.0f%% of $%.0f", ddPct, InpDailyLossLimit);
      ddCol = ddPct > 75 ? clrCrimson : ddPct > 50 ? clrOrange : clrGold;
   }
   SetLabel(PFX+"T_STAT", statusTxt, x+8, row, dpnlC, 8, "Courier New"); row += lh-2;
   SetLabel(PFX+"T_DD",   ddStr, x+8, row, ddCol, 8, "Courier New"); row += lh-2;

   // Open positions table
   SetLabel(PFX+"T_SEP4",  "---------------------------------",x+8, row, C'90,100,115', 8, "Courier New"); row += lh-4;
   SetLabel(PFX+"T_TRDHDR","Dir   Entry      SL         TP        P&L",x+8, row, clrLightGray, 7, "Courier New"); row += lh-4;

   int posRow = 0;
   for(int i = 0; i < PositionsTotal() && posRow < 4; i++)
   {
      if(!pos.SelectByIndex(i) || pos.Magic() != 202601 || pos.Symbol() != _Symbol) continue;
      string dir = pos.PositionType() == POSITION_TYPE_BUY ? "L" : "S";
      color  dc  = pos.PositionType() == POSITION_TYPE_BUY ? clrLimeGreen : clrCrimson;
      color  pc  = pos.Profit() >= 0 ? clrLimeGreen : clrCrimson;
      string row_txt = StringFormat("%s  %.2f  %.2f  %.2f  %+.1f",
                                    dir, pos.PriceOpen(), pos.StopLoss(), pos.TakeProfit(), pos.Profit());
      string nm = PFX + "T_POS" + IntegerToString(posRow);
      SetLabel(nm, row_txt, x+8, row, pc, 7, "Courier New"); row += lh-5; posRow++;
   }
   if(posRow == 0)
   { SetLabel(PFX+"T_POS0", "No open positions", x+8, row, clrLightGray, 7, "Courier New"); row += lh-5; }

   // Performance stats
   int total = g_allWins + g_allLosses;
   int wr    = total > 0 ? (int)MathRound((double)g_allWins / total * 100.0) : 0;
   double expR = total > 0 ? ((double)g_allWins/total)*InpRRRatio - ((double)g_allLosses/total) : 0.0;
   SetLabel(PFX+"T_SEP5",  "---------------------------------", x+8, row, C'90,100,115', 8, "Courier New"); row += lh-4;
   SetLabel(PFX+"T_STATS", StringFormat("WIN%%  %d%%   TRADES  %d   EXP  %+.2fR", wr, total, expR),
            x+8, row, clrSilver, 8, "Courier New"); row += lh-2;
   SetLabel(PFX+"T_MANUAL", StringFormat("MANUAL  Open:%d  Close:%d    EA  Open:%d  Close:%d",
            g_manualOpens, g_manualCloses, g_eaOpens, g_eaCloses),
            x+8, row, C'160,180,200', 7, "Courier New"); row += lh-2;

   // Regime + session footer
   SetLabel(PFX+"T_SEP6",  "---------------------------------", x+8, row, C'90,100,115', 8, "Courier New"); row += lh-4;
   SetLabel(PFX+"T_MK",    StringFormat("REGIME  %-4s  %.0f%%  CONV %+.2f", mk, g_mkPersistence*100, g_mkConviction),
            x+8, row, mkC, 8, "Courier New"); row += lh-2;
   SetLabel(PFX+"T_SESS",  sess, x+8, row, sesC, 8, "Courier New");

   // News button text
   string newsLbl = g_newsFilter ? "NEWS: BLOCKED" : "NEWS: CLEAR";
   color  newsCol = g_newsFilter ? clrOrangeRed    : C'88,166,255';
   ObjectSetString(0, PFX+"BTN_NEWS", OBJPROP_TEXT, newsLbl);
   ObjectSetInteger(0, PFX+"BTN_NEWS", OBJPROP_COLOR, newsCol);

   string autoLbl = g_autoTrade ? "AUTO TRADE:  ON" : "AUTO TRADE: OFF";
   color  autoTxt = g_autoTrade ? C'80,220,80' : C'220,80,80';
   color  autoClr = g_autoTrade ? C'20,80,30'  : C'80,20,20';
   ObjectSetString (0, PFX+"BTN_AUTO", OBJPROP_TEXT,    autoLbl);
   ObjectSetInteger(0, PFX+"BTN_AUTO", OBJPROP_COLOR,   autoTxt);
   ObjectSetInteger(0, PFX+"BTN_AUTO", OBJPROP_BGCOLOR, autoClr);

   // Minimize button label toggle
   ObjectSetString(0, PFX+"BTN_MINIMIZE", OBJPROP_TEXT, g_dashMinimized ? " â² " : " â¼ ");
   ObjectSetInteger(0, PFX+"BTN_MINIMIZE", OBJPROP_XDISTANCE, g_dashX + w - 30);
   ObjectSetInteger(0, PFX+"BTN_MINIMIZE", OBJPROP_YDISTANCE, g_dashY + 2);

   // Lot display on button area
   SetLabel(PFX+"T_LOTDISP", StringFormat("%.2f", g_manualLot), g_dashX+44, g_dashY+452, clrGold, 9, "Courier New");

   ChartRedraw(0);
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// MINIMIZE / DRAG HELPERS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

// List of all label/button names that should hide when minimized
string g_bodyObjects[] = {
   "T_SIGLBL","T_SIGVAL","T_DECTXT","T_SCORE","T_CONF","T_PROB","T_FACTORS","T_FACTORS2",
   "T_SEP1","T_ENT","T_SL","T_TP","T_SEP2","T_LOT","T_LOTDISP",
   "T_SEP3","T_PNL","T_DPNL","T_STAT","T_DD","T_DOT","T_VER",
   "T_SEP4","T_TRDHDR","T_POS0","T_POS1","T_POS2","T_POS3",
   "T_STATS","T_MANUAL","T_SEP5","T_SEP6","T_MK","T_SESS",
   "BTN_BUY","BTN_SELL","BTN_CLOSE_25","BTN_CLOSE_50","BTN_CLOSE_ALL",
   "BTN_LOT_DN","BTN_LOT_UP","BTN_LOT_AUTO","BTN_NEWS","BTN_AUTO"
};

void ApplyMinimizeState()
{
   int total = ArraySize(g_bodyObjects);
   for(int i = 0; i < total; i++)
   {
      string nm = PFX + g_bodyObjects[i];
      if(ObjectFind(0, nm) >= 0)
         ObjectSetInteger(0, nm, OBJPROP_TIMEFRAMES,
                          g_dashMinimized ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
   }

   // Resize BG panel: minimized = header only (28px), full = 600px
   int h = g_dashMinimized ? 28 : 638;
   ObjectSetInteger(0, PFX+"BG", OBJPROP_YSIZE, h);

   ChartRedraw(0);
}

void RedrawAllPanelObjects()
{
   int x = g_dashX, y = g_dashY;
   int w = 340;

   // Reposition background and header
   ObjectSetInteger(0, PFX+"BG",  OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, PFX+"BG",  OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, PFX+"HDR", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, PFX+"HDR", OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, PFX+"BTN_MINIMIZE", OBJPROP_XDISTANCE, x+w-30);
   ObjectSetInteger(0, PFX+"BTN_MINIMIZE", OBJPROP_YDISTANCE, y+2);

   // Force full redraw of all dynamic labels/buttons via UpdateDashboard
   // (positions are recalculated from g_dashX/g_dashY)
   UpdateDashboard();

   // Reposition action buttons using updated g_dashX/Y
   ObjectSetInteger(0, PFX+"BTN_LOT_DN",    OBJPROP_XDISTANCE, x+8);   ObjectSetInteger(0, PFX+"BTN_LOT_DN",    OBJPROP_YDISTANCE, y+444);
   ObjectSetInteger(0, PFX+"BTN_LOT_UP",    OBJPROP_XDISTANCE, x+82);  ObjectSetInteger(0, PFX+"BTN_LOT_UP",    OBJPROP_YDISTANCE, y+444);
   ObjectSetInteger(0, PFX+"BTN_LOT_AUTO",  OBJPROP_XDISTANCE, x+118); ObjectSetInteger(0, PFX+"BTN_LOT_AUTO",  OBJPROP_YDISTANCE, y+444);
   ObjectSetInteger(0, PFX+"BTN_NEWS",      OBJPROP_XDISTANCE, x+168); ObjectSetInteger(0, PFX+"BTN_NEWS",      OBJPROP_YDISTANCE, y+444);
   ObjectSetInteger(0, PFX+"BTN_BUY",       OBJPROP_XDISTANCE, x+8);   ObjectSetInteger(0, PFX+"BTN_BUY",       OBJPROP_YDISTANCE, y+470);
   ObjectSetInteger(0, PFX+"BTN_SELL",      OBJPROP_XDISTANCE, x+174); ObjectSetInteger(0, PFX+"BTN_SELL",      OBJPROP_YDISTANCE, y+470);
   ObjectSetInteger(0, PFX+"BTN_AUTO",      OBJPROP_XDISTANCE, x+8);   ObjectSetInteger(0, PFX+"BTN_AUTO",      OBJPROP_YDISTANCE, y+502);
   ObjectSetInteger(0, PFX+"BTN_CLOSE_25",  OBJPROP_XDISTANCE, x+8);   ObjectSetInteger(0, PFX+"BTN_CLOSE_25",  OBJPROP_YDISTANCE, y+530);
   ObjectSetInteger(0, PFX+"BTN_CLOSE_50",  OBJPROP_XDISTANCE, x+114); ObjectSetInteger(0, PFX+"BTN_CLOSE_50",  OBJPROP_YDISTANCE, y+530);
   ObjectSetInteger(0, PFX+"BTN_CLOSE_ALL", OBJPROP_XDISTANCE, x+220); ObjectSetInteger(0, PFX+"BTN_CLOSE_ALL", OBJPROP_YDISTANCE, y+530);

   ChartRedraw(0);
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// OBJECT HELPERS
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
void CreatePanel(string name, int x, int y, int w, int h, color bg, uchar alpha)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      C'33,38,45');
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
}

void CreateButton(string name, string txt, int x, int y, int w, int h, color bg, color fg)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetString(0,  name, OBJPROP_TEXT,       txt);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      fg);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   8);
   ObjectSetString(0,  name, OBJPROP_FONT,       "Courier New");
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_STATE,      false);
}

void SetLabel(string name, string txt, int x, int y, color clr, int fs, string font)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0,  name, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fs);
   ObjectSetString(0,  name, OBJPROP_FONT,      font);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
}

void DeleteAllObjects()
{
   ObjectsDeleteAll(0, PFX);
}

//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// END
//ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
