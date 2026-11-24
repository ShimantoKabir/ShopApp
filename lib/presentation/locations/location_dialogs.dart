import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/entities.dart';
import '../components/components.dart';
import '../labels.dart';

NewChoice<LocationType> _newType() => NewChoice<LocationType>(
      label: Bn.newLocationType,
      title: Bn.newLocationTypeTitle,
      hint: Bn.newLocationTypeHint,
      create: (name) {
        final t = LocationType.custom(name);
        return (value: t, label: t.label);
      },
    );

List<({LocationType value, String label})> _options(Iterable<StorageLocation> existing, [LocationType? also]) => [
      for (final t in LocationType.offered([...existing, if (also != null) StorageLocation(name: '', type: also, code: '')]))
        (value: t, label: t.label),
    ];

/// Asks for a new location's name and type. Shared by every screen that can add one.
/// [existing] are the locations there are now: the types they use are offered.
/// The person can also make up a new type.
Future<({String name, LocationType type})?> askNewLocation(BuildContext context, {Iterable<StorageLocation> existing = const []}) async {
  final result = await showTextWithChoiceDialog<LocationType>(
    context,
    title: Bn.newLocation,
    hint: Bn.locationNameHint,
    choiceLabel: Bn.locationType,
    initialChoice: LocationType.shelf,
    options: _options(existing),
    newChoice: _newType(),
  );
  return result == null ? null : (name: result.text, type: result.choice);
}

/// Asks for a new name (and type) for [location], starting from what it is now.
Future<({String name, LocationType type})?> askEditLocation(
  BuildContext context,
  StorageLocation location, {
  Iterable<StorageLocation> existing = const [],
}) async {
  final result = await showTextWithChoiceDialog<LocationType>(
    context,
    title: Bn.editLocation,
    hint: Bn.locationNameHint,
    initialText: location.name,
    choiceLabel: Bn.locationType,
    initialChoice: location.type,
    options: _options(existing, location.type),
    confirmLabel: Bn.save,
    newChoice: _newType(),
  );
  return result == null ? null : (name: result.text, type: result.choice);
}
