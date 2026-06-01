\l core/init.q
/ ============================================================================
/ test_crude_trend.q - R24: the crudeTrend directional time-series-momentum strategy (.template.crudeTrend.*).
/ SYNTHETIC. Asserts: (1) the position state machine maps sign(trend) with a min-hold; on a TRENDING synthetic
/ the strategy goes LONG (and SHORT in a downtrend); (2) the trade is the ACTUAL contract R11's .roll.active
/ names; the run record PASSES the R13 evidence audit (all 8 checks); (3) the trend-PERSISTENCE gate BITES (a
/ mean-reverting series is rejected, a persistent/momentum one passes); (4) the trend signal is CAUSAL (a
/ planted FUTURE move does NOT change a past signal - R9's door); (5) the PASSIVE-LONG benchmark is computed
/ apples-to-apples and the ALPHA = trend - passive is correct on a known-answer (a pure uptrend -> trend ~
/ passive -> alpha ~ 0); (6) the run through .workflow.runReplay is BOUNDED (escalateToHuman, no deploy field,
/ never tradeable without all gates) and the attribution is computed (LEVEL-dominated, as expected for a
/ directional strategy). Gov-state isolation: reset the registry + restore the real card store + UNIQUE hypoIds.
/ ============================================================================
chk:{[b;msg] if[not b; '"FAIL: ",msg]};
.gov.hypoTbl:.gov.__emptyHypotheses[]; .gov.trialTbl:.gov.__emptyTrials[];
modelCards:.cfg.cards;
cfg:.cfg.strategy.crudeTrend;                                    / the PRE-REGISTERED params (lookback=60 daily)

/ ---------------------------------------------------------------------------
/ (1) POSITION STATE MACHINE (known-answer): sign(trend) with a min-hold (R18's machine, REUSED).
/ ---------------------------------------------------------------------------
upTrendSig:20#0.05;                                             / positive trend -> LONG
chk[all 1=.template.crudeCarry.__positions[upTrendSig;cfg`threshold;cfg`holdingPeriod]; "(1) a positive trend signal -> all LONG"];
downTrendSig:20#-0.05;                                          / negative trend -> SHORT
chk[all -1=.template.crudeCarry.__positions[downTrendSig;cfg`threshold;cfg`holdingPeriod]; "(1) a negative trend signal -> all SHORT (downtrend)"];

/ ---------------------------------------------------------------------------
/ (3) TREND-PERSISTENCE gate BITES: momentum (smooth, positive AR(1)) passes, mean-reversion (alternating,
/ negative AR(1)) is rejected. The gate feeds the daily $-changes (the returns the trend is built on).
/ ---------------------------------------------------------------------------
momChanges:0.05*cos 0.08*`float$til 80;                         / smooth, slowly varying -> high positive AR(1)
chk[(.template.crudeTrend.persistence[momChanges;cfg])`persistent; "(3) a PERSISTENT (momentum) change series passes the trend-persistence gate"];
mrChanges:80#0.05 -0.05f;                                       / alternating -> negative AR(1) -> mean-reverting
chk[not (.template.crudeTrend.persistence[mrChanges;cfg])`persistent; "(3) the trend-persistence gate BITES: a mean-reverting change series is rejected"];

/ ---------------------------------------------------------------------------
/ Synthetic HDB-backed TRENDING futures (daily dates, monthly SYNT contracts): a global momentum price level
/ (monotone up, smoothly-varying positive daily increments -> positive AR(1) of changes) + a mild contango;
/ the active (front) contract's price trends UP -> a positive trailing-return trend -> the strategy goes LONG.
/ ---------------------------------------------------------------------------
mexp:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".25"};
dts:2019.06.01+til 520;                                         / ~17 months of daily dates
yms:raze {[y] (y*100)+1+til 12} each 2019 2020;                / monthly contracts
eY:mexp each yms; yms:yms where (eY>(first dts)-1) and eY<(last dts)+40;
nD:count dts;
gIncr:0.05+0.04*sin 0.03*`float$til nD;                        / smooth positive daily increments (0.01..0.09)
gLevel:50f+sums gIncr;                                          / monotone uptrend
gMap:dts!gLevel;
buildT:{[ym;dts;gMap;mexp]
    e:mexp ym; rows:dts where (dts<e) and dts>e-150;           / the 150 days before expiry (the trading window)
    n:count rows; if[0=n; :()];
    m2e:{[e;d] `int$(`month$e)-`month$d}[e] each rows;
    px:(gMap rows)+0.2*`float$m2e;                             / global trend level + mild contango
    flip `commodity`contractYM`expiry`firstDate`date`settle`open`high`low`volume!(
        (n#`SYNT);(n#ym);(n#e);(n#first rows);rows;px;px;px;px;(n#5000))};
futures:raze buildT[;dts;gMap;mexp] each yms;
tv:.gov.zone.range[`SYNT;`trainValidate];
res:.template.crudeTrend.run `commodity`dateFrom`dateTo!(`SYNT;tv 0;tv 1);
run:(res`meta)`runRecord;

/ (1-end-to-end) on the uptrend the strategy is predominantly LONG.
chk[0<count run`steps; "(1) the run record has steps"];
chk[(sum 0<run[`steps]`position) > sum 0>run[`steps]`position; "(1) on a sustained uptrend the strategy is predominantly LONG"];

/ (2) ACTUAL CONTRACTS + the run passes the evidence audit.
rollCheck:all {[c;st] st[`activeContract]=(.roll.active[st`stepDate;c])`active}[`SYNT] each run`steps;
chk[rollCheck; "(2) every recorded activeContract == R11's .roll.active for that date (trades the actual contract)"];
aud:.evidence.audit run;
chk[aud`pass; "(2) the run record PASSES the evidence audit (all 8 checks): ",aud`reason];

/ (4) CAUSALITY: a planted FUTURE move does NOT change a PAST trend signal (R9's door, evalDates<=toD).
dMid:(.data.hdb.dates `SYNT) 250;
sig1:(.template.crudeTrend.__replay[`SYNT;0Nd;dMid;cfg])[`steps]`trendSignal;
futures:update settle:settle+30f, open:open+30f, high:high+30f, low:low+30f from futures where date>dMid;
sig2:(.template.crudeTrend.__replay[`SYNT;0Nd;dMid;cfg])[`steps]`trendSignal;
chk[sig1~sig2; "(4) causal: a planted FUTURE move does not change a past trend signal"];
futures:update settle:settle-30f, open:open-30f, high:high-30f, low:low-30f from futures where date>dMid;  / restore

/ (5) THE PASSIVE-LONG BENCHMARK + the alpha-over-beta read (THE meaningful test for a directional strategy).
bench:(res`meta)`benchmark;
chk[all `trendTotal`passiveTotal`alpha`trendSharpe`passiveSharpe`sharpeAlpha`beatsPassive in key bench; "(5) the benchmark dict carries trend vs passive PnL/Sharpe + alpha + beatsPassive"];
chk[-1h=type bench`beatsPassive; "(5) beatsPassive is a derived boolean (does timing beat holding?)"];
chk[0f<bench`passiveTotal; "(5) passive-long an uptrend makes money (positive beta)"];
chk[(abs bench`alpha) < 0.15*abs bench`passiveTotal; "(5) KNOWN-ANSWER: on a PURE UPTREND timing ~ holding -> alpha ~ 0 (the trend strategy is long ~all days, like passive)"];

/ (6) BOUNDED end-to-end loop via .workflow.runReplay + the attribution is computed (LEVEL-dominated).
prop:`hypoId`thesis`edgeSource`instruments`claimedRegimes`capName`runRecord`runner!(
    `R24_TREND_CLEAN; "crude trend (synthetic)"; `riskPremium; enlist `SYNT; `backwardation`contango`flat;
    `crudeTrend; run; .template.crudeTrend.runner[`SYNT;cfg]);
pkt:.workflow.runReplay prop;
chk[`escalateToHuman=pkt`decision; "(6) the packet ALWAYS escalates to the human"];
chk[1b=pkt`humanSignOffRequired; "(6) human sign-off is required"];
chk[not any `deploy`allocate`autoTrade in key pkt; "(6) the packet carries NO deploy/allocate/autoTrade field (bounded)"];
chk[-1h=type pkt`anyTradeable; "(6) anyTradeable is a derived boolean fact, not a decision"];
chk[`replay=pkt`mode; "(6) the packet is tagged replay mode"];
chk[all `level`slope`curvature`carry`residual in key pkt`attribution; "(6) the PnL attribution is computed on the run"];
a:pkt`attribution;
chk[(abs a`level)=max abs (a`level;a`slope;a`curvature;a`carry); "(6) LEVEL-dominated attribution - EXPECTED for a directional strategy (not a red flag)"];

/ R18 + R16 are UNTOUCHED: the crudeCarry helpers + the seasonalCalSpread template are intact + distinct.
chk[100h=type .template.crudeCarry.__positions; "R18's crudeCarry helpers are intact (reused, unchanged by R24)"];
chk[100h=type .template.scs.run; "R16's seasonalCalSpread template is intact (unchanged by R24)"];

-1 "test_crude_trend: PASS";
