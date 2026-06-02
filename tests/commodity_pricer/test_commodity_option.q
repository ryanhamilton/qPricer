\l core/init.q
/ ============================================================================
/ test_commodity_option.q - R26: the European commodity-options pricer on the crude futures curve
/ (.commodity.option.*). SYNTHETIC (fixed inputs - does NOT depend on a market vol surface). Asserts:
/ (1) the FDM cross-check AGREES with the Black-76 closed form on a European CALL and PUT to a tight
/ tolerance (a known-answer, the way the equity FDM is validated); (2) put-call PARITY holds on the forward
/ (C - P = exp(-rT)*(F - K)); (3) the curve-sourced forward matches .curve.build's value at the tenor;
/ (4) the `volSource label is present and honest (model/historical, NOT market); (5) the greeks have the
/ right signs (call delta>0, put delta<0, gamma>0, vega>0, theta<0); (6) the pricer is registered + conforms.
/ ============================================================================
chk:{[b;msg] if[not b; '"FAIL: ",msg]};
apx:{[a;b;tol] tol>abs a-b};

/ --- synthetic crude-like futures curve (the `futures global .curve.build reads; no HDB needed) ---
d0:2024.05.15;
yms:202406+til 8;                                                / 8 monthly contracts
mexp:{"D"$(string x div 100),".",(-2#"0",string x mod 100),".20"};
buildC:{[ym;mexp;d0]
    e:mexp ym; me:`int$(`month$e)-`month$d0;                     / months to expiry
    px:60f+0.4*`float$me;                                        / a mild CONTANGO curve (deferred higher)
    flip `commodity`contractYM`expiry`firstDate`date`settle`open`high`low`volume!(
        enlist[`SYN];enlist ym;enlist e;enlist d0;enlist d0;enlist px;enlist px;enlist px;enlist px;enlist 5000)};
futures:raze buildC[;mexp;d0] each yms;

/ pick a tenor at an EXACT contract node so the forward is un-interpolated (the contract's own price).
cv:.curve.build[d0;`SYN]; curve:cv`curve;
nodeTenor:`float$(curve`tenor) 3;                                / the 4th contract's tenor (years)
nodePrice:`float$(curve`price) 3;                               / its forward price
strike:62f; vol:0.30; rate:0.04;

/ ---------------------------------------------------------------------------
/ (1) FDM cross-check AGREES with the Black-76 closed form (known-answer) - CALL and PUT.
/ ---------------------------------------------------------------------------
callRes:.commodity.option.priceEuropean `commodity`asOf`tenor`strike`optionType`vol`volSource!(`SYN;d0;nodeTenor;strike;`call;vol;`historical);
putRes:.commodity.option.priceEuropean `commodity`asOf`tenor`strike`optionType`vol`volSource!(`SYN;d0;nodeTenor;strike;`put;vol;`historical);
chk[0.05>callRes`fdmAgreement; "(1) CALL: the FDM cross-check agrees with the Black-76 closed form (",(string callRes`fdmAgreement),")"];
chk[0.05>putRes`fdmAgreement; "(1) PUT: the FDM cross-check agrees with the Black-76 closed form (",(string putRes`fdmAgreement),")"];
chk[(callRes`unitPrice)>0f; "(1) the call price is positive"];
chk[(putRes`unitPrice)>0f; "(1) the put price is positive"];

/ ---------------------------------------------------------------------------
/ (2) PUT-CALL PARITY on the forward: C - P = exp(-rT)*(F - K).
/ ---------------------------------------------------------------------------
parity:(callRes[`unitPrice]-putRes`unitPrice)-(exp neg rate*nodeTenor)*(callRes`forward)-strike;
chk[apx[parity;0f;1e-8]; "(2) put-call parity holds on the forward (residual=",(string parity),")"];
chk[apx[.commodity.option.parityResidual[d0;`SYN;nodeTenor;strike;vol;rate];0f;1e-8]; "(2) .commodity.option.parityResidual is ~0"];

/ ---------------------------------------------------------------------------
/ (3) the curve-sourced forward matches .curve.build's value at the tenor (un-interpolated at a node).
/ ---------------------------------------------------------------------------
chk[apx[callRes`forward;nodePrice;1e-9]; "(3) the forward at an exact contract tenor == .curve.build's contract price (",(string callRes`forward)," vs ",(string nodePrice),")"];
chk[apx[(.commodity.option.forwardAt[d0;`SYN;nodeTenor])`forward;nodePrice;1e-9]; "(3) .commodity.option.forwardAt matches the curve at the node"];

/ ---------------------------------------------------------------------------
/ (4) the volSource label is present and HONEST (model/historical, NOT market).
/ ---------------------------------------------------------------------------
chk[`volSource in key callRes; "(4) the result carries a volSource label"];
chk[(callRes`volSource) in `model`historical`flat; "(4) volSource is model/historical/flat - NOT market-implied (no surface in this data)"];
chk[`model=(.commodity.option.priceEuropean `commodity`asOf`tenor`strike`optionType`vol!(`SYN;d0;nodeTenor;strike;`call;vol))`volSource; "(4) volSource defaults to `model when unspecified"];

/ ---------------------------------------------------------------------------
/ (5) the greeks have the right signs.
/ ---------------------------------------------------------------------------
chk[(callRes`delta)>0f; "(5) call delta > 0"];
chk[(putRes`delta)<0f; "(5) put delta < 0"];
chk[(callRes`gamma)>0f; "(5) gamma > 0 (call)"];
chk[(callRes`vega)>0f; "(5) vega > 0 (call)"];
chk[(callRes`theta)<0f; "(5) theta < 0 (call, time decay)"];
chk[(putRes`gamma)>0f; "(5) gamma > 0 (put)"];
chk[(putRes`vega)>0f; "(5) vega > 0 (put)"];

/ ---------------------------------------------------------------------------
/ (6) registered as an R2 `model capability and conforms.
/ ---------------------------------------------------------------------------
chk[`commodityEuropeanOption in .model.list[]; "(6) the pricer is registered as a `model capability"];
chk[.model.conforms `commodityEuropeanOption; "(6) the pricer conforms to .model.contract"];

/ the equity FDM core is intact (REUSED, unchanged by R26).
chk[100h=type .engine.priceOption; "the equity FDM core .engine.priceOption is intact (reused, unchanged)"];
chk[100h=type .commodity.black76.price; "the Black-76 closed form is intact (reused, unchanged)"];

-1 "test_commodity_option: PASS";
