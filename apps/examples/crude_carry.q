\l core/init.q
/ ============================================================================
/ crude_carry.q - real-data example (NOT a test), DATA-CONDITIONAL. POST-FOUNDATION R18.
/ Run the crudeCarry strategy (the term-structure / roll-yield RISK-PREMIUM) on real CRUDE END-TO-END
/ through the WHOLE foundation (R9 door -> R10 curve -> R11 roll -> R12 replay -> R13 evidence audit ->
/ R14 carry -> R15 attribution) via .workflow.runReplay, and print the HONEST verdict + the PnL attribution
/ + the regime skeptic's crash-risk memory + the human-escalation packet. The parameters are PRE-REGISTERED
/ (.cfg.strategy.crudeCarry) and NOT tuned: carry is the easiest premium to overfit and the most dangerous
/ to harvest naively ('pennies in front of a steamroller'). The SUCCESS case is a surviving edge whose
/ PnL comes from CARRY (not residual); a residual-dominated survivor would mean it is NOT harvesting carry.
/ Either verdict is honest. Skips if no HDB.
/ ============================================================================
hdbPath:.cfg.paths`hdb;
useHdb:0<count @[{[p] key hsym `$p,"/sym"};hdbPath;{[e] ()}];
if[not useHdb;
    -1 "crude_carry SKIPPED - no HDB at ",hdbPath," (run scripts/ingest_hdb.q first).";
    exit 0];
.data.hdb.open hdbPath;
/ open the R4 regime-analogue library so the workflow's regime skeptic can attach the crash-risk memory
/ (the energyShock2022 caveat the carry premium demands); graceful if the library isn't built.
if[0<count key hsym `$hdbPath,"/regimeEpisodes/"; .regime.library.open hdbPath];

comm:`CRUDE; cfg:.cfg.strategy.crudeCarry;
/ scope the audited run record to train+validate (the holdout stays sealed; gov reads it one-shot).
tv:.gov.zone.range[comm;`trainValidate];
res:.template.crudeCarry.run `commodity`dateFrom`dateTo!(comm; tv 0; tv 1);
run:(res`meta)`runRecord;
-1 "crudeCarry on ",(string comm)," (train+validate ",(string tv 0)," .. ",(string tv 1),"):";
-1 "  signal: R14's carrySignal (impliedCarry - costOfCarry); LONG > +",(string cfg`threshold),", SHORT < -",(string cfg`threshold),", smoothed over ",(string cfg`lookback)," days, min-hold ",(string cfg`holdingPeriod)," days (PRE-REGISTERED, NOT tuned)";
-1 "  traded contract: R11's .roll.active (days_before_expiry); NET of .exec.fill cost";
-1 "  carry-PERSISTENCE gate: ",(res[`validation;`persistence])`detail;
-1 "  run record: ",(string count run`steps)," steps, replay totalPnl=",string (run`meta)`totalPnl;
-1 "";

/ run the END-TO-END bounded replay-mode loop, carded on card_crudeCarry (risk memory energyShock2022).
/ NOTE: the gov hypothesis declares edgeSource `riskPremium - the term-structure / roll-yield premium - which
/ IS in gov's validEdgeSources (riskPremium/mispricing/info); the model card uses the same `riskPremium term.
prop:`hypoId`thesis`edgeSource`instruments`claimedRegimes`capName`runRecord`runner!(
    `crude_carry_premium;
    "crude term-structure / roll-yield premium: long when the curve is backwardated (positive net carry), short in contango";
    `riskPremium; enlist comm; `backwardation`contango`flat; `crudeCarry;
    run; .template.crudeCarry.runner[comm;cfg]);
pkt:.workflow.runReplay prop;

-1 "(1) The HONEST verdict (per regime bucket; gates: cost -> deflated Sharpe -> walk-forward -> sealed holdout):";
$[98h=type pkt`verdicts;
    show select bucket,nObs,verdict,failedGate,tradeable,netSharpe,dsr from pkt`verdicts;
    -1 "    ",-3!pkt`verdicts];
-1 "  anyTradeable = ",(string pkt`anyTradeable),"   (evidence audit passed = ",(string pkt`evidencePassed),")";
-1 "  regime risk-memory (the crash-risk the premium demands): ",$[0<count pkt`riskMemory; pkt`riskMemory; "(none)"];
-1 "";

-1 "(2) PnL ATTRIBUTION (R15: is the money actually CARRY, or unexplained residual?):";
a:pkt`attribution;
-1 "    level=",(string a`level),"  slope=",(string a`slope),"  curvature=",(string a`curvature),"  carry=",(string a`carry),"  residual=",string a`residual;
-1 "    total=",(string a`total),"  RESIDUAL FRACTION=",string a`residualFraction;
-1 "    (the carry thesis CLAIMS the term-structure / roll-yield premium. The SUCCESS case is PnL dominated";
-1 "     by the CARRY term; a residual-dominated survivor would mean it is NOT really harvesting carry - the";
-1 "     red flag deflation + the holdout exist to punish. Whatever the split, the attribution is the honest";
-1 "     test of the thesis, not the headline Sharpe.)";
-1 "";

-1 "(3) The human-escalation packet:";
-1 "    decision=",(string pkt`decision),"  humanSignOffRequired=",(string pkt`humanSignOffRequired),"  stage=",string pkt`stage;
-1 "    summary: ",pkt`summary;
-1 "";
-1 "This is the first strategy the system judges with a real RISK-PREMIUM thesis - a recognised premium that";
-1 "pays small-and-steady and crashes in shocks is exactly what a naive frictionless backtest flatters and a";
-1 "realistic, deflated, regime-aware judge treats with suspicion. The verdict is judged net of realistic roll";
-1 "cost, deflated against the trial count, through the sealed holdout, ATTRIBUTED (carry vs residual), and the";
-1 "regime skeptic attaches the crash-risk memory the premium demands. Whatever it returns, it is honest.";

exit 0;
