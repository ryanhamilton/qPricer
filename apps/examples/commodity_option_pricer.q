\l core/init.q
/ ============================================================================
/ commodity_option_pricer.q - real-data example (NOT a test), DATA-CONDITIONAL. POST-FOUNDATION R26.
/ The PIVOT TO THE PRICING TRACK. Price a European crude option where the FORWARD is the ACTUAL point-in-time
/ crude futures curve (R10's .curve.build, through R9's door) at a chosen tenor - so the pricer is consistent
/ with the same realistic infrastructure the strategies used. The price + greeks come from the validated
/ Black-76 closed form (.commodity.black76.*); the FDM cross-check (the equity FDM via the Black-76 transform)
/ VERIFIES it against a known answer. The vol is a HISTORICAL realised vol computed from the data and clearly
/ LABELLED model/historical - NOT market-implied (we have no options / implied-vol surface in this data; that
/ is the R25 data-gap, future data-gated work - this pricer does NOT fabricate a surface). Skips if no HDB.
/ ============================================================================
hdbPath:.cfg.paths`hdb;
useHdb:0<count @[{[p] key hsym `$p,"/sym"};hdbPath;{[e] ()}];
if[not useHdb;
    -1 "commodity_option_pricer SKIPPED - no HDB at ",hdbPath," (run scripts/ingest_hdb.q first).";
    exit 0];
.data.hdb.open hdbPath;

comm:`CRUDE;
/ a representative real as-of date (~75% through the history) - guaranteed present.
dts:.data.hdb.dates comm;
asOf:dts floor 0.75*count dts;

/ the realistic point-in-time curve (R10) and a chosen tenor at an actual contract (an un-interpolated forward).
cv:.curve.build[asOf;comm]; curve:cv`curve;
tenorIdx:2 & -1+count curve`tenor;                              / the 3rd contract (a few months out), clamped
tenorYears:`float$(curve`tenor) tenorIdx;
fwd:`float$(curve`price) tenorIdx;

/ a HISTORICAL realised vol from the front-price log-returns up to asOf (causal) - the honest model vol.
ch:.data.hdb.curveHistory[comm; dts where dts<=asOf];
frontByDate:0!select front:first price by asofDate from `asofDate`tenor xasc ch;
fp:`float$frontByDate`front;
logRet:1_ (log fp) - prev log fp;                              / daily front log-returns (drop the leading null)
win:60 & count logRet;
histVol:(sqrt 252f)*dev (neg win) sublist logRet;             / annualised trailing realised vol

strike:fwd;                                                    / ATM (strike = the forward)
rate:.cfg.commodityOption`riskFreeRate;

callRes:.commodity.option.priceEuropean `commodity`asOf`tenor`strike`optionType`vol`volSource!(comm;asOf;tenorYears;strike;`call;histVol;`historical);
putRes:.commodity.option.priceEuropean `commodity`asOf`tenor`strike`optionType`vol`volSource!(comm;asOf;tenorYears;strike;`put;histVol;`historical);

-1 "European crude option on the REAL point-in-time curve (R10), as of ",(string asOf),":";
-1 "  forward (R10 curve @ tenor ",(string tenorYears)," yr, contract ",(string (curve`contractYM) tenorIdx),") = ",string fwd;
-1 "  strike = ",(string strike)," (ATM)   rate = ",(string rate)," (MODEL discount rate, not market)";
-1 "  vol = ",(string histVol)," = a trailing ",(string win),"-day realised vol  -> volSource = ",(string callRes`volSource)," (model/historical, NOT market-implied)";
-1 "";
-1 "(1) PRICE (Black-76 closed form on the curve forward), verified by an FDM cross-check:";
-1 "    CALL: price=",(string callRes`unitPrice),"   FDM=",(string callRes`fdmPrice),"   agreement=",(string callRes`fdmAgreement);
-1 "    PUT : price=",(string putRes`unitPrice),"   FDM=",(string putRes`fdmPrice),"   agreement=",(string putRes`fdmAgreement);
-1 "    (the FDM reuses the VALIDATED equity FDM via the Black-76 transform: B76 = exp(-rT)*BS(spot=F,r=0) -";
-1 "     so the new pricer is VERIFIED against a known answer, not asserted.)";
-1 "";
-1 "(2) GREEKS (Black-76, on the curve forward):";
-1 "    CALL delta=",(string callRes`delta),"  gamma=",(string callRes`gamma),"  vega=",(string callRes`vega),"  theta=",(string callRes`theta),"  rho=",string callRes`rho;
-1 "    PUT  delta=",(string putRes`delta),"  gamma=",(string putRes`gamma),"  vega=",(string putRes`vega),"  theta=",(string putRes`theta),"  rho=",string putRes`rho;
-1 "";
-1 "(3) put-call PARITY on the forward (C - P == exp(-rT)*(F - K)):";
-1 "    residual = ",(string .commodity.option.parityResidual[asOf;comm;tenorYears;strike;histVol;rate])," (~0 -> internally consistent)";
-1 "";
-1 "THE HONEST VOL SCOPE: this prices on the REAL crude curve (the forward is the actual point-in-time futures";
-1 "curve the strategies used), with a HISTORICAL realised vol clearly labelled model-not-market. A MARKET";
-1 "implied-vol surface - needed to calibrate the smile/skew and to trade a vol-risk premium - is the R25";
-1 "data-gap: future, data-gated work. This pricer does NOT fabricate a surface. BOUNDED: European calls/puts";
-1 "only; American exercise, barriers, smile/skew calibration, and the eventual power / multi-asset work build";
-1 "on this pattern (reuse the validated engine, price on the realistic curve, validate against a known answer,";
-1 "flag the data we don't have) - the first step of the pricing track, on the same realistic foundation.";

exit 0;
