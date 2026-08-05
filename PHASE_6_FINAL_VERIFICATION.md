# Property Pulse — Phase 6 Final Parity Verification

**Date:** 2026-07-29
**Source of truth:** native SwiftUI app at `../Property Pulse/Property Pulse.xcodeproj`
**Method:** 8 parallel deep-read verification passes (navigation, screens inventory, core features, messaging/notifications, AI, monetization/business logic, UI/UX system patterns, backend infrastructure), each opening actual Swift/Dart/Cloud-Function source — not directory listings — followed by an immediate fix pass on every confirmed, safely-scoped issue found. This is the 6th and deepest audit round of this project, building on Phases 1–5.

## A note on "100%"

Literal 100% parity — zero discrepancies of any kind, pixel-identical spacing, identical animation curves, identical dark-mode rendering — is not a real, achievable, or honestly-reportable end-state between two independently-rendered UI frameworks (SwiftUI vs. Flutter). This report does not claim it, because doing so would be false. What follows is instead the most thorough verification this project has done: every one of the 8 passes found real, previously-undetected issues (including in domains this project had already marked "matches" in earlier rounds), every genuine bug or safely-scoped gap found was fixed immediately in this same pass, and every item that was NOT fixed is named explicitly below with the reason it wasn't — not silently dropped.

---

## 1. Overall parity percentage

**~93% overall**, up from ~90% at the end of Phase 5.

This is a considered estimate from the verification evidence below, not an automated metric — there is no tool that computes "% UI parity" between a SwiftUI and a Flutter codebase. It reflects: no missing core user-facing screens or flows, all identified functional bugs fixed, several cross-cutting system-level gaps (accessibility breadth, tablet two-pane layouts, some deep-linking) knowingly not fully closed and documented in §4/§9.

## 2. Parity percentage by role

| Role | Parity | Notes |
|---|---|---|
| Guest | ~96% | Browsing/search/auth are the strongest domains; nothing role-specific found broken. |
| Property Seeker | ~95% | Same strength as Guest plus saved/favorites, messaging, reviews — all verified solid this round. |
| Property Owner | ~93% | Owner subscription tiers are still "Coming Soon" (matches iOS, not a gap) but their copy is now correct; verification-status display bug (was showing false rejections) fixed. |
| Realtor | ~90% | Core listing/lead flows solid; the `visibilityWeight` feed-ranking boost promised in Realtor Pro/Elite copy still has no Flutter implementation (deferred, §4). |
| Developer | ~89% | The critical "paid for Pro/Growth, stayed capped at 1 project" bug is fixed this round; a client-side pre-submission limit check (nice-to-have, not required for correctness) remains deferred. |
| Airbnb Host | ~93% | Listing wizard, cancellation policies, business rules all verified matching; boost-purchase now correctly respects the ops kill-switch. |
| Admin | ~96% | Strongest role — Flutter's audit logging is a confirmed superset of iOS's, moderation drill-through exceeds iOS in places. |

## 3. What was found and fixed this round

Every item below was independently confirmed against the actual iOS/Cloud-Functions source before being fixed — none are taken on an audit agent's word alone.

