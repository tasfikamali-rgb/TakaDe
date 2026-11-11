# TakaDe — Claude Code Project Instructions

## Purpose and authority

Build **TakaDe**, a Bangladesh-first shared-expense and settlement product inspired by the bill-splitting category. These instructions are the product and engineering constitution for work in this repository. Treat the brief as product direction, not proof that a payment, legal, platform, security, or infrastructure capability is available.

Before changing code, inspect the repository, its `README`, existing architecture, tests, and any more specific `CLAUDE.md` or `AGENTS.md` instructions. Preserve established conventions unless they conflict with a safety requirement here. Do not claim a feature is implemented, compliant, encrypted, verified, or production-ready without evidence. Record material decisions in a concise ADR (architecture decision record) when the repository has an ADR convention.

If requirements conflict or external facts are unknown, choose the safest reversible implementation, label assumptions, and create a decision gate. Never invent provider credentials, contracts, legal approval, API capabilities, device models, repository access, or test results.

## Product brief

TakaDe helps people record shared expenses, understand who owes whom, split costs fairly, and settle balances. It is designed first for Bangladesh and should support:

- Personal and event-based groups; expenses, participants, split rules, balance summaries, edits, and an auditable history.
- Settlement coordination for bKash, upay, and supported banks, only through approved provider or bank pathways and after required approvals.
- A guest-friendly way to share an amount and settlement instructions with someone without a TakaDe account. A recipient may view the request and choose an available supported transfer path. Guests must not be represented as authenticated TakaDe users.
- Group and expense invitations by share link, phone number, or email where the relevant service and consent exist. Allow practical export/download and sharing of expense details without exposing unrelated group data.
- Receipt capture and OCR for printed receipts. Treat OCR as a suggestion: show extracted merchant, date, currency, items, taxes, and totals for human review before saving or splitting.
- Bengali and English UI with an obvious in-app language selector. Translate interface content with reviewed Bengali strings. Keep names from contacts and user-entered names unchanged; do not translate, transliterate, or silently normalize them. Respect locale-aware Bangla/Latin digits, currency display, dates, and text direction where appropriate.
- iPhone, Android phones, iPadOS/tablets, foldables, and home-screen widgets, with layouts that adapt to changing screen sizes, hinges, orientation, and platform conventions. Do not hard-code support for unreleased or ambiguously named devices; test responsive behavior against current supported hardware and simulators.
- A minimal, accessible light and dark interface, with latency and reliability treated as core product qualities.
- A future public website, domain, email, privacy/legal pages, and coordinated logo/brand work.

## Non-negotiable product principles

1. **Ledger first; money movement is a separate capability.** The expense ledger records claims and settlements. A recorded expense is not a payment, and a “settled” state must not be inferred from a tap, screenshot, deep link, or user assertion alone.
2. **No silent central ledger assumption.** The stated preference is local-first storage with SQLite and no central database. Build the single-device/local mode as a real, useful mode. Multi-device synchronization, shared group state, invitations, push notifications, account recovery, and provider callbacks generally require some reachable service or a carefully designed alternative. Do not smuggle in a central database. Present concrete options and require a product decision before choosing a hosted sync or identity service.
3. **Be precise about privacy and encryption.** Local SQLite is not automatically encrypted. End-to-end encryption (E2EE) is only a claim if the client controls keys and the server cannot decrypt the protected content. Provider payment processing, fraud monitoring, receipt OCR, email/SMS delivery, and push services may reveal data to third parties. Describe exactly what is encrypted, where keys live, what metadata remains visible, and what is excluded. Never describe provider-managed or server-readable data as E2EE.
4. **Verify payments with authoritative evidence.** Prefer provider/bank API status, signed callbacks/webhooks validated server-side, or other officially supported reconciliation. Bind confirmation to the expected recipient, amount, currency, reference, and transaction state; handle duplicate, delayed, reversed, and disputed events. If the provider offers no permitted verification integration, label settlement “reported by user” or “awaiting confirmation,” not verified. Never collect banking or mobile-wallet PINs, passwords, OTPs, or credentials in TakaDe.
5. **Minimize data.** Request contacts, camera, photos, notifications, location, or other permissions only when necessary and explain the purpose at the point of use. Prefer explicit contact selection and on-device processing. Avoid uploading address books. Keep secrets out of source control, logs, analytics, crash reports, screenshots, widget previews, and test fixtures.
6. **Safe defaults and user control.** Make sharing scope visible; links should be unguessable, revocable, narrowly scoped, and time-limited where feasible. Provide export and deletion paths appropriate to the storage mode. Use accessible controls, clear error states, and confirmation for consequential actions.

