# Research Findings — Post-Foundation Strategy Search (R8 + R16–R24)

*A synthesis of the post-foundation strategy research, sourced strictly from the committed evidence
(`docs/MODEL_CARDS.md`, `CHANGELOG.md`, the R23 re-attribution sweep `apps/examples/reattribution_sweep.q`,
the strategy demos under `apps/examples/`, and the governance ledger `.gov.*`). Every figure below is
cross-checked against those sources — see **§5 Cross-check / provenance**. This is a research OUTPUT, not a
strategy: a defensible account of what was tested, what is tradeable, and why.*

> **Bottom line.** Across the three edge types — **risk-premium**, **structural**, **directional** — and
> eight strategies, **no cleanly tradeable edge was found from this data** (crude + gas daily settle futures,
> ≈ 2018-12 → 2026, futures-only). Every strategy returned `anyTradeable = 0`. The R23-corrected
> attribution shows *why*, and it is not "the PnL is noise": the PnL is **well-explained by curve structure**
> (local residual fractions 0.008–0.146 — not noise) and is **overwhelmingly directional (LEVEL)**. The one
> dimension that pays is **passive directional beta** (passive-long crude Sharpe ≈ 0.31), which the
> structural/relative strategies do not capture and which **timing cannot improve** — the R24 trend test beat
> *nothing*: trend Sharpe 0.002 vs passive 0.31, alpha **−50.95**. A "no tradeable edge here, and here is
> precisely why, and here is what would change it" is the result the governance spine and the evidence layer
> were built to make trustworthy.

---

## 1. The strategy ledger

Each row: the thesis · the claimed edge-type · the honest gate verdict (the gate that killed it + the
deflated Sharpe where a bucket reached it) · the **R23 units-honest** PnL attribution (global / local residual
fraction + dominant component). All eight returned `anyTradeable = 0`. *Verdict figures are from the demos'
gov-gate output recorded in `CHANGELOG.md`; attribution figures are from the re-attribution sweep (§5).*

| # | strategy | claimed edge | killing gate / verdict | units-honest attribution (global resid · local resid · dominant) |
|---|----------|--------------|------------------------|------------------------------------------------------------------|
| R8 | `factorRelativeValue` (old engine) | structural | no edge on the old frictionless, full-sample-PCA engine (level/slope/curvature explained var 0.856 / 0.138 / 0.006); re-validated by R17 | — (see R17, the realistic re-run) |
| R16 | `seasonalCalendarSpread` | structural | backwardation/contango **reject at cost** (net Sharpe 0.24 / −0.06); flat (138 obs, in-sample Sharpe 2.6) **deflated → research** (DSR **0.86** < 0.95) | 0.807 · **0.067** · level |
| R17 | `factorRvReplay` | structural | backwardation/contango **reject at cost** (0.03 / −0.18); flat (87 obs) **deflated → research** (DSR **0.61**) | **0.094** · 0.055 · level |
| R18 | `crudeCarry` | risk-premium (term-structure / roll-yield) | backwardation/flat **reject at cost** (−0.38 / −0.17); contango **research** (DSR **0.54**) | 0.225 · 0.043 · level −90.5 / **carry +36.2** |
| R19 | `xCommodityCarry` | risk-premium (relative carry, β-neutral) | all buckets **reject at the two-leg cost** | 0.704 · 0.057 · level −42.8 / **carry +26.4** |
| R20 | `crudeButterfly` | structural (curvature) | backwardation/flat **research**; contango **reject at cost** | 1.877 · **0.146** · carry (global) / **curvature (local)**; level+slope ≈ 0 |
| R21 | `xCommodityCarryVW` | risk-premium (relative carry, equal-risk) | all buckets **reject at cost** | 0.173 · **0.008** · level −92.1 / **carry +24.3** |
| R24 | `crudeTrend` | risk-premium (directional / time-series momentum) | trend-persistence gate **fails a-priori** (AR1 **−0.002**); backwardation/contango **reject at cost**; flat **research** (DSR **0.78**); **benchmark: trend Sharpe 0.002 vs passive-long 0.31, alpha −50.95, beats-passive = 0** | level **−37.8** dominant (total ≈ 0.31, so the residual fraction is large by construction — large offsetting directional bets net to ≈ 0) |

