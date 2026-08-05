# Property Pulse — iOS ↔ Flutter Feature Parity Audit

**Source of truth:** native SwiftUI app at `../Property Pulse/Property Pulse.xcodeproj`
**Audit target:** this Flutter app (`lib/`), which ships to both iOS and Android
**Date:** 2026-07-27 (Phase 1 implemented same day — see status notes below). **Phase 5 final verification completed 2026-07-28. Phase 6 (deepest round — nav/screens/features/UI-UX/business-logic/AI/backend, per-role) completed 2026-07-29, see [PHASE_6_FINAL_VERIFICATION.md](PHASE_6_FINAL_VERIFICATION.md).**
**Method:** 7 parallel deep-read audits (not filename comparisons) across every role and feature domain, followed by a Phase 5 re-audit (3 more parallel deep-read agents) and a Phase 6 re-audit (8 more parallel deep-read agents, one per domain: navigation, screens inventory, core features, messaging/notifications, AI, monetization/business-logic, UI/UX system patterns, backend infrastructure) verifying prior remediation actually landed correctly and hunting for anything missed. Every claim below is backed by an agent that opened the actual Swift and Dart source, not just directory listings.

---

## Executive summary

| Domain | Parity | Direction |
|---|---|---|
| Auth / Onboarding / Navigation / Profile / Verification / Support | ~~~78% → 92%~~ **~95%** | Flutter behind (small remaining gaps) |
| Home / Explore / Search / Property Details / Map / Saved | ~~~85% → 93%~~ **~95%** | Flutter behind (small remaining gaps) |
| Listing Management — Realtor 85%, Developer 90%, Airbnb Host 90% | ~~~88% → 93%~~ **~95%** | Flutter behind (small remaining gaps) |
| AI Features (Pulse Finder, AI listing/search) | **~97-98%** | **Flutter is ahead** — iOS is the one catching up here |
| Messaging / Notifications / Reviews | ~~~75-80% → 93%~~ **~96%** | Flutter behind (small remaining gaps) |
| Monetization (Subscriptions, Billing, Cancellation, Dispute) | ~~~30-35% → 78%~~ **~88%** | Flutter behind — most-improved domain, still the laggard |
| Admin | ~~~85% → 95%~~ **~96%** | At or near parity — Flutter now audits a superset of iOS's admin actions |

**Blended estimate: ~93% overall**, up from ~75-80% at the start of implementation. Every Phase 6 re-audit found something new — including two critical bugs in domains previously marked "matches" (a broken photo-upload Storage path, and approved verifications displaying as rejected) — proof that later rounds keep surfacing real issues rather than converging to zero; see [PHASE_6_FINAL_VERIFICATION.md](PHASE_6_FINAL_VERIFICATION.md) for the full breakdown, per-role percentages, and everything deliberately left unfixed with its reasoning.

### The two findings that matter most before anything else

1. ✅ **DONE** — **Security issue, not just a gap:** `lib/screens/host/dispute_flow_screen.dart` submits disputes via a **direct client-side Firestore write** (`collection('disputes').add(...)`) instead of going through the `openDispute` Cloud Function iOS uses. This bypasses server-side validation entirely and should be treated as a correctness/security fix, independent of the broader parity backlog.
   *Fixed:* now calls the already-deployed `openDispute` Cloud Function (confirmed live in `functions/dispute-functions.js`, alongside `resolveDispute`/`sendDisputeMessage`/`addDisputeEvidence`/`assignDispute`, which the broader Dispute lifecycle work in Phase 2 can build on). Errors surface the server's sanitized `HttpsError.message` instead of a raw exception string.
2. ✅ **DONE** — **No admin audit trail:** every ban, suspend, role change, property status change, and moderation action performed in the Flutter admin console is currently unaudited — `admin_repository.dart` never writes to the reserved `admin_audit_log` collection that iOS's `AdminAuditService` populates on every mutating action.
   *Fixed:* added `lib/services/admin_audit_service.dart` (mirrors iOS field-for-field) and wired it into all 16 mutating methods on `AdminRepository` — bans/unbans, suspensions, role changes, property status/moderation changes, listing removal, trust-score events, project moderation, admin-application decisions, verification decisions, moderation/property-report status changes, settings changes, and maintenance backfills. Logging is best-effort and never blocks the underlying admin action if it fails.

Both are called out again in the phased plan below at the top of Phase 1.

---

## 1. Auth, Onboarding, Navigation, Profile/Settings, Verification, Support — ~78%

