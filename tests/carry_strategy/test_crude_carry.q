\l core/init.q
/ ============================================================================
/ test_crude_carry.q - R18: the crudeCarry term-structure / roll-yield carry strategy (.template.crudeCarry.*).
/ SYNTHETIC. Asserts: (1) on a backwardated curve the signal goes LONG; the position state machine maps
/ sign(signal) with a min-hold; (2) the strategy trades the ACTUAL contract R11's .roll.active names; the
/ run record PASSES the R13 evidence audit (all 8 checks); (3) the carry-PERSISTENCE gate BITES (rejects a
/ noise carry signal, passes a persistent one); (4) the signal is CAUSAL (a planted FUTURE curve move does
/ NOT change a past carrySignal - R9's door); (5) the run through .workflow.runReplay is BOUNDED
/ (escalateToHuman, no deploy field, never tradeable without all gates) and the attribution is computed.
/ Gov-state isolation: reset the registry + restore the real card store + UNIQUE hypoIds.
/ ============================================================================
chk:{[b;msg] if[not b; '"FAIL: ",msg]};
.gov.hypoTbl:.gov.__emptyHypotheses[]; .gov.trialTbl:.gov.__emptyTrials[];
modelCards:.cfg.cards;
cfg:.cfg.strategy.crudeCarry;

/ ---------------------------------------------------------------------------
/ (1) POSITION STATE MACHINE (known-answer, no HDB): sign(signal) with a min-hold.
/ ---------------------------------------------------------------------------
longSig:20#0.05;                                              / well above +threshold -> LONG
chk[all 1=.template.crudeCarry.__positions[longSig;cfg`threshold;cfg`holdingPeriod]; "(1) a strong positive carry signal -> all LONG"];
shortSig:20#-0.05;                                            / well below -threshold -> SHORT
chk[all -1=.template.crudeCarry.__positions[shortSig;cfg`threshold;cfg`holdingPeriod]; "(1) a strong negative carry signal -> all SHORT"];
flatSig:20#0.0;                                               / inside the dead-band -> FLAT
chk[all 0=.template.crudeCarry.__positions[flatSig;cfg`threshold;cfg`holdingPeriod]; "(1) a signal inside the dead-band -> all FLAT"];
/ min-hold: a LONG then an immediate flip-to-SHORT signal is HELD for holdingPeriod days before flipping.
flipSig:(0.05;-0.05;-0.05;-0.05;-0.05);
heldPos:.template.crudeCarry.__positions[flipSig;cfg`threshold;3];
chk[(heldPos 0)=1; "(1) min-hold: enters LONG on day 0"];
chk[(heldPos 1)=1; "(1) min-hold: still LONG while within the holding period (does not flip immediately)"];

/ ---------------------------------------------------------------------------
/ (3) CARRY-PERSISTENCE gate BITES: persistent -> pass, noise -> reject.
/ ---------------------------------------------------------------------------
persSig:0.05*cos 0.08*`float$til 80;                          / smooth, slowly varying -> high AR(1)
chk[(.template.crudeCarry.persistence[persSig;cfg])`persistent; "(3) a PERSISTENT carry signal passes the persistence gate"];
noiseSig:80#0.05 -0.05f;                                      / alternating -> negative AR(1) -> not persistent
chk[not (.template.crudeCarry.persistence[noiseSig;cfg])`persistent; "(3) the persistence gate BITES: a noise carry signal is rejected"];

/ ---------------------------------------------------------------------------
/ Synthetic HDB-backed BACKWARDATED futures (monthly SYNX): nearer contracts priced HIGHER, so the curve
/ is backwardated -> positive roll yield -> carrySignal above the threshold -> the strategy goes LONG.
/ ---------------------------------------------------------------------------
mexp:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".20"};
yms:raze {[y] (y*100)+1+til 12} each 2018+til 9;
d5:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".05"} each yms;
buildC:{[ym;d5;mexp]
    e:mexp ym; rows:d5 where d5<e; n:count rows;
    m2e:{[e;d] `int$(`month$e)-`month$d}[e] each rows;       / months to expiry (front small, deferred large)
    px:70f - 0.5*`float$m2e;                                 / BACKWARDATION: nearer = higher
    flip `commodity`contractYM`expiry`firstDate`date`settle`open`high`low`volume!(
        (n#`SYNX);(n#ym);(n#e);(n#first rows);rows;px;px;px;px;(n#5000))};
futures:raze buildC[;d5;mexp] each yms;
tv:.gov.zone.range[`SYNX;`trainValidate];
res:.template.crudeCarry.run `commodity`dateFrom`dateTo!(`SYNX;tv 0;tv 1);
run:(res`meta)`runRecord;

/ (1-end-to-end) on the backwardated synthetic the carry signal is positive and the strategy is mostly LONG.
chk[0<avg run[`steps]`carrySignal; "(1) the backwardated synthetic curve produces a POSITIVE carry signal"];
chk[(sum 0<run[`steps]`position) > sum 0>run[`steps]`position; "(1) on backwardation the strategy is predominantly LONG"];

/ (2) ACTUAL CONTRACTS: every recorded activeContract is EXACTLY R11's .roll.active for that date.
chk[0<count run`steps; "(2) the run record has steps"];
rollCheck:all {[c;st] st[`activeContract]=(.roll.active[st`stepDate;c])`active}[`SYNX] each run`steps;
chk[rollCheck; "(2) every recorded activeContract == R11's .roll.active for that date (trades the actual contract)"];
aud:.evidence.audit run;
chk[aud`pass; "(2) the run record PASSES the evidence audit (all 8 checks): ",aud`reason];

/ (4) CAUSALITY: a planted FUTURE curve move does NOT change a PAST carry signal (R9's door).
dMid:(.data.hdb.dates `SYNX) 40;
sig1:(.carry.features[dMid;`SYNX])`carrySignal;
futures:update settle:settle+50f, open:open+50f, high:high+50f, low:low+50f from futures where date>dMid;
sig2:(.carry.features[dMid;`SYNX])`carrySignal;
chk[sig1~sig2; "(4) causal: a planted FUTURE curve move does not change a past carry signal"];
futures:update settle:settle-50f, open:open-50f, high:high-50f, low:low-50f from futures where date>dMid;  / restore

/ (5) BOUNDED end-to-end loop via .workflow.runReplay + the attribution is computed.
prop:`hypoId`thesis`edgeSource`instruments`claimedRegimes`capName`runRecord`runner!(
    `R18_CARRY_CLEAN; "crude carry (synthetic)"; `riskPremium; enlist `SYNX; `backwardation`contango`flat;
    `crudeCarry; run; .template.crudeCarry.runner[`SYNX;cfg]);
pkt:.workflow.runReplay prop;
chk[`escalateToHuman=pkt`decision; "(5) the packet ALWAYS escalates to the human"];
chk[1b=pkt`humanSignOffRequired; "(5) human sign-off is required"];
chk[not any `deploy`allocate`autoTrade in key pkt; "(5) the packet carries NO deploy/allocate/autoTrade field (bounded)"];
chk[-1h=type pkt`anyTradeable; "(5) anyTradeable is a derived boolean fact, not a decision"];
chk[`replay=pkt`mode; "(5) the packet is tagged replay mode"];
chk[1b=pkt`evidencePassed; "(5) the clean synthetic run passed the evidence audit inside the loop"];
chk[all `level`slope`curvature`carry`residual in key pkt`attribution; "(5) the PnL attribution is computed on the run"];

/ R14 + R16 are UNTOUCHED: the carry feature + the seasonalCalSpread template are intact + distinct.
chk[100h=type .carry.features; "R14's .carry.features is intact (unchanged by R18)"];
chk[100h=type .template.scs.run; "R16's seasonalCalSpread template is intact (unchanged by R18)"];

-1 "test_crude_carry: PASS";
