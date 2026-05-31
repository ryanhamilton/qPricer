/ templates/xcommodity_carry.q - the xCommodityCarry problem template (.template.xCommodityCarry.*) (v0.84, Post-foundation R19)
/ ----------------------------------------------------------------------------
/ R19: market-neutral CROSS-commodity carry (crude vs gas) - the direct iterative RESPONSE to R18's finding.
/ R18's time-series crude carry harvested some carry (+0.69) but its PnL was 98% directional RESIDUAL: "long
/ crude when backwardated" is largely just "long crude". R19 strips that common energy beta with a
/ DOLLAR-NEUTRAL long/short - LONG the commodity with the higher carry signal (more backwardated), SHORT the
/ one with the lower (more contango) - so the relative carry PREMIUM has to stand on its own. The attribution
/ (R15) is the decisive test: beta-removed, does CARRY now dominate the PnL, or is it STILL residual?
/ -
/ THE KEY DESIGN POINT (multi-leg, cores FROZEN): R12's replay is single-commodity; we do NOT change it.
/ The book is built by COMPOSITION at the template level - run a per-leg R12-shape replay TWICE (crude with
/ its sign, gas with the opposite, sized dollar-neutral, reusing R18's helpers), then COMBINE the two run
/ records into ONE market-neutral record in the SAME R12 shape, carrying a `legs field. The evidence audit
/ (R13) and PnL attribution (R15) gained ADDITIVE `legs-aware branches (audit each leg with the UNCHANGED
/ single-commodity function + verify the combined book/PnL ties; attribute each leg + sum + reconcile) - the
/ single-commodity behaviour is byte-identical (a one-leg record has no `legs key).
/ -
/ DO NOT TUNE: the dispersion threshold / lookback / holding period are PRE-REGISTERED in
/ .cfg.strategy.xCommodityCarry (FIXED, round, a-priori). And a two-leg strategy pays roll/txn cost on BOTH
/ legs, so the cost gate is MORE demanding here - that realism is the point. This file does NOT modify R14,
/ R16's/R18's templates, .workflow.runReplay, gov/, or the R12 core; it REUSES R18's helpers + the cores.
/ -
/ CAUSAL + ACTUAL CONTRACTS on BOTH legs: R14's carrySignal is point-in-time (through R9's door) for crude
/ AND gas; each leg trades the ACTUAL contract R11's .roll.active names and books its own price change NET of
/ .exec.fill (difference method, 0 on a roll). A planted FUTURE move on either leg cannot change a past signal.
/ -
/ RESERVED-NAME NOTE: `asOf` NEVER `asof`; `comm` NOT `commodity`; builtins not shadowed (dev/avg/var/
/ signum/first/last/sums/deltas/prev/differ/inter/fills).
/ ----------------------------------------------------------------------------

/ A single-leg R12-shape replay driven by an INJECTED per-date position series (the cross-commodity decision
/ is made at the template level). Same shape + helpers as R18's crudeCarry __replay (REUSED: __activeSeries),
/ so each leg is a valid single-commodity run record the UNCHANGED .evidence.audit / .attribution.pnl consume.
.template.xCommodityCarry.__legReplay:{[comm;evalDates;positionsAll;fromD;toD;cfg]
    ch0:.data.hdb.curveHistory[comm; .data.hdb.dates comm];
    pm:exec contractYM!price by asofDate from ch0;              / asofDate -> (contractYM -> price)
    actAll:.template.crudeCarry.__activeSeries[comm; evalDates];                / R11's .roll.active per date
    pxAll:{[pm;d;a] p:pm[d][a]; $[null p; 0n; p]}[pm]'[evalDates;actAll];
    keep:evalDates within (fromD;toD);
    dates:evalDates where keep; ac:actAll where keep; px:pxAll where keep; posK:positionsAll where keep;
    n:count dates;
    isRoll:differ ac; isRoll[0]:0b;
    dPriceFull:deltas px; nullMask:(null px) or null prev px;
    dPrice:?[isRoll or nullMask; 0f; dPriceFull]; dPrice[0]:0f;
    px:fills px;
    posLag:0f,-1_posK;
    positionPnl:posLag*dPrice;
    order:deltas posK; filledQty:order;
    execCfg:.exec.__resolve cfg;
    cost:{[execCfg;ord] (.exec.fill[ord; `refPrice`currentPos!(1f;0f); execCfg])`totalCost}[execCfg] each order;
    stepPnl:positionPnl-cost;
    steps:flip `stepIndex`stepDate`asOf`activeContract`isRoll`rollFrom`position`frontReturn`positionPnl`proportionalCost`slippageCost`fixedCost`rollCost`financingCost`totalCost`stepPnl`cumPnl`filledQty`refPrice`provDateTo!(
        til n; dates; dates; ac; isRoll; ?[isRoll; prev ac; 0Nj]; posK; dPrice; positionPnl;
        cost; n#0f; n#0f; n#0f; n#0f; cost; stepPnl; sums stepPnl; filledQty; px; dates);
    rollEvents:select date:stepDate, commodity:comm, fromContract:rollFrom, toContract:activeContract, reason:`xCarryRoll from steps where isRoll;
    `meta`steps`rollEvents`provenance!(
        `strategy`commodity`fromDate`toDate`nSteps`totalPnl!(`xCommodityCarry; comm; min dates; max dates; n; sum stepPnl);
        steps; rollEvents; select stepDate, asOf, provDateTo from steps)
 };

