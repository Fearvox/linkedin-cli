---
algorithm: Multiplicative Interaction Term
category: optimization
complexity_time: O(1)
complexity_space: O(1)
used_in: scripts/prospect.sh
date: 2026-04-08
---

## Why This Was Chosen
Authority depends on BOTH seniority AND company scale simultaneously. Additive treats VP-at-unknown (4+1=5) same as Manager-at-Hilton (1+5=6). Multiplication correctly models the interaction: VP-at-Hilton (4*5=20) >> VP-at-unknown (4*1=4). Equivalent to an interaction term in logistic regression.

## Implementation Notes
authority = seniority * company_tier produces 0-25 range. Primary axis for tier classification. Tier A requires authority >= 12 (minimum: Director at Tier-4 brand or VP at Tier-3).

## Reference
Interaction terms in feature engineering. Also known as cross-features in recommendation systems.