**Strongest sub-areas:** Verification (near-1:1, both sides were explicitly built to mirror each other, including matching Firestore dual-writes and image-compression logic) and Navigation (role→tab routing logic is close to a line-for-line port of iOS's `MainTabView.compactMiddleTab`).

**Missing entirely:**
- `RequiredUserTypeOnboardingView` equivalent — iOS forces a non-dismissible role selection immediately after signup; Flutter's role picker is just one optional, skippable step in a 9-step onboarding flow. A Flutter user can end up with no role resolved and no forced path to fix it.
- `AirbnbHostOnboardingView` equivalent — iOS's dedicated 5-step Airbnb host setup wizard (space type, income goal, availability, booking policy, Stripe Connect payout gate) has no Flutter counterpart.
- Legal consent footer (tappable ToS/Privacy links) on the sign-in screen.
- "Rate the App" / in-app review prompt in Support.
- "Account Deleted" reactivation alert on sign-in.
- iPad sidebar's dedicated Support/Admin nav entries (Flutter's tablet rail doesn't surface these — may be an intentional simplification, needs a decision either way).

**Suggested order:** legal consent footer → mandatory role-lock screen → Airbnb host onboarding wizard (depends on role-lock existing first) → rate-app action → account-deleted alert → decide on iPad sidebar parity.

---

## 2. Home, Explore/Search, Map, Property Details, Saved — ~85%

**Strongest sub-areas:** Property Details is comprehensive (gallery, amenities, contact/inquiry, save/share, trust score, schedule-viewing, mini-map, report listing, document sharing all present). No mortgage calculator exists on either platform — not a gap, the feature doesn't exist in the product.

**Real gaps:**
- **Search pagination is capped, not infinite.** iOS does cursor-based pagination (`loadMoreProperties()` on scroll). Flutter's `PropertyRepository.watchFilteredListings()` uses a fixed `.limit()` stream with no load-more — results silently truncate at 20 (or 400 for Airbnb) with no way to see more.
- **Owner status picker missing from the property detail screen.** iOS lets an owner/realtor change Available/Pending/Sold/Rented inline from the listing detail view; Flutter has no equivalent outside the admin dashboard.
- **"Nudge" / visibility-reduction subsystem entirely absent** — iOS tracks `nudgeCount`, `isVisibilityReduced`, `autoDowngradeCount`, `statusUpdateRemindersSent`, `isFlaggedForInactivity` on stale listings with a "Mark as Active" recovery action. None of these fields exist on Flutter's `PropertyModel`, and no UI references them.
- **Airbnb detail: data modeled but not displayed.** `AirbnbInfoModel` already has `checkInTime`/`checkOutTime`/`cancellationPolicy`/`maxGuests` — the detail screen just never renders them. Purely a UI task, no new data plumbing needed.
- **Airbnb booking date picker has no booked/blocked-date awareness** — guests can select already-booked dates with no visual warning (iOS shows an inline calendar with booked dates in orange, host-blocked in gray).
- Minor: no "Clear all" on Saved, no empty-state CTAs on Saved, "Add Property" quick action isn't role-gated on Flutter home (Seekers/Hosts/Developers see it when iOS hides it from them).

**Suggested order:** pagination fix → Airbnb detail UI (cheap, data already exists) → owner status picker → nudge subsystem (needs new model fields, largest effort here) → saved-screen polish → quick-action role gating.

---

## 3. Listing Management — Realtor 85% / Developer 90% / Airbnb Host 90%

**Strongest sub-areas:** the Airbnb 11-step listing wizard is close to an exact port (identical step enum, order, and even copy). Developer project/unit/team/leads/billing screens are comprehensive.

**Real gaps:**
- **No validated property status state machine.** iOS's `updatePropertyStatus`/`isValidStatusTransition` enforces legal transitions (e.g. `sold` → only `archived`), ownership/admin checks, and fires save/like notifications on status change. Flutter's `PropertyRepository.updateProperty()` is a raw pass-through — any caller can set any status with no validation and no notification side effects. This is the same root cause as the missing owner status picker in section 2, and should be built once and reused by both.
- No "duplicate unit type" action in the developer project/unit editor (iOS has it).
- `RegisterInterestView`/`CustomerDashboardView` iOS equivalents weren't located in Flutter under the audited paths — flagged for follow-up verification rather than confirmed missing.
- Booking accept/decline race-condition guards (iOS re-validates `status == confirmed` before accepting) weren't fully verified line-by-line on the Flutter side — worth a dedicated pass.

**Suggested order:** port the validated status-transition service first (foundational, unblocks the owner status picker from section 2) → duplicate-unit-type action → verify register-interest/customer-dashboard coverage → line-by-line booking accept/decline diff.

---

## 4. AI Features (Pulse Finder, AI listing/search) — ~97-98%, Flutter ahead

This is the one domain where Flutter is not behind. Every iOS AI source file's own header comments state it mirrors the Flutter/Android implementation, not the other way around — both clients call the same shared Firebase Functions backend. Every Pulse Finder capability (intent lock, refinement parsing, recommendations, explainers, development matching, question answering, consultation history/resume) has a working, tested Flutter port, wired into navigation and correctly feature-flag-gated at both entry points (Home quick action, Explore entry card).

**The only asymmetries run the other direction:**
- iOS's `AIFeatureFlagsViewModel` only wires 3 of the 6 backend AI capability flags (`listingGeneration`, `search`, `propertyChat`) — Flutter's `AiCapability` enum has all 6, including `comparison`, `moderation`, `recommendations`, which iOS can't currently read at all.
- Flutter logs `latency_ms`/`cache_hit` in its `pulse_finder_search_executed` analytics event; iOS's equivalent event doesn't.

**Suggested order (this time, work is on the iOS side):** add the 3 missing capability fields to iOS's feature-flag view model → add the missing analytics fields to iOS's search-executed event. No Flutter-side action needed.

---

## 5. Messaging, Notifications, Reviews — ~75-80%

**Strongest sub-areas:** real-time conversation/message listeners, optimistic send with de-dupe, image attachments, and the in-app notification center are all faithful ports (several files explicitly comment "same Firestore path as iOS"). Flutter's read-receipt and per-user unread-counter implementations actually exceed what iOS does.

**Real gaps:**
- **Typing-indicator schema mismatch.** iOS writes typing state as a map field on the conversation doc; Flutter writes to a `typing` subcollection. Neither client can currently see the other's typing signal — this only matters if iOS and Flutter/Android users are expected to interoperate live in the same conversation, but if so it's a real incompatibility, not just a style difference.
- **No push notification triggered on message send.** iOS explicitly calls a `sendMessageNotification` Cloud Function after every send; grepping all of `lib/` found no equivalent call anywhere in the messaging service. Unless a server-side Firestore trigger covers this invisibly (not present in this repo), sending a message from Flutter does not push-notify the recipient.
- **No OS app-icon badge**, and **no in-app Messages-tab badge** — the bottom-nav item model has no badge-count field at all. (The home-screen bell badge, by contrast, is exact parity.)
- **Review "Report" flow is entirely missing** — iOS has a full spam/abuse report sheet; Flutter's reviews screen has no report UI, and nothing client-side ever writes to the moderation-reports collection for a review.
- **Property rating fields don't sync after a review is added.** iOS updates `averageRating`/`totalReviews` on the property document when a review is submitted; Flutter's `UserProfileRepository.addReview` only inserts the review — the stars shown on property cards/search/home go stale until something else updates those fields.
- Message search only filters the loaded conversation-list preview, not message bodies within a thread (iOS searches the last 100 messages per conversation).

**Suggested order:** property rating write-back (cheap, high visible impact — this is the highest-value one-line-ish fix in the whole audit) → message-send push trigger → app-icon + tab badge → review report flow → cross-thread message search → reconcile typing-indicator schema if cross-platform interop in the same conversation is a requirement.

---

## 6. Monetization — ~30-35%, the weakest domain by far

Payment *plumbing* that already exists is solid: Stripe booking payments, lead-credit top-up, general Premium in-app-purchase, restore-purchases, and the quota/grace-period entitlement model are all close ports. Everything past that is thin, stubbed, or unsafe.

**Real gaps, roughly worst-first:**
- **Dispute flow does an unsafe direct client Firestore write** instead of calling the `openDispute` Cloud Function — see the security callout at the top of this report. There is also no `DisputeService`, no evidence upload, no post-submission messaging thread, and no admin resolve/assign action (the admin dashboard only *displays* the disputes list today).
- **Cancellation is host-only.** There is no guest-initiated cancellation flow, and the refund shown is a hard-coded static message ("5-7 business days") rather than iOS's server-computed tiered refund preview (`CancellationPolicyEngine`, which factors hours-before-check-in against the property's cancellation policy). No admin-override cancellation path exists either.
- **Boost credit packs are purchase-only, not redeemable.** The IAP plumbing to buy a 3-pack/5-pack of boost credits exists but is dead code — nothing ever debits a credit, applies it to a listing, or tracks a `boostCredits` balance. Single-duration boosts (7/14/30-day) work but write a simpler schema than iOS (no `propertyBoosts` audit collection, no transaction-ID trail, no ownership-verification guard before boosting).
- **Role-tier subscriptions beyond the single Premium/Developer-Pro tier are mockup UI with fake product IDs.** `subscription_plans_screen.dart` shows Owner Pro, Realtor Pro/Elite, and Airbnb Host Pro/Plus tiers, but none of them call the real billing service — they use invented product-ID strings and a hard-coded "coming soon" snackbar, even for tiers (Realtor Pro, Airbnb Host Pro) that are actually live and purchasable on iOS today.
- No Flutter equivalent of the developer billing-explanation model (free-trial-lead vs. paid-balance messaging, volume-discount tiers).

