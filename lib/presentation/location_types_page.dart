import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';
import '../domain/entities.dart';
import 'components/components.dart';
import 'viewmodels.dart';

/// The location types the shop made up: rename one (every location that has it
/// follows) or delete it (they become shelves). The built-in four are not here.
class LocationTypesPage extends StatefulWidget {
  final LocationTypesViewModel viewModel;
  const LocationTypesPage({super.key, required this.viewModel});

  @override
  State<LocationTypesPage> createState() => _LocationTypesPageState();
}

class _LocationTypesPageState extends State<LocationTypesPage> {
  LocationTypesViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.load();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _rename(({LocationType type, int count}) item) async {
    final name = await showTextPromptDialog(
      context,
      title: Bn.editLocationType,
      hint: Bn.newLocationTypeHint,
      initialText: item.type.name,
      confirmLabel: Bn.save,
    );
    if (name != null) await _vm.rename(item.type, name);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(Bn.locationTypesTitle)),
        body: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) {
            if (_vm.items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(Bn.locationTypesEmpty, textAlign: TextAlign.center),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: _vm.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final item = _vm.items[i];
                return DeletableListTile(
                  leading: const Icon(Icons.label_outline),
                  title: item.type.name,
                  subtitle: Bn.locationTypeUsage(item.count),
                  onEdit: () => _rename(item),
                  onDelete: () => _vm.delete(item.type),
                );
              },
            );
          },
        ),
      );
}
