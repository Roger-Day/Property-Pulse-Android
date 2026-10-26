import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/screens/profile/edit_profile_screen.dart';
import 'package:property_pulse/services/role_switch_service.dart';
import 'package:property_pulse/utils/role_label.dart';

/// People never see the third-party brand name as a role label, but the stored value stays exactly
/// as it is: existing user documents and the Firestore rules hold "Airbnb Host".
void main() {
  group('short-stay host role', () {
    test('the stored value is unchanged', () {
      expect(ProfileRoleLabels.airbnbHost, 'Airbnb Host');
      expect(RoleSwitchService.displayName('airbnbHost'), 'Airbnb Host');
    });

    test('every stored spelling is shown with the neutral label', () {
      for (final stored in ['Airbnb Host', 'airbnbHost', 'airbnb_host', 'airbnb host']) {
        expect(roleUiLabel(stored), 'Short-Stay Host', reason: stored);
      }
      expect(RoleSwitchService.uiLabel('airbnbHost'), 'Short-Stay Host');
      expect(ProfileRoleLabels.uiLabel(ProfileRoleLabels.airbnbHost), 'Short-Stay Host');
    });

    test('other roles are shown as stored', () {
      for (final stored in ['Property Seeker', 'Property Owner', 'Realtor', 'Developer', 'Admin']) {
        expect(roleUiLabel(stored), stored);
      }
    });
  });
}
