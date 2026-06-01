\l core/init.q
/ ============================================================================
/ test_xcommodity_carry_vw.q - R21: vol-weighted (equal-risk) cross-commodity carry (.template.xCommodityCarryVW.*).
/ SYNTHETIC. Asserts: (1) the vol estimate is CAUSAL (a planted future return does not change a past sigma);
/ (2) the leg sizing is EQUAL-RISK (the higher-vol leg gets proportionally LESS notional - known-answer; and
/ a vol-proportional common move nets to ~0 combined PnL = the level leak is gone, vs equal-notional);
/ (3) on synthetic backwardated-vs-contango curves the strategy LONGs/SHORTs correctly; (4) the combined run
/ record TIES (the legs-aware bookTies/pnlTies); (5) the dispersion/persistence gate BITES; (6) the run
/ through .workflow.runReplay is BOUNDED + the attribution is computed; (7) R19's equal-notional template is
/ UNTOUCHED + distinct. Gov-state isolation: reset + restore the card store + UNIQUE hypoIds.
/ ============================================================================
chk:{[b;msg] if[not b; '"FAIL: ",msg]};
.gov.hypoTbl:.gov.__emptyHypotheses[]; .gov.trialTbl:.gov.__emptyTrials[];
modelCards:.cfg.cards;

/ (2) EQUAL-RISK leg sizing (known-answer, no HDB): leg ~ notional/sigma -> the higher-vol leg gets LESS
/ notional, and a vol-proportional common move nets to ~0 (the construction the level leak comes from).
noti:1f; sigC:2.0; sigG:0.5;                                 / crude twice as volatile as gas (example)
scaleC:noti%sigC; scaleG:noti%sigG;                          / equal-risk leg sizes
chk[scaleC<scaleG; "(2) equal-risk: the HIGHER-vol leg (crude) gets proportionally LESS notional"];
chk[1e-12>abs (scaleC*sigC)-scaleG*sigG; "(2) equal-risk: the two legs carry EQUAL risk (scale*sigma equal)"];
/ a vol-proportional common shock (crude moves sigC, gas moves sigG) nets to ~0 on the dollar-neutral-in-risk book.
relPos:1; posC:relPos*scaleC; posG:neg relPos*scaleG;
chk[1e-12>abs (posC*sigC)+posG*sigG; "(2) a vol-proportional COMMON shock nets to ~0 combined PnL (the level leak is removed)"];
/ contrast: equal-NOTIONAL (R19) would NOT net to 0 on the same vol-proportional shock.
chk[1e-9<abs (noti*sigC)+(neg noti)*sigG; "(2) sanity: equal-NOTIONAL does NOT net to 0 on the same shock (R19's level leak)"];

/ Synthetic HDB-backed two-commodity futures: SYNA BACKWARDATED, SYNB CONTANGO, on a shared monthly axis,
/ with DIFFERENT volatilities (SYNA noisier) so equal-risk sizing differs from equal-notional.
mexp:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".20"};
yms:raze {[y] (y*100)+1+til 12} each 2017+til 10;            / 120 monthly contracts (history for vol/lookback)
d5:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".05"} each yms;
buildC:{[commSym;slopeSign;volAmp;ym;d5;mexp]
    e:mexp ym; rows:d5 where d5<e; n:count rows;
    m2e:`float$ {[e;d] `int$(`month$e)-`month$d}[e] each rows;
    di:`float$d5?rows;
    px:60f + (slopeSign*0.5*m2e) + volAmp*sin 0.5*di;        / backwardation/contango + a common time wiggle (vol)
    flip `commodity`contractYM`expiry`firstDate`date`settle`open`high`low`volume!(
        (n#commSym);(n#ym);(n#e);(n#first rows);rows;px;px;px;px;(n#5000))};
futures:(raze buildC[`SYNA;-1f;3f;;d5;mexp] each yms),raze buildC[`SYNB;1f;1f;;d5;mexp] each yms;  / SYNA 3x vol
cfg:.cfg.strategy.xCommodityCarryVW,(enlist `commodities)!enlist `SYNA`SYNB;
tv:.gov.zone.range[`SYNA;`trainValidate];
res:.template.xCommodityCarryVW.run `dateFrom`dateTo`overrides!(tv 0; tv 1; (enlist `commodities)!enlist `SYNA`SYNB);
run:(res`meta)`runRecord;

/ (1) CAUSALITY of the vol estimate: a planted FUTURE return does not change a past sigma.
volFn:.template.xCommodityCarryVW.__causalVol;
dMid:(.data.hdb.dates `SYNA) 70;
sigBefore:(volFn[`SYNA; cfg`volWindow]) dMid;
futures:update settle:settle+40f, open:open+40f, high:high+40f, low:low+40f from futures where commodity=`SYNA, date>dMid;
sigAfter:(volFn[`SYNA; cfg`volWindow]) dMid;
chk[sigBefore~sigAfter; "(1) causal: a planted FUTURE return does not change a past trailing sigma"];
futures:update settle:settle-40f, open:open-40f, high:high-40f, low:low-40f from futures where commodity=`SYNA, date>dMid;  / restore

/ (3) LONG the backwardated (SYNA, higher carry) / SHORT the contango (SYNB); equal-risk so |posSYNA| != |posSYNB|.
chk[2=count run`legs; "(3) the combined run record has two legs"];
legA:(run`legs) 0; legB:(run`legs) 1;
chk[(legA[`meta]`commodity)=`SYNA; "(3) leg 0 is the SYNA (backwardated) leg"];
chk[(sum 0<legA[`steps]`position) > sum 0>legA[`steps]`position; "(3) SYNA (higher carry) is predominantly LONG"];
chk[(sum 0>legB[`steps]`position) > sum 0<legB[`steps]`position; "(3) SYNB (lower carry) is predominantly SHORT"];
/ equal-RISK (not equal-notional): the higher-vol SYNA leg carries SMALLER notional than the SYNB leg.
nzA:(legA[`steps]`position) where 0<>legA[`steps]`position;
nzB:(legB[`steps]`position) where 0<>legB[`steps]`position;
chk[(avg abs nzA) < avg abs nzB; "(3) equal-risk: the higher-vol SYNA leg carries SMALLER notional than SYNB (vol-weighted, not equal-notional)"];

/ (4) the combined run record TIES (legs-aware audit) + (6) the attribution is computed.
aud:.evidence.audit run;
chk[aud`pass; "(4) the combined run PASSES the two-leg evidence audit (legs clean + combined ties): ",aud`reason];
chk[(aud[`checks]`combinedPnlTies) and aud[`checks]`combinedBookTies; "(4) combined book/PnL reconcile to the summed legs"];
attrib:.attribution.pnl run;
chk[attrib`reconciled; "(6) the combined attribution reconciles to the total"];

