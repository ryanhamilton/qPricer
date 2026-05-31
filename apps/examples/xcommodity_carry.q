\l core/init.q
/ ============================================================================
/ xcommodity_carry.q - real-data example (NOT a test), DATA-CONDITIONAL. POST-FOUNDATION R19.
/ Market-neutral CROSS-commodity carry (crude vs gas), run END-TO-END through the WHOLE foundation
/ (R9 door -> R10 curve -> R11 roll -> R12 replay [twice, one per leg] -> R13 evidence audit -> R14 carry
/ -> R15 attribution) via .workflow.runReplay, and print the HONEST verdict + the PnL attribution +
/ a CONTRAST with R18's time-series crude carry. R18 found the carry harvest was real (+0.69) but 98%
/ directional RESIDUAL - mostly a long-crude bet. R19 removes that common energy beta with a dollar-neutral
/ long/short, so the relative carry PREMIUM stands on its own. THE DECISIVE TEST is the attribution: with
/ beta removed, does carry now dominate / does the residual fraction fall? The params are PRE-REGISTERED
/ (.cfg.strategy.xCommodityCarry) and NOT tuned. Skips if no HDB.
/ ============================================================================
hdbPath:.cfg.paths`hdb;
useHdb:0<count @[{[p] key hsym `$p,"/sym"};hdbPath;{[e] ()}];
if[not useHdb;
    -1 "xcommodity_carry SKIPPED - no HDB at ",hdbPath," (run scripts/ingest_hdb.q first).";
    exit 0];
.data.hdb.open hdbPath;
if[0<count key hsym `$hdbPath,"/regimeEpisodes/"; .regime.library.open hdbPath];

cfg:.cfg.strategy.xCommodityCarry; cl:cfg`commodities;
/ scope the audited run record to crude's train+validate (gas shares the same date axis + boundary).
tv:.gov.zone.range[cl 0;`trainValidate];
res:.template.xCommodityCarry.run `dateFrom`dateTo!(tv 0; tv 1);
run:(res`meta)`runRecord;
-1 "xCommodityCarry (",(("/" sv string cl)),", train+validate ",(string tv 0)," .. ",(string tv 1),"):";
-1 "  signal: R14 carrySignal(",(string cl 0),") - carrySignal(",(string cl 1),"); LONG the higher-carry / SHORT the lower when |dispersion| > ",(string cfg`dispersionThreshold),", dollar-neutral (PRE-REGISTERED, NOT tuned)";
-1 "  legs traded on the ACTUAL contracts R11's .roll.active names; each leg NET of .exec.fill (a TWO-leg cost - the cost gate is more demanding)";
-1 "  dispersion/persistence gate: ",(res[`validation;`dispersion])`detail;
-1 "  combined run record: ",(string count run`steps)," steps, ",(string count run`legs)," legs, replay totalPnl=",string (run`meta)`totalPnl;
-1 "";

/ run the END-TO-END bounded replay-mode loop, carded on card_xCommodityCarry (risk memory energyShock2022).
/ edgeSource `riskPremium (the cross-sectional / relative term-structure premium) is in gov's validEdgeSources.
prop:`hypoId`thesis`edgeSource`instruments`claimedRegimes`capName`runRecord`runner!(
    `xcommodity_carry_premium;
    "relative term-structure / roll-yield premium: long the more-backwardated of crude/gas, short the more-contango, dollar-neutral (the common energy beta removed)";
    `riskPremium; cl; `backwardation`contango`flat; `xCommodityCarry;
    run; .template.xCommodityCarry.runner cfg);
pkt:.workflow.runReplay prop;

-1 "(1) The HONEST verdict (per regime bucket; gates: cost -> deflated Sharpe -> walk-forward -> sealed holdout):";
$[98h=type pkt`verdicts;
    show select bucket,nObs,verdict,failedGate,tradeable,netSharpe,dsr from pkt`verdicts;
    -1 "    ",-3!pkt`verdicts];
-1 "  anyTradeable = ",(string pkt`anyTradeable),"   (evidence audit passed = ",(string pkt`evidencePassed),")";
-1 "  regime risk-memory: ",$[0<count pkt`riskMemory; pkt`riskMemory; "(none)"];
-1 "";

-1 "(2) PnL ATTRIBUTION (R15, summed over both legs - THE DECISIVE TEST: carry, or still residual?):";
a:pkt`attribution;
-1 "    level=",(string a`level),"  slope=",(string a`slope),"  curvature=",(string a`curvature),"  carry=",(string a`carry),"  residual=",string a`residual;
-1 "    total=",(string a`total),"  RESIDUAL FRACTION=",string a`residualFraction;
-1 "";
-1 "(3) CONTRAST with R18 (time-series crude carry):";
-1 "    R18 (directional): carry +0.69 but RESIDUAL FRACTION 0.98 - mostly a long-crude bet, not a carry harvest.";
-1 "    R19 (market-neutral): carry=",(string a`carry),", residual fraction=",(string a`residualFraction),".";
-1 "    Removing the common energy beta ",$[(a`residualFraction)<0.98; "CUT the residual fraction and raised the carry share"; "did NOT cut the residual"],": the relative";
-1 "    carry premium is ",$[(a`carry)>0; "POSITIVE and now visible"; "not positive"]," with the directional exposure stripped. (A large LEVEL term would mean";
-1 "    equal-NOTIONAL is not equal-RISK - dollar-neutral hedges beta only to first order; vol-weighting is the natural next iteration.)";
-1 "";

-1 "(4) The human-escalation packet:";
-1 "    decision=",(string pkt`decision),"  humanSignOffRequired=",(string pkt`humanSignOffRequired),"  stage=",string pkt`stage;
-1 "    summary: ",pkt`summary;
-1 "";
-1 "This is the system's first ITERATIVE research: R18's attribution diagnosed the carry harvest was swamped";
-1 "by directional beta, and R19 is the experiment that diagnosis demanded - strip the beta, re-attribute, and";
-1 "let the numbers say whether the relative carry premium stands on its own. A verdict is not an endpoint; it";
-1 "is evidence that shapes the next hypothesis - and that loop is what the whole architecture was built for.";

exit 0;
