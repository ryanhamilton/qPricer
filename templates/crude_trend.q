/ templates/crude_trend.q - the crudeTrend problem template (.template.crudeTrend.*) (v0.89, Post-foundation R24)
/ ----------------------------------------------------------------------------
/ R24: a DIRECTIONAL crude trend / time-series-momentum strategy, run END-TO-END through the foundation AND
/ against a PASSIVE-LONG-CRUDE benchmark. R23's re-attribution showed that on this data the PnL across every
/ strategy is LEVEL/directional-dominated - the relative and structural dimensions (slope/curvature/carry)
/ carry no tradeable edge; the action is all in the DIRECTIONAL dimension. So the one strategy question left
/ is whether the directional dimension ITSELF is tradeable: is there a timing / trend edge OVER passive beta,
/ or does everything reduce to being long crude? R24 answers it.
/ -
/ THE POINT (read first): for a DIRECTIONAL strategy the usual reads INVERT. (a) A LEVEL-dominated attribution
/ is EXPECTED, not a red flag - the thesis IS directional, so "the PnL is mostly level" is the strategy
/ WORKING. (b) The deflated-Sharpe gate alone is NOT sufficient: passive long crude ALSO has a Sharpe, so a
/ strategy that merely TIMES beta can clear the absolute bar while adding nothing. The meaningful test is
/ BENCHMARK-RELATIVE: does timing the directional dimension BEAT simply holding it? That needs an
/ apples-to-apples passive-long benchmark (same period, same roll + costs through R12) and the strategy's
/ ALPHA OVER BETA. Both outcomes are conclusive: real alpha + cleared gates = the first genuine edge candidate
/ the arc has produced; no alpha (just timed beta) and/or no gates = the directional dimension is also
/ no-tradeable-edge and the strategy line is honestly CONCLUDED for this data.
/ -
/ DO NOT TUNE: the trend lookback / thresholds are the easiest things to overfit (the lookback IS the knob).
/ They are PRE-REGISTERED in .cfg.strategy.crudeTrend (FIXED, round, a-priori) and run ONCE.
/ -
/ THE TEMPLATE: a time-series-momentum rule - LONG when the CAUSAL trailing-lookback return is positive
/ (> +threshold), SHORT (or FLAT) when negative (< -threshold), with a min holdingPeriod (cuts whipsaw). The
/ trend signal is the trailing-lookback SUM of the active contract's roll-clean daily returns (causal, through
/ R9's door); positions on the ACTUAL contract R11's .roll.active names; books its own price change NET of
/ .exec.fill; emits an R12-shape run record so R13's audit + R15's attribution consume it. REUSES R18's helpers
/ (__activeSeries / __positions / persistence) - the only differences are the SIGNAL (trend, not carry) and the
/ PASSIVE-LONG BENCHMARK. Edge: RISK-PREMIUM (time-series momentum / trend) - but the HONEST caveat is that for
/ a directional strategy the edge must be ALPHA OVER BETA (timing), not absolute return (which includes beta).
/ -
/ RESERVED-NAME NOTE: `asOf` NEVER `asof`; `comm` NOT `commodity`; builtins not shadowed (avg/dev/var/signum/
/ first/last/sums/deltas/prev/differ/fills/msum/mavg). msum/mavg are causal moving-window builtins.
/ ----------------------------------------------------------------------------

/ The trend-PERSISTENCE gate: REUSE R18's AR(1) persistence (persistent iff ar1 >= minPersistence), fed the
/ daily $-change series (the returns the trend is built on). Trend-following NEEDS momentum: a mean-reverting
/ (negative-AR(1)) / non-trending series is the WRONG tool and is REJECTED before the universal gates. This is
/ the persistence ORIENTATION the milestone asks for (the opposite bar to the mean-reversion gates).
.template.crudeTrend.persistence:.template.crudeCarry.persistence;

