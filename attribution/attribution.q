/ attribution/attribution.q - PnL explain + bucketed curve risk (.attribution.*) (v0.80 R15 / v0.87 R22 / v0.88 R23)
/ ----------------------------------------------------------------------------
/ ARCHITECTURE.md Part II 11.8(g) / 13-R15. Turns "explain why this makes money" from prose into a
/ QUANTITATIVE attribution: given a replay run record (R12) + the curve (R10), decompose the realized
/ PnL into commodity-market components - level / slope / curvature / carry / residual - and compute the
/ bucketed curve risk on the positions. This is the quantitative form of the "name which of the three
/ edges" discipline (Sec 10): mostly CARRY = a harvested risk premium; mostly SLOPE/curvature = a
/ structural relative-value normalisation; a large RESIDUAL = unexplained (a red flag for noise/overfit).
/ -
/ LAYERING (the correction): the attribution is a NEW HIGH layer ABOVE backtest/ - it CONSUMES a replay
/ run record (which lives in backtest/), so it canNOT live in analytics/ (analytics/ is BELOW backtest/;
/ that would be an illegal upward dependency). It reads backtest/ (the run record - a data structure),
/ curve/ (R10's curve + the parallel/slope/butterfly shock operators - the decomposition BASIS - and
/ rollYield), and state/ (R9) - all downward. Loads after the backtest block; opens nothing at import.
/ ADDITIVE: it does NOT touch the existing analytics/ risk functions and does NOT rewire cards/.
/ -
/ THE DECOMPOSITION (reconciles by construction). Per step the active contract's price change splits as
/ P_t(tau_t) - P_{t-1}(tau_{t-1}) = [P_t(tau_t) - P_t(tau_{t-1})]  (the CARRY / roll-down along the
/ current curve as the contract ages) + [P_t(tau_{t-1}) - P_{t-1}(tau_{t-1})] (the curve SHIFT at the
/ fixed tenor). The shift is projected onto R10's parallel/slope/butterfly shapes (normal equations) ->
/ level/slope/curvature; whatever the basis does not span is the curve RESIDUAL. residual is DEFINED as
/ realizedStepPnL - (level+slope+curvature+carry), so it also absorbs costs/financing - and the five
/ ALWAYS reconcile to the realized total (like R13's pnlTies). A large residual FRACTION is the
/ quantitative "name which edge, or it's noise."
/ -
/ UNITS / ROLL DISCIPLINE (R23, the correction that makes residual mean what the governance layer assumes).
/ R15's components were always in RETURN units (a /Pp divide), so they reconcile to a run whose stepPnl is
/ position*return (R15's own tests + the generic R12 replay). But the R16-R21 strategy templates book DOLLAR
/ PnL (position*dP, net of costs); attributed in return units, the components came out ~1/Pp too small and the
/ residual absorbed almost the whole PnL - residual-dominated by a UNIT MISMATCH, not by basis or noise (this
/ was a large part of R20's 1.06). R23 makes the decomposition UNITS-AWARE: it attributes in the SAME units as
/ the run's realized PnL. .attribution.__resolveUnits decides dollar-vs-return per run (an explicit `units key
/ on the run/meta or .cfg.attribution`defaultUnits wins; otherwise it INFERS by comparing the run's booked
/ price PnL to the reconstructed dollar-vs-return gross - the ~Pp factor makes single-contract records
/ unambiguous). DOLLAR runs attribute price-unit components (NO /Pp); RETURN runs keep the original /Pp path
/ BYTE-IDENTICALLY (R15's tests + R22's return-booked synthetics are unchanged to the last bit). R23 ALSO routes
/ ROLL-step PnL (the difference-method contract switch - not a curve move) to CARRY, not residual: on isRoll the
/ booked positionPnl is the carry component and level/slope/curvature are 0 (so a roll books no phantom curve
/ move into residual). Both are gated additively - records without `units / isRoll / positionPnl take the
/ original path. The bounded fix; the R12/R13 cores + the strategy templates + how they book PnL are UNCHANGED.
/ -
/ RESERVED-NAME NOTE: `asOf` NEVER `asof`; `comm` NOT `commodity`; builtins not shadowed (lsq/mmu/inv/
/ sum/wsum/avg/dev/var/first/last/bin/binr). The basis is derived FROM R10's shock operators (not reinvented).
/ ----------------------------------------------------------------------------

.attribution.defaultConfig:{[] .cfg.attribution};

/ ── helpers ──────────────────────────────────────────────────────────────────

/ Linear interpolation of a curve (sorted ascending tenors xs -> prices ys) at tenor x (flat outside).
.attribution.__interp:{[xs;ys;x]
    $[x<=first xs; first ys;
      x>=last xs; last ys;
      [j:xs bin x; x0:xs j; x1:xs j+1; (ys j)+((ys j+1)-ys j)*(x-x0)%x1-x0]]
 };

/ The level/slope/curvature shape vectors on a curve, derived FROM R10's shock operators (a unit shock
/ minus the base price): parallel -> 1s, slope -> tenor-first, butterfly -> the 4x(1-x) bow.
.attribution.__shapes:{[curve]
    px:`float$curve`price;
    (((.curve.shock.parallel[curve;1f])`price)-px;
     ((.curve.shock.slope[curve;1f])`price)-px;
     ((.curve.shock.butterfly[curve;1f])`price)-px)
 };

/ Least-squares coefficients (3-vec) for dP ~ B*coefs (B is M x 3) via the normal equations; 0 0 0f on
/ too-few rows / a singular system (then the whole shift lands in the residual).
.attribution.__solve:{[B;dP]
    $[3>count dP; 0 0 0f;
        @[{[B;dP] bt:flip B; (inv bt mmu B) mmu bt mmu dP}[B;]; dP; {[e] 0 0 0f}]]
 };

/ ── units resolution (R23) ────────────────────────────────────────────────────

/ Reconstruct one step's gross price move BOTH ways (dollar prevPos*(Pt-Pp); return prevPos*(Pt-Pp)/Pp),
/ for the units inference. Returns (grossDollar; grossReturn; valid). t=0 / a missing curve / the active
/ contract off either curve / a non-positive prior price -> not valid (excluded from the inference sums).
.attribution.__reconMove:{[cc;steps;prevPos;t]
    if[t=0; :(0f;0f;0b)];
    d:steps[t]`stepDate; p:steps[t-1]`stepDate; c:steps[t]`activeContract;
    ccur:cc d; cprev:cc p;
    if[((::)~ccur) or (::)~cprev; :(0f;0f;0b)];
    curP:cprev`curve; curC:ccur`curve;
    cymP:curP`contractYM; cymC:curC`contractYM;
    iP:cymP?c; iC:cymC?c;
    if[(iP=count cymP) or iC=count cymC; :(0f;0f;0b)];
    Pp:`float$(curP`price) iP;
    if[Pp<=0f; :(0f;0f;0b)];
    Pt:`float$(curC`price) iC;
    gd:(prevPos t)*Pt-Pp;
    (gd; gd%Pp; 1b)
 };

/ The inference evidence for ONE single-commodity record: (sumBookedPricePnL; sumGrossDollar; sumGrossReturn)
/ over the CLEAN steps (valid reconstruction + not a roll). Booked price PnL = positionPnl (or stepPnl+totalCost
/ if positionPnl is absent). 0 0 0f when there is nothing to reconstruct. Aggregating these across the legs of a
/ legs record is robust to a degenerate leg (e.g. a constant-price wing whose reconstruction is all zero).
.attribution.__unitsEvidence:{[run]
    steps:run`steps; n:count steps;
    if[0=n; :0 0 0f];
    if[not `activeContract in cols steps; :0 0 0f];
    comm:(run`meta)`commodity;
    udts:asc distinct steps`stepDate;
    cc:udts!{[comm;dd] @[{.curve.build[x;y]}[;comm];dd;{[e] (::)}]}[comm] each udts;
    prevPos:0f^prev steps`position;
    recon:.attribution.__reconMove[cc;steps;prevPos;] each til n;
    valid:`boolean$recon[;2];
    isRollV:$[`isRoll in cols steps; `boolean$steps`isRoll; n#0b];
    clean:valid and not isRollV;
    if[0=sum clean; :0 0 0f];
    gD:`float$recon[;0]; gR:`float$recon[;1];
    booked:$[`positionPnl in cols steps; `float$steps`positionPnl;
             (`float$steps`stepPnl)+$[`totalCost in cols steps; `float$steps`totalCost; 0f]];
    (sum booked where clean; sum gD where clean; sum gR where clean)
 };

/ Decide whether a run is DOLLAR- or RETURN-booked -> 1b (dollar) / 0b (return). An explicit `units key on
/ the run (then its meta) wins; then .cfg.attribution`defaultUnits if not `infer; else INFER: reconstruct the
/ gross price move both ways and pick whichever matches the run's booked price PnL - the ~Pp factor makes a
/ single-contract record unambiguous. A legs record aggregates the evidence over ALL legs (robust to a
/ degenerate leg). The tie-break is STRICT (dollar iff |booked-grossDollar| < |booked-grossReturn|), so a
/ degenerate / all-zero / Pp~1 case defaults to RETURN - the original R15 path, the safe historical default.
.attribution.__resolveUnits:{[run]
    if[`units in key run; :`dollar=run`units];
    m:$[`meta in key run; run`meta; ()!()];
    if[`units in key m; :`dollar=m`units];
    du:.cfg.attribution`defaultUnits;
    if[not `infer~du; :`dollar=du];
    ev:$[`legs in key run; sum .attribution.__unitsEvidence each run`legs; .attribution.__unitsEvidence run];
    sb:ev 0; sgd:ev 1; sgr:ev 2;
    (abs sb-sgd)<abs sb-sgr
 };

