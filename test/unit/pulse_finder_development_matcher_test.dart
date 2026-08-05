// Unit tests for PulseFinderDevelopmentMatcher — deterministic matching
// against off-plan/in-progress developments (ProjectModel), the adjunct
// fixing the bug where a real, existing development (e.g. "Palm Heights
// Residence") was reported as "no matches" purely because developments
// live in a separate Firestore collection the property search never
// touches.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/logic/pulse_finder_development_matcher.dart';
import 'package:property_pulse/models/project_model.dart';
import 'package:property_pulse/models/project_unit_type_model.dart';
import 'package:property_pulse/repositories/property_repository.dart';

ProjectModel _make({
  String id = 'proj1',
  String projectName = 'Palm Heights Residence',
  String location = 'Kingston, Jamaica',
  String description = 'A new gated community.',
  double? startingPrice,
  List<String> amenities = const [],
  List<ProjectUnitTypeModel> unitTypes = const [],
}) =>
    ProjectModel(
      id: id,
      firestoreDocumentId: id,
      projectName: projectName,
      location: location,
      description: description,
      developerId: 'dev1',
      ownerId: 'owner1',
      teamMembers: const [],
      developerName: 'Test Developer',
      heroImages: const [],
      statusRaw: 'active',
      isActive: true,
      moderationStatusRaw: 'approved',
      startingPrice: startingPrice,
      amenities: amenities,
      unitTypes: unitTypes,
    );

ProjectUnitTypeModel _unit({int bedrooms = 2, int bathrooms = 2, double price = 20000000}) =>
    ProjectUnitTypeModel(
      id: 'unit1',
      name: null,
      currencyCode: 'JMD',
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      price: price,
      imageURLs: const [],
      floorPlanImageURLs: const [],
    );

void main() {
  group('PulseFinderDevelopmentMatcher.match', () {
    test('finds a development by name from a free-text query, with no other constraints', () {
      final developments = [
        _make(id: 'p1', projectName: 'Palm Heights Residence'),
        _make(id: 'p2', projectName: 'Ocean View Towers'),
      ];
      final matches = PulseFinderDevelopmentMatcher.match(
        developments,
        const PropertyFilter(query: 'palm heights residence'),
      );
      expect(matches.map((p) => p.id), ['p1']);
    });

    test('an unrelated free-text query with no structured constraint matches nothing', () {
      final developments = [_make(id: 'p1', projectName: 'Palm Heights Residence')];
      final matches = PulseFinderDevelopmentMatcher.match(
        developments,
        const PropertyFilter(query: 'something completely unrelated'),
      );
      expect(matches, isEmpty);
    });

    test('an empty filter (no query, no constraints) matches every development', () {
      final developments = [_make(id: 'p1'), _make(id: 'p2', projectName: 'Ocean View Towers')];
      final matches = PulseFinderDevelopmentMatcher.match(developments, const PropertyFilter());
      expect(matches.length, 2);
    });

    test('filters out developments outside the requested location', () {
      final developments = [
        _make(id: 'kingston', location: 'Kingston, Jamaica'),
        _make(id: 'montego-bay', location: 'Montego Bay, Jamaica'),
      ];
      final matches = PulseFinderDevelopmentMatcher.match(
        developments,
        const PropertyFilter(city: 'Kingston'),
      );
      expect(matches.map((p) => p.id), ['kingston']);
    });

    test('filters out developments over budget, but never excludes unpriced ones', () {
      final developments = [
        _make(id: 'affordable', startingPrice: 15000000),
        _make(id: 'expensive', startingPrice: 50000000),
        _make(id: 'unpriced', startingPrice: null),
      ];
      final matches = PulseFinderDevelopmentMatcher.match(
        developments,
        const PropertyFilter(maxPrice: 25000000),
      );
      expect(Set.from(matches.map((p) => p.id)), {'affordable', 'unpriced'});
    });

    test('filters by bedroom count using unit types, never excluding developments with no unit data', () {
      final developments = [
        _make(id: 'has-3bed', unitTypes: [_unit(bedrooms: 3)]),
        _make(id: 'only-1bed', unitTypes: [_unit(bedrooms: 1)]),
        _make(id: 'no-unit-data', unitTypes: const []),
      ];
      final matches = PulseFinderDevelopmentMatcher.match(
        developments,
        const PropertyFilter(minBedrooms: 3),
      );
      expect(Set.from(matches.map((p) => p.id)), {'has-3bed', 'no-unit-data'});
    });

    test('filters by amenities as a subset match', () {
      final developments = [
        _make(id: 'has-pool-gym', amenities: const ['pool', 'gym']),
        _make(id: 'has-only-gym', amenities: const ['gym']),
      ];
      final matches = PulseFinderDevelopmentMatcher.match(
        developments,
        const PropertyFilter(amenities: ['pool']),
      );
      expect(matches.map((p) => p.id), ['has-pool-gym']);
    });

    test('caps matches at maxMatches', () {
      final developments = List.generate(
        10,
        (i) => _make(id: 'p$i', location: 'Kingston, Jamaica'),
      );
      final matches = PulseFinderDevelopmentMatcher.match(
        developments,
        const PropertyFilter(city: 'Kingston'),
      );
      expect(matches.length, PulseFinderDevelopmentMatcher.maxMatches);
    });

    test('ranks a name match above a mere description match', () {
      final developments = [
        _make(id: 'mentions-in-description', projectName: 'Ocean View Towers', description: 'Close to palm trees.'),
        _make(id: 'named-match', projectName: 'Palm Heights Residence'),
      ];
      final matches = PulseFinderDevelopmentMatcher.match(
        developments,
        const PropertyFilter(query: 'palm'),
      );
      expect(matches.first.id, 'named-match');
    });
  });
}
