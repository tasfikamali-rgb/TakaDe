# 30. Settling with bKash, Nagad and upay: copy, open the app, record, confirm

Status: accepted (Sabit, 2026-11-12, asked whether friends can pay and have it recorded inside
TakaDe through bKash, and then "yeah" to the copy-and-open plan). Built; checked by the CI build,
not yet on a real phone.

## What we found (2026-11-12)
- bKash's Payment Gateway (tokenized checkout: grant token, create, execute, status, refund),
  Nagad's and upay's APIs are **merchant checkout**: a customer pays a registered business.
  None offers a person-to-person "send money" API. Access needs merchant onboarding (trade
  licence, NID, bank account), credentials kept on a server, and for Nagad and upay a
  whitelisted server IP. Fees aren't published. Sources: github.com/bKash-developer,
  bkash.com/page/tokenized_checkout. The Nagad and upay libraries Sabit linked
  (arif98741/nagadApi, codeboxrcodehub/upay) are third-party, not official. The bKash sandbox
  write-up at arman.bd describes the same merchant checkout.
- Using a merchant account for friends would mean TakaDe receives and passes on other people's
  money, which needs Bangladesh Bank licensing, and App Review 3.2.1(viii) expects money apps
  to be submitted by the licensed institution.
- No official link opens bKash, Nagad or upay with a number and amount filled in.
- App Store in-app purchase doesn't apply to money between people; Google Play's Payments
  policy says peer-to-peer payments must not use Play Billing. Sending people to the wallet
  app is allowed on both.

## Decision
- Settle up shows the person's wallet numbers and the amount, each with **Copy**, and an
  **Open bKash / Open Nagad** link to the wallet's App Store page (it shows "Open" when the app
  is installed). The link carries no number, amount or name. upay and Rocket get copy only
  until their App Store ids are confirmed.
- After paying, the payer swipes to record it: `reported_unverified`, shown as "Reported paid,
  not confirmed yet".
- The person paid sees **I got it** on that payment in the group's Payments card, which moves it
  to `acknowledged_by_recipient` through `Settlement.acknowledge(by:)`. That's both people's
  word, never provider verification; `confirmed` still needs provider evidence, which TakaDe
  doesn't have.
- No money passes through TakaDe, no merchant account, no server keys.

## Revisit when
TakaDe becomes a company with a licence or a written provider partnership for person-to-person
payments; see docs/decisions-needed.md.