## Contradictions, options, and decision gates

Do not resolve these by assumption. Keep interfaces modular so a selected option can replace another.

### Local-only accounts vs shared groups, notifications, and email

A device-only app can use SQLite and local notifications, but cannot reliably deliver email, cross-device updates, invite redemption, or remote push by itself. Options:

- **Local-first, no account/service:** groups exist on a device; sharing sends a read-only or explicitly portable snapshot; no remote notifications or synchronized membership. Appropriate for an MVP if that limitation is accepted.
- **Encrypted sync service:** the client encrypts eligible ledger content before upload; a service stores ciphertext and limited routing metadata. Requires identity/key recovery design, abuse prevention, retention/deletion rules, and review of metadata leakage.
- **Conventional hosted service:** enables accounts, invitations, push, collaboration, and reconciliation, but the service may access data unless field-level protections prove otherwise. This changes the no-central-database premise and requires explicit approval.

**Gate:** Product owner selects a synchronization and identity model, defines recovery and deletion expectations, and approves data categories before implementation. Email or phone invitations require a delivery provider, domain/sender setup, consent/anti-abuse controls, and a decision about whether addresses/numbers are stored. Do not send invitations until this is approved.

### E2EE vs OCR, payment verification, and collaboration

OCR may run on-device or through a third-party service. On-device OCR best supports minimization but needs device/library evaluation. Cloud OCR requires disclosure, consent, retention controls, and a processor review. Payment verification requires an authorized party to see enough transaction data to reconcile; it may be isolated from encrypted expense notes, but cannot be honestly promised as entirely end-to-end private if a service/provider can access reconciliation data.

**Gate:** Define separately which fields are end-to-end encrypted (for example, notes and item details), which fields are service-readable (for example, invitation routing and reconciliation tokens), and which leave the device for providers. Threat-model metadata and key recovery before marketing encryption claims.

### bKash, upay, bank transfers, and payment initiation

Do not assume public APIs, merchant status, deep-link behavior, personal transfers, or transaction lookup. Investigate each provider’s current official documentation, eligible partner/merchant program, supported markets, security requirements, fees, dispute process, and contractual restrictions. Support only approved integrations. If initiation is unavailable, offer a user-directed handoff to the official app/site or clear transfer instructions, then return to TakaDe with a pending/reporting state. Never scrape provider apps, automate credential entry, or claim a handoff succeeded.

**Gate:** For each rail, obtain written provider/partner confirmation, integration documentation, test credentials and sandbox, callback/signature details, reconciliation semantics, operational ownership, and legal/compliance review. Separate initiation from confirmation in the domain model.

### Apple Pay / Google Play billing vs external financial payments

TakaDe’s core purchase is a transfer between people, not necessarily a purchase of digital content. Do not use Apple in-app purchase or Google Play Billing as a substitute for bKash, upay, or bank rails, and do not route peer-to-peer money through app-store billing. Keep app-store policies distinct from regulated payment-provider rules. Whether linking out to external payment apps or displaying payment instructions is permitted can depend on current platform rules, geography, entitlement, and flow details.

**Gate:** Before release, review current Apple App Review Guidelines and Google Play policies for the exact payment, account, link-out, and digital-feature flows; have counsel/provider partners review as needed. Document approval and platform-specific UX before enabling live rails.

### Public website, domains, email, legal pages, and branding

These are future deliverables. Do not register domains, create accounts, publish policy text, or send mail without explicit authorization. Use placeholders in development and never present draft terms as legal advice. Coordinate the logo with the owner/designer; preserve brand assets and licensing details in the repository.

**Gate:** Owner supplies preferred domain/name checks, registrar/account access through a secure process, sender identity and email provider, support contact, approved privacy/data practices, and counsel-reviewed terms/privacy disclosures before public launch.

## Suggested architecture principles

Adapt to the existing stack; do not introduce a framework or cloud service without a clear repository need and an ADR.

