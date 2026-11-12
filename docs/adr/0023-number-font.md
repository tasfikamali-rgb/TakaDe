# 23. Anek Bangla for Bengali digits

Status: accepted (Sabit, 2026-11-12: the Bengali number font didn't look right; English
digits and Bengali words are fine. Picked Anek Bangla from a side-by-side comparison).

## Decision
- Bengali digits (০–৯) in amounts (`AmountText`: balances, lists, keypad display), keypad
  keys, the keypad's sum line, meal counts and the share card use **Anek Bangla**
  Medium/SemiBold through `AppFont.figures`. In those places the ৳, comma and decimal point
  come from Anek Bangla too, so the amount reads as one piece.
- Bengali words stay in Hind Siliguri. Latin digits stay in Inter / Inter Display.
- The files are static instances (weight 500 and 600, normal width) cut from the Google
  Fonts variable font with fontTools, since iOS registers fonts by PostScript name.
  License: SIL OFL 1.1, in `App/Resources/Fonts/AnekBangla`.
- Like Hind Siliguri, Anek Bangla has no tabular forms for Bengali digits, so Bengali
  amounts in a column don't line up digit for digit (no change from before).

## Alternatives shown to Sabit
Noto Sans Bengali, Baloo Da 2, Mina, Tiro Bangla and Noto Serif Bengali.