1. **🔴 Critical — property photo uploads were broken.** `add_property_screen.dart` and `edit_property_screen.dart` uploaded to Storage path `properties/{id}/...`, which has no grant in `storage.rules` (only `property_images/{id}/...` is granted; everything else hits the deny-all catch-all). Every photo upload from the core Add/Edit Property flow would fail with permission-denied on-device — untestable via `flutter analyze`, only surfaces at runtime. **Fixed**: both now upload to `property_images/{id}/...`.
2. **🔴 Critical — approved verification requests displayed as "Rejected."** Admin approvals write `status: 'verified'`; `enhanced_verification_screen.dart` and `verification_details_screen.dart` only checked for `status == 'approved'`. Every genuinely-approved realtor/owner saw a red "Rejected" banner. **Fixed**: both now accept either spelling, matching iOS's own banner (which already checks both for this exact reason).
3. **🔴 High — most push notifications never deep-linked anywhere.** The Cloud Functions backend is itself inconsistent about the type-key it sends (`notificationType` for every booking event and for messages; `type` for disputes/cancellations/payouts). `push_notification_service.dart` read only `data['type']`, so tapping a notification for a new message or any booking-lifecycle event always fell through to the generic notifications screen — all of Flutter's carefully-built routing switch was effectively dead code. Compounding this, the message case read `threadId` when the payload field is actually `conversationId`. **Fixed**: added iOS's exact 3-way fallback (`type ?? notificationType ?? notification_type`), fixed the conversation-id field name, and added routing cases for every real notification-type value the backend actually sends (was previously missing `booking_declined`, `booking_expired`, `dispute_opened`/`resolved`, `payout_released`, and others). Also fixed the same bug in the foreground in-app banner's icon selection.
4. **🔴 High — Developer Pro/Growth subscribers stayed capped at the free tier.** `InAppBillingService._syncBackendPlan` wrote `plan: "pro"` on any subscription purchase but never wrote the separate `developerSubscriptionTier` field the Cloud Function's project-limit trigger (`onDeveloperProjectCreated`) actually reads. A developer who paid for 5 or 20 project slots stayed capped at 1 and had every subsequent project silently rejected server-side. **Fixed**: now writes `developerSubscriptionTier: 'pro'|'growth'` alongside `plan` for the relevant product IDs.
5. **🟡 Medium — cross-platform review data loss.** `ReviewCategory` wrote lowercase enum-name keys (`"cleanliness"`) while iOS reads/writes capitalized rawValues (`"Cleanliness"`) — every per-category star rating was silently invisible cross-platform. `ReviewType` was worse: Flutter had invented an entirely unrelated case set (buyer/renter/investor) with no correspondence to iOS's real domain values (general/stay/visit/purchase/rental). **Fixed**: category keys now write iOS's exact capitalized strings (reads stay case-insensitive for backward compatibility); `ReviewType` realigned to iOS's actual five values.
6. **🟡 Medium — Android ignored an operational kill-switch iOS obeys.** iOS's `boostedListingsEnabled` remote flag (off by default at launch) gates the boost-purchase UI; Flutter's `FeatureFlagsProvider` never read this field, so Android would keep selling boosts even while ops paused them for iOS. **Fixed**: flag now read and enforced with a matching "Coming Soon" state on `boost_listing_screen.dart`.
7. **🟡 Medium — a real navigation bug with no iOS equivalent to match.** Home screen's "Map" quick-action buttons (`context.go('/map')`) switched the bottom-nav's underlying branch index for lister/developer/host roles, but those roles' bottom-nav icon at that slot is labeled Add/Manage/Developer/Host — producing a highlighted-wrong-tab visual mismatch (Map content showing, "Add" tab highlighted). **Fixed**: added a standalone `/map-view` route pushed above the shell, so viewing the map from this shortcut no longer touches branch/tab state for any role.
8. **🟡 Medium — admin-application events generated no in-app notification on Android.** iOS's `AdminApplicationService` notifies all admins on a new submission and notifies the applicant on every status change; Flutter's equivalent repositories performed the same Firestore writes but never wrote to `in_app_notifications`. **Fixed**: added a small `InAppNotificationService` mirroring iOS's schema/behavior exactly and wired it into both submission and status-change paths.
9. **🟡 Medium — tablet nav rail thinner than iOS's `IPadSidebarView`.** iOS's iPad sidebar has always-visible Projects/Appointments entries and a role-gated Analytics entry that Flutter's tablet `NavigationRail` lacked (Support/Admin only, from Phase 4.9). **Fixed**: added all three, each pushing a plain route rather than switching branches (avoiding the same tab-highlight-desync class of bug as #7).
10. **🟢 Low — `host_reservations_screen.dart` had no error/retry state.** A failed load rendered identically to the empty state, masking real failures from hosts. **Fixed**: added a distinct error view with retry, matching the pattern used elsewhere in the app.
11. **🟢 Low — accessibility on the highest-traffic widget.** `_OverlayIconButton` (like/save/share on every property card, app-wide) had no accessible name at all — an icon with zero semantic label. **Fixed**: added proper `Semantics` labels ("Like property"/"Save property"/"Share property", state-aware).
12. **🟢 Low — `public_profile_screen.dart` queried a nonexistent field.** Its stats bar queried `reviews` for a `realtorId` field that has never existed on that collection (reviews only carry `propertyId`) — the query always silently returned empty, so lister public profiles never showed a rating. **Fixed**: now aggregates the same denormalized `averageRating`/`totalReviews` fields iOS reads off each property doc.

