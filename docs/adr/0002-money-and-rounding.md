# 2. Money as integer minor units with largest-remainder rounding

Status: Accepted (2026-11-11)

## Decision
- `Money` stores `Int64` minor units (poisha for BDT) plus a `Currency`. No floating point.
- All arithmetic checks for overflow and currency mismatch and throws rather than wrapping.
- Parsing rejects more decimals than the currency allows (no silent rounding) and accepts
  Bengali digits.
- Splits use the largest-remainder method: each share is floored, then leftover minor units
  go one at a time to the largest remainders, ties broken by participant order. Every
  allocation sums exactly to the total; tests assert this across many totals.
- Percentages are stored as basis points (10000 = 100%) and must sum to exactly 10000.

## Open
Thousands grouping currently uses 1,234,567. Bangladeshi convention often uses lakh
grouping (12,34,567); see docs/decisions-needed.md.
