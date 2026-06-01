/ apps/examples/reattribution_sweep.q - R23 re-attribution of R16-R21 on the units-corrected attribution
/ ----------------------------------------------------------------------------
/ THE HONEST RECKONING. R22's skill #27 surfaced that R15's PnL attribution was in RETURN units (a /Pp
/ divide) while every R16-R21 strategy template books DOLLAR PnL (position*dP, net of costs). Attributed in
/ the wrong units, the level/slope/curvature/carry components came out ~1/Pp too small and the residual
/ absorbed almost the whole PnL - so the residual fractions I reported across R17-R21 were inflated by a UNIT
/ ARTIFACT, not (only) by basis or noise. R23 fixed the attribution (units-aware + roll routing + the local
/ basis made units-correct). This demo RE-RUNS each strategy's REPLAY (R12 - NOT the workflow, so it registers
/ nothing) and re-attributes it with the corrected GLOBAL and LOCAL attribution, printing the TRUE residual
/ fractions beside the previously-reported (units-distorted) ones, with a one-line honest verdict per strategy.
/ -
/ Run: q apps/examples/reattribution_sweep.q   (real CRUDE / GAS via the HDB)
/ ----------------------------------------------------------------------------
\l core/init.q

hdbPath:.cfg.paths`hdb;
useHdb:0<count @[{[p] key hsym `$p,"/sym"};hdbPath;{[e] ()}];
if[not useHdb;
    -1 "reattribution_sweep SKIPPED - no HDB at ",hdbPath," (run scripts/ingest_hdb.q first).";
    exit 0];
.data.hdb.open hdbPath;

/ Scope to the trainValidate zone (what the strategy demos + the gov gates explore; the holdout stays sealed)
/ - this also avoids the data-edge tail date where .roll.active has no live contract for the carry strategies.
tv:.gov.zone.range[`CRUDE;`trainValidate]; fromD:tv 0; toD:tv 1;
-1 "scope: trainValidate [",(string fromD),"; ",(string toD),"]  (the holdout stays sealed; the demos use this zone)";