- **Domain core:** model users/local profiles, groups, memberships, expenses, split allocations, balances, settlements, invitations, receipts, and payment attempts as explicit concepts. Keep currency amounts as integer minor units (or a carefully specified decimal type), with currency code and rounding rules; never use binary floating point for money. Bangladesh Taka is the initial currency assumption, not a hard-coded global limitation.
- **Ledger integrity:** preserve who/when/source for changes; define edit, deletion, reversal, and settlement semantics. Derive balances from immutable or auditable entries where practical. Reconcile computed balances against source entries. Do not allow negative/overflow or ambiguous rounding to silently alter money.
- **Local persistence:** SQLite behind a repository/data-access boundary, schema migrations, transaction boundaries, backup/export behavior, and a documented encryption-at-rest choice. Avoid placing raw SQL throughout UI code. Keep migrations reversible where feasible and test upgrades from prior schemas.
- **Sync boundary:** define a transport-neutral synchronization interface only when needed. Use versioned changes, conflict handling, idempotency keys, tombstones/deletion semantics, and least-privilege authorization. Do not add a dormant abstraction without an actual use case.
- **Payments boundary:** provider adapters expose capabilities and states without leaking provider SDK types into the ledger. Model states such as `not_started`, `handoff_started`, `pending`, `confirmed`, `failed`, `reversed`, and `reported_unverified`; only trusted provider evidence can transition into confirmed. Store a provider reference/token rather than credentials. Verify callbacks and make processing idempotent.
- **OCR boundary:** extraction output is untrusted structured input with confidence/provenance. Validate totals and fields, allow edits, and never create or settle an expense without user confirmation.
- **Localization:** centralize UI strings, use typed translation keys and locale-aware formatters, and test Bengali rendering, font fallback, text expansion, digit choices, accessibility labels, and names preserved exactly.
- **Widgets:** expose only user-approved, minimal data. Widgets are glance surfaces, not trusted transaction controls; sensitive details should be hidden on lock screens where platform settings require. Deep links must re-check authorization in the app.
- **Observability:** collect only approved, minimized telemetry. Redact amounts, names, phone numbers, emails, receipt images, tokens, and financial references by default. Use correlation IDs that are not secrets.

## UI, accessibility, and performance

- Keep core flows short: record expense, review split, see balances, start settlement, confirm evidence/status. Explain each payment state in plain language.
- Support light/dark themes, scalable text, screen readers, sufficient contrast, visible focus, touch targets, and reduced motion. Do not use color alone to indicate debt, success, or failure.
- Design responsive layouts for narrow phones, large phones, tablets, landscape, split view, and foldable inner/outer displays. Avoid assuming a particular future product name; rely on size classes/window metrics and test hinge/fold transitions where tooling allows.
- Keep startup, scrolling, OCR, image loading, database work, and navigation responsive. Use asynchronous I/O and background work for expensive operations; avoid blocking the UI thread. Set measurable performance budgets after establishing a baseline on representative lower-end Android hardware and supported iPhones.
- Handle offline mode explicitly: show when data is local, pending, stale, unsynchronized, or unavailable. Never imply server confirmation while offline.
- Keep animations purposeful and lightweight. Avoid unnecessary dependencies, excessive polling, hidden background work, or dead code.

## Security and privacy threat model

Assume attackers may have a lost/unlocked device, malicious or compromised invite recipient, link forwarding, malicious receipt image, rooted/jailbroken device, compromised dependency, network interception attempt, fraudulent payment proof, replayed callback, or access to backups/logs. Consider insider/provider access and metadata exposure as well.

Required controls, proportional to the chosen architecture:

- Use platform secure storage for keys and tokens; do not implement custom cryptography. Select maintained, reviewed libraries and document algorithms, key derivation, rotation, recovery, and backup implications. If no vetted key/recovery design exists, do not claim E2EE.
- Encrypt sensitive local data at rest when the threat model and platform support it; define behavior for key loss and app reinstall. Protect exports and warn that exported files leave app controls.
- Use TLS for network traffic; validate server certificates using platform defaults. Authenticate and authorize every shared-data operation server-side if a backend exists. Apply least privilege, rate limits, abuse detection, and safe error messages.
- Treat deep links, share links, OCR output, imported files, callback payloads, and user-entered references as untrusted. Validate sizes, types, schemas, ownership, expiry, and replay/idempotency.
- Do not log secrets or sensitive financial/identity data. Scrub crash reports and test artifacts. Keep development and production credentials separate and rotate any exposed secret.
- Protect against account enumeration, invitation spam, insecure direct object references, duplicate settlement, unauthorized group access, link leakage, and backup disclosure.
- Document data inventory, purpose, lawful/consent basis as reviewed by counsel, processors, retention, deletion, export, and incident response before launch.

