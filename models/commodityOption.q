/ models/commodityOption.q - European commodity-options pricer on the realistic crude futures curve (.commodity.option.*) (v0.91, Post-foundation R26)
/ ----------------------------------------------------------------------------
/ THE PIVOT TO THE PRICING TRACK. With R24+R25 the strategy search is conclusively closed (no cleanly
/ tradeable edge in this data); the work now turns to the project's STATED long-term target - commodity
/ (and eventually power / multi-asset) options - which it can finally build on the realistic point-in-time
/ curve the research OS produced. R26 is the first pricing-track milestone: price European options where the
/ FORWARD is the ACTUAL point-in-time crude futures curve (R10's .curve.build, through R9's door), not an
/ abstract level - so the pricer is consistent with the same realistic infrastructure the strategies used.
/ -
/ REUSE, DON'T DUPLICATE. The validated Black-76 closed form (.commodity.black76.price / .greeks) is the core;
/ this is the CURVE-CONSISTENT WRAPPER on top of it (the forward from R10's curve) - NOT a parallel pricer.
/ The FDM CROSS-CHECK reuses the validated equity FDM (.engine.priceOption) via the Black-76 transform:
/   Black-76(F,K,T,sigma,r) = exp(-rT) * BlackScholes(spot=F, K, T, sigma, r=0, q=0)
/ (the forward is a driftless martingale; the equity BS with spot=F and ZERO drift gives the undiscounted
/ forward-measure value, discounted separately by exp(-rT)). So the new pricer is VERIFIED against a known
/ answer the way the equity FDM is - not asserted.
/ -
/ HONEST VOL SCOPE (the R25 data-gap). We have NO market options / implied-vol surface in this data, so the
/ pricer takes a vol INPUT clearly labelled `volSource (model / historical / flat) - NOT market-implied. A
/ market vol surface (needed to calibrate and to trade a vol-risk premium) is explicitly FUTURE, data-gated
/ work - this pricer does NOT fabricate a surface (the same honesty as R11's no-open-interest, R14's
/ inventory-proxy). BOUNDED: European calls/puts only; American / barriers / exotics / smile-skew calibration
/ build on this later, when justified.
/ -
/ LAYER: reads R10's curve (the forward) + R9's door (the as-of curve, via .curve.build) + the validated
/ engine (.commodity.black76.*, .engine.priceOption), all downward; opens nothing at import. ADDITIVE - the
/ equity FDM core + the engine canonicals are byte-for-byte UNCHANGED. Registered as an R2 `model capability.
/ -
/ RESERVED-NAME NOTE: `asOf` NEVER `asof`; `comm` NOT `commodity`; builtins not shadowed (exp/log/sqrt/avg/
/ var/bin/first/last); the d1/d2 are REUSED from .commodity.black76 (not rewritten - no precedence risk).
/ ----------------------------------------------------------------------------

.commodity.option.defaultConfig:{[] .cfg.commodityOption};

/ Linear interpolation of the tenor-sorted curve (tenors -> prices) at a target tenor (flat outside the ends).
.commodity.option.__interp:{[tenors;prices;t]
    $[t<=first tenors; first prices;
      t>=last tenors; last prices;
      [j:tenors bin t; t0:tenors j; t1:tenors j+1; (prices j)+((prices j+1)-prices j)*(t-t0)%t1-t0]]
 };

/ The FORWARD from R10's curve at a target tenor (years), point-in-time (through R9's door via .curve.build).
/ Returns the forward + the curve span context. The forward IS a tradeable futures price (interpolated between
/ the actual contracts the curve names); pick a tenor at an actual contract for an exact (un-interpolated) forward.
.commodity.option.forwardAt:{[asOf;comm;tenorYears]
    cv:.curve.build[asOf;comm]; curve:cv`curve;
    tenors:`float$curve`tenor; prices:`float$curve`price;
    fwd:.commodity.option.__interp[tenors;prices;tenorYears];
    `forward`tenorYears`effectiveDate`commodity`asOf`nTenors`minTenor`maxTenor!(
        fwd; tenorYears; cv`effectiveDate; comm; asOf; count tenors; first tenors; last tenors)
 };