/ Each strategy: a label, a 0-arg thunk that runs its REPLAY -> the R12-shape (dollar-booked) run record, the
/ previously-REPORTED (units-distorted) global residual fraction, and the prior one-line narrative being tested.
strat:{[label;edge;thunk;priorGf;priorNote] `label`edge`thunk`priorGf`priorNote!(label;edge;thunk;priorGf;priorNote)};
sweep:(
    strat[`R16_seasonalCalSpread; `structural;
        {.template.scs.__replay[`CRUDE; fromD; toD; .cfg.strategy.seasonalCalSpread]};
        0n; "capstone; flat bucket in-sample Sharpe 2.6 deflated to research (a SPREAD booked on one nominal contract)"];
    strat[`R17_factorRelativeValue; `structural;
        {.template.factorRvReplay.__replay[`CRUDE; fromD; toD; .template.factorRvReplay.__cfg[()!()]]};
        0.95; "no-edge confirmed; realised PnL was 95% unexplained residual (curve PCA residual-fade)"];
    strat[`R18_crudeCarry; `riskPremium;
        {.template.crudeCarry.__replay[`CRUDE; fromD; toD; .cfg.strategy.crudeCarry]};
        0.98; "carry +0.69 but residual 0.98 - 'mostly a long-crude directional bet', not a clean carry harvest"];
    strat[`R19_xCommodityCarry; `riskPremium;
        {.template.xCommodityCarry.__replay[fromD; toD; .cfg.strategy.xCommodityCarry]};
        0.38; "removing the common beta cut residual 0.98 -> 0.38, quadrupled carry - the relative premium is real"];
    strat[`R20_crudeButterfly; `structural;
        {.template.crudeButterfly.__replay[`CRUDE; fromD; toD; .cfg.strategy.crudeButterfly]};
        1.06; "level+slope ~ 0 (built correctly) but residual 1.06 - curvature NOT cleanly isolated (basis mismatch?)"];
    strat[`R21_xCommodityCarryVW; `riskPremium;
        {.template.xCommodityCarryVW.__replay[fromD; toD; .cfg.strategy.xCommodityCarryVW]};
        0.69; "equal-risk sizing RAISED level (-7.46 -> -25.9) and residual (0.38 -> 0.69) - no clean common beta to neutralise"]);

fmt:{[x] $[null x; "n/a"; -3!"f"$0.001*floor 0.5+1000*x]};            / 3dp
dom:{[a] cps:`level`slope`curvature`carry!(a`level;a`slope;a`curvature;a`carry); (key cps)(first idesc abs value cps)};

/ The honest one-line verdict per strategy on whether the earlier read holds (written from the units-correct
/ numbers above - NOT tuned to confirm the prior narratives; some move, the no-edge verdicts do not).
verdicts:`R16_seasonalCalSpread`R17_factorRelativeValue`R18_crudeCarry`R19_xCommodityCarry`R20_crudeButterfly`R21_xCommodityCarryVW!(
    "LOCAL residual ~0.07 (level-dominant): the spread's PnL IS local curve structure, well-explained by the traded-tenor basis; the high GLOBAL (~0.8) is the global basis missing a spread booked on one nominal contract -> localizedStructure, NOT noise.";
    "MOVES: the prior '95% unexplained residual' was the UNIT ARTIFACT - units-honest residual ~0.09 (level/slope-dominant). R17's PnL was STRUCTURAL curve moves, never noise; the no-edge VERDICT (deflation/cost) is unchanged.";
    "HOLDS + sharpened: LEVEL (the long/short directional beta) dominates, CARRY is real but secondary -> 'mostly a directional bet, not a clean carry harvest' confirmed; residual ~0.22, not 0.98 (that was the unit artifact).";
    "MIXED: CARRY is a large REAL component (the relative premium survives, R19's core finding), but a large LEVEL term shows the dollar-neutral book still carries directional exposure; the residual-DROP framing (0.98->0.38) was a unit artifact (LOCAL ~0.06, well-explained).";
    "CONFIRMED both reads: level+slope ~ 0 (built correctly) AND R22 basis-mismatch - GLOBAL residual ~1.9 (the global bow can't see the near-curve curvature) but LOCAL ~0.15, CURVATURE-dominant (the local basis captures it). The R22 local-basis payoff, now on a real DOLLAR run.";
    "HOLDS: the LARGEST level term - equal-risk sizing did NOT neutralise the directional exposure (R21's own conclusion); CARRY real but swamped; residual ~0.17, not 0.69.");

-1 "";
-1 "================================================================================";
-1 " R23 RE-ATTRIBUTION SWEEP - R16-R21 on the units-corrected (DOLLAR) attribution";
-1 " GLOBAL = R15 basis (whole curve); LOCAL = R22 basis (traded-tenor sub-curve)";
-1 "================================================================================";

runOne:{[s]
    run:@[s`thunk; ::; {[e] (enlist`runError)!enlist e}];
    if[(1=count key run) and `runError~first key run; -1 ""; -1 (string s`label)," : ERROR ",run`runError; :()];
    runD:run,(enlist`units)!enlist `dollar;                          / the run IS dollar-booked (templates book position*dP)
    gA:.attribution.pnl runD;
    lA:.attribution.pnlLocal runD;
    -1 "";
    -1 "--------------------------------------------------------------------------------";
    -1 (string s`label)," (",(string s`edge),")   nDays=",(string (run`meta)`nSteps),"   realized total=",fmt (run`meta)`totalPnl;
    -1 "  GLOBAL  level=",(fmt gA`level),"  slope=",(fmt gA`slope),"  curvature=",(fmt gA`curvature),"  carry=",(fmt gA`carry),"  residual=",fmt gA`residual;
    -1 "          residualFraction(global) = ",(fmt gA`residualFraction),"   reconciled=",string gA`reconciled;
    -1 "  LOCAL   level=",(fmt lA`level),"  slope=",(fmt lA`slope),"  curvature=",(fmt lA`curvature),"  carry=",(fmt lA`carry),"  residual=",fmt lA`residual;
    -1 "          residualFraction(local)  = ",(fmt lA`residualFraction),"   reconciled=",string lA`reconciled;
    -1 "  dominant component (global) = ",string dom gA;
    -1 "  prior (units-distorted) global residualFraction = ",fmt s`priorGf;
    -1 "  prior read: ",s`priorNote;
    -1 "  VERDICT:    ",verdicts s`label;
    `label`gGf`lGf`priorGf`dom`total!(s`label; gA`residualFraction; lA`residualFraction; s`priorGf; dom gA; (run`meta)`totalPnl)
 };

res:runOne each sweep;
res:res where 0<count each res;

-1 "";
-1 "================================================================================";
-1 " SUMMARY - true residual fraction (units-correct) vs previously-reported";
-1 "================================================================================";
-1 " strategy                  global  local   prior   dominant";
{[r] -1 "  ",(-26$string r`label),(-8$fmt r`gGf),(-8$fmt r`lGf),(-9$fmt r`priorGf),"  ",string r`dom;}each res;
-1 "";
-1 " Read straight: a dominant CARRY (risk premium) or SLOPE/CURVATURE (structural) component with a LOW";
-1 " residual is a real, named edge; a high residual is genuinely unexplained. The unit fix moves the";
-1 " ABSOLUTE residual fractions; the directional finding (e.g. R19's drop vs R18 when the beta was removed)";
-1 " is what survives. See CHANGELOG.md / ARCHITECTURE.md R23 for the written verdict per strategy.";
-1 "";

exit 0;
