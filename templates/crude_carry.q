/ templates/crude_carry.q - the crudeCarry problem template (.template.crudeCarry.*) (v0.83, Post-foundation R18)
/ ----------------------------------------------------------------------------
/ R18: the first strategy with a genuine RISK-PREMIUM thesis - harvest the commodity TERM-STRUCTURE /
/ ROLL-YIELD premium. Built on R14's carry signal as the milestone promised ("the basis for the carry
/ strategies after"). A TIME-SERIES carry rule: LONG crude when the curve is backwardated / positive net
/ carry (R14's carrySignal > +threshold - the curve pays you to hold), SHORT in contango (< -threshold -
/ holding costs you), FLAT in the dead-band. Trades the ACTUAL front contract R11 names, books NET PnL via
/ .exec.fill, and emits an R12-shape run record so R13's audit + R15's attribution consume it end-to-end.
/ Composes R14 (.carry.features) + R11 (roll discipline) + R10/R9 downward. Edge: RISK-PREMIUM.
/ -
/ THE POINT (read first): commodity carry is a RECOGNISED premium, so it MIGHT survive more gates than R16's
/ structural mean-reversion or R8's relative-value. That makes two things matter MORE, not less. (1) Carry is
/ one of the EASIEST premia to overfit (threshold / lookback / holding period) and most dangerous to harvest
/ naively - it pays small-and-steady then loses badly in a regime shift ('pennies in front of a steamroller',
/ the energyShock2022 risk memory). So the params are PRE-REGISTERED in .cfg.strategy.crudeCarry (FIXED,
/ round, a-priori, NOT swept). (2) The ATTRIBUTION (R15) is the real test: the SUCCESS case is a surviving
/ edge whose PnL comes from CARRY; a residual-dominated survivor is NOT really harvesting carry (a red flag).
/ -
/ TEMPLATE-SPECIFIC GATE that BITES: the carry signal must be PERSISTENT to be harvestable (a backwardated
/ curve tends to STAY backwardated, so today's carry predicts the near-term roll). Reuse R6's AR(1) machinery
/ (.template.rv.stationarity gives ar1) but INVERT the bar: persistent iff ar1 >= minPersistence. A
/ non-persistent (noise) carry signal is REJECTED before the universal gov gates run - a gate carry demands.
/ -
/ CAUSAL + ACTUAL CONTRACTS: R14's carrySignal is point-in-time (built from R10's as-of curve, through R9's
/ door); a planted FUTURE curve move cannot change a past signal. The traded front = the nearest contract
/ with days-to-expiry > rollBuffer (rollBuffer = .cfg.rolls CRUDE rollDays, so it EQUALS R11's
/ days_before_expiry active contract); its OWN price change is booked (difference method, 0 on a roll).
/ -
/ RESERVED-NAME NOTE: `asOf` NEVER `asof`; `comm` NOT `commodity`; builtins not shadowed (dev/avg/var/
/ signum/first/last/sums/deltas/prev/differ; `dev` is stddev - a local named `dev` throws 'assign).
/ ----------------------------------------------------------------------------

/ The per-date ACTIVE contract id: R11's .roll.active VERBATIM (the contract a desk would actually hold,
/ decided from as-of data only - days_before_expiry for CRUDE). One call per date. FAITHFUL to R11 (no
/ approximation of the W-day blend). Returns a contractYM per date.
.template.crudeCarry.__activeSeries:{[comm;dates]
    {[comm;d] (.roll.active[d;comm])`active}[comm] each dates
 };

/ R14's carry signal per date (point-in-time, causal): carrySignal = impliedCarry - costOfCarry (positive in
/ strong backwardation). Reuses .carry.features VERBATIM. null -> 0 (no signal / flat). One call per date.
.template.crudeCarry.__carrySeries:{[comm;dates]
    {[comm;d] cs:(.carry.features[d;comm])`carrySignal; $[null cs; 0f; cs]}[comm] each dates
 };

