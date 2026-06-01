/ templates/xcommodity_carry_vw.q - the xCommodityCarryVW problem template (.template.xCommodityCarryVW.*) (v0.86, Post-foundation R21)
/ ----------------------------------------------------------------------------
/ R21: R19's market-neutral cross-commodity carry, but with the two legs sized by CAUSAL trailing realised
/ VOLATILITY (equal-RISK / risk-parity, not equal-notional) - the direct, attribution-driven next iteration
/ of R19. R19 confirmed a REAL relative carry premium (residual 0.98 -> 0.38, carry +0.69 -> +2.62 once the
/ common beta was stripped) but its attribution flagged a large LEVEL term: equal-notional != equal-risk -
/ crude and gas have different volatilities, so a dollar-neutral book still carries directional exposure.
/ R21 fixes exactly that - size each leg ~ 1/sigma so the legs contribute EQUAL RISK, driving the level term
/ toward ~0 and isolating the relative carry premium as cleanly as this data allows.
/ -
/ THE ONLY CHANGE FROM R19 is the leg sizing. Everything else is R19's construction - REUSED VERBATIM:
/ the carry signal (.template.crudeCarry.__carrySeries), the relative-position state machine
/ (.template.crudeCarry.__positions), the per-leg R12 replay (.template.xCommodityCarry.__legReplay), the
/ dispersion/persistence gate (.template.xCommodityCarry.gate), and the combined `legs-bearing run record
/ consumed by the R19 `legs-aware audit/attribution. R19's equal-notional template stays FROZEN as the
/ historical record of the equal-notional verdict (the R8/R17 precedent). R20 / .workflow.runReplay / gov/ /
/ the R12/R13/R15 cores UNCHANGED.
/ -
/ DO NOT TUNE: the vol window + R19's dispersion threshold / lookback / holding period are PRE-REGISTERED in
/ .cfg.strategy.xCommodityCarryVW (FIXED, round, a-priori). The point is the CONCLUSIVE read on cross-commodity
/ carry, not a passing one: a cleaner isolation (level -> ~0, carry share up) that is STILL sub-cost
/ (vol-weighting cleans the isolation, it does not lower the two-leg cost gate) is the honest end of the line.
/ -
/ CAUSAL VOL: sigma is a TRAILING realised $ vol of the front price CHANGES (plain differences - robust to the
/ non-positive crude print, like .factor.changePanel), through R9's door (date<=asOf). A full-sample sigma
/ would be look-ahead; a planted future return cannot change a past sigma.
/ -
/ RESERVED-NAME NOTE: `asOf` NEVER `asof`; `comm` NOT `commodity`; builtins not shadowed (dev/var/avg/
/ first/last/sums/deltas/inter).
/ ----------------------------------------------------------------------------