/ Per-step component tuple (level;slope;curvature;carry) in the run's units (dollar iff dollar=1b, else the
/ original return units). cc is the date->curve-object cache; t is the step index (t=0 -> all zero: no prior
/ curve). R23 roll routing: on a roll step (isRoll=1b) the booked positionPnl is the CARRY component and the
/ curve components are 0 (a contract switch is not a curve move - so no phantom move pollutes residual).
.attribution.__stepComp:{[cc;steps;prevPos;dollar;t]
    if[t=0; :0 0 0 0f];
    if[$[`isRoll in cols steps; `boolean$steps[t]`isRoll; 0b];
        :(0f;0f;0f; $[`positionPnl in cols steps; `float$steps[t]`positionPnl; 0f])];
    d:steps[t]`stepDate; p:steps[t-1]`stepDate; c:steps[t]`activeContract;
    ccur:cc d; cprev:cc p;
    if[((::)~ccur) or (::)~cprev; :0 0 0 0f];
    curC:ccur`curve; curP:cprev`curve;
    cymP:curP`contractYM; cymC:curC`contractYM;
    iP:cymP?c; iC:cymC?c;
    if[(iP=count cymP) or iC=count cymC; :0 0 0 0f];     / active not on both curves -> all residual
    Pp:`float$(curP`price) iP;
    if[Pp<=0f; :0 0 0 0f];
    Pt:`float$(curC`price) iC;
    tauP:`float$(curP`tenor) iP;
    shp:.attribution.__shapes curP; L:shp 0; S:shp 1; Cv:shp 2;
    / curve SHIFT at FIXED tenor: interpolate the CURRENT curve at each prior tenor, minus the prior
    / price (so the roll-down/aging is NOT in the projection - that is the carry term, computed below).
    ccurT:`float$curC`tenor; ccurP:`float$curC`price;
    tenP:`float$curP`tenor;
    dP:(.attribution.__interp[ccurT;ccurP;] each tenP)-`float$curP`price;
    coefs:.attribution.__solve[flip (L;S;Cv); dP];
    / carry / roll-down: the active contract's actual new price vs the current curve at its OLD tenor.
    carryMove:Pt - .attribution.__interp[ccurT; ccurP; tauP];
    pp:prevPos t;
    / R23 units: DOLLAR -> price-unit components (NO /Pp), reconciling to position*dP; RETURN -> the original
    / /Pp expressions (BYTE-IDENTICAL to R15), reconciling to position*dP/Pp.
    $[dollar;
      ((pp*(coefs 0)*L iP);                              / level (dollar)
       (pp*(coefs 1)*S iP);                              / slope (dollar)
       (pp*(coefs 2)*Cv iP);                             / curvature (dollar)
       (pp*carryMove));                                  / carry (dollar)
      ((pp*(coefs 0)*(L iP)%Pp);                         / level
       (pp*(coefs 1)*(S iP)%Pp);                         / slope
       (pp*(coefs 2)*(Cv iP)%Pp);                        / curvature
       (pp*carryMove%Pp))]                               / carry (roll-down)
 };

/ ── PnL decomposition (.attribution.pnl) ─────────────────────────────────────

/ Decompose a replay run's realized PnL into level/slope/curvature/carry/residual (+ the residual
/ fraction). The five reconcile to the run's realized total by construction (residual is the plug). R23:
/ units are resolved once and threaded down (dollar runs reconcile in dollar; return runs are byte-identical).
.attribution.pnl:{[run]
    dollar:.attribution.__resolveUnits run;
    if[`legs in key run; :.attribution.__pnlCombined[run;dollar]];   / ADDITIVE: two-leg / multi-commodity record (R19)
    steps:run`steps; comm:(run`meta)`commodity;
    n:count steps;
    if[0=n; '"attribution.pnl: empty run record"];
    udts:asc distinct steps`stepDate;
    cc:udts!{[comm;dd] @[{.curve.build[x;y]}[;comm];dd;{[e] (::)}]}[comm] each udts;
    prevPos:0f^prev steps`position;                       / the position HELD during each step (pre-fill)
    comps:.attribution.__stepComp[cc;steps;prevPos;dollar;] each til n;
    sp:steps`stepPnl;
    sm:not null sp;                                       / a null stepPnl = the contract did not print -> no realized PnL,
    lev:?[sm; 0f^comps[;0]; 0f]; slo:?[sm; 0f^comps[;1]; 0f];   / so attribute NOTHING on that step (zero the components),
    cur:?[sm; 0f^comps[;2]; 0f]; car:?[sm; 0f^comps[;3]; 0f];   / keeping the plug exact (clean runs: sm all 1b -> byte-identical).
    sp:0f^sp;
    resid:sp-(lev+slo+cur+car);
    total:sum sp;
    `level`slope`curvature`carry`residual`total`residualFraction`reconciled!(
        sum lev; sum slo; sum cur; sum car; sum resid; total;
        $[0f=abs total; 0n; (abs sum resid)%abs total];
        (.cfg.attribution`reconcileTol)>abs total-(sum lev)+(sum slo)+(sum cur)+(sum car)+sum resid)
 };

/ ADDITIVE two-leg / multi-commodity attribution (R19): a cross-commodity run record carries `legs (one
/ single-commodity R12 record per leg). Attribute EACH leg with the UNCHANGED single-commodity .attribution.pnl
/ (its own as-of curve via .curve.build), then SUM the components and reconcile to the combined total - the
/ combined level/slope/curvature/carry/residual are the leg sums, and they reconcile by construction (each
/ leg reconciles, sums of reconciling parts reconcile). R23: the resolved units are PROPAGATED to each leg
/ (so a dollar combined record attributes its legs in dollar). The single-commodity path above is untouched.
.attribution.__pnlCombined:{[run;dollar]
    u:$[dollar;`dollar;`return];
    a:.attribution.pnl each {[lg;u] lg,(enlist`units)!enlist u}[;u] each run`legs;
    lev:sum a@\:`level; slo:sum a@\:`slope; cur:sum a@\:`curvature; car:sum a@\:`carry; res:sum a@\:`residual;
    total:sum a@\:`total;
    `level`slope`curvature`carry`residual`total`residualFraction`reconciled!(
        lev; slo; cur; car; res; total;
        $[0f=abs total; 0n; (abs res)%abs total];
        (.cfg.attribution`reconcileTol)>abs total-(lev+slo+cur+car+res))
 };

/ ── LOCAL-basis attribution mode (.attribution.pnlLocal) (R22) ────────────────
/ R20's butterfly was constructed correctly (global level + slope ~ 0) yet its residual fraction was 1.06 -
/ residual-dominated - because a near-curve fly's LOCAL curvature is not well spanned by R15's GLOBAL
/ level/slope/curvature basis, so the strategy's real curvature exposure fell into residual. That exposed a
/ blind spot in the evidence layer's central "residual = unexplained = noise" reading (Sec 10): a large
/ residual can mean BASIS MISMATCH (localized real structure the global basis can't see), not noise.
/ -
/ R22 closes the gap with a LOCAL basis: per step, fit the SAME small fixed level/slope/curvature, but on a
/ LOCAL WINDOW of the curve around the traded contract (.cfg.attribution`localWindow contracts) rather than
/ the whole curve, and attribute the contract's move on the LOCAL fitted shapes. Localized structure (the
/ butterfly's curvature) now attributes to the local component -> the LOCAL residual is the genuine
/ idiosyncratic part. Reporting BOTH residuals distinguishes the two kinds: HIGH local residual = genuine
/ noise (the real red flag); LOW local + HIGH global = localized real structure the global basis missed.
/ -
/ THE HONESTY SAFEGUARD: the local basis is still only THREE fixed factors (local level/slope/curvature),
/ NOT one factor per traded contract. The window has MORE points than factors (overdetermined), so a
/ genuine-noise move at the traded tenor is NOT spanned -> the local residual stays high. A basis flexible
/ enough to explain everything would drive residual to ~0 always and destroy its diagnostic value; the
/ local factors are added so residual RECOVERS its meaning, not so it disappears. R23: the local basis is
/ units-aware the SAME way (so on a DOLLAR-booked localized-curvature run the LOCAL residual is genuinely
/ low - the R22 effect, now on the dollar runs real strategies produce, not just return-booked synthetics).
/ The global-basis .attribution.pnl / __stepComp / __pnlCombined are byte-identical for return runs.

/ Per-step LOCAL component tuple (level;slope;curvature;carry): exactly .attribution.__stepComp but the
/ level/slope/curvature SHAPES are built on a LOCAL WINDOW (the h-radius sub-curve around the contract on
/ the prior curve), and the shift is projected onto those LOCAL shapes. Carry (roll-down) is identical.
/ R23: roll routing + units-awareness, the same as __stepComp.
.attribution.__stepCompLocal:{[cc;steps;prevPos;h;dollar;t]
    if[t=0; :0 0 0 0f];
    if[$[`isRoll in cols steps; `boolean$steps[t]`isRoll; 0b];
        :(0f;0f;0f; $[`positionPnl in cols steps; `float$steps[t]`positionPnl; 0f])];
    d:steps[t]`stepDate; p:steps[t-1]`stepDate; c:steps[t]`activeContract;
    ccur:cc d; cprev:cc p;
    if[((::)~ccur) or (::)~cprev; :0 0 0 0f];
    curC:ccur`curve; curP:cprev`curve;
    cymP:curP`contractYM; cymC:curC`contractYM;
    iP:cymP?c; iC:cymC?c;
    if[(iP=count cymP) or iC=count cymC; :0 0 0 0f];     / active not on both curves -> all residual
    Pp:`float$(curP`price) iP;
    if[Pp<=0f; :0 0 0 0f];
    Pt:`float$(curC`price) iC;
    tauP:`float$(curP`tenor) iP;
    m:count cymP;
    lo:0|iP-h; hi:(m-1)&iP+h;                             / the LOCAL window of contracts around iP
    locP:curP lo+til 1+hi-lo;                             / the local sub-curve (a slice of the prior curve)
    shp:.attribution.__shapes locP; L:shp 0; S:shp 1; Cv:shp 2;
    ccurT:`float$curC`tenor; ccurP:`float$curC`price;
    locT:`float$locP`tenor;
    dP:(.attribution.__interp[ccurT;ccurP;] each locT)-`float$locP`price;   / shift at the LOCAL window tenors
    coefs:.attribution.__solve[flip (L;S;Cv); dP];
    li:iP-lo;                                            / the contract's index WITHIN the local window
    carryMove:Pt - .attribution.__interp[ccurT; ccurP; tauP];
    pp:prevPos t;
    $[dollar;
      ((pp*(coefs 0)*L li);                              / local level (dollar)
       (pp*(coefs 1)*S li);                              / local slope (dollar)
       (pp*(coefs 2)*Cv li);                             / local curvature (dollar)
       (pp*carryMove));                                  / carry (dollar)
      ((pp*(coefs 0)*(L li)%Pp);                         / local level
       (pp*(coefs 1)*(S li)%Pp);                         / local slope
       (pp*(coefs 2)*(Cv li)%Pp);                        / local curvature
       (pp*carryMove%Pp))]                               / carry (roll-down) - same as global
 };

/ Decompose a run's realized PnL onto the LOCAL basis (local level/slope/curvature + carry + LOCAL residual).
/ Same shape as .attribution.pnl + a `basis tag; reconciles to the realized total by construction. The
/ global-basis .attribution.pnl is unchanged. (legs records: attribute each leg on its own local window + sum.)
.attribution.pnlLocal:{[run]
    dollar:.attribution.__resolveUnits run;
    if[`legs in key run; :.attribution.__pnlLocalCombined[run;dollar]];
    steps:run`steps; comm:(run`meta)`commodity;
    n:count steps;
    if[0=n; '"attribution.pnlLocal: empty run record"];
    h:(.cfg.attribution`localWindow) div 2;
    udts:asc distinct steps`stepDate;
    cc:udts!{[comm;dd] @[{.curve.build[x;y]}[;comm];dd;{[e] (::)}]}[comm] each udts;
    prevPos:0f^prev steps`position;
    comps:.attribution.__stepCompLocal[cc;steps;prevPos;h;dollar;] each til n;
    sp:steps`stepPnl;
    sm:not null sp;                                       / null stepPnl -> attribute nothing (clean runs: sm all 1b -> byte-identical)
    lev:?[sm; 0f^comps[;0]; 0f]; slo:?[sm; 0f^comps[;1]; 0f];
    cur:?[sm; 0f^comps[;2]; 0f]; car:?[sm; 0f^comps[;3]; 0f];
    sp:0f^sp;
    resid:sp-(lev+slo+cur+car);
    total:sum sp;
    `level`slope`curvature`carry`residual`total`residualFraction`reconciled`basis!(
        sum lev; sum slo; sum cur; sum car; sum resid; total;
        $[0f=abs total; 0n; (abs sum resid)%abs total];
        (.cfg.attribution`reconcileTol)>abs total-(sum lev)+(sum slo)+(sum cur)+(sum car)+sum resid;
        `local)
 };

/ legs records dispatch: SAME-commodity multi-contract legs (e.g. the butterfly) need ONE local basis per
/ step fit on the window SPANNING all the legs' traded tenors, with every leg attributed against that SHARED
/ fit - so the JOINT structure (the fly's curvature across the legs) is captured, not each leg in its own
/ disjoint window. CROSS-commodity legs (R19/R21) have no shared sub-curve, so each leg uses its own local
/ window on its own curve, summed (mirrors __pnlCombined). R23: units propagated to the legs.
.attribution.__pnlLocalCombined:{[run;dollar]
    legs:run`legs;
    comms:{[lg] (lg`meta)`commodity} each legs;
    if[1=count distinct comms; :.attribution.__pnlLocalJoint[run;dollar]];
    u:$[dollar;`dollar;`return];
    a:.attribution.pnlLocal each {[lg;u] lg,(enlist`units)!enlist u}[;u] each legs;
    lev:sum a@\:`level; slo:sum a@\:`slope; cur:sum a@\:`curvature; car:sum a@\:`carry; res:sum a@\:`residual;
    total:sum a@\:`total;
    `level`slope`curvature`carry`residual`total`residualFraction`reconciled`basis!(
        lev; slo; cur; car; res; total;
        $[0f=abs total; 0n; (abs res)%abs total];
        (.cfg.attribution`reconcileTol)>abs total-(lev+slo+cur+car+res);
        `local)
 };

/ Per-step JOINT local attribution for same-commodity legs: ONE local window spanning all the legs' traded
/ tenors on the prior curve, ONE shape fit, every leg attributed against the SHARED coefs (so the fly's
/ curvature - a relationship ACROSS the legs - lands on local curvature). Returns the summed (level;slope;
/ curvature;carry) for the step. (The per-leg context is bundled into a dict - a q lambda takes at most 8
/ params; SKILL #8.) R23: per-leg roll routing + units-awareness inside legAttr.
.attribution.__stepCompLocalJoint:{[cc;legSteps;legPrevPos;h;dollar;t]
    if[t=0; :0 0 0 0f];
    d:(legSteps 0)[t]`stepDate; p:(legSteps 0)[t-1]`stepDate;
    ccur:cc d; cprev:cc p;
    if[((::)~ccur) or (::)~cprev; :0 0 0 0f];
    curC:ccur`curve; curP:cprev`curve;
    cymP:curP`contractYM; mP:count cymP;
    contracts:{[ls;t] (ls t)`activeContract}[;t] each legSteps;
    iPs:cymP?contracts;
    valid:where iPs<mP;
    if[0=count valid; :0 0 0 0f];
    iPv:iPs valid;
    / the LOCAL sub-curve is the TRADED tenors themselves when there are >=3 distinct (so local level/slope/
    / curvature span the traded structure - the butterfly's 3 tenors -> the fly's curvature is captured
    / exactly); when fewer (the single-/few-contract case), pad to a contiguous window of >=2h+1 contracts
    / around them so slope/curvature are defined AND the fit stays OVERDETERMINED (so a genuine idiosyncratic
    / move is NOT spanned - the honesty safeguard).
    tradedIdx:asc distinct iPv;
    widx:$[(count tradedIdx)>=3; tradedIdx;
        [spanLo:min iPv; spanHi:max iPv; need:0|(2*h+1)-1+spanHi-spanLo; padLo:need div 2;
         lo:0|spanLo-padLo; hi:(mP-1)&spanHi+(need-padLo); lo+til 1+hi-lo]];
    locP:curP widx;
    shp:.attribution.__shapes locP; L:shp 0; S:shp 1; Cv:shp 2;
    ccurT:`float$curC`tenor; ccurP:`float$curC`price;
    dP:(.attribution.__interp[ccurT;ccurP;] each `float$locP`tenor)-`float$locP`price;
    coefs:.attribution.__solve[flip (L;S;Cv); dP];
    ctx:`curP`curC`cymP`cymC`mC`coefs`L`S`Cv`widx`ccurT`ccurP`dollar!(
        curP; curC; cymP; curC`contractYM; count curC`contractYM; coefs; L; S; Cv; widx; ccurT; ccurP; dollar);
    legAttr:{[ctx;legSteps;t;idx;pp;c]
        st:(legSteps idx) t;
        if[$[`isRoll in cols legSteps idx; `boolean$st`isRoll; 0b];
            :(0f;0f;0f; $[`positionPnl in cols legSteps idx; `float$st`positionPnl; 0f])];
        iP:(ctx`cymP)?c; iC:(ctx`cymC)?c;
        if[iC=ctx`mC; :0 0 0 0f];
        Pp:`float$((ctx`curP)`price) iP; if[Pp<=0f; :0 0 0 0f];
        Pt:`float$((ctx`curC)`price) iC;
        tauP:`float$((ctx`curP)`tenor) iP;
        L:ctx`L; S:ctx`S; Cv:ctx`Cv; coefs:ctx`coefs;
        li:(ctx`widx)?iP;                                / the contract's index WITHIN the local sub-curve
        if[li>=count L; :0 0 0 0f];
        carryMove:Pt-.attribution.__interp[ctx`ccurT; ctx`ccurP; tauP];
        $[ctx`dollar;
          ((pp*(coefs 0)*L li);(pp*(coefs 1)*S li);(pp*(coefs 2)*Cv li);(pp*carryMove));
          ((pp*(coefs 0)*(L li)%Pp);(pp*(coefs 1)*(S li)%Pp);(pp*(coefs 2)*(Cv li)%Pp);(pp*carryMove%Pp))]
        }[ctx;legSteps;t];
    sum legAttr'[valid; legPrevPos[;t] valid; contracts valid]
 };

.attribution.__pnlLocalJoint:{[run;dollar]
    legs:run`legs; comm:(legs[0]`meta)`commodity;
    legSteps:legs@\:`steps;
    n:count legSteps 0;
    udts:asc distinct (legSteps 0)`stepDate;
    cc:udts!{[comm;dd] @[{.curve.build[x;y]}[;comm];dd;{[e] (::)}]}[comm] each udts;
    legPrevPos:{0f^prev x`position} each legSteps;
    comps:.attribution.__stepCompLocalJoint[cc;legSteps;legPrevPos;(.cfg.attribution`localWindow) div 2;dollar;] each til n;
    sp:sum 0f^legSteps@\:`stepPnl;                       / combined realized PnL per step (0-fill any leg null)
    sm:not null sp;
    lev:?[sm; 0f^comps[;0]; 0f]; slo:?[sm; 0f^comps[;1]; 0f];
    cur:?[sm; 0f^comps[;2]; 0f]; car:?[sm; 0f^comps[;3]; 0f];
    sp:0f^sp;
    resid:sp-(lev+slo+cur+car);
    total:sum sp;
    `level`slope`curvature`carry`residual`total`residualFraction`reconciled`basis!(
        sum lev; sum slo; sum cur; sum car; sum resid; total;
        $[0f=abs total; 0n; (abs sum resid)%abs total];
        (.cfg.attribution`reconcileTol)>abs total-(sum lev)+(sum slo)+(sum cur)+(sum car)+sum resid;
        `local)
 };

/ The diagnostic that makes "residual" trustworthy again: report the GLOBAL residual fraction (R15) AND the
/ LOCAL residual fraction, and classify - HIGH local = genuine idiosyncratic noise (the real red flag);
/ LOW local + HIGH global = localized real structure the global basis missed (the R20 butterfly case);
/ both low = well explained. (The 0.5 thresholds are illustrative reporting, not a gate.)
.attribution.residualSplit:{[run]
    gf:(.attribution.pnl run)`residualFraction;
    lf:(.attribution.pnlLocal run)`residualFraction;
    verdict:$[(not null lf) and lf>0.5; `genuineNoise;
              (not null gf) and (gf>0.5) and (not null lf) and lf<=0.5; `localizedStructure;
              `wellExplained];
    `globalResidualFraction`localResidualFraction`verdict!(gf;lf;verdict)
 };

/ ── bucketed curve risk (.attribution.risk) ──────────────────────────────────

/ The bucketed curve delta (the end position's $ sensitivity to a unit move per tenor bucket) + the
/ roll-down exposure (position x the end curve's rollYield) + the calendar-spread exposure on the
/ end-of-run position. (Inter-commodity basis exposure is out of scope for a single-commodity run.)
.attribution.risk:{[run]
    steps:run`steps; comm:(run`meta)`commodity;
    buckets:.cfg.attribution`buckets;
    endDate:max steps`stepDate;
    endPos:`float$last steps`position;
    endActive:last steps`activeContract;
    cv:.curve.build[endDate;comm]; curC:cv`curve;
    iA:(curC`contractYM)?endActive;
    tauA:$[iA<count curC`contractYM; `float$(curC`tenor) iA; 0n];
    bucketDelta:(`$"b",/:string til count buckets)!(count buckets)#0f;
    if[not null tauA; bucketDelta[(`$"b",string buckets bin tauA)]:endPos];
    `endDate`endContract`endPosition`tenor`buckets`bucketDelta`rollDownExposure`calendarSpreadExposure!(
        endDate; endActive; endPos; tauA; buckets; bucketDelta;
        endPos*(cv`features)`rollYield;                   / roll-down (carry) exposure
        endPos)                                           / single front leg: net spread exposure = the position
 };

/ ── register as an R2 `attribution capability ────────────────────────────────

.attribution.contract:`version`requiredIn`requiredOut!(
    1;
    `run`commodity!`dict`symbol;
    `level`slope`curvature`carry`residual!`float`float`float`float`float);
.registry.new[`attribution; .attribution.contract];
.attribution.register:{[name;fn;manifest] .registry.register[`attribution;name;fn;manifest]};
.attribution.get:{[name] .registry.get[`attribution;name]};
.attribution.list:{[] .registry.list `attribution};
.attribution.conforms:{[name] .registry.conforms[`attribution;name]};

.attribution.register[`pnlAttribution; .attribution.pnl;
    `contractVersion`description`in`out!(
        1;
        "decompose a replay run's realized PnL into level/slope/curvature/carry/residual (R10 shock basis) + the residual fraction; reconciles to the realized total";
        `run`commodity!`dict`symbol;
        `level`slope`curvature`carry`residual!`float`float`float`float`float)];

-1 "attribution.q loaded - .attribution.* PnL decomposition + bucketed curve risk ready (a HIGH layer above backtest/; not opened)";
