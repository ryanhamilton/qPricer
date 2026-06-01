\l core/init.q
/ ============================================================================
/ test_attribution.q - PnL explain + bucketed curve risk (.attribution.*). R15. SYNTHETIC.
/ KNOWN-ANSWER decompositions on hand-built runs: a pure PARALLEL move -> level (residual~0); a pure
/ SLOPE move on a deferred position -> slope dominant; a pure ROLL-DOWN -> carry; THE RECONCILIATION
/ (level+slope+curvature+carry+residual == realized total within tol); an UNEXPLAINED move -> high
/ residual fraction; the bucketed risk -> per-tenor delta + roll-down sign.
/ ============================================================================
chk:{[b;msg] if[not b; '"FAIL: ",msg]};
apx:{[a;b;tol] tol>abs a-b};

/ 6 monthly contracts; build a futures snapshot on `date` with the given per-contract prices.
yms:202406+til 6;
mkSnap:{[date;prices] e:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".20"} each yms; n:6;
    flip `commodity`contractYM`expiry`firstDate`date`settle`open`high`low`volume!(
        (n#`SYN);yms;e;(n#date);(n#date);prices;prices;prices;prices;(n#5000))};
/ a 2-step run holding `heldYM` (position 1) across (prevDate -> curDate); stepPnl[1] = the held
/ contract's realized return (so the decomposition has a real total to reconcile to).
mkRun:{[prevDate;curDate;heldYM;heldRet]
    steps:flip `stepIndex`stepDate`activeContract`position`frontReturn`positionPnl`stepPnl`totalCost`financingCost!(
        (0 1); (prevDate;curDate); (heldYM;heldYM); (1f;1f); (0f;heldRet); (0f;heldRet); (0f;heldRet); (0f;0f); (0f;0f));
    `meta`steps`rollEvents`provenance!((`commodity`fromDate`toDate!(`SYN;prevDate;curDate)); steps; (); ())};
pd:2024.06.03; cd:2024.06.04;
tau:{[date] (((mkSnap[date;6#0f])`expiry)-date)%365};       / per-contract tenor (years) on a date

/ === (1) PURE PARALLEL: flat curve + a uniform +0.5 shift; held front -> level dominates ===
futures:(mkSnap[pd;6#60f]),mkSnap[cd;6#60.5f];
r1:mkRun[pd;cd;first yms;(60.5-60)%60];
a1:.attribution.pnl r1;
chk[a1`reconciled; "(parallel) the decomposition reconciles to the realized total"];
chk[(abs a1`level)>(abs a1`slope)+(abs a1`curvature)+abs a1`carry; "(parallel) level is the dominant component"];
chk[1e-6>a1`residualFraction; "(parallel) the residual fraction is ~0 (fully explained by level)"];

/ === (2) PURE SLOPE (R10 slope shape = k*(tenor-frontTenor)); held a DEFERRED contract -> slope dominates ===
tcd:tau cd; k:6f;
futures:(mkSnap[pd;6#60f]),mkSnap[cd;60f+k*tcd-first tcd];   / curDate = flat + k*(tenor-front)
heldD:yms 4;                                                / a deferred contract (not the front pivot)
heldRet2:((60f+k*(tcd 4)-first tcd)-60f)%60f;               / the deferred contract's realized return
r2:mkRun[pd;cd;heldD;heldRet2];
a2:.attribution.pnl r2;
chk[a2`reconciled; "(slope) the decomposition reconciles"];
chk[(abs a2`slope)>(abs a2`level)|(abs a2`curvature)|abs a2`carry; "(slope) slope is the dominant component on a deferred position"];

/ === (3) PURE ROLL-DOWN: a TENOR-SPACE-STATIC backwardated curve C(tau)=70-8*tau; held front, aged 30
/ days -> the held contract slides UP the static backwardated curve as its tenor shrinks -> carry ===
pd3:2024.06.03; cd3:2024.07.03;                            / 30 days apart -> meaningful roll-down
fr:yms 2;                                                  / a deferred contract that survives both dates
pd3Prices:70f-8f*tau pd3;                                  / each contract priced off the fixed curve C(tau)
cd3Prices:70f-8f*tau cd3;                                  / 30 days later: each contract's tenor shrank
futures:(mkSnap[pd3;pd3Prices]),mkSnap[cd3;cd3Prices];
heldRet3:((cd3Prices 2)-pd3Prices 2)%pd3Prices 2;          / the held contract's realized roll-down return
r3:mkRun[pd3;cd3;fr;heldRet3];
a3:.attribution.pnl r3;
chk[a3`reconciled; "(carry) the decomposition reconciles"];
chk[(abs a3`carry)>(abs a3`level)|(abs a3`slope)|abs a3`curvature; "(carry) carry is the dominant curve-factor component on a static curve"];

/ === (4) UNEXPLAINED: a high-frequency zigzag shift (orthogonal to level/slope/butterfly) -> high residual ===
zig:0.6*(-1 1 -1 1 -1 1f);                                  / alternating, not spanned by the smooth basis
futures:(mkSnap[pd;6#60f]),mkSnap[cd;60f+zig];
heldZ:yms 3;
heldRetZ:((60f+zig 3)-60f)%60f;
r4:mkRun[pd;cd;heldZ;heldRetZ];
a4:.attribution.pnl r4;
chk[a4`reconciled; "(unexplained) the decomposition reconciles"];
chk[0.5<a4`residualFraction; "(unexplained) an out-of-basis move lands in residual with a HIGH residual fraction"];

/ === (5) bucketed risk: a known front position -> delta in the front bucket; roll-down sign matches ===
futures:(mkSnap[pd3;pd3Prices]),mkSnap[cd3;cd3Prices];
rk:.attribution.risk r3;
chk[1f=(rk`bucketDelta)`b0; "(risk) the front position's delta is in the front tenor bucket"];
chk[0f<rk`rollDownExposure; "(risk) roll-down exposure is positive on a backwardated curve (long, +rollYield)"];
chk[1f=rk`calendarSpreadExposure; "(risk) the single-leg calendar-spread exposure equals the position"];

/ === (R22) LOCAL-basis attribution: distinguishes localized structure (basis-mismatch) from genuine noise ===
/ N monthly contracts + a DIRECTIONAL localized near-curvature (a bow over ranks 0..4) where the GLOBAL bow
/ (peaks mid-curve) is ~0 -> the global basis misses it; the local traded-tenor basis captures it. Runs are
/ RETURN-booked (stepPnl = position * return), matching the attribution's per-Pp convention (test 1-4 above).
flyYms:202501+til 12;
flyMexp:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".20"} each flyYms;
flyDts:2024.06.05 2024.06.12 2024.06.19 2024.06.26 2024.07.03;
nearBow:{[r] $[r<=4; (r*4f-r)%4f; 0f]};                      / a bow peaking at rank 2, zero at rank 0/4 and beyond
mkFut:{[yms;mexp;dts;amp;bowfn]
    raze {[ym;rk;e;dts;amp;bowfn] px:60f+(0.2*rk)+amp*bowfn rk;
        flip `commodity`contractYM`expiry`firstDate`date`settle`open`high`low`volume!(
            (count[dts]#`SYN);(count[dts]#ym);(count[dts]#e);(count[dts]#first dts);dts;px;px;px;px;count[dts]#5000)}[;;;dts;amp;bowfn]'[yms; til count yms; mexp]};
pxOf:{[d;c] first exec settle from futures where date=d, contractYM=c};
mkLeg:{[ym;w;dts] px:pxOf[;ym] each dts; n:count dts;
    `meta`steps!((`commodity`strategy!(`SYN;`hand)); flip `stepDate`activeContract`position`stepPnl!(dts; n#ym; n#w; (0f,-1_n#w)*0f,(1_deltas px)%(-1_px)))};

futures:mkFut[flyYms;flyMexp;flyDts;0 3 6 9 12f;nearBow];    / directional growing localized curvature
flyRun:(`meta`legs)!((enlist[`commodity]!enlist `SYN); mkLeg[;;flyDts]'[flyYms 0 2 4; 1 -2 1f]);
gFly:.attribution.pnl flyRun; lFly:.attribution.pnlLocal flyRun;
chk[lFly`reconciled; "(R22) the LOCAL decomposition reconciles to the realized total"];
chk[(lFly`residualFraction) < gFly`residualFraction; "(R22) localized curvature: LOCAL residual fraction < GLOBAL (the traded-tenor basis captures what the global basis missed)"];
chk[0.2>lFly`residualFraction; "(R22) localized curvature: LOCAL residual is LOW (the curvature IS captured -> structure, not noise)"];
chk[0.4<gFly`residualFraction; "(R22) localized curvature: GLOBAL residual is HIGH (the global basis cannot see the near-curve curvature) - the R20 basis-mismatch case"];
chk[`localizedStructure=(.attribution.residualSplit flyRun)`verdict; "(R22) residualSplit classifies it as localizedStructure (basis-mismatch, not noise)"];

/ THE SAFEGUARD: a genuine high-frequency NOISE move (the zigzag case r4 above - a move orthogonal to the
/ smooth shapes) must keep a HIGH local residual too: the THREE fixed local factors do NOT span it, so the
/ local basis RECOVERS the meaning of residual rather than destroying it (residual is NOT forced to 0). The
/ basis is 3 fixed factors regardless of contract count - a one-factor-per-contract basis would explain this.
futures:(mkSnap[pd;6#60f]),mkSnap[cd;60f+zig];               / restore the zigzag snapshot (test 4's curve)
lNoise:.attribution.pnlLocal r4;
chk[lNoise`reconciled; "(R22 safeguard) the noise LOCAL decomposition reconciles"];
chk[0.5<lNoise`residualFraction; "(R22 safeguard) genuine high-frequency noise keeps a HIGH local residual - 3 fixed factors do NOT spuriously explain it (residual not forced to 0)"];
chk[`genuineNoise=(.attribution.residualSplit r4)`verdict; "(R22 safeguard) residualSplit classifies the noise run as genuineNoise (the real red flag)"];

-1 "test_attribution: PASS";
