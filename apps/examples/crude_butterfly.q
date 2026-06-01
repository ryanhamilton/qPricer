\l core/init.q
/ ============================================================================
/ crude_butterfly.q - real-data example (NOT a test), DATA-CONDITIONAL. POST-FOUNDATION R20.
/ Fade the crude curve BUTTERFLY (curvature) END-TO-END through the WHOLE foundation (R9 door -> R10 curve
/ -> R11 roll -> R12 replay [three crude legs] -> R13 evidence audit -> R15 attribution) via
/ .workflow.runReplay, and print the HONEST verdict + the DUAL-PURPOSE attribution. A butterfly is built to
/ express CURVATURE alone, so the attribution does double duty: level + slope ~ 0 confirms the neutrality
/ CONSTRUCTION; curvature dominating (vs residual) would confirm the THESIS. The params are PRE-REGISTERED
/ (.cfg.strategy.crudeButterfly) and NOT tuned. Skips if no HDB.
/ ============================================================================
hdbPath:.cfg.paths`hdb;
useHdb:0<count @[{[p] key hsym `$p,"/sym"};hdbPath;{[e] ()}];
if[not useHdb;
    -1 "crude_butterfly SKIPPED - no HDB at ",hdbPath," (run scripts/ingest_hdb.q first).";
    exit 0];
.data.hdb.open hdbPath;
if[0<count key hsym `$hdbPath,"/regimeEpisodes/"; .regime.library.open hdbPath];

comm:`CRUDE; cfg:.cfg.strategy.crudeButterfly;
tv:.gov.zone.range[comm;`trainValidate];
res:.template.crudeButterfly.run `commodity`dateFrom`dateTo!(comm; tv 0; tv 1);
run:(res`meta)`runRecord;
-1 "crudeButterfly on ",(string comm)," (train+validate ",(string tv 0)," .. ",(string tv 1),"):";
-1 "  signal: causal z of the level/slope-neutral +1/-2/+1 fly at tenor ranks ",(-3!cfg`legRanks),"; fade beyond +-",(string cfg`entryThreshold)," (PRE-REGISTERED, NOT tuned)";
-1 "  three ACTUAL crude legs (rollBuffer ",(string cfg`rollBuffer),"), each NET of .exec.fill - a THREE-leg cost, the most demanding cost gate yet";
-1 "  butterfly-stationarity gate: ",(res[`validation;`stationarity])`detail;
-1 "  combined run record: ",(string count run`steps)," steps, ",(string count run`legs)," legs, replay totalPnl=",string (run`meta)`totalPnl;
-1 "";

prop:`hypoId`thesis`edgeSource`instruments`claimedRegimes`capName`runRecord`runner!(
    `crude_butterfly_curvature;
    "the crude curve curvature is rich/cheap vs its norm and mean-reverts; fade the level/slope-neutral butterfly (structural curvature normalisation)";
    `mispricing; enlist comm; `backwardation`contango`flat; `crudeButterfly;
    run; .template.crudeButterfly.runner[comm;cfg]);
pkt:.workflow.runReplay prop;

-1 "(1) The HONEST verdict (per regime bucket; gates: cost -> deflated Sharpe -> walk-forward -> sealed holdout):";
$[98h=type pkt`verdicts;
    show select bucket,nObs,verdict,failedGate,tradeable,netSharpe,dsr from pkt`verdicts;
    -1 "    ",-3!pkt`verdicts];
-1 "  anyTradeable = ",(string pkt`anyTradeable),"   (evidence audit passed = ",(string pkt`evidencePassed),")";
-1 "  regime risk-memory: ",$[0<count pkt`riskMemory; pkt`riskMemory; "(none)"];
-1 "";

-1 "(2) PnL ATTRIBUTION (R15, summed over the three legs) - THE DUAL TEST:";
a:pkt`attribution;
-1 "    level=",(string a`level),"  slope=",(string a`slope),"  curvature=",(string a`curvature),"  carry=",(string a`carry),"  residual=",string a`residual;
-1 "    total=",(string a`total),"  RESIDUAL FRACTION=",string a`residualFraction;
-1 "    READ 1 (construction): level + slope = ",(string (a`level)+a`slope)," ~ 0  =>  ",$[0.1>abs (a`level)+a`slope; "the +1/-2/+1 fly IS level/slope-neutral (construction confirmed)"; "WARNING: level/slope leaking - the neutrality construction is not holding"],".";
-1 "    READ 2 (thesis): ",$[(abs a`curvature)>abs a`residual; "curvature DOMINATES the residual -> the curvature mean-reversion is real"; "the PnL is RESIDUAL-dominated -> the curvature edge is NOT cleanly isolated (a near-curve fly's local curvature is not well-spanned by R10's global butterfly basis - the curvature, to the extent it exists, sits in the residual)"],".";
-1 "";

-1 "(3) The human-escalation packet:";
-1 "    decision=",(string pkt`decision),"  humanSignOffRequired=",(string pkt`humanSignOffRequired),"  stage=",string pkt`stage;
-1 "    summary: ",pkt`summary;
-1 "";
-1 "This completes the curve-shape mean-reversion family - R16 took the slope/level (the calendar spread),";
-1 "R20 takes the curvature (the butterfly) - with the cleanest attribution test in the series: the very tool";
-1 "that judges the strategy (the PnL decomposition) also confirms it was built correctly (level/slope ~ 0).";
-1 "Whether the curvature edge clears the three-leg cost gate or not, the attribution says precisely what happened.";

exit 0;