/ The per-date active contract + its as-of price over the evaluation dates (<= toDate). pm is the asofDate ->
/ (contractYM -> price) map. The active contract is R11's .roll.active (REUSED from R18). PURE w.r.t. the HDB.
.template.crudeTrend.__series:{[comm;toDate]
    ch0:.data.hdb.curveHistory[comm; .data.hdb.dates comm];
    pm:exec contractYM!price by asofDate from ch0;
    allDates:asc distinct ch0`asofDate;
    toD:$[null toDate; max allDates; toDate];
    evalDates:allDates where allDates<=toD;
    actAll:.template.crudeCarry.__activeSeries[comm; evalDates];                / R11's .roll.active per date
    pxAll:{[pm;d;a] p:pm[d][a]; $[null p; 0n; p]}[pm]'[evalDates;actAll];       / the active contract's as-of price
    `allDates`evalDates`actAll`pxAll!(allDates;evalDates;actAll;pxAll)
 };

/ The shared booking core: given the per-date active contract / price / position / signal series (over the FULL
/ eval window), slice to [fromD;toD] and book NET PnL via .exec.fill, emitting an R12-shape run record. The
/ active contract's OWN price change (difference method): 0 on a roll day (contract changed) and 0 where a
/ price is missing, so PnL never books a roll gap. (Per-date inputs bundled into a dict - SKILL #8.) The trend
/ strategy and the passive benchmark share this core verbatim; only the position series differs.
.template.crudeTrend.__book:{[comm;ser;fromD;toD;cfg]
    evalDates:ser`evalDates; actAll:ser`actAll; pxAll:ser`pxAll; posAll:ser`posAll; sigAll:ser`sigAll;
    keep:evalDates within (fromD;toD);
    dates:evalDates where keep; ac:actAll where keep; px:pxAll where keep;
    posK:posAll where keep; sigK:sigAll where keep;
    n:count dates;
    isRoll:differ ac; isRoll[0]:0b;
    dPriceFull:deltas px; nullMask:(null px) or null prev px;
    dPrice:?[isRoll or nullMask; 0f; dPriceFull]; dPrice[0]:0f;
    px:fills px;                                                / forward-fill for the refPrice column (no nulls)
    posLag:0f,-1_posK;                                          / position held INTO each day's move
    positionPnl:posLag*dPrice;
    order:deltas posK; filledQty:order;
    execCfg:.exec.__resolve cfg;
    cost:{[execCfg;ord] (.exec.fill[ord; `refPrice`currentPos!(1f;0f); execCfg])`totalCost}[execCfg] each order;
    stepPnl:positionPnl-cost;
    steps:flip `stepIndex`stepDate`asOf`activeContract`isRoll`rollFrom`position`frontReturn`positionPnl`proportionalCost`slippageCost`fixedCost`rollCost`financingCost`totalCost`stepPnl`cumPnl`filledQty`refPrice`provDateTo`trendSignal!(
        til n; dates; dates; ac; isRoll; ?[isRoll; prev ac; 0Nj]; posK; dPrice; positionPnl;
        cost; n#0f; n#0f; n#0f; n#0f; cost; stepPnl; sums stepPnl; filledQty; px; dates; sigK);
    rollEvents:select date:stepDate, commodity:comm, fromContract:rollFrom, toContract:activeContract, reason:`trendRoll from steps where isRoll;
    `meta`steps`rollEvents`provenance!(
        `strategy`commodity`fromDate`toDate`nSteps`totalPnl!(`crudeTrend; comm; min dates; max dates; n; sum stepPnl);
        steps; rollEvents; select stepDate, asOf, provDateTo from steps)
 };

