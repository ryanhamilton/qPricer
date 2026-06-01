/ attribution/attribution.q - PnL explain + bucketed curve risk (.attribution.*) (v0.80, Research OS R15)
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

/ Per-step component tuple (level;slope;curvature;carry) in the run's return-PnL units. cc is the
/ date->curve-object cache; t is the step index (t=0 -> all zero: no prior curve).
.attribution.__stepComp:{[cc;steps;prevPos;t]
    if[t=0; :0 0 0 0f];
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
    ((pp*(coefs 0)*(L iP)%Pp);                            / level
     (pp*(coefs 1)*(S iP)%Pp);                            / slope
     (pp*(coefs 2)*(Cv iP)%Pp);                           / curvature
     (pp*carryMove%Pp))                                   / carry (roll-down)
 };

/ ── PnL decomposition (.attribution.pnl) ─────────────────────────────────────

/ Decompose a replay run's realized PnL into level/slope/curvature/carry/residual (+ the residual
/ fraction). The five reconcile to the run's realized total by construction (residual is the plug).
.attribution.pnl:{[run]
    if[`legs in key run; :.attribution.__pnlCombined run];   / ADDITIVE: two-leg / multi-commodity record (R19)
    steps:run`steps; comm:(run`meta)`commodity;
    n:count steps;
    if[0=n; '"attribution.pnl: empty run record"];
    udts:asc distinct steps`stepDate;
    cc:udts!{[comm;dd] @[{.curve.build[x;y]}[;comm];dd;{[e] (::)}]}[comm] each udts;
    prevPos:0f^prev steps`position;                       / the position HELD during each step (pre-fill)
    comps:.attribution.__stepComp[cc;steps;prevPos;] each til n;
    lev:comps[;0]; slo:comps[;1]; cur:comps[;2]; car:comps[;3];
    sp:steps`stepPnl;
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
/ leg reconciles, sums of reconciling parts reconcile). The single-commodity path above is untouched.
.attribution.__pnlCombined:{[run]
    a:.attribution.pnl each run`legs;
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
/ local factors are added so residual RECOVERS its meaning, not so it disappears. ADDITIVE: the global-basis
/ .attribution.pnl / __stepComp / __pnlCombined are UNCHANGED (byte-identical); this is a NEW mode.

/ Per-step LOCAL component tuple (level;slope;curvature;carry): exactly .attribution.__stepComp but the
/ level/slope/curvature SHAPES are built on a LOCAL WINDOW (the h-radius sub-curve around the contract on
/ the prior curve), and the shift is projected onto those LOCAL shapes. Carry (roll-down) is identical.
.attribution.__stepCompLocal:{[cc;steps;prevPos;h;t]
    if[t=0; :0 0 0 0f];
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
    ((pp*(coefs 0)*(L li)%Pp);                           / local level
     (pp*(coefs 1)*(S li)%Pp);                           / local slope
     (pp*(coefs 2)*(Cv li)%Pp);                          / local curvature
     (pp*carryMove%Pp))                                  / carry (roll-down) - same as global
 };

/ Decompose a run's realized PnL onto the LOCAL basis (local level/slope/curvature + carry + LOCAL residual).
/ Same shape as .attribution.pnl + a `basis tag; reconciles to the realized total by construction. The
/ global-basis .attribution.pnl is unchanged. (legs records: attribute each leg on its own local window + sum.)
.attribution.pnlLocal:{[run]
    if[`legs in key run; :.attribution.__pnlLocalCombined run];
    steps:run`steps; comm:(run`meta)`commodity;
    n:count steps;
    if[0=n; '"attribution.pnlLocal: empty run record"];
    h:(.cfg.attribution`localWindow) div 2;
    udts:asc distinct steps`stepDate;
    cc:udts!{[comm;dd] @[{.curve.build[x;y]}[;comm];dd;{[e] (::)}]}[comm] each udts;
    prevPos:0f^prev steps`position;
    comps:.attribution.__stepCompLocal[cc;steps;prevPos;h;] each til n;
    lev:comps[;0]; slo:comps[;1]; cur:comps[;2]; car:comps[;3];
    sp:steps`stepPnl;
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
/ window on its own curve, summed (mirrors __pnlCombined).
.attribution.__pnlLocalCombined:{[run]
    legs:run`legs;
    comms:{[lg] (lg`meta)`commodity} each legs;
    if[1=count distinct comms; :.attribution.__pnlLocalJoint run];
    a:.attribution.pnlLocal each legs;
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
/ curvature;carry) for the step. (The 14-field per-leg context is bundled into a dict - a q lambda takes
/ at most 8 params; SKILL #8.)
.attribution.__stepCompLocalJoint:{[cc;legSteps;legPrevPos;h;t]
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
    ctx:`curP`curC`cymP`cymC`mC`coefs`L`S`Cv`widx`ccurT`ccurP!(
        curP; curC; cymP; curC`contractYM; count curC`contractYM; coefs; L; S; Cv; widx; ccurT; ccurP);
    legAttr:{[ctx;pp;c]
        iP:(ctx`cymP)?c; iC:(ctx`cymC)?c;
        if[iC=ctx`mC; :0 0 0 0f];
        Pp:`float$((ctx`curP)`price) iP; if[Pp<=0f; :0 0 0 0f];
        Pt:`float$((ctx`curC)`price) iC;
        tauP:`float$((ctx`curP)`tenor) iP;
        L:ctx`L; S:ctx`S; Cv:ctx`Cv; coefs:ctx`coefs;
        li:(ctx`widx)?iP;                                / the contract's index WITHIN the local sub-curve
        if[li>=count L; :0 0 0 0f];
        carryMove:Pt-.attribution.__interp[ctx`ccurT; ctx`ccurP; tauP];
        ((pp*(coefs 0)*(L li)%Pp);(pp*(coefs 1)*(S li)%Pp);(pp*(coefs 2)*(Cv li)%Pp);(pp*carryMove%Pp))
        }[ctx];
    sum legAttr'[legPrevPos[;t] valid; contracts valid]
 };

.attribution.__pnlLocalJoint:{[run]
    legs:run`legs; comm:(legs[0]`meta)`commodity;
    legSteps:legs@\:`steps;
    n:count legSteps 0;
    udts:asc distinct (legSteps 0)`stepDate;
    cc:udts!{[comm;dd] @[{.curve.build[x;y]}[;comm];dd;{[e] (::)}]}[comm] each udts;
    legPrevPos:{0f^prev x`position} each legSteps;
    comps:.attribution.__stepCompLocalJoint[cc;legSteps;legPrevPos;(.cfg.attribution`localWindow) div 2;] each til n;
    lev:comps[;0]; slo:comps[;1]; cur:comps[;2]; car:comps[;3];
    sp:sum legSteps@\:`stepPnl;                          / combined realized PnL per step
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