/ The position state machine over a (smoothed) carry-signal series: LONG (+1) when sig > +threshold, SHORT
/ (-1) when sig < -threshold, FLAT (0) in the dead-band; a position is held at least holdingPeriod days
/ before it may flip (cuts roll turnover). A scan threading (position; daysHeld). PURE.
.template.crudeCarry.__positions:{[sig;threshold;holdingPeriod]
    step:{[threshold;hold;st;si]
        pos:st 0; held:st 1;
        target:$[si>threshold; 1; si<neg threshold; -1; 0];
        $[(pos<>0) and held<hold; (pos; held+1);                 / within min-hold: keep, count up
          target=0; (0;0);                                       / past min-hold, signal flat -> go flat
          target=pos; (pos; held+1);                             / same direction -> keep holding
          (target; 1)]                                           / new direction -> flip, reset hold counter
        }[threshold;holdingPeriod];
    (step\[(0;0); sig])[;0]                                      / one position per signal element (seed not in scan output)
 };

/ The carry-PERSISTENCE gate (template-specific). Reuse R6's AR(1) regression (.template.rv.stationarity
/ gives ar1) but INVERT the test: a HARVESTABLE carry signal is PERSISTENT (high autocorrelation), the
/ opposite of mean-reverting. persistent iff ar1 >= minPersistence. PURE.
.template.crudeCarry.persistence:{[carrySig;cfg]
    st:.template.rv.stationarity carrySig;
    ar1:st`ar1;
    `ar1`persistent!(ar1; (not null ar1) and ar1>=cfg`minPersistence)
 };

/ The end-to-end as-of REPLAY: causal carry signal over dates <= toD, smoothed (causal rollMean), positioned
/ (state machine), traded on the ACTUAL front contract, NET of .exec.fill cost -> an R12-shape run record
/ (the shape R13's audit + R15's attribution consume). Output sliced to [fromDate;toDate]; the carry signal
/ is point-in-time so the signal at a date is independent of the [from;to] window (split-consistent).
.template.crudeCarry.__replay:{[comm;fromDate;toDate;cfg]
    ch0:.data.hdb.curveHistory[comm; .data.hdb.dates comm];
    pm:exec contractYM!price by asofDate from ch0;              / asofDate -> (contractYM -> price)
    allDates:asc distinct ch0`asofDate;
    fromD:$[null fromDate; min allDates; fromDate];
    toD:$[null toDate; max allDates; toDate];
    / causal carry signal + positions over dates <= toD (point-in-time; smoothing uses only <= each date).
    evalDates:allDates where allDates<=toD;
    actAll:.template.crudeCarry.__activeSeries[comm; evalDates];                / R11's active contract per date
    pxAll:{[pm;d;a] p:pm[d][a]; $[null p; 0n; p]}[pm]'[evalDates;actAll];       / the active contract's as-of price
    carrySigAll:.template.crudeCarry.__carrySeries[comm; evalDates];
    sm:.template.rv.__rollMean[cfg`lookback; carrySigAll];
    posAll:cfg[`notional]*.template.crudeCarry.__positions[sm; cfg`threshold; cfg`holdingPeriod];
    / slice the OUTPUT to [from;to]; each window starts flat (the R16 convention).
    keep:evalDates within (fromD;toD);
    dates:evalDates where keep; ac:actAll where keep; px:pxAll where keep;
    posK:posAll where keep; carrySig:carrySigAll where keep;
    n:count dates;
    isRoll:differ ac; isRoll[0]:0b;
    / the active contract's OWN price change (difference method): 0 on a roll day (contract changed) and 0
    / where a price is missing (the active contract did not print that day), so PnL never books a roll gap.
    dPriceFull:deltas px; nullMask:(null px) or null prev px;
    dPrice:?[isRoll or nullMask; 0f; dPriceFull]; dPrice[0]:0f;
    px:fills px;                                                / forward-fill for the refPrice column (no nulls)
    posLag:0f,-1_posK;                                           / position held INTO each day's move
    positionPnl:posLag*dPrice;
    order:deltas posK; filledQty:order;
    execCfg:.exec.__resolve cfg;
    cost:{[execCfg;ord] (.exec.fill[ord; `refPrice`currentPos!(1f;0f); execCfg])`totalCost}[execCfg] each order;
    stepPnl:positionPnl-cost;
    steps:flip `stepIndex`stepDate`asOf`activeContract`isRoll`rollFrom`position`frontReturn`positionPnl`proportionalCost`slippageCost`fixedCost`rollCost`financingCost`totalCost`stepPnl`cumPnl`filledQty`refPrice`provDateTo`carrySignal!(
        til n; dates; dates; ac; isRoll; ?[isRoll; prev ac; 0Nj]; posK; dPrice; positionPnl;
        cost; n#0f; n#0f; n#0f; n#0f; cost; stepPnl; sums stepPnl; filledQty; px; dates; carrySig);
    rollEvents:select date:stepDate, commodity:comm, fromContract:rollFrom, toContract:activeContract, reason:`carryRoll from steps where isRoll;
    `meta`steps`rollEvents`provenance!(
        `strategy`commodity`fromDate`toDate`nSteps`totalPnl!(
            `crudeCarry; comm; min dates; max dates; n; sum stepPnl);
        steps; rollEvents; select stepDate, asOf, provDateTo from steps)
 };

/ The runner seam for the gov gates: run the replay over [from;to] -> (date;pnl). Reuses __replay.
.template.crudeCarry.runner:{[comm;cfg] {[comm;cfg;from;to] r:.template.crudeCarry.__replay[comm;from;to;cfg]; select date:stepDate, pnl:stepPnl from r`steps}[comm;cfg]};