/ The CAUSAL trend signal over the eval window: the trailing-lookback SUM of the active contract's roll-clean
/ daily returns (deltas price / prior price; 0 on a roll / a missing print). LONG when > +threshold, SHORT
/ when < -threshold, FLAT in the dead-band (R18's position state machine). allowShort=0b clamps SHORT -> FLAT.
.template.crudeTrend.__positionsFromSeries:{[ser;cfg]
    actAll:ser`actAll; pxAll:ser`pxAll;
    isRollAll:differ actAll; isRollAll[0]:0b;
    dPxAll:deltas pxAll; nullMaskAll:(null pxAll) or null prev pxAll;
    retAll:?[isRollAll or nullMaskAll; 0f; dPxAll % prev pxAll]; retAll[0]:0f;   / roll-clean daily returns
    trendAll:(cfg`lookback) msum retAll;                        / trailing-lookback cumulative return (causal)
    posRaw:.template.crudeCarry.__positions[trendAll; cfg`threshold; cfg`holdingPeriod];   / +1/-1/0 (R18 machine)
    posAll:cfg[`notional]*$[cfg`allowShort; posRaw; 0|posRaw];  / FLAT instead of SHORT if shorts disallowed
    `posAll`sigAll!(posAll; trendAll)
 };

/ The end-to-end as-of REPLAY of the trend strategy -> an R12-shape run record (R13 audit + R15 attribution).
.template.crudeTrend.__replay:{[comm;fromDate;toDate;cfg]
    ser:.template.crudeTrend.__series[comm;toDate];
    fromD:$[null fromDate; min ser`allDates; fromDate];
    toD:$[null toDate; max ser`allDates; toDate];
    ps:.template.crudeTrend.__positionsFromSeries[ser;cfg];
    ser:ser,ps;                                                / add posAll / sigAll
    .template.crudeTrend.__book[comm;ser;fromD;toD;cfg]
 };

/ The PASSIVE-LONG-CRUDE benchmark replay: ALWAYS long the active contract (+notional every day), rolled by
/ R11 and filled by R12 over the SAME window - the apples-to-apples beta the trend strategy must BEAT.
.template.crudeTrend.__passiveReplay:{[comm;fromDate;toDate;cfg]
    ser:.template.crudeTrend.__series[comm;toDate];
    fromD:$[null fromDate; min ser`allDates; fromDate];
    toD:$[null toDate; max ser`allDates; toDate];
    nE:count ser`evalDates;
    ser:ser,`posAll`sigAll!(cfg[`notional]*nE#1f; nE#1f);      / always long
    .template.crudeTrend.__book[comm;ser;fromD;toD;cfg]
 };

/ Annualised Sharpe of a per-day PnL series (252 trading days). Apples-to-apples for trend vs passive.
.template.crudeTrend.__sharpe:{[pnl] sd:dev pnl; $[0f=sd; 0f; (sqrt 252f)*(avg pnl)%sd]};

/ The ALPHA-OVER-BETA comparison (THE meaningful read for a directional strategy): replay the trend strategy
/ AND the passive-long benchmark over the SAME [from;to] (same roll + costs through R12), and report each one's
/ total PnL + Sharpe, the ALPHA (trend - passive total), the Sharpe difference, and whether trend BEATS passive.
.template.crudeTrend.benchmark:{[comm;fromDate;toDate;cfg]
    tr:.template.crudeTrend.__replay[comm;fromDate;toDate;cfg];
    pa:.template.crudeTrend.__passiveReplay[comm;fromDate;toDate;cfg];
    trP:tr[`steps]`stepPnl; paP:pa[`steps]`stepPnl;
    trTot:sum trP; paTot:sum paP;
    trSh:.template.crudeTrend.__sharpe trP; paSh:.template.crudeTrend.__sharpe paP;
    `trendTotal`passiveTotal`alpha`trendSharpe`passiveSharpe`sharpeAlpha`beatsPassive!(
        trTot; paTot; trTot-paTot; trSh; paSh; trSh-paSh; trSh>paSh)
 };

/ The runner seam for the gov gates: run the trend replay over [from;to] -> (date;pnl). Reuses __replay.
.template.crudeTrend.runner:{[comm;cfg] {[comm;cfg;from;to] r:.template.crudeTrend.__replay[comm;from;to;cfg]; select date:stepDate, pnl:stepPnl from r`steps}[comm;cfg]};

/ The template run (the `template` contract): inputs carry commodity (+ optional overrides / dateFrom / dateTo).
/ Returns `pnl`validation`meta - validation carries the trend-persistence gate; meta carries the R12-shape run
/ record (the artifact .workflow.runReplay audits + attributes) AND the passive-long benchmark comparison.
.template.crudeTrend.run:{[inputs]
    cfg:.cfg.strategy.crudeTrend,$[`overrides in key inputs; inputs`overrides; ()!()];
    comm:$[`commodity in key inputs; inputs`commodity; `CRUDE];
    fromD:$[`dateFrom in key inputs; inputs`dateFrom; 0Nd];
    toD:$[`dateTo in key inputs; inputs`dateTo; 0Nd];
    run:.template.crudeTrend.__replay[comm;fromD;toD;cfg];
    pers:.template.crudeTrend.persistence[run[`steps]`frontReturn; cfg];        / momentum persistence of the $-changes
    bench:.template.crudeTrend.benchmark[comm;fromD;toD;cfg];                    / the alpha-over-beta comparison
    pnl:select date:stepDate, pnl:stepPnl from run`steps;
    `pnl`validation`meta!(
        pnl;
        (enlist `persistence)!enlist `passed`detail!(pers`persistent; "trend-persistence (momentum): AR1=",(string pers`ar1),", persistent=",(string pers`persistent)," (bar minPersistence=",(string cfg`minPersistence),")");
        `shape`commodity`nDays`trendAr1`edgeSource`runRecord`benchmark!(
            `crudeTrend; comm; count pnl; pers`ar1; `riskPremium; run; bench))
 };

.template.register[`crudeTrend; .template.crudeTrend.run;
    `contractVersion`description`shape`composes`in`out!(
        1;
        "time-series momentum / trend-following on crude: LONG when the causal trailing-return trend is positive, SHORT/FLAT when negative, trade the actual front contract (R11), emit an auditable run record; the edge must be ALPHA OVER BETA (timing) - measured against a passive-long benchmark, not absolute return";
        `crudeTrend;
        `timeSeriesMomentumTrend;
        (enlist `commodity)!enlist `symbol;
        `pnl`validation`meta!`table`dict`dict)];

-1 "crude_trend.q loaded - .template.crudeTrend.* crudeTrend template registered (R24: directional trend strategy + passive-long benchmark / alpha-over-beta; reuses R18 helpers)";