**Notes on the attribution column (R23 units-honest).** The *local* residual fractions are all **0.008–0.146**
— the realised PnL is **curve structure, not idiosyncratic noise**. The dominant component is **LEVEL**
(directional) for every strategy except R20, whose construction is curvature (the +1/−2/+1 fly is
level/slope-neutral: level+slope ≈ 0, confirmed; its curvature is captured by the local/traded-tenor basis at
residual 0.146, while the global basis cannot see a near-curve fly's local curvature → global 1.877). The
carry strategies (R18/R19/R21) carry a **real, positive carry component** (+36.2 / +26.4 / +24.3) — but it is
swamped by a large **negative LEVEL** term (−90.5 / −42.8 / −92.1): the directional exposure dominates.

---

## 2. The cross-cutting conclusion (by edge type)

**Structural (slope / level / curvature / factor-residual) — no tradeable edge.**
R8/R17 (factor-residual fade), R16 (seasonal calendar spread = slope/level), and R20 (butterfly = curvature)
all fail the cost and/or deflation gates (`anyTradeable = 0`). After R23 the attribution shows their PnL is
*not* noise — R17's "95% unexplained residual" was a unit artifact; units-honest it is **0.094 global /
0.055 local**, well-explained and LEVEL-dominated — but the structural *premium* (the slope/curvature
normalisation the thesis claims) does not pay net of cost on this data. R20 is the cleanest case: the
construction is provably correct (level+slope ≈ 0) and the curvature is real and localisable (local residual
0.146), yet it does not clear the three-leg cost gate.

**Risk-premium / relative carry — real but not cleanly isolatable or tradeable.**
The term-structure / roll-yield premium is genuinely present: R18's time-series carry shows a positive carry
component (+36.2 units-honest), and stripping the common energy beta (R19) leaves a **larger** carry
component (+26.4) — the relative premium stands on its own. But two facts kill it: (a) it is **swamped by
directional LEVEL** exposure (R18 level −90.5; R19 −42.8), and (b) the market-neutral premise is weak for a
**two-asset, decorrelated** pair — R21's equal-risk sizing, hypothesised to drive the level term to ~0,
*increased* it (−42.8 → −92.1) because crude and gas share no clean common beta. The premium is real; it is
not cleanly harvestable, and it fails the (two-leg) cost gate.

**Directional / timing — the only paying dimension is passive beta, which timing does not improve.**
R23 showed every strategy's PnL is LEVEL/directional-dominated, so R24 tested the directional dimension
directly. Two independent reads both fail: the **trend-persistence gate fails a-priori** (daily crude
returns are not momentum-persistent, AR1 −0.002 — trend-following is the wrong tool), and — decisively for a
directional strategy — the **benchmark-relative alpha is strongly negative**: passive-long crude earns Sharpe
0.31, the timed trend strategy earns Sharpe **0.002** (alpha **−50.95**). Timing the directional dimension
*destroys* the beta rather than adding to it. Passive long crude's 0.31 Sharpe is **beta, not an edge** — it
is the directional risk premium of holding the asset, available without skill and not improvable by these
signals.

**The honest bottom line.** There is **no tradeable edge in any of the three dimensions** on this dataset.
The structural and relative premia do not pay net of cost; the carry premium is real but secondary to (and
inseparable from) directional exposure; and the directional dimension's only return is passive beta, which
timing reduces. This is a defensible research conclusion, not a failure — the opposite of a flattering
backtest.

---

## 3. Data-gap analysis (what would have to change to find more)

The conclusion is *conditional on the data*, and the constraints are specific and known:

- **Futures-only, daily settle bars** — no options / implied-vol surface, no intraday or order-book data.
- **Volume + expiry, but no open interest** — R11's `oi_switch` roll rule errors rather than fabricating OI.
- **Two commodities (crude + gas) that decorrelate** — no cross-sectional breadth; R21 showed they share no
  clean common beta, so a 2-asset "cross-section" cannot be made market-neutral.
- **No inventory / storage / supply fundamentals** — R14's inventory-tightness is a backwardation *proxy*,
  never fabricated.
- **No power / electricity data.**

Each deferred strategy (ARCHITECTURE.md "Deferred") names the data it would actually need:

| Deferred strategy / capability | Data required to unlock it |
|--------------------------------|----------------------------|
| Volatility-risk-premium (variance/vol selling) | an **options chain / implied-vol surface** (the engine prices options; the *data* is futures-only) |
| Cross-sectional carry & momentum (breadth) | **more commodities** — a real cross-section; crude + gas alone decorrelate (R21), so no breadth |
| Fundamental / event strategies | **inventory / storage / supply** data (the proxy is not a substitute) |
| Power / electricity specialization | **power / electricity** price data (spikes, non-storability, seasonality) |
| Finer execution / microstructure | **intraday / order-book** data (settle-only bars hide it) |
| The "priced-in" gate | **surface / positioning** data the HDB lacks |
| Open-interest-based roll discipline | **open interest** per contract |

This table is the bridge to the next phase: it says exactly what to acquire to make each deferred thesis
testable, so the "no edge" conclusion is forward-looking rather than terminal.

---

## 4. Methodology note — the system worked as designed

The value of this output is that it is **trustworthy**, and that is a property of how it was produced:

- **Honest verdicts, run once, not tuned.** Every strategy's parameters were PRE-REGISTERED and run ONCE; no
  lookback or threshold was swept to pass. A "research, not tradeable" verdict is the system working.
- **It corrected its own author three times.** R21's hypothesis (equal-risk sizing would neutralise the level
  term) was **refuted** by its own attribution; R20's mechanism (a single-record fly) was corrected to a
  three-leg decomposition so the construction check was even possible; and R17's "95% unexplained residual"
  characterization was overturned by R23 as a **unit artifact** (the PnL was structural, not noise).
