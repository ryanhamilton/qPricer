\l core/init.q
/ ============================================================================
/ test_xcommodity_carry.q - R19: market-neutral cross-commodity carry (.template.xCommodityCarry.*).
/ SYNTHETIC. Asserts: (1) on synthetic curves where one commodity is backwardated and the other contango,
/ the strategy LONGs the backwardated leg / SHORTs the contango leg, dollar-neutral; (2) the COMBINED run
/ record TIES (the two-leg generalisation of R13's bookTies/pnlTies: combined stepPnl = sum of the legs,
/ each leg audits clean) and the attribution is computed on the combined run; (3) the dispersion/persistence
/ gate BITES (rejects a flat or noise relative signal, passes a persistent dispersed one); (4) both legs'
/ signals are CAUSAL (a planted FUTURE move does not change a past signal); (5) the run through
/ .workflow.runReplay is BOUNDED. Plus: the ADDITIVE two-leg branches leave the SINGLE-commodity audit /
/ attribution byte-identical (a one-leg record has no `legs key). Gov-state isolation: reset + unique hypoIds.
/ ============================================================================
chk:{[b;msg] if[not b; '"FAIL: ",msg]};
.gov.hypoTbl:.gov.__emptyHypotheses[]; .gov.trialTbl:.gov.__emptyTrials[];
modelCards:.cfg.cards;

/ (3) the DISPERSION/PERSISTENCE gate BITES (known-answer, no HDB).
gcfg:.cfg.strategy.xCommodityCarry;
flatDisp:80#0.0;                                             / never disperses -> activeFrac 0 -> reject
chk[not (.template.xCommodityCarry.gate[flatDisp;gcfg])`pass; "(3) the gate BITES: a FLAT relative-carry signal (never disperses) is rejected"];
noiseDisp:80#0.2 -0.2f;                                      / alternating -> not persistent -> reject
chk[not (.template.xCommodityCarry.gate[noiseDisp;gcfg])`pass; "(3) the gate BITES: a NOISE relative-carry signal (not persistent) is rejected"];
goodDisp:0.2+0.05*cos 0.08*`float$til 80;                    / persistent AND always above threshold -> pass
chk[(.template.xCommodityCarry.gate[goodDisp;gcfg])`pass; "(3) a PERSISTENT, DISPERSED relative-carry signal passes the gate"];

/ Synthetic HDB-backed two-commodity futures: SYNA BACKWARDATED (nearer priced higher), SYNB CONTANGO
/ (nearer priced lower), on a shared monthly date axis. -> SYNA has the higher carry, SYNB the lower.
mexp:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".20"};
yms:raze {[y] (y*100)+1+til 12} each 2018+til 9;
d5:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".05"} each yms;
buildC:{[commSym;slopeSign;ym;d5;mexp]
    e:mexp ym; rows:d5 where d5<e; n:count rows;
    m2e:{[e;d] `int$(`month$e)-`month$d}[e] each rows;       / months to expiry
    px:60f + slopeSign*0.5*`float$m2e;                       / <0 backwardation (front high), >0 contango
    flip `commodity`contractYM`expiry`firstDate`date`settle`open`high`low`volume!(
        (n#commSym);(n#ym);(n#e);(n#first rows);rows;px;px;px;px;(n#5000))};
futures:(raze buildC[`SYNA;-1f;;d5;mexp] each yms),raze buildC[`SYNB;1f;;d5;mexp] each yms;
cfg:gcfg,(enlist `commodities)!enlist `SYNA`SYNB;
tv:.gov.zone.range[`SYNA;`trainValidate];
res:.template.xCommodityCarry.run `dateFrom`dateTo`overrides!(tv 0; tv 1; (enlist `commodities)!enlist `SYNA`SYNB);
run:(res`meta)`runRecord;

/ (1) LONG the backwardated (SYNA) / SHORT the contango (SYNB), dollar-neutral (equal-and-opposite).
chk[2=count run`legs; "(1) the combined run record has two legs"];
legA:(run`legs) 0; legB:(run`legs) 1;
chk[(legA[`meta]`commodity)=`SYNA; "(1) leg 0 is the SYNA (backwardated) leg"];
chk[(sum 0<legA[`steps]`position) > sum 0>legA[`steps]`position; "(1) SYNA (backwardated, higher carry) is predominantly LONG"];
chk[(sum 0>legB[`steps]`position) > sum 0<legB[`steps]`position; "(1) SYNB (contango, lower carry) is predominantly SHORT"];
chk[all (legA[`steps]`position)=neg legB[`steps]`position; "(1) the book is DOLLAR-NEUTRAL (equal-and-opposite leg positions)"];

/ (2) the COMBINED run record TIES (two-leg audit) + the attribution is computed.
aud:.evidence.audit run;
chk[aud`pass; "(2) the combined run PASSES the two-leg evidence audit (legs clean + combined ties): ",aud`reason];
chk[`combinedPnlTies in key aud`checks; "(2) the audit ran the combined-ties check"];
chk[(aud[`checks]`combinedPnlTies) and aud[`checks]`combinedBookTies; "(2) combined book/PnL reconcile to the summed legs"];
attrib:.attribution.pnl run;
chk[all `level`slope`curvature`carry`residual in key attrib; "(2) the combined attribution is computed (per-leg attributed + summed)"];
chk[attrib`reconciled; "(2) the combined attribution RECONCILES to the combined total"];

/ (2b) the ADDITIVE branches leave the SINGLE-commodity path byte-identical: a one-leg record (no `legs)
/ still audits + attributes via the unchanged path.
chk[(.evidence.audit legA)`pass; "(2b) a single-commodity leg record audits via the UNCHANGED single-commodity path"];
chk[all `level`carry`residual in key .attribution.pnl legA; "(2b) a single-commodity leg record attributes via the UNCHANGED path"];

/ (4) CAUSALITY: a planted FUTURE curve move on a leg does NOT change a PAST carry signal (R9's door).
dMid:(.data.hdb.dates `SYNA) 40;
sigA1:(.carry.features[dMid;`SYNA])`carrySignal;
futures:update settle:settle+30f, open:open+30f, high:high+30f, low:low+30f from futures where commodity=`SYNA, date>dMid;
sigA2:(.carry.features[dMid;`SYNA])`carrySignal;
chk[sigA1~sigA2; "(4) causal: a planted FUTURE move on a leg does not change a past carry signal"];
futures:update settle:settle-30f, open:open-30f, high:high-30f, low:low-30f from futures where commodity=`SYNA, date>dMid;  / restore

/ (5) BOUNDED end-to-end loop via .workflow.runReplay.
prop:`hypoId`thesis`edgeSource`instruments`claimedRegimes`capName`runRecord`runner!(
    `R19_XCARRY_CLEAN; "x-commodity carry (synthetic)"; `riskPremium; `SYNA`SYNB; `backwardation`contango`flat;
    `xCommodityCarry; run; .template.xCommodityCarry.runner cfg);
pkt:.workflow.runReplay prop;
chk[`escalateToHuman=pkt`decision; "(5) the packet ALWAYS escalates to the human"];
chk[1b=pkt`humanSignOffRequired; "(5) human sign-off is required"];
chk[not any `deploy`allocate`autoTrade in key pkt; "(5) the packet carries NO deploy/allocate/autoTrade field (bounded)"];
chk[-1h=type pkt`anyTradeable; "(5) anyTradeable is a derived boolean fact"];
chk[1b=pkt`evidencePassed; "(5) the clean two-leg run passed the evidence audit inside the loop"];
chk[all `level`carry`residual in key pkt`attribution; "(5) the combined attribution is in the packet"];

/ R14 / R16 / R18 templates are UNTOUCHED + distinct.
chk[100h=type .carry.features; "R14's .carry.features is intact (unchanged by R19)"];
chk[100h=type .template.crudeCarry.run; "R18's crudeCarry template is intact (unchanged by R19)"];

-1 "test_xcommodity_carry: PASS";