/ The dispersion/persistence gate (template-specific). The relative-carry (dispersion) signal must be both
/ PERSISTENT (reuse R18's AR(1) persistence) and DISPERSED enough to harvest (it must actually exceed the
/ threshold on a non-trivial fraction of dates). A flat relative signal (never disperses) or a noise one
/ (not persistent) is REJECTED before the universal gates. PURE.
.template.xCommodityCarry.gate:{[disp;cfg]
    pers:.template.crudeCarry.persistence[disp;cfg];
    activeFrac:$[0=count disp; 0f; (sum (abs disp)>cfg`dispersionThreshold)%count disp];
    dispersed:activeFrac>=cfg`minActiveFrac;
    `ar1`activeFrac`persistent`dispersed`pass!(
        pers`ar1; activeFrac; pers`persistent; dispersed; (pers`persistent) and dispersed)
 };

/ The end-to-end as-of REPLAY: per common date compute R14's carry signal for BOTH commodities (causal),
/ the smoothed dispersion (crude - gas), the relative position (R18's state machine: LONG crude/SHORT gas
/ when dispersion > +threshold, the reverse when < -threshold, with a min-hold), then replay each leg
/ dollar-neutral and COMBINE into one market-neutral R12-shape run record carrying `legs.
.template.xCommodityCarry.__replay:{[fromDate;toDate;cfg]
    cl:cfg`commodities; crude:cl 0; gas:cl 1;
    common:asc (.data.hdb.dates crude) inter .data.hdb.dates gas;
    fromD:$[null fromDate; min common; fromDate];
    toD:$[null toDate; max common; toDate];
    evalDates:common where common<=toD;
    csC:.template.crudeCarry.__carrySeries[crude; evalDates];   / R14 carry per date (causal), crude leg
    csG:.template.crudeCarry.__carrySeries[gas; evalDates];     / R14 carry per date (causal), gas leg
    disp:csC-csG;                                               / relative carry (crude minus gas)
    sm:.template.rv.__rollMean[cfg`lookback; disp];             / causal smoothing
    relPos:.template.crudeCarry.__positions[sm; cfg`dispersionThreshold; cfg`holdingPeriod];   / +1 long crude/short gas
    posC:cfg[`notional]*relPos; posG:neg cfg[`notional]*relPos; / dollar-neutral: equal-and-opposite
    legC:.template.xCommodityCarry.__legReplay[crude; evalDates; posC; fromD; toD; cfg];
    legG:.template.xCommodityCarry.__legReplay[gas;   evalDates; posG; fromD; toD; cfg];
    sC:legC`steps; sG:legG`steps;
    dates:sC`stepDate; n:count dates;
    relSliced:sm where evalDates within (fromD;toD);
    combinedStepPnl:(sC`stepPnl)+sG`stepPnl;
    combinedSteps:flip `stepIndex`stepDate`asOf`provDateTo`positionPnl`proportionalCost`slippageCost`fixedCost`rollCost`financingCost`totalCost`stepPnl`cumPnl`relSignal!(
        til n; dates; sC`asOf; sC`provDateTo;
        (sC`positionPnl)+sG`positionPnl; (sC`proportionalCost)+sG`proportionalCost;
        (sC`slippageCost)+sG`slippageCost; (sC`fixedCost)+sG`fixedCost; (sC`rollCost)+sG`rollCost;
        (sC`financingCost)+sG`financingCost; (sC`totalCost)+sG`totalCost;
        combinedStepPnl; sums combinedStepPnl; relSliced);
    `meta`steps`rollEvents`provenance`legs!(
        `strategy`commodity`commodities`fromDate`toDate`nSteps`totalPnl!(
            `xCommodityCarry; crude; cl; min dates; max dates; n; sum combinedStepPnl);
        combinedSteps; (legC`rollEvents),legG`rollEvents; legC`provenance; (legC;legG))
 };

/ The runner seam for the gov gates: run the replay over [from;to] -> (date;pnl) of the COMBINED net PnL.
.template.xCommodityCarry.runner:{[cfg] {[cfg;from;to] r:.template.xCommodityCarry.__replay[from;to;cfg]; select date:stepDate, pnl:stepPnl from r`steps}[cfg]};

/ The template run (the `template` contract): inputs optional (overrides / dateFrom / dateTo); the commodity
/ pair is the PRE-REGISTERED .cfg.strategy.xCommodityCarry`commodities. Returns `pnl`validation`meta -
/ validation carries the dispersion/persistence gate; meta carries the COMBINED (legs-bearing) run record.
.template.xCommodityCarry.run:{[inputs]
    cfg:.cfg.strategy.xCommodityCarry,$[`overrides in key inputs; inputs`overrides; ()!()];
    fromD:$[`dateFrom in key inputs; inputs`dateFrom; 0Nd];
    toD:$[`dateTo in key inputs; inputs`dateTo; 0Nd];
    run:.template.xCommodityCarry.__replay[fromD;toD;cfg];
    g:.template.xCommodityCarry.gate[run[`steps]`relSignal; cfg];
    pnl:select date:stepDate, pnl:stepPnl from run`steps;
    `pnl`validation`meta!(
        pnl;
        (enlist `dispersion)!enlist `passed`detail!(g`pass; "dispersion/persistence: AR1=",(string g`ar1),", activeFrac=",(string g`activeFrac),", dispersed=",(string g`dispersed),", persistent=",(string g`persistent),", pass=",string g`pass);
        `shape`commodity`commodities`nDays`dispersionAr1`edgeSource`runRecord!(
            `xCommodityCarry; (cfg`commodities) 0; cfg`commodities; count pnl; g`ar1; `riskPremium; run))
 };

.template.register[`xCommodityCarry; .template.xCommodityCarry.run;
    `contractVersion`description`shape`composes`in`out!(
        1;
        "market-neutral cross-commodity carry (crude vs gas): LONG the higher-carry / SHORT the lower, dollar-neutral on the actual contracts of both legs, emit a combined auditable run record";
        `xCommodityCarry;
        `crossCommodityCarry;
        (enlist `commodities)!enlist `symbol;
        `pnl`validation`meta!`table`dict`dict)];

-1 "xcommodity_carry.q loaded - .template.xCommodityCarry.* xCommodityCarry template registered (R19: market-neutral crude-vs-gas carry; combines two R12-shape legs; reuses R18 helpers + R13/R15 cores)";
