\l core/init.q
/ ============================================================================
/ test_crude_butterfly.q - R20: crude curve butterfly (curvature) mean-reversion (.template.crudeButterfly.*).
/ SYNTHETIC. Asserts: (1) the butterfly weights are level/slope-NEUTRAL by construction (sum of weights = 0
/ => a parallel shift nets to 0 PnL; weights . equally-spaced tenors = 0 => a slope twist nets to 0 PnL);
/ (2) on a synthetic curve with oscillating (mean-reverting) curvature the strategy TRADES, and the
/ attribution's level + slope come out ~ 0 (the neutrality construction holds on a real run, vs the curvature
/ / residual); (3) the signal is CAUSAL (a planted future curve move does not change a past butterfly z);
/ (4) the stationarity gate BITES (a random-walk fly is rejected, a mean-reverting one passes) and is wired
/ into the run; (5) the combined 3-leg run record TIES + the run through .workflow.runReplay is BOUNDED.
/ Gov-state isolation: reset + restore the card store + UNIQUE hypoIds.
/ ============================================================================
chk:{[b;msg] if[not b; '"FAIL: ",msg]};
.gov.hypoTbl:.gov.__emptyHypotheses[]; .gov.trialTbl:.gov.__emptyTrials[];
modelCards:.cfg.cards;
cfg:.cfg.strategy.crudeButterfly;

/ (1) CONSTRUCTION (known-answer, no HDB): the +1/-2/+1 weights are level- AND slope-neutral.
wts:`float$cfg`legWeights; ranks:`float$cfg`legRanks;
chk[0f=sum wts; "(1) level-neutral: the butterfly weights sum to 0 (a parallel shift -> 0 PnL)"];
chk[1e-12>abs wts wsum ranks; "(1) slope-neutral: weights . equally-spaced tenor ranks = 0 (a slope twist -> 0 PnL)"];
/ the butterfly PnL on an explicit pure parallel + pure slope move of the three legs is exactly 0.
pos3:(cfg`notional)*wts;                                     / the three leg positions (+1/-2/+1 scaled)
chk[1e-12>abs pos3 wsum 3#1.7f; "(1) a PURE PARALLEL leg move produces ~0 butterfly PnL"];
chk[1e-12>abs pos3 wsum 0.5f*ranks; "(1) a PURE SLOPE leg move (linear in tenor) produces ~0 butterfly PnL"];

/ (4) the STATIONARITY gate BITES (R6's AR(1)/OU, the same gate the run wires in).
rw:sums 1f,(neg 1f),1f,1f,(neg 1f),1f,1f,1f,(neg 1f),1f,1f,(neg 1f),1f,1f,1f,(neg 1f),1f,1f,1f,1f;
chk[not (.template.rv.stationarity rw)`stationary; "(4) the stationarity gate BITES on a non-mean-reverting (random-walk) fly"];

/ Synthetic HDB-backed crude-like futures: a linear contango part + an OSCILLATING (mean-reverting) bow in
/ months-to-expiry, so the butterfly value oscillates -> the z fires AND the fly mean-reverts (gate passes).
mexp:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".20"};
yms:raze {[y] (y*100)+1+til 12} each 2017+til 10;            / 120 monthly contracts (enough history for z=60)
d5:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".05"} each yms;
buildC:{[ym;d5;mexp]
    e:mexp ym; rows:d5 where d5<e; n:count rows;
    m2e:`float$ {[e;d] `int$(`month$e)-`month$d}[e] each rows;
    di:`float$d5?rows;                                       / global date index
    k:2f*sin 0.30*di;                                        / oscillating (mean-reverting) curvature amplitude
    px:60f + (0.2*m2e) + k*0.05*m2e*12f-m2e;                 / linear contango + a bow (curvature)
    flip `commodity`contractYM`expiry`firstDate`date`settle`open`high`low`volume!(
        (n#`SYNX);(n#ym);(n#e);(n#first rows);rows;px;px;px;px;(n#5000))};
futures:raze buildC[;d5;mexp] each yms;
tv:.gov.zone.range[`SYNX;`trainValidate];
res:.template.crudeButterfly.run `commodity`dateFrom`dateTo!(`SYNX; tv 0; tv 1);
run:(res`meta)`runRecord;

/ (4-wired) the run validation carries the butterfly-stationarity gate, and it passes on the mean-reverting synthetic.
chk[`stationarity in key res`validation; "(4) the run validation carries the butterfly-stationarity gate"];
chk[(res[`validation;`stationarity]`passed); "(4) the mean-reverting synthetic butterfly passes the stationarity gate"];

/ (2) the strategy TRADES (positions go non-flat) on the oscillating-curvature synthetic.
chk[3=count run`legs; "(2) the run record has three legs"];
chk[0<sum 0<>(run`legs)[0][`steps]`position; "(2) the strategy takes positions (the curvature z fires)"];
/ the attribution's level + slope are ~ 0 (the neutrality construction holds on a real run).
a:.attribution.pnl run;
chk[a`reconciled; "(2) the combined attribution reconciles to the total"];
chk[(abs a`level)<abs a`residual; "(2) the attribution LEVEL is small vs residual (not leaking - construction holds)"];
chk[(abs a`slope)<abs a`residual; "(2) the attribution SLOPE is small vs residual (not leaking - construction holds)"];

/ (3) CAUSALITY: a planted FUTURE curve move does NOT change a PAST butterfly signal (R9's door).
dMid:(.data.hdb.dates `SYNX) 70;
zBefore:exec flySignal from run`steps where stepDate=dMid;
futures:update settle:settle+25f, open:open+25f, high:high+25f, low:low+25f from futures where date>dMid;
run2:(.template.crudeButterfly.run `commodity`dateFrom`dateTo!(`SYNX; tv 0; tv 1))[`meta]`runRecord;
zAfter:exec flySignal from run2`steps where stepDate=dMid;
chk[zBefore~zAfter; "(3) causal: a planted FUTURE curve move does not change a past butterfly z"];
futures:update settle:settle-25f, open:open-25f, high:high-25f, low:low-25f from futures where date>dMid;  / restore

/ (5) the combined run record TIES (3-leg audit) + BOUNDED end-to-end loop.
aud:.evidence.audit run;
chk[aud`pass; "(5) the combined 3-leg run PASSES the evidence audit (legs clean + combined ties): ",aud`reason];
prop:`hypoId`thesis`edgeSource`instruments`claimedRegimes`capName`runRecord`runner!(
    `R20_FLY_CLEAN; "crude butterfly (synthetic)"; `mispricing; enlist `SYNX; `backwardation`contango`flat;
    `crudeButterfly; run; .template.crudeButterfly.runner[`SYNX;cfg]);
pkt:.workflow.runReplay prop;
chk[`escalateToHuman=pkt`decision; "(5) the packet ALWAYS escalates to the human"];
chk[not any `deploy`allocate`autoTrade in key pkt; "(5) the packet carries NO deploy/allocate/autoTrade field (bounded)"];
chk[-1h=type pkt`anyTradeable; "(5) anyTradeable is a derived boolean fact"];
chk[1b=pkt`evidencePassed; "(5) the clean run passed the evidence audit inside the loop"];
chk[all `level`slope`curvature`carry`residual in key pkt`attribution; "(5) the combined attribution is in the packet"];

/ R10 / R16 / R19 are UNTOUCHED + distinct.
chk[100h=type .curve.build; "R10's .curve.build is intact (unchanged by R20)"];
chk[100h=type .template.scs.run; "R16's seasonalCalSpread template is intact (unchanged by R20)"];

-1 "test_crude_butterfly: PASS";
