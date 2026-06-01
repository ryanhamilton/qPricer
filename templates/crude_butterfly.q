/ templates/crude_butterfly.q - the crudeButterfly problem template (.template.crudeButterfly.*) (v0.85, Post-foundation R20)
/ ----------------------------------------------------------------------------
/ R20: fade the crude curve BUTTERFLY (curvature) - the next-order curve shape after R16's calendar spread
/ (slope/level). A butterfly is a level- and slope-neutral combination of THREE contracts (+1 wing / -2
/ belly / +1 wing) that ISOLATES R10's curvature. That gives this milestone its sharpest property: because
/ the strategy expresses exactly ONE attribution component, the R15 attribution does DOUBLE DUTY - it
/ confirms the neutrality construction holds (level + slope PnL ~ 0) AND tests whether the curvature edge is
/ real (curvature should dominate, not residual). Fade the causal z of the butterfly: SHORT the fly when z
/ is unusually high, LONG when unusually low, exit on a z-cross of zero or maxHold.
/ -
/ THE KEY DESIGN POINT (why three LEGS, single-commodity): to get the level/slope/curvature decomposition
/ the milestone's attribution test needs, the three contracts are modelled as three single-commodity crude
/ LEGS and combined into one `legs-bearing R12-shape run record - REUSING the R19 `legs-aware audit
/ (.evidence.__auditCombined) and attribution (.attribution.__pnlCombined), which are commodity-agnostic and
/ already handle N legs. (A single-record butterfly with one nominal contract - the R16 spread pattern -
/ could only attribute that one contract's move, swamping the curvature in residual; the per-leg sum is what
/ makes level/slope cancel and curvature stand out.) This is SINGLE-COMMODITY (all crude) and adds NO new
/ machinery - it reuses the committed `legs platform. R12/R13/R15 cores + R16/R18/R19 templates UNCHANGED.
/ -
/ DO NOT TUNE: the leg tenors / weights / z-window / thresholds are PRE-REGISTERED in
/ .cfg.strategy.crudeButterfly (FIXED, round, a-priori). And a butterfly pays roll/txn cost on THREE legs,
/ so the cost gate is the most demanding yet - that realism is the point.
/ -
/ CAUSAL + ACTUAL CONTRACTS: the curvature + its z are causal (R10's curvature on the as-of curve, a causal
/ trailing-window z via R6/R14's __rollMean/__rollSd through R9's door); each leg trades the ACTUAL contract
/ at its tenor rank (rollBuffer-filtered = R11's days_before_expiry rule per rank) and books its own price
/ change NET of .exec.fill (difference method, 0 on a roll). A planted future move cannot change a past signal.
/ -
/ RESERVED-NAME NOTE: `asOf` NEVER `asof`; `comm` NOT `commodity`; the butterfly is (wing1+wing2)-2*belly -
/ mind right-to-left precedence (parenthesise); builtins not shadowed (dev/avg/var/first/last/sums/deltas/
/ prev/differ/fills/mmu/wsum).
/ ----------------------------------------------------------------------------

/ The per-date butterfly: from a curve history, per date sort by tenor, rollBuffer-filter (skip the expiring
/ contract), require >= max(legRanks)+1 live contracts, and pick the three legs at legRanks. Returns the
/ butterfly VALUE (legWeights wsum the three prices = R10's curvature for +1/-2/+1) + the legs' prices/ids
/ (nDates x 3 matrices). PURE w.r.t. the curve history passed in.
.template.crudeButterfly.__flySeries:{[ch;ranks;wts;rollBuffer]
    d2e:`int$(ch`expiry)-ch`asofDate;
    ch:ch where d2e>rollBuffer;
    s:`asofDate`tenor xasc ch;
    g:0!select px:price, ym:contractYM by asofDate from s;
    g:select from g where (max ranks)<count each px;
    legPx:(g`px)@\:ranks;                                    / nDates x 3 leg prices
    legYm:(g`ym)@\:ranks;                                    / nDates x 3 leg contractYMs
    `date`fly`legPx`legYm!(g`asofDate; legPx mmu `float$wts; legPx; legYm)
 };

/ A single crude LEG R12-shape replay driven by an INJECTED contract-id + price + position series (the
/ contract at a chosen tenor rank). Same shape + discipline as R16/R19's leg replays, so each leg is a
/ valid single-commodity run record the UNCHANGED .evidence.audit / .attribution.pnl consume.
.template.crudeButterfly.__legReplay:{[comm;evalDates;ymAll;pxAll;positionsAll;fromD;toD;cfg]
    keep:evalDates within (fromD;toD);
    dates:evalDates where keep; ac:ymAll where keep; px:pxAll where keep; posK:positionsAll where keep;
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
    rollEvents:select date:stepDate, commodity:comm, fromContract:rollFrom, toContract:activeContract, reason:`flyRoll from steps where isRoll;
    `meta`steps`rollEvents`provenance!(
        `strategy`commodity`fromDate`toDate`nSteps`totalPnl!(`crudeButterfly; comm; min dates; max dates; n; sum stepPnl);
        steps; rollEvents; select stepDate, asOf, provDateTo from steps)
 };