/ FDM cross-check: price the European futures option with the equity FDM under Black-76 dynamics (spot=forward,
/ ZERO drift r=q=0), then discount by exp(-rT). REUSES the validated .engine.priceOption - VERIFIES the closed
/ form against a numerical PDE solve, not a re-derivation. fdmCfg = `method`numberOfSpotSteps`numberOfTimeSteps`maximumSpot.
.commodity.option.__fdmCrossCheck:{[optType;fwd;strike;expiryT;vol;rate;fdmCfg]
    trade:`tradeId`underlying`productType`exerciseStyle`optionType`strike`expiry`notional!(
        `CMDYOPT;`CMDY;`equityOption;`european;optType;strike;expiryT;1f);
    marketData:`underlying`spot`riskFreeRate`dividendYield`volatility!(`CMDY;fwd;0f;0f;vol);   / forward as spot, ZERO drift
    model:.model.createBlackScholesModel[];
    cfg:.config.createFiniteDifferenceConfig[`method`numberOfSpotSteps`numberOfTimeSteps`maximumSpot!(
        fdmCfg`method; fdmCfg`numberOfSpotSteps; fdmCfg`numberOfTimeSteps; fdmCfg`maximumSpot)];
    undiscounted:(.engine.priceOption[trade;marketData;model;cfg])`unitPrice;   / BS(F, r=0) = undiscounted fwd-measure value
    (exp neg rate*expiryT)*undiscounted                                          / discount: Black-76 = exp(-rT)*BS(F,r=0)
 };

/ Price a European commodity option on the realistic crude futures curve. spec (a dict): commodity, asOf, tenor
/ (years to the option's expiry = the futures tenor the forward is read at), strike, optionType (`call/`put),
/ vol, optional volSource (`model/`historical/`flat - default `model), optional riskFreeRate (else .cfg), optional
/ notional. The FORWARD comes from R10's curve (point-in-time); the price + greeks from the validated Black-76
/ closed form; the FDM cross-check VERIFIES it. Output carries the price, greeks, the forward, the `volSource
/ label (model-NOT-market), and the closed-form-vs-FDM agreement.
.commodity.option.priceEuropean:{[spec]
    asOf:spec`asOf; comm:spec`commodity; tenorYears:`float$spec`tenor;
    strike:`float$spec`strike; optType:spec`optionType; vol:`float$spec`vol;
    volSource:$[`volSource in key spec; spec`volSource; `model];
    rate:$[`riskFreeRate in key spec; `float$spec`riskFreeRate; .cfg.commodityOption`riskFreeRate];
    notional:$[`notional in key spec; `float$spec`notional; 1f];
    fwdInfo:.commodity.option.forwardAt[asOf;comm;tenorYears];
    fwd:fwdInfo`forward;
    / the validated closed form (Black-76) + greeks - the authoritative futures-option price.
    b76:.commodity.black76.price[optType;fwd;strike;tenorYears;vol;rate];
    grk:.commodity.black76.greeks[optType;fwd;strike;tenorYears;vol;rate];
    / the FDM cross-check (reuses the equity FDM via the Black-76 transform) - VERIFIES, not asserts.
    ocfg:.cfg.commodityOption;
    fdmCfg:`method`numberOfSpotSteps`numberOfTimeSteps`maximumSpot!(
        ocfg`fdmMethod; ocfg`numberOfSpotSteps; ocfg`numberOfTimeSteps; (ocfg`maxSpotMult)*fwd);
    fdm:.commodity.option.__fdmCrossCheck[optType;fwd;strike;tenorYears;vol;rate;fdmCfg];
    `commodity`asOf`optionType`strike`tenorYears`forward`vol`volSource`riskFreeRate`unitPrice`notionalPrice`closedFormPrice`fdmPrice`fdmAgreement`delta`gamma`vega`theta`rho`method!(
        comm; asOf; optType; strike; tenorYears; fwd; vol; volSource; rate;
        b76; b76*notional; b76; fdm; abs b76-fdm;
        grk`delta; grk`gamma; grk`vega; grk`theta; grk`rho; `black76FdmCheck)
 };

/ Put-call parity on the forward: C - P = exp(-rT)*(F - K). A diagnostic the validation reuses.
.commodity.option.parityResidual:{[asOf;comm;tenorYears;strike;vol;rate]
    sp:`commodity`asOf`tenor`strike`vol`riskFreeRate!(comm;asOf;tenorYears;strike;vol;rate);
    c:(.commodity.option.priceEuropean sp,(enlist`optionType)!enlist `call)`unitPrice;
    p:(.commodity.option.priceEuropean sp,(enlist`optionType)!enlist `put)`unitPrice;
    fwd:(.commodity.option.forwardAt[asOf;comm;tenorYears])`forward;
    (c-p)-(exp neg rate*tenorYears)*fwd-strike
 };

/ ── register as an R2 `model capability (the spine) ──────────────────────────
/ Conforms to .model.contract (in: spot/strike/expiry/rate/vol; out: unitPrice/notionalPrice). For a futures
/ option `spot is the curve FORWARD and `expiry is the option tenor (years); a superset is fine.
.commodity.option.register:{[] .model.register[`commodityEuropeanOption; .commodity.option.priceEuropean;
    `contractVersion`description`in`out!(
        1;
        "European commodity-options pricer on the realistic crude futures curve (R10): forward from .curve.build (point-in-time), Black-76 closed form + an FDM cross-check; vol is model/historical (NOT market-implied - no surface in this data)";
        `spot`strike`expiry`rate`vol`commodity`asOf`volSource!`float`float`float`float`float`symbol`date`symbol;
        `unitPrice`notionalPrice`forward`fdmPrice`fdmAgreement`delta`gamma`vega`theta`rho`volSource!`float`float`float`float`float`float`float`float`float`float`symbol)]};
.commodity.option.register[];

-1 "commodityOption.q loaded - .commodity.option.* European commodity-options pricer on the R10 curve (Black-76 + FDM cross-check; vol model-not-market); registered as `commodityEuropeanOption";
