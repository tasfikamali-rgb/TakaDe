# 6. Lakh grouping and Bengali digits by default in Bengali

Status: Accepted (2026-11-11)

Amounts use South Asian grouping (1,23,45,678), which is how people in Bangladesh write
money. Western grouping stays available in `MoneyFormatter` (`grouping: .western`).
Digits follow the interface language by default: Bengali digits (১২৩) in the Bengali
interface and Latin digits (123) in English. People can override this in Profile > Numbers.
Parsing always accepts both digit sets.
