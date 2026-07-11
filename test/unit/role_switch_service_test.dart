// Unit tests for RoleSwitchService.
// iOS parity: RoleSwitchService.swift — 7-day cooldown, display names, cooldown math.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/services/role_switch_service.dart';

void main() {
  group('RoleSwitchService', () {
    group('cooldown constants', () {
      test('cooldownDays is 7 — matches iOS', () {
        expect(RoleSwitchService.cooldownDays, 7);
      });
    });

    group('daysRemainingInCooldown', () {
      test('null lastSwitch means no cooldown (0 days remaining)', () {
        expect(RoleSwitchService.daysRemainingInCooldown(null), 0);
      });

      test('switch today leaves 7 days remaining', () {
        final now = DateTime.now();
        expect(RoleSwitchService.daysRemainingInCooldown(now), 7);
      });

      test('switch 3 days ago leaves 4 days remaining', () {
        final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
        expect(RoleSwitchService.daysRemainingInCooldown(threeDaysAgo), 4);
      });

      test('switch exactly 7 days ago means 0 days remaining (can switch)', () {
        final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
        expect(RoleSwitchService.daysRemainingInCooldown(sevenDaysAgo), 0);
      });

      test('switch 10 days ago clamped to 0 (not negative)', () {
        final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
        expect(RoleSwitchService.daysRemainingInCooldown(tenDaysAgo), 0);
      });

      test('result is never negative', () {
        final wayBack = DateTime.now().subtract(const Duration(days: 100));
        expect(RoleSwitchService.daysRemainingInCooldown(wayBack), 0);
      });
    });

    group('displayName', () {
      test('seeker → Property Seeker', () {
        expect(RoleSwitchService.displayName('seeker'), 'Property Seeker');
      });

      test('owner → Property Owner', () {
        expect(RoleSwitchService.displayName('owner'), 'Property Owner');
      });

      test('realtor → Realtor', () {
        expect(RoleSwitchService.displayName('realtor'), 'Realtor');
      });

      test('developer → Developer', () {
        expect(RoleSwitchService.displayName('developer'), 'Developer');
      });

      test('airbnbHost → Airbnb Host', () {
        expect(RoleSwitchService.displayName('airbnbHost'), 'Airbnb Host');
      });

      test('airbnb_host (snake_case) → Airbnb Host', () {
        expect(RoleSwitchService.displayName('airbnb_host'), 'Airbnb Host');
      });

      test('admin → Admin', () {
        expect(RoleSwitchService.displayName('admin'), 'Admin');
      });

      test('unknown role falls back to original string', () {
        expect(RoleSwitchService.displayName('superuser'), 'superuser');
      });
    });

    group('selectableRoles', () {
      test('contains exactly 5 selectable roles', () {
        expect(RoleSwitchService.selectableRoles.length, 5);
      });

      test('seeker is selectable', () {
        expect(RoleSwitchService.selectableRoles, contains('seeker'));
      });

      test('admin is NOT selectable (granted separately)', () {
        expect(RoleSwitchService.selectableRoles, isNot(contains('admin')));
      });
    });

    group('cooldownExpiryString', () {
      test('null lastSwitch returns empty string', () {
        expect(RoleSwitchService.cooldownExpiryString(null), '');
      });

      test('returns non-empty string when cooldown is active', () {
        final lastSwitch = DateTime.now();
        final result = RoleSwitchService.cooldownExpiryString(lastSwitch);
        expect(result, isNotEmpty);
      });

      test('expiry date is 7 days after lastSwitch', () {
        // Jan 1 2025 → expiry Jan 8 2025 → "Jan 8"
        final lastSwitch = DateTime(2025, 1, 1);
        final result = RoleSwitchService.cooldownExpiryString(lastSwitch);
        expect(result, contains('8'));
        expect(result.toLowerCase(), contains('jan'));
      });
    });
  });
}