/ Causal trailing realised $ vol per date: the trailing-window stddev of the front price CHANGES (plain
/ differences - robust to non-positive prints). Returns a date->sigma dict. CAUSAL (each sigma uses only
/ price changes up to that date). The legs are sized inversely to this (equal risk).
.template.xCommodityCarryVW.__causalVol:{[comm;volWindow]
    ch:.data.hdb.curveHistory[comm; .data.hdb.dates comm];
    g:0!select front:first price by asofDate from `asofDate`tenor xasc ch;
    fp:`float$g`front;
    dp:0f,1_ deltas fp;                                      / daily front price changes (0 on day 0)
    (g`asofDate)!.template.rv.__rollSd[volWindow; dp]        / causal trailing $ vol per date
 };

/ The end-to-end as-of REPLAY: R19's relative-carry position, but EQUAL-RISK sized (leg ~ notional/sigma).
/ Reuses R19's per-leg replay + R18's carry/position helpers; combines into a `legs-bearing record (the only
/ delta from R19 is scaleC/scaleG = notional/sigma instead of a flat notional).
.template.xCommodityCarryVW.__replay:{[fromDate;toDate;cfg]
    cl:cfg`commodities; crude:cl 0; gas:cl 1;
    common:asc (.data.hdb.dates crude) inter .data.hdb.dates gas;
    fromD:$[null fromDate; min common; fromDate];
    toD:$[null toDate; max common; toDate];
    evalDates:common where common<=toD;
    csC:.template.crudeCarry.__carrySeries[crude; evalDates];   / R14 carry per date (causal), crude
    csG:.template.crudeCarry.__carrySeries[gas; evalDates];     / R14 carry per date (causal), gas
    disp:csC-csG;
    sm:.template.rv.__rollMean[cfg`lookback; disp];
    relPos:.template.crudeCarry.__positions[sm; cfg`dispersionThreshold; cfg`holdingPeriod];   / +1 long crude/short gas
    volC:(.template.xCommodityCarryVW.__causalVol[crude; cfg`volWindow]) evalDates;
    volG:(.template.xCommodityCarryVW.__causalVol[gas;   cfg`volWindow]) evalDates;
    noti:cfg`notional;
    / equal-RISK leg sizing: scale ~ 1/sigma (higher-vol leg -> less notional), but NORMALISED by the per-date
    / geometric-mean vol so the OVERALL notional stays ~noti (comparable to R19) - the 1/sigma RATIO is what
    / matters (scaleC*volC == scaleG*volG => equal $ risk), not the absolute scale. (Normalising the
    / proportionality constant is not tuning the verdict; it just keeps the notional interpretable.)
    volBar:sqrt volC*volG;
    scaleC:?[volC>0f; (noti*volBar)%volC; 0f];
    scaleG:?[volG>0f; (noti*volBar)%volG; 0f];
    posC:relPos*scaleC; posG:neg relPos*scaleG;              / equal-RISK long/short (the higher-vol leg sized down)
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
            `xCommodityCarryVW; crude; cl; min dates; max dates; n; sum combinedStepPnl);
        combinedSteps; (legC`rollEvents),legG`rollEvents; legC`provenance; (legC;legG))
 };

/ The runner seam for the gov gates: run the replay over [from;to] -> (date;pnl) of the COMBINED net PnL.
.template.xCommodityCarryVW.runner:{[cfg] {[cfg;from;to] r:.template.xCommodityCarryVW.__replay[from;to;cfg]; select date:stepDate, pnl:stepPnl from r`steps}[cfg]};

/ The template run (the `template` contract): inputs optional (overrides / dateFrom / dateTo). Reuses R19's
/ dispersion/persistence gate (.template.xCommodityCarry.gate) verbatim; meta carries the combined run record.
.template.xCommodityCarryVW.run:{[inputs]
    cfg:.cfg.strategy.xCommodityCarryVW,$[`overrides in key inputs; inputs`overrides; ()!()];
    fromD:$[`dateFrom in key inputs; inputs`dateFrom; 0Nd];
    toD:$[`dateTo in key inputs; inputs`dateTo; 0Nd];
    run:.template.xCommodityCarryVW.__replay[fromD;toD;cfg];
    g:.template.xCommodityCarry.gate[run[`steps]`relSignal; cfg];
    pnl:select date:stepDate, pnl:stepPnl from run`steps;
    `pnl`validation`meta!(
        pnl;
        (enlist `dispersion)!enlist `passed`detail!(g`pass; "dispersion/persistence: AR1=",(string g`ar1),", activeFrac=",(string g`activeFrac),", dispersed=",(string g`dispersed),", persistent=",(string g`persistent),", pass=",string g`pass);
        `shape`commodity`commodities`nDays`dispersionAr1`edgeSource`runRecord!(
            `xCommodityCarryVW; (cfg`commodities) 0; cfg`commodities; count pnl; g`ar1; `riskPremium; run))
 };

.template.register[`xCommodityCarryVW; .template.xCommodityCarryVW.run;
    `contractVersion`description`shape`composes`in`out!(
        1;
        "vol-weighted (equal-risk) market-neutral cross-commodity carry: R19's long higher-carry / short lower-carry crude-vs-gas, each leg sized ~1/sigma (causal trailing vol) so the common beta is neutralised properly and the relative carry premium is isolated cleanly";
        `xCommodityCarryVW;
        `crossCommodityCarryRiskParity;
        (enlist `commodities)!enlist `symbol;
        `pnl`validation`meta!`table`dict`dict)];

-1 "xcommodity_carry_vw.q loaded - .template.xCommodityCarryVW.* xCommodityCarryVW template registered (R21: vol-weighted/equal-risk cross-commodity carry; reuses R19 composition + helpers, only the leg sizing changes)";
