\l core/init.q
/ ============================================================================
/ crude_trend.q - real-data example (NOT a test), DATA-CONDITIONAL. POST-FOUNDATION R24.
/ Run the crudeTrend DIRECTIONAL time-series-momentum strategy on real CRUDE END-TO-END through the whole
/ foundation (R9 door -> R10 curve -> R11 roll -> R12 replay -> R13 evidence audit -> R15 attribution) via
/ .workflow.runReplay, AND - the meaningful test for a directional strategy - against an apples-to-apples
/ PASSIVE-LONG-CRUDE benchmark (same period, same roll + costs). The parameters are PRE-REGISTERED
/ (.cfg.strategy.crudeTrend) and NOT tuned (the lookback is the knob momentum overfits on).
/ -
/ THE READS INVERT for a directional strategy: (a) a LEVEL-dominated attribution is EXPECTED (the thesis IS
/ directional) - NOT a red flag; (b) the absolute deflated-Sharpe gate is NOT sufficient (passive long crude
/ also has a Sharpe), so the decisive question is BENCHMARK-RELATIVE: does TIMING the directional dimension
/ (ALPHA) beat simply HOLDING it (beta)? Both outcomes are conclusive: alpha + cleared gates = the first
/ genuine edge candidate the arc has produced; no alpha and/or no gates = the directional dimension is ALSO
/ no-tradeable-edge and the strategy line is honestly concluded for this data. Skips if no HDB.
/ ============================================================================
hdbPath:.cfg.paths`hdb;
useHdb:0<count @[{[p] key hsym `$p,"/sym"};hdbPath;{[e] ()}];
if[not useHdb;
    -1 "crude_trend SKIPPED - no HDB at ",hdbPath," (run scripts/ingest_hdb.q first).";
    exit 0];
.data.hdb.open hdbPath;
if[0<count key hsym `$hdbPath,"/regimeEpisodes/"; .regime.library.open hdbPath];

comm:`CRUDE; cfg:.cfg.strategy.crudeTrend;
/ scope the audited run record to train+validate (the holdout stays sealed; gov reads it one-shot).
tv:.gov.zone.range[comm;`trainValidate];
res:.template.crudeTrend.run `commodity`dateFrom`dateTo!(comm; tv 0; tv 1);
run:(res`meta)`runRecord;
bench:(res`meta)`benchmark;
-1 "crudeTrend on ",(string comm)," (train+validate ",(string tv 0)," .. ",(string tv 1),"):";
-1 "  signal: trailing-",(string cfg`lookback),"-day cumulative return (CAUSAL); LONG when > +",(string cfg`threshold),", ",($[cfg`allowShort;"SHORT";"FLAT"])," when < -",(string cfg`threshold),", min-hold ",(string cfg`holdingPeriod)," days (PRE-REGISTERED, NOT tuned)";
-1 "  traded contract: R11's .roll.active (days_before_expiry); NET of .exec.fill cost";
-1 "  trend-PERSISTENCE gate: ",(res[`validation;`persistence])`detail;
-1 "  run record: ",(string count run`steps)," steps, replay totalPnl=",string (run`meta)`totalPnl;
-1 "";

prop:`hypoId`thesis`edgeSource`instruments`claimedRegimes`capName`runRecord`runner!(
    `crude_trend_momentum;
    "crude time-series momentum / trend-following: long when the trailing return trend is positive, short when negative; the edge must be ALPHA OVER BETA (timing), not absolute return";
    `riskPremium; enlist comm; `backwardation`contango`flat; `crudeTrend;
    run; .template.crudeTrend.runner[comm;cfg]);
pkt:.workflow.runReplay prop;

-1 "(1) The HONEST verdict (per regime bucket; gates: cost -> deflated Sharpe -> walk-forward -> sealed holdout):";
$[98h=type pkt`verdicts;
    show select bucket,nObs,verdict,failedGate,tradeable,netSharpe,dsr from pkt`verdicts;
    -1 "    ",-3!pkt`verdicts];
-1 "  anyTradeable = ",(string pkt`anyTradeable),"   (evidence audit passed = ",(string pkt`evidencePassed),")";
-1 "  regime risk-memory (a directional book is fully exposed to a directional crash): ",$[0<count pkt`riskMemory; pkt`riskMemory; "(none)"];
-1 "";

-1 "(2) PnL ATTRIBUTION (R15, units-honest per R23): is the money the directional LEVEL, as the thesis intends?";
a:pkt`attribution;
-1 "    level=",(string a`level),"  slope=",(string a`slope),"  curvature=",(string a`curvature),"  carry=",(string a`carry),"  residual=",string a`residual;
-1 "    total=",(string a`total),"  RESIDUAL FRACTION=",string a`residualFraction;
-1 "    (a LEVEL-dominated attribution is EXPECTED for a DIRECTIONAL strategy - the thesis IS directional, so";
-1 "     'the PnL is mostly level' is the strategy working, NOT a red flag. The attribution confirms the PnL is";
-1 "     the directional exposure; whether that exposure is an EDGE is the benchmark question below.)";
-1 "";

-1 "(3) *** THE MEANINGFUL TEST: ALPHA OVER BETA - does TIMING the level beat HOLDING it? ***";
-1 "    trend    : total PnL=",(string bench`trendTotal),"   Sharpe=",string bench`trendSharpe;
-1 "    passive  : total PnL=",(string bench`passiveTotal),"   Sharpe=",string bench`passiveSharpe;
-1 "    ALPHA (trend - passive) = ",(string bench`alpha),"   Sharpe alpha = ",string bench`sharpeAlpha;
-1 "    does trend BEAT passive (on Sharpe)? ",string bench`beatsPassive;
-1 "    (for a DIRECTIONAL strategy the absolute Sharpe gate is NOT sufficient - passive long crude also has a";
-1 "     Sharpe, so a strategy that merely TIMES beta can clear the bar while adding nothing. The edge, if any,";
-1 "     is the ALPHA OVER the passive-long benchmark. If trend does not beat passive, timing the directional";
-1 "     dimension is not an edge - and with the relative/structural dimensions already no-edge (R23), the";
-1 "     strategy line reaches an honest, complete conclusion for this data.)";
-1 "";

-1 "(4) The human-escalation packet:";
-1 "    decision=",(string pkt`decision),"  humanSignOffRequired=",(string pkt`humanSignOffRequired),"  stage=",string pkt`stage;
-1 "    summary: ",pkt`summary;
-1 "";
-1 "R23 showed the PnL on this data lives entirely in the DIRECTIONAL dimension; R24 is the test that decides";
-1 "the strategy line - is timing that dimension a real edge (ALPHA over the passive-long benchmark), or just";
-1 "beta? Judged net of realistic cost, deflated, through the sealed holdout, attributed (level as expected),";
-1 "and - decisively - measured against passive-long. Whatever it returns, it is honest and it is conclusive.";

exit 0;