## 4. Deliberately NOT fixed — named, not hidden

- **Realtor `visibilityWeight`/`RealtorEntitlementService` feed-ranking boost** (promised in Realtor Pro/Elite copy) — no Flutter port exists. This is a genuine ranking-algorithm feature, not a wiring bug; porting it is new-feature-sized work.
- **`isFeatured`/`featuredUntil` vs. iOS's `isBoosted`/`boostEndDate`** — confirmed (again, this round) that iOS's feed sort actually keys on `isBoosted`, so a boost purchased on one platform has zero ranking effect on the other. Deferred since Phase 2 for the same reason: unifying it is a cross-cutting change to every feed query, not a local fix.
- **Developer project-count client-side pre-submission check** — the server-side Cloud Function backstop is correct and now properly triggered (see fix #4 above); a client-side upfront warning (instead of a post-hoc rejection) would be a UX nicety, not a correctness issue, and computing the exact "active project count" the way the trigger does needs more verification than this pass had budget for.
- **`MapSearchView` (place/address autocomplete on the map)** — confirmed genuinely missing (the one true missing-screen finding out of ~200 iOS views inventoried). Low-severity UX convenience, not a blocking gap.
- **Accessibility semantics breadth** — iOS uses `accessibilityLabel` 174 times across 44 files; Flutter's equivalent `Semantics`/`semanticLabel` usage, even after this round's property-card fix, remains far lower (forms like `add_property_screen.dart` have none). This is a real, broad gap; closing it fully means auditing every form and icon button app-wide, which is a substantial standalone effort, not a "discrepancy" fixable in this pass.
- **Tablet two-pane master-detail layouts** — Flutter has a real responsive system (breakpoints, adaptive grid columns, max-width constraints) but nothing matching iOS's `NavigationSplitView` (e.g. host dashboard stays single-pane on tablet). A genuine gap, but a layout-architecture change, not a bug fix.
- **`savedSearches` Firestore schema divergence** (flat vs. iOS's nested `filters{}`) — real but currently inert on both platforms (the reactivation Cloud Function is a no-op), so fixing it now would be correcting a schema nobody reads yet.
- **Deep linking** — confirmed non-functional on *both* platforms today, for different reasons (iOS's `DeepLinkManager` and its `NotificationCenter` posts are orphaned dead code; Android declares intent-filters with no consuming code). Not a Flutter regression — matches iOS's current (broken) behavior — but flagged since Android's manifest comment implies a working feature that doesn't exist on either side.

## 5–10. Discrepancy categories (per the requested breakdown)

- **Missing screens:** 1 confirmed (`MapSearchView` — §4).
- **Inconsistent behavior:** items #3, #5, #7 in §3 (all fixed).
- **UI discrepancies:** item #11 (fixed); accessibility breadth and tablet two-pane layouts (§4, not fixed — scoped as larger efforts).
- **UX discrepancies:** item #7 (fixed); coming-soon gating now correct (item #6).
- **Navigation discrepancies:** items #7, #9 (both fixed).
- **Business logic discrepancies:** items #2, #4, #6 (all fixed); realtor visibility-weight and boost cross-platform ranking (§4, deferred).
- **AI discrepancies:** none found this round — Pulse Finder, AI Search, and AI Listing Description were independently re-verified line-for-line against iOS and confirmed at parity (Flutter's typed error/offline handling is marginally ahead of iOS, not behind).
- **Backend discrepancies:** items #1, #5, #12 (all fixed); `savedSearches` schema (§4, deferred, currently inert).

## 11. Verification

`flutter analyze`: 0 errors, 725 pre-existing info/warning-level lints (no new errors from this round's changes).
`flutter test`: 572/572 passing, no regressions.

---

*Continues from [PARITY_AUDIT_REPORT.md](PARITY_AUDIT_REPORT.md), which covers Phases 1–5.*
