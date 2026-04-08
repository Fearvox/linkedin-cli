---
algorithm: Gated Cascade Filter
category: optimization
complexity_time: O(n)
complexity_space: O(k)
used_in: scripts/prospect.sh
date: 2026-04-08
---

## Why This Was Chosen
Lead scoring requires hard minimum thresholds (industry relevance, profile quality) before comparative scoring is meaningful. Pure additive scoring allows weak signals to accumulate into false positives. The gated cascade models the actual decision function: reject garbage first, rank survivors.

## Implementation Notes
Three stages: quality gate (6 composite signals), industry gate (core vs adjacent keywords), multi-axis scoring. Each gate outputs early with tier=D and a diagnostic note. Space O(k) where k = keyword list size (~50 terms).

## Reference
Standard pattern in CRM lead scoring (Salesforce, HubSpot). Equivalent to a shallow decision tree with soft scoring at leaf nodes.