/ The template run (the `template` contract): inputs carry commodity (+ optional overrides / dateFrom /
/ dateTo). Returns `pnl`validation`meta - validation carries the carry-persistence gate; meta carries the
/ R12-shape run record (the artifact .workflow.runReplay audits + attributes).
.template.crudeCarry.run:{[inputs]
    cfg:.cfg.strategy.crudeCarry,$[`overrides in key inputs; inputs`overrides; ()!()];
    comm:$[`commodity in key inputs; inputs`commodity; `CRUDE];
    fromD:$[`dateFrom in key inputs; inputs`dateFrom; 0Nd];
    toD:$[`dateTo in key inputs; inputs`dateTo; 0Nd];
    run:.template.crudeCarry.__replay[comm;fromD;toD;cfg];
    pers:.template.crudeCarry.persistence[run[`steps]`carrySignal; cfg];
    pnl:select date:stepDate, pnl:stepPnl from run`steps;
    `pnl`validation`meta!(
        pnl;
        (enlist `persistence)!enlist `passed`detail!(pers`persistent; "carry-persistence: AR1=",(string pers`ar1),", persistent=",(string pers`persistent)," (bar minPersistence=",(string cfg`minPersistence),")");
        `shape`commodity`nDays`carryAr1`edgeSource`runRecord!(
            `crudeCarry; comm; count pnl; pers`ar1; `riskPremium; run))
 };

.template.register[`crudeCarry; .template.crudeCarry.run;
    `contractVersion`description`shape`composes`in`out!(
        1;
        "time-series commodity carry (the term-structure / roll-yield risk premium): long backwardation / short contango on R14's carry signal, trade the actual front contract, emit an auditable run record";
        `crudeCarry;
        `termStructureCarry;
        (enlist `commodity)!enlist `symbol;
        `pnl`validation`meta!`table`dict`dict)];

-1 "crude_carry.q loaded - .template.crudeCarry.* crudeCarry template registered (R18: term-structure / roll-yield risk premium; reuses R14 carry + R11 roll)";