## Engineering and repository workflow

- Inspect before editing. Make focused, reviewable changes consistent with existing style and architecture.
- Keep business rules out of presentation code. Prefer small, cohesive modules and explicit types. Avoid unnecessary frameworks, hidden global state, magic money values, broad catch-and-ignore blocks, and speculative features.
- Validate inputs at boundaries. Handle errors intentionally and give users actionable messages without exposing internals.
- Keep dependencies current enough for supported platforms, pinned/reproducible where appropriate, and reviewed for maintenance, licensing, transitive risk, and data handling. Do not add a dependency for a trivial helper.
- Never commit secrets, real personal data, production payment references, or unredacted receipts. Include safe example configuration and a clear `.env.example` only if the stack uses environment variables.
- Use branches/PRs and human review according to repository norms. Do not rewrite shared history or force-push unless explicitly instructed. Never claim a commit, remote update, collaborator invitation, or deployment occurred unless it did.
- Keep docs aligned with actual behavior. Mark future work as planned and provider integrations as unavailable until proven.

## Testing and release quality

“Every line tested” is not a useful literal requirement. Aim for meaningful coverage of critical behavior and risk, especially money calculations, permissions, and state transitions. Do not optimize for a coverage percentage at the expense of useful assertions.

- **Unit tests:** split algorithms, rounding, currency formatting, balance derivation, ledger invariants, state machines, validation, and localization formatters. Include property/boundary tests for zero, large values, uneven splits, participant changes, duplicate actions, and reversals.
- **Persistence tests:** migrations, transaction rollback, restart recovery, backup/restore, export/import, deletion, and corruption/error handling.
- **Integration tests:** repository/data flows, provider sandbox adapter behavior, callback signature validation/replay/idempotency, offline/retry behavior, and OCR parsing against synthetic or consented redacted fixtures. Never use real customer data.
- **UI/accessibility tests:** primary journeys, language switch, screen-reader semantics, large text, dark/light mode, permission denial, keyboard/focus where relevant, deep links, empty/error/offline states, and widget privacy.
- **Device matrix:** supported iOS and Android versions; phone and tablet layouts; narrow/large screens; portrait/landscape; foldable states when available; lower-end Android performance. Use simulators/emulators and real devices for hardware-dependent behavior. State exactly what was and was not tested.
- **End-to-end acceptance:** create group; invite or share scoped access; record receipt/manual expense; review split; compute balances; initiate an approved payment handoff; return with pending state; confirm only through approved evidence; handle failure/reversal; export/delete as designed.
- **CI:** format/lint, static analysis/type checking, unit/integration tests, dependency and secret scanning, build checks for supported targets, and migration checks. Keep secrets in CI secret storage. Block release on critical security, payment-integrity, or data-loss failures.
- **Release gate:** signed builds, privacy disclosures and permission rationale, store policy review, provider sandbox certification/production approval, legal/compliance review, support/incident process, backup/recovery policy, accessibility review, and tested rollback/disable switch for payment features.

## Compliance and legal review gates

This document is not legal advice and does not assert that TakaDe is licensed or compliant. Before processing real payments or launching in Bangladesh, obtain qualified local legal/compliance advice on the applicable roles and obligations, which may include payment services, money transmission, agent/merchant arrangements, consumer protection, AML/CFT, KYC, sanctions, privacy/data protection, cybersecurity, records, tax, cross-border processing, and outsourcing. Confirm the obligations with relevant regulators and each provider; do not assume that merely redirecting to a provider eliminates them.

Before any production payment flow, approve and document: product role, funds flow, who holds/controls funds, provider authorization, onboarding/KYC responsibility, fees/disclosures, complaints/refunds/reversals, fraud monitoring, transaction records, consent, data sharing/retention, security review, operational incident response, and kill switch. Keep live rails disabled until all required parties approve.

Before app-store release, verify current policies and technical requirements from official Apple and Google sources for the exact app version and flow. Re-check policy changes at submission time. Do not encode policy assumptions as permanent facts.