**Suggested order:** fix the dispute security gap first (independent of everything else, do this regardless of sequencing) → port the cancellation policy engine + guest cancellation flow → build a real `DisputeService` (evidence upload, messaging, admin resolve) → wire boost-credit redemption (cheapest high-value fix, purchase side already works) → decide fate of the mocked role-tier subscription screen (wire to real product IDs or clearly label not-yet-available, matching iOS's own `comingSoon` convention, rather than leaving fake IDs in a shipped screen).

**Cross-cutting note from this audit:** if a developer/realtor entitlement-tier service gets built to close this gap, coordinate it with the existing `ListingEntitlements` model (section 3) rather than creating a second, inconsistent source of entitlement truth.

---

## 7. Admin — ~85%

The 19-vs-5 file-count difference between iOS and Flutter is **not** a real capability gap — Flutter's `admin_dashboard_screen.dart` is a single 4,500-line file that consolidates roughly ten iOS views into tab-switched sections, and the overwhelming majority of iOS admin capabilities (dashboard, users, verification queue, moderation queue, properties, settings, developments, booking moderation, analytics, admin-application lifecycle) do have a working Flutter counterpart, several with in-code comments confirming they were deliberately built to mirror iOS.

**Real gaps:**
- **No admin audit logging anywhere in Flutter** — see the top-of-report callout. Every destructive/moderation admin action is currently silent, with the `admin_audit_log` collection reserved but never written to.
- **No drill-through from a moderation report to the actual reported property/user.** Flutter's report detail sheet shows only the raw target ID as text; iOS fetches and renders the actual entity with an inline action path.
- **Verification document viewer is broken for real-world use.** It only reads a single flat `documentUrl` field and renders it via a basic image widget — multi-document verification requests aren't represented at all, and a PDF document will render as a broken image rather than being viewable.
- No "Edit Property" action, no bulk/multi-select actions (archive/take-down/delete many at once), and no owner/realtor name shown in the admin Properties row.

**Suggested order:** admin audit logging first (accountability gap, should block nothing else and is additive) → moderation report drill-through → verification document viewer (PDF + multi-document support — trust/safety-critical) → properties bulk actions + edit-in-place → owner name in Properties row (cosmetic, do last).

---

## Implementation plan and status

Superseded by the user's own phase ordering (Phase 1 security/correctness → Phase 2 Monetization → Phase 3 remaining feature parity → Phase 4 polish → Phase 5 final verification). Status below reflects that ordering, not the original §-numbered backlog this report started with.

**Phase 1 — correctness & security: ✅ COMPLETE**
1. ✅ Fixed the dispute flow's unsafe direct Firestore write → routed through the `openDispute` Cloud Function (§6).
2. ✅ Added admin audit logging to every mutating admin action (§7).
3. ✅ Property `averageRating`/`totalReviews` write-back on review submission (§5).

Verified via `flutter analyze` (clean) and the full test suite (552/552 passing).

**Phase 2 — Monetization parity: ✅ COMPLETE**
1. ✅ Booking cancellation — ported `CancellationPolicyEngine`/`CancellationPolicy` (client-side tiered-refund preview mirroring the server's `BUILTIN_POLICIES`), added a real guest-initiated cancellation flow with guest-specific reasons (guests previously could only hard-cancel via a bare confirm dialog with no refund preview), and unified host/guest onto the same preview + reason-selection UI.
2. ✅ Dispute lifecycle — new `DisputeService` + `Dispute`/`DisputeMessage`/`EvidenceItem` models wrapping the already-deployed `sendDisputeMessage`/`addDisputeEvidence`/`resolveDispute`/`assignDispute` Cloud Functions (confirmed live in `functions/dispute-functions.js`, previously unused by the client); new `DisputeDetailScreen` with evidence upload, a real-time message thread, and an admin resolve/assign panel. Along the way, found and fixed a **second** unsafe direct-Firestore-write in the admin dashboard's dispute queue (`_DisputeQueueAdmin` — it was marking disputes "resolved" with no refund, no Stripe interaction, and no notification), plus a field-name bug (`orderBy('createdAt', ...)` against docs that only ever had `openedAt`) that silently hid every dispute from the admin queue.
3. ✅ Boost credit redemption — rewrote `PremiumBoostService` to match iOS's `propertyBoosts` audit-trail collection, idempotent `boostCredits` ledger, and ownership check. Found and fixed a real product-delivery bug: buying a 3-pack/5-pack of boost credits was silently applying a generic 7-day boost to whatever property was mid-purchase instead of crediting the user's balance — packs were purchase-only with no redemption path. `boost_listing_screen.dart` now shows the credit balance and lets a user redeem a credit against any owned listing, or buy a pack independent of any specific property.
4. ✅ Purchase validation / subscription tiers — `subscription_plans_screen.dart` was entirely disconnected mockup UI (fake product-ID strings, a snackbar pretending to open Google Play). Wired Developer Pro, Realtor Pro, and Airbnb Host Pro to their real store product IDs (Realtor Pro's and Airbnb Host Plus's IDs didn't even exist in `InAppBillingService` yet — added them); the remaining tiers (Developer Growth, Owner Pro/Investor, Realtor Elite, Host Plus) are now honestly labeled "Coming Soon" and disabled, matching iOS's own `comingSoon` convention instead of a fake purchase button. Also fixed the Airbnb Host tier's name and price, which were wrong on both counts ("Host Elite $49.99/mo" shown instead of "Host Plus $39.99/mo"; "Host Pro" was listed at $19.99/mo instead of $9.99/mo).
5. ✅ Payment edge cases — added distinct "pending approval" messaging (e.g. Family Library purchases needing approval) separate from the generic purchase spinner and from hard errors, surfaced on all three purchase screens; added `effectiveTierProductId()` implementing iOS's legacy-plan grandfathering rules (old host-listings add-on → Host Pro, old general Premium held by a realtor → Realtor Pro), wired into the "Current Plan" badge for the realtor context.

**Not done in Phase 2 (explicitly out of scope, flagged for later):**
- `isFeatured`/`featuredUntil` vs iOS's separate `isBoosted`/`boostEndDate` fields remain unreconciled — boosts still write to the existing `isFeatured` fields to avoid touching every Home/Explore "Featured" query; unifying the two flag pairs is a larger UI-wide change.
- `DeveloperProfileSnapshot`/`LeadBillingContext` (free-trial vs paid-balance billing-explanation model) — not ported.
- `PaymentEscrowService` (admin hold/release payout, freeze/unfreeze) — likely admin-console-only by design; not touched.
- Subscription grandfathering is only wired into the realtor context's "Current Plan" badge; not threaded into a general-purpose role-aware entitlement check elsewhere in the app.

Verified via `flutter analyze` (0 errors project-wide) and the full test suite (564/564 passing, up from 552 — added `cancellation_policy_test.dart`).

**Phase 3 — remaining feature parity: ✅ COMPLETE** (one item deliberately deferred to Phase 4 — see below)
1. ✅ Validated property status-transition service — `PropertyRepository.updatePropertyStatus` now enforces iOS's exact transition graph (e.g. `sold` → only `archived`) plus an ownership/admin check; the existing owner status picker on the detail screen (`_OwnerListingToolsCard`, which the original audit had missed — it already existed but called the old unvalidated `updateProperty`) now calls it and only offers legal next-states.
2. ✅ Search pagination — `watchFilteredListings` gained an optional `limitOverride` (fully backward-compatible; every other caller is unaffected), and Explore's results list now has a "Load more" control that widens the query a page at a time, including proportionally scaling the airbnb client-side-filter pool so "load more" doesn't shrink it.
3. ✅ Airbnb property-detail UI — check-in/out, max guests, and cancellation policy (reusing the Phase 2 `CancellationPolicy` model for the policy name/description) now render in a "Booking information" section; the booking date picker gained real booked/blocked-date awareness (`selectableDayPredicate` sourced from `bookings`, `host_bookings`, and `hostBlockedDates`), rejecting a range that overlaps an existing booking instead of silently allowing it.
4. ✅ Message-send push notification trigger — `MessagingService` now calls the already-deployed `sendMessageNotification` Cloud Function after every text/image send (best-effort, never blocks the send).
5. ✅ Verification document viewer — now supports both submission schemas (`documentUrl` and the enhanced flow's `documentUrls` array, which was previously invisible to admins entirely), renders a thumbnail grid, and opens PDFs externally instead of showing a broken image.
6. ✅ Review report/flag flow — reviews now have a report action wired to the same `moderation_reports` collection/schema the admin queue already reads.
7. ✅ App-icon + Messages-tab badges — added the `app_badge_plus` plugin (+ the OEM permissions its own README recommends) for the OS badge, and a generic `badgeCount` on `IosNavBarItem` for the in-app Messages-tab badge; both reuse the same unread-count computation as the existing home-screen bell.
8. ✅ Duplicate-unit-type action in the developer project/unit editor.
9. ✅ Admin moderation drill-through + properties bulk actions — the moderation report sheet now fetches and previews the actual reported property/user/review with a button to open it directly (previously just a raw target-id string); the admin Properties tab gained a bulk-select mode (archive/remove many at once) and an "Edit listing" action reusing the existing lister-facing edit screen via a new `isAdminContext` bypass of its ownership gate.
10. ✅ Mandatory post-signup role-lock screen + Airbnb host onboarding wizard — a new one-time-per-device gate (`OnboardingProvider.requiredRoleSelected`, checked in the router redirect) shows a non-dismissible 5-option role picker after sign-in, writing the real `role` (not just the pre-auth optional flow's local-only preference, which — confirmed while implementing this — never actually reached Firestore on either platform's Flutter code path before now); choosing Airbnb Host chains into a new 5-step wizard (space type, income goal, availability, booking style, Stripe Connect) matching iOS step-for-step. Note: iOS's own wizard is unwired dead code (not reachable from anywhere in the iOS app) — Android's version is actually wired up, which is a case of Android now exceeding iOS rather than matching it; worth flagging back if strict behavioral parity (including iOS's gap) is preferred over a working feature.

Verified via `flutter analyze` (0 errors project-wide) and the full test suite (570/570 passing, up from 564 — added 6 router-redirect tests covering the new mandatory-role gate, including admin/guest exemptions and the not-yet-loaded case).

**Deliberately not done in Phase 3:**
- Nudge/visibility-reduction subsystem (§2) — the largest net-new modeling effort in the whole backlog (new `PropertyModel` fields, a UI section, and whatever backend job populates them); pushed to Phase 4 rather than rushed.

**Phase 4 — polish: ✅ COMPLETE**
1. ✅ Legal consent footer on sign-in (ToS/Privacy links).
2. ✅ Rate-app prompt in Support (`in_app_review`).
3. ✅ Account-deleted reactivation alert — `AuthProvider` now checks `isDeleted`/`isBanned`/`isSuspended` after every non-anonymous sign-in and surfaces a dedicated dialog/inline error instead of a silent failed sign-in.
4. ✅ Saved-screen polish — "Clear all" action (optimistic, restores failed removals) and Browse/Search CTAs on the empty state.
5. ✅ Quick-action role gating on Home — "Add property" now hidden for roles that can't list (mirrors iOS's role check instead of showing a dead-end action to every signed-in user).
6. ✅ Typing-indicator schema reconciliation — Flutter was writing typing state to its own subcollection while iOS reads/writes a `typingStatus` map field on the conversation doc itself; an iOS user typing was invisible to their Flutter peer and vice versa. Unified onto iOS's schema.
7. ✅ Cross-thread message search — `MessagingService.searchMessages` (unions `participants`/`participantIds`, scans the last 100 messages per conversation, same cost profile as iOS's `MessageViewModel.searchMessages`) wired into `messages_screen.dart` with a 300ms debounce, replacing the conversation list with a dedicated results view while a query is active — mirrors iOS `MessageCenterView`'s `isSearchActive` behavior exactly, including the debounce interval.
8. ✅ Nudge/visibility-reduction subsystem — added `nudgeCount`/`isVisibilityReduced`/`statusUpdateRemindersSent`/`autoDowngradeCount`/`isFlaggedForInactivity` to `PropertyModel` (dual camelCase/snake_case Firestore keys, matching iOS's own flexible decoding) and a status section on the owner's listing-tools card showing nudge count, a visibility-reduced warning banner, auto-downgrade count, and a "Mark as Active" recovery action for flagged listings. One deliberate divergence: iOS's own recovery button (`BackendSyncViewModel.markPropertyAsActive`) only writes `status: "active"` and never clears the flags it's reacting to, so on iOS the button never actually disappears after use — a bug in the source of truth. `PropertyRepository.markPropertyActive` fixes this by also clearing `isFlaggedForInactivity`/`isVisibilityReduced`/`nudgeCount` so the recovery action resolves the flagged state, with the same ownership/admin check pattern used by `updatePropertyStatus`.
9. ✅ iPad/tablet sidebar Support + Admin entries — `home_shell.dart`'s tablet `NavigationRail` (≥600dp) gained Support (pushes `/profile/support`) and, for admins, Admin (reuses the existing `navigateToAdminDashboard` helper and highlights correctly via the real admin shell-branch index) — mirrors iOS `IPadSidebarView`'s "Account" section, which has room for rows the phone tab bar cannot fit. Phone bottom nav is intentionally unchanged (still capped at 5 items, matching iOS's own compact-mode tab bar).

Verified via `flutter analyze` (0 errors project-wide, 722 pre-existing info/warning-level lints untouched by this phase) and the full test suite (572/572 passing, up from 570 — the 2 additional passes are the Phase 4.4 `clearAll` tests; no dedicated unit tests were added for the search/nudge/sidebar UI work itself, which is integration-shaped rather than unit-shaped).

**Phase 5 — final parity verification: ✅ COMPLETE**

Three parallel deep-read re-audit agents independently re-verified the Phase 1-4 work against the iOS source of truth and swept for anything missed. This surfaced several real, previously-undetected issues — proof the re-audit step was worth doing, not a formality. All CONFIRMED functional bugs found were fixed in this phase; cosmetic/lower-priority items and genuinely large net-new features were triaged and explicitly deferred (see below), not silently dropped.

**Fixed as a direct result of the Phase 5 re-audit:**
1. ✅ **Visibility-reduced properties were leaking into every discovery feed.** iOS suppresses `isVisibilityReduced: true` listings at the Firestore query layer in `PropertyLoadingService`/`PaginatedPropertyService`; Flutter's `PropertyModel.isDiscoverable` (added in Phase 4.8) was never actually wired into the feed-filtering path, so a flagged listing still appeared in Home, Search, Map, and every other `PropertyRepository` stream. Fixed in `_mapSnapshot` (`property_repository.dart`) — not as a Firestore-level `where` filter (which would have introduced the exact "silently excludes documents where the field is absent" bug the codebase's own `_baseQuery` deliberately avoids for `deleted`), but as the same client-side filtering pattern already established there.
2. ✅ Added the missing "Reminders Sent" indicator to the nudge status section (`property_detail_screen.dart`) — `statusUpdateRemindersSent` was parsed into the model in Phase 4.8 but never rendered, unlike iOS's `PropertyMetaSection`.
3. ✅ **Cross-platform unread-message-badge desync — the highest-severity Phase 5 finding.** iOS never writes or reads an `unreadCounts` field at all; it computes a lightweight 0/1 per-conversation flag from `lastMessageAt > lastReadAtByUser[uid]` (`MessageViewModel.swift:287-295`), and the app-icon/tab badge sums that flag across conversations (i.e. "number of conversations with something unread," not a running message tally). Flutter had invented its own `unreadCounts.{uid}` incrementing counter, written only from Flutter's own send path — so a message sent **from an iOS user to an Android user never incremented it**, silently breaking the Messages-tab badge, the home-screen bell, and the OS app-icon badge for that entire direction of cross-platform messaging. Fixed by replacing the counter with `MessagingService.isConversationUnread` (the same `lastReadAtByUser`-derived boolean iOS uses), stamping `lastReadAtByUser.{senderId}` on every send (mirroring iOS marking a sender's own message as immediately "read"), and updating every badge call site (`messages_screen.dart`, `home_shell.dart`, `home_screen.dart`) plus new-conversation creation (`property_repository.dart`) to match. The per-thread badge changed from a numeric pill to a dot, because iOS has no real per-conversation count to show — showing one on Android would have been a fabricated number.
4. ✅ **Premium subscriptions did not unlock any listing capacity — the highest-severity Monetization finding.** `InAppBillingService._onPurchaseUpdates` flipped the in-memory `isPremium` flag on a successful purchase but never wrote anything to Firestore. iOS's `SubscriptionService.syncBackendPlan` writes `plan: "pro"` to `users/{uid}` on every active subscription, which both `listing-limit-functions.js` (`inferPlan`) and the client's own entitlement check read as the signal to lift the listing cap. Without it, a paying Android subscriber's server-enforced listing limit silently never changed, and the entitlement would vanish entirely on reinstall since nothing survived outside local memory. Fixed with a `_syncBackendPlan()` write mirroring iOS exactly. Separately, `ListingEntitlements.allowedActiveListingLimit` only special-cased `plan == developer` for the unlimited-listings bypass, never `plan == pro` — a second, compounding bug on the client-side check, even though `ListingPlan.pro` was already a recognized enum value. Fixed to match iOS `Monetization.swift`/`listing-limit-functions.js`'s `allowedLimit` exactly (both `pro` and `developer` bypass the cap).
5. ✅ **Misleading plan copy on live, purchasable products.** Cross-checked every advertised limit in `subscription_plans_screen.dart` against the actual enforcement values in iOS `SubscriptionService.swift` and found multiple mismatches beyond the tier name/price fix already made in Phase 2: Host Pro/Plus described their cap as an *Airbnb* listing limit ("Up to 5/25 Airbnb listings") when Airbnb listings are actually always unlimited for that role — the real cap is on *general* listings (5 for Pro, 15 for Plus, not 25). Developer Pro/Growth showed "Up to 10 active developments"/"Unlimited" against a real 5/20. Owner Pro/Investor (not-yet-live "Coming Soon" tiers) showed a single blended number instead of iOS's split general/Airbnb caps (3+2 and 10+10). All corrected to match `SubscriptionService.swift`'s tier definitions exactly.

**Confirmed correct, no changes needed** (re-verified, not just re-asserted): all subscription/boost product ID constants match iOS exactly; cancellation refund tiers in `cancellation_policy.dart` match `functions/cancellation-functions.js`'s `BUILTIN_POLICIES` exactly; every dispute Cloud Function payload matches expected server params; boost-credit ledger idempotency mirrors iOS; typing indicators, `sendMessageNotification` payload, cross-thread search, and the review-report/admin-audit-log schemas from Phases 3-4 all hold up under re-inspection; Flutter's admin audit logging is a confirmed *superset* of iOS's, not a gap.

**Deliberately NOT fixed in Phase 5 — flagged for a future pass, not silently dropped:**
- **Developer project-count limits are enforced nowhere in Flutter** (zero references to any project-limit concept in `lib/`), vs. iOS's real 5/20 tier caps. This is the sharper edge of the `DeveloperProfileSnapshot`/`LeadBillingContext` gap already noted as deferred in Phase 2 — implementing it properly means porting the tier/grace-period model and gating project creation, which is new-feature-sized work, not a verification-pass fix.
- **`RealtorEntitlementService`/`visibilityWeight` has no Flutter port at all.** The Realtor Pro/Elite plan copy promises a "1.5×/2.5× feed ranking boost" that, on Android, is not backed by any ranking logic today.
- **The `isFeatured`/`featuredUntil` vs. `isBoosted`/`boostEndDate` split (deferred since Phase 2) is more impactful than originally scoped**: iOS actually sorts the shared discovery feed by `isBoosted`/`boostEndDate` (`PropertyViewModel.swift:231`), so a boost purchased on one platform currently has zero effect on the other platform's feed ranking — not just a display inconsistency, a cross-platform monetization-value gap.
- **iPad/tablet sidebar structure remains thinner than iOS's `IPadSidebarView`** per the original Phase 4.9 task scope (Support + Admin only, added and confirmed working) — iOS additionally has standalone Map/Projects entries, a role-gated "Manage" section (Add Listing/Host/Analytics), and a dedicated Appointments entry, none of which exist in the Flutter tablet rail. Flagged here for visibility since Phase 5 confirmed the gap directly, but left as-is since expanding tablet nav structure was never in scope for what Phase 4.9 asked for.

Verified via `flutter analyze` (0 errors project-wide, 722 pre-existing info/warning-level lints, unchanged) and the full test suite (572/572 passing — unchanged count, since Phase 5's fixes corrected existing behavior/copy rather than adding new testable surface area; no regressions introduced).

**No action needed:** AI/Pulse Finder (§4) — this domain is already at parity or ahead; the only follow-up items are on the iOS side.

---

*This report reflects the working tree as of 2026-07-27. Phases 1 and 2 are implemented and verified as of this same session. Re-running the relevant domain audit after significant further changes is recommended before treating any percentage above as current.*
