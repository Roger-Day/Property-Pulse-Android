/// Text to show people for a stored role.
///
/// The short-stay host role is stored as "Airbnb Host": existing user documents and the Firestore
/// rules hold that exact value, so it cannot change. The screen shows a neutral label instead.
String roleUiLabel(String stored) {
  final key = stored.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
  return key == 'airbnbhost' ? 'Short-Stay Host' : stored;
}
