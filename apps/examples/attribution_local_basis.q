\l core/init.q
/ ============================================================================
/ attribution_local_basis.q - example (NOT a test). POST-FOUNDATION R22.
/ The local-basis attribution refinement, demonstrated + contrasted. R20's butterfly was constructed
/ correctly (global level+slope ~ 0) yet GLOBAL-residual-dominated, because a near-curve fly's LOCAL
/ curvature is not spanned by R15's GLOBAL level/slope/curvature basis (which peaks mid-curve). That is a
/ blind spot in the evidence layer's "residual = unexplained = noise" reading: a large residual can mean
/ BASIS MISMATCH (localized real structure), not noise. R22's local basis (3 fixed factors fit to the
/ TRADED-tenor sub-curve) + reporting GLOBAL vs LOCAL residual distinguishes the two:
/   LOW local + HIGH global  = localized real structure the global basis missed   (the R20 butterfly)
/   HIGH local               = genuine idiosyncratic noise (the real red flag)     (the safeguard)
/ Self-contained (synthetic, no HDB). Runs are RETURN-booked, matching the attribution's per-Pp convention.
/ ============================================================================
flyYms:202501+til 12;
flyMexp:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".20"} each flyYms;
flyDts:2024.06.05 2024.06.12 2024.06.19 2024.06.26 2024.07.03;
nearBow:{[r] $[r<=4; (r*4f-r)%4f; 0f]};                      / a bow peaking at rank 2, zero beyond rank 4 (LOCAL to the near curve)
mkFut:{[yms;mexp;dts;amp;bowfn]
    raze {[ym;rk;e;dts;amp;bowfn] px:60f+(0.2*rk)+amp*bowfn rk;
        flip `commodity`contractYM`expiry`firstDate`date`settle`open`high`low`volume!(
            (count[dts]#`SYN);(count[dts]#ym);(count[dts]#e);(count[dts]#first dts);dts;px;px;px;px;count[dts]#5000)}[;;;dts;amp;bowfn]'[yms; til count yms; mexp]};
pxOf:{[d;c] first exec settle from futures where date=d, contractYM=c};
mkLeg:{[ym;w;dts] px:pxOf[;ym] each dts; n:count dts;
    `meta`steps!((`commodity`strategy!(`SYN;`hand)); flip `stepDate`activeContract`position`stepPnl!(dts; n#ym; n#w; (0f,-1_n#w)*0f,(1_deltas px)%(-1_px)))};

/ (1) the R20-shaped case: a butterfly (+1/-2/+1 on the near tenors) through a DIRECTIONAL localized curvature.
futures:mkFut[flyYms;flyMexp;flyDts;0 3 6 9 12f;nearBow];
flyRun:(`meta`legs)!((enlist[`commodity]!enlist `SYN); mkLeg[;;flyDts]'[flyYms 0 2 4; 1 -2 1f]);
gFly:.attribution.pnl flyRun; lFly:.attribution.pnlLocal flyRun; sFly:.attribution.residualSplit flyRun;
-1 "(1) R20-shaped butterfly - a localized near-curve curvature move (the curve's curvature, not noise):";
-1 "    GLOBAL basis: curvature=",(string gFly`curvature),"  residual fraction=",string gFly`residualFraction;
-1 "    LOCAL  basis: curvature=",(string lFly`curvature),"  residual fraction=",string lFly`residualFraction;
-1 "    => GLOBAL residual is HIGH (the whole-curve bow peaks mid-curve, ~0 at the near fly tenors, so it CANNOT see";
-1 "       the localized curvature) but LOCAL residual is ~0 (the traded-tenor sub-curve basis captures it exactly).";
-1 "    verdict: ",(string sFly`verdict)," -> the R20 residual was BASIS-MISMATCH (localized structure), NOT noise.";
-1 "";

/ (2) the SAFEGUARD: a genuine high-frequency idiosyncratic move (a zigzag), orthogonal to the smooth shapes.
yms6:202406+til 6;
mkSnap:{[date;prices] e:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".20"} each yms6;
    flip `commodity`contractYM`expiry`firstDate`date`settle`open`high`low`volume!(
        (6#`SYN);yms6;e;(6#date);(6#date);prices;prices;prices;prices;(6#5000))};
pd:2024.06.03; cd:2024.06.04; zig:0.6*(-1 1 -1 1 -1 1f);
futures:(mkSnap[pd;6#60f]),mkSnap[cd;60f+zig];
heldZ:yms6 3; heldRetZ:((60f+zig 3)-60f)%60f;
zigRun:(`meta`steps`rollEvents`provenance)!((`commodity`fromDate`toDate!(`SYN;pd;cd));
    flip `stepIndex`stepDate`activeContract`position`stepPnl`totalCost`financingCost!((0 1);(pd;cd);(heldZ;heldZ);(1f;1f);(0f;heldRetZ);(0f;0f);(0f;0f)); (); ());
gZig:.attribution.pnl zigRun; lZig:.attribution.pnlLocal zigRun; sZig:.attribution.residualSplit zigRun;
-1 "(2) SAFEGUARD - a genuine high-frequency idiosyncratic (zigzag) move, orthogonal to level/slope/curvature:";
-1 "    GLOBAL residual fraction=",(string gZig`residualFraction),"   LOCAL residual fraction=",string lZig`residualFraction;
-1 "    => the LOCAL residual stays HIGH: the THREE fixed local factors do NOT span the zigzag, so the local basis";
-1 "       honestly does NOT explain genuine noise (a basis flexible enough to explain everything would measure nothing).";
-1 "    verdict: ",(string sZig`verdict)," -> genuine idiosyncratic noise (the real red flag).";
-1 "";
-1 "THE DISTINCTION restored: reporting GLOBAL vs LOCAL residual tells basis-mismatch (low local / high global -> localized";
-1 "structure the global basis missed, the R20 case) APART from genuine noise (high local -> the real red flag). After R22,";
-1 "every verdict's residual means what the governance layer assumes it means.";
-1 "";
-1 "NOTE (honest scope): R15's attribution is in RETURN units (per-price); a strategy run booking DOLLAR PnL";
-1 "(position x price-change, as the R16-R20 templates do) is residual-dominated under it regardless of basis -";
-1 "a unit-convention effect distinct from basis-mismatch. This demonstration uses RETURN-booked runs so the basis";
-1 "is the operative factor; the global-basis .attribution.pnl behaviour is unchanged (byte-identical).";

exit 0;