/ The end-to-end as-of REPLAY: causal butterfly value over dates <= toD, its causal trailing z, the fade
/ position (R16's state machine: SHORT the fly when z>+threshold, LONG when z<-threshold, exit on z-cross /
/ maxHold), then THREE leg replays (leg i position = notional*flyPos*legWeights[i]) combined into one
/ `legs-bearing R12-shape run record (PnL summed across legs; the R19 legs platform, single-commodity here).
.template.crudeButterfly.__replay:{[comm;fromDate;toDate;cfg]
    ch0:.data.hdb.curveHistory[comm; .data.hdb.dates comm];
    ranks:cfg`legRanks; wts:`float$cfg`legWeights;
    fs:.template.crudeButterfly.__flySeries[ch0;ranks;wts;cfg`rollBuffer];
    allDates:fs`date;
    fromD:$[null fromDate; min allDates; fromDate];
    toD:$[null toDate; max allDates; toDate];
    evalMask:allDates<=toD;
    evalDates:allDates where evalMask;
    fly:(fs`fly) where evalMask; legPx:(fs`legPx) where evalMask; legYm:(fs`legYm) where evalMask;
    rm:.template.rv.__rollMean[cfg`zWindow; fly]; rsd:.template.rv.__rollSd[cfg`zWindow; fly];
    z:?[rsd>0f; (fly-rm)%rsd; 0f];
    flyPos:.template.scs.__positions[z; cfg`entryThreshold; cfg`maxHold];   / -1 short fly / +1 long fly
    / bundle the per-leg replay context into one dict (a q lambda takes at most 8 params; SKILL #8).
    la:`comm`evalDates`legPx`legYm`flyPos`noti`wts`fromD`toD`cfg!(comm;evalDates;legPx;legYm;flyPos;cfg`notional;wts;fromD;toD;cfg);
    legReplays:{[la;i]
        .template.crudeButterfly.__legReplay[la`comm; la`evalDates; (la`legYm)[;i]; (la`legPx)[;i]; (la`noti)*(la`flyPos)*(la`wts) i; la`fromD; la`toD; la`cfg]
        }[la] each til count ranks;
    legSteps:legReplays@\:`steps;
    cs:{[legSteps;c] sum legSteps@\:c}[legSteps;];           / elementwise sum of a column across legs
    dates:(legSteps 0)`stepDate; n:count dates;
    keep:evalDates within (fromD;toD);
    flyValue:fly where keep; flyZ:z where keep;
    combinedStepPnl:cs`stepPnl;
    combinedSteps:flip `stepIndex`stepDate`asOf`provDateTo`positionPnl`proportionalCost`slippageCost`fixedCost`rollCost`financingCost`totalCost`stepPnl`cumPnl`flyValue`flySignal!(
        til n; dates; (legSteps 0)`asOf; (legSteps 0)`provDateTo;
        cs`positionPnl; cs`proportionalCost; cs`slippageCost; cs`fixedCost; cs`rollCost;
        cs`financingCost; cs`totalCost; combinedStepPnl; sums combinedStepPnl; flyValue; flyZ);
    `meta`steps`rollEvents`provenance`legs!(
        `strategy`commodity`fromDate`toDate`nSteps`totalPnl!(`crudeButterfly; comm; min dates; max dates; n; sum combinedStepPnl);
        combinedSteps; raze legReplays@\:`rollEvents; (legReplays 0)`provenance; legReplays)
 };

/ The runner seam for the gov gates: run the replay over [from;to] -> (date;pnl) of the COMBINED net PnL.
.template.crudeButterfly.runner:{[comm;cfg] {[comm;cfg;from;to] r:.template.crudeButterfly.__replay[comm;from;to;cfg]; select date:stepDate, pnl:stepPnl from r`steps}[comm;cfg]};

/ The template run (the `template` contract): inputs carry commodity (+ optional overrides / dateFrom /
/ dateTo). Returns `pnl`validation`meta - validation carries the butterfly-stationarity gate (R6's AR(1)/OU
/ on the butterfly VALUE); meta carries the combined (legs-bearing) R12-shape run record.
.template.crudeButterfly.run:{[inputs]
    cfg:.cfg.strategy.crudeButterfly,$[`overrides in key inputs; inputs`overrides; ()!()];
    comm:$[`commodity in key inputs; inputs`commodity; `CRUDE];
    fromD:$[`dateFrom in key inputs; inputs`dateFrom; 0Nd];
    toD:$[`dateTo in key inputs; inputs`dateTo; 0Nd];
    run:.template.crudeButterfly.__replay[comm;fromD;toD;cfg];
    stat:.template.rv.stationarity run[`steps]`flyValue;
    pnl:select date:stepDate, pnl:stepPnl from run`steps;
    `pnl`validation`meta!(
        pnl;
        (enlist `stationarity)!enlist `passed`detail!(stat`stationary; "butterfly-stationarity: AR1=",(string stat`ar1),", half-life=",(string stat`halfLife),", stationary=",string stat`stationary);
        `shape`commodity`nDays`ar1`halfLife`edgeSource`runRecord!(
            `crudeButterfly; comm; count pnl; stat`ar1; stat`halfLife; `structural; run))
 };

.template.register[`crudeButterfly; .template.crudeButterfly.run;
    `contractVersion`description`shape`composes`in`out!(
        1;
        "crude curve butterfly (curvature) mean-reversion: fade the causal z of the level/slope-neutral +1/-2/+1 three-contract fly, trade the actual contracts, emit a combined auditable run record";
        `crudeButterfly;
        `curvatureReversion;
        (enlist `commodity)!enlist `symbol;
        `pnl`validation`meta!`table`dict`dict)];

-1 "crude_butterfly.q loaded - .template.crudeButterfly.* crudeButterfly template registered (R20: curvature mean-reversion; three crude legs via the R19 legs platform; reuses R6/R16 helpers + R10 curvature)";