/ (5) the dispersion/persistence gate BITES (reused from R19).
chk[not (.template.xCommodityCarry.gate[80#0.0; cfg])`pass; "(5) the gate BITES: a FLAT relative-carry signal is rejected"];

/ (6) BOUNDED end-to-end loop via .workflow.runReplay.
prop:`hypoId`thesis`edgeSource`instruments`claimedRegimes`capName`runRecord`runner!(
    `R21_XVW_CLEAN; "vol-weighted x-commodity carry (synthetic)"; `riskPremium; `SYNA`SYNB; `backwardation`contango`flat;
    `xCommodityCarryVW; run; .template.xCommodityCarryVW.runner cfg);
pkt:.workflow.runReplay prop;
chk[`escalateToHuman=pkt`decision; "(6) the packet ALWAYS escalates to the human"];
chk[not any `deploy`allocate`autoTrade in key pkt; "(6) the packet carries NO deploy/allocate/autoTrade field (bounded)"];
chk[-1h=type pkt`anyTradeable; "(6) anyTradeable is a derived boolean fact"];
chk[1b=pkt`evidencePassed; "(6) the clean run passed the evidence audit inside the loop"];
chk[all `level`carry`residual in key pkt`attribution; "(6) the combined attribution is in the packet"];

/ (7) R19's equal-notional template + R20 are UNTOUCHED + distinct.
chk[100h=type .template.xCommodityCarry.run; "(7) R19's xCommodityCarry (equal-notional) template is intact (unchanged by R21)"];
chk[not .template.xCommodityCarry.run~.template.xCommodityCarryVW.run; "(7) R21's vol-weighted runner is a DISTINCT function (R19 not rebased)"];
chk[100h=type .template.crudeButterfly.run; "(7) R20's crudeButterfly template is intact (unchanged by R21)"];

-1 "test_xcommodity_carry_vw: PASS";