- **The attribution is now units-, roll-, and basis-honest (R23).** The residual the governance layer leans on
  ("name which of the three edges, or it's noise") finally means exactly that on the real dollar-booked runs —
  which is why §1's "the PnL is structure, not noise, but it's directional" reading is reliable.
- **The judging logic adapted to the question.** R24 made the system measure a directional thesis the way it
  must be measured — against a passive benchmark (alpha over beta) — because for a directional strategy a
  level-dominated attribution is *expected* and the absolute Sharpe gate can be cleared by timed beta.

A system that can conclude *"no tradeable edge here, and here's why, and here's what would change it"* — on
audited, causal, cost-and-roll-aware, deflated, holdout-protected evidence — is doing exactly what it was
built to do. Building the judge before chasing the edge is what makes this conclusion worth more than a
backtest that found one.

---

## 5. Cross-check / provenance

Every figure was sourced from the committed evidence and reconciled (not from recollection):

- **Gate verdicts, killing gates, deflated Sharpes** (R8, R16–R21, R24) — `CHANGELOG.md` per-milestone
  entries (the demo gov-gate output recorded there). R24's per-bucket table was additionally re-confirmed by
  re-running the committed `apps/examples/crude_trend.q`: backwardation 1105 reject@cost (netSharpe −0.146),
  contango 249 reject@cost (−0.124), flat 138 research (DSR **0.783**); persistence gate AR1 **−0.001618**;
  benchmark trend Sharpe **0.001858** / passive **0.311798** / alpha **−50.954** / beats-passive 0;
  `anyTradeable = 0`.
- **Units-honest attribution (global/local residual + components)** — re-running the committed
  `apps/examples/reattribution_sweep.q` reproduced the §1 figures **exactly** (deterministic): R16
  0.807/0.067, R17 0.094/0.055, R18 0.225/0.043 (level −90.5 / carry +36.2), R19 0.704/0.057 (level −42.8 /
  carry +26.4), R20 1.877/0.146 (level 0 / slope 0.061 / curvature 1.174 / carry −2.497), R21 0.173/0.008
  (level −92.1 / carry +24.3) — matching `docs/MODEL_CARDS.md` and `CHANGELOG.md`.
- **Edge-types, theses, failure modes** — `docs/MODEL_CARDS.md` (`edgeSource` + the assumptions / failure-mode
  fields), consistent with each strategy's gov hypothesis.
- **Deferred strategies + data gaps** — `ARCHITECTURE.md` "Deferred"; the data constraints (no OI, no power,
  no inventory, two decorrelated commodities) from the data/HDB + R11/R14 notes.

No figure in this document was taken from memory; where a recorded number and a fresh re-run could differ, the
**re-run (the committed code) is authoritative** and was used. A synthesis that misstates a verdict is worse
than none — so this section is the audit trail.

---

*See also: `docs/MODEL_CARDS.md` (per-capability cards + validation status), `CHANGELOG.md` (the per-milestone
record), `ARCHITECTURE.md` §11.8 / §13 (the R9–R24 arc), `apps/examples/reattribution_sweep.q` (the R23
units-honest re-attribution), `apps/examples/crude_trend.q` (the R24 directional test + passive benchmark).*