## Suggested phased roadmap

1. **Discovery and foundations:** inspect repository/stack; resolve account, sync, data, currency/rounding, and target-support decisions; define threat model and ADRs; build design tokens and localization structure.
2. **Local ledger MVP:** local profiles, groups, manual expenses, split methods, balances, edit history, SQLite migrations, export/delete, English/Bengali UI, accessible light/dark layouts, and offline-first behavior. No live money movement.
3. **Sharing and receipts:** scoped share/export and invite prototypes that clearly disclose limitations; receipt capture/OCR with human review; choose on-device/cloud path after privacy evaluation. Add abuse controls if links/services are introduced.
4. **Provider feasibility:** secure written approval and sandbox details for each bKash/upay/bank rail; implement isolated adapters and verified state machines; run security, legal, and provider certification reviews. Begin with handoff/pending/reporting UX if confirmation is not available.
5. **Collaboration/sync:** only after the owner chooses a service model; implement identity, access control, sync/conflict/recovery, notifications and invitation delivery with privacy and abuse controls.
6. **Platform readiness and launch:** widgets, device coverage, performance/accessibility, store review, legal pages, support, domain/email setup, monitoring, incident response, and staged rollout.

## Acceptance criteria for meaningful changes

A change is ready for review when:

- Its user-facing behavior and limitations are clear, including offline/provider-pending states.
- Money and privacy invariants are preserved; no reported or unverified transfer appears provider-confirmed.
- Localization includes English and Bengali where applicable and preserves personal names.
- Accessibility and responsive behavior are considered for affected screens.
- Relevant tests and static checks pass, or any unrun checks are reported with the reason.
- Migrations, permissions, data retention, logging, and threat-model impact are addressed.
- Documentation describes what exists now, not an aspirational capability.

## Owner decisions and materials needed later

Collect these before the corresponding work begins; do not block safe local-only foundations while waiting for unrelated decisions.

1. **Repository:** GitHub owner/organization and private repository URL, preferred default branch, access method, and whether the repository is already cloned. Confirm the intended collaborator identity/username for Zawad Nafi before any invitation; do not add collaborators without explicit authorization in the active task.
2. **Product:** confirm product name spelling/brand, first release scope, intended user age/market, primary split rules, whether guests can only view/settle or also edit, and the exact meaning of “no central database.”
3. **Architecture:** choose local-only, encrypted sync, or conventional backend; account/authentication model; recovery model; backup/export/deletion expectations; permitted analytics/crash reporting.
4. **Payments:** target providers/banks, legal entity/merchant/partner status, provider contacts/contracts, official API docs, sandbox and test credentials through a secure channel, supported rails/currencies, who bears fees, verification/reversal semantics, support owner, and explicit legal/compliance approval. Never place secrets in chat or source control.
5. **Email setup (especially required):** chosen domain and who controls DNS; sender address/name (for example, a verified product support/invitations mailbox); sending provider and account owner; DNS verification authority for SPF, DKIM, and DMARC; reply-to/support inbox; whether email is for invitations, authentication, receipts, or support; consent/retention policy; and whether transactional delivery is needed before launch. Provide access via a secrets manager or provider invitation, never by pasting passwords/API keys into prompts. Phone/SMS provider and sender registration decisions are separate.
6. **Localization:** approved Bengali terminology/translator/reviewer, font preference, locale conventions for digits, dates, and currency, and whether Bengali is the default for any audience.
7. **Platforms/devices:** confirmed minimum OS versions, device lab or representative models, widget scope, and any actual foldable models to prioritize. Treat “iPhone Duo” as an unverified device label; use responsive layout requirements until an official model is identified.
8. **Brand/legal/web:** logo owner/designer and source/licensing files; approved domain(s); support/contact details; counsel-reviewed privacy notice, terms, and required disclosures; public launch geography and legal entity details.
9. **Operations:** support and incident contacts, backup/recovery owner, release approvers, production monitoring/data retention, and feature kill-switch expectations.

## How Claude should report work

At completion, summarize the user-visible change, key design/security decisions, tests actually run and their results, device/platform coverage actually performed, unresolved decision gates, and any repository actions taken. Distinguish “implemented,” “tested in sandbox,” “provider-approved,” and “production-enabled.” If access or evidence is missing, say so plainly and leave the safest state in place.
