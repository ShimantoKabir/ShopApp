import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/entities.dart';
import '../components/components.dart';
import '../labels.dart';
import 'location_dialogs.dart';
import '../screen_factory.dart';
import 'locations_viewmodel.dart';

class LocationsPage extends StatefulWidget {
  final LocationsViewModel viewModel;
  final ScreenFactory screens;
  const LocationsPage({super.key, required this.viewModel, required this.screens});

  @override
  State<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends State<LocationsPage> {
  LocationsViewModel get _vm => widget.viewModel;

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

  Future<void> _add() async {
    final result = await askNewLocation(context, existing: _vm.items);
    if (result != null) await _vm.add(result.name, result.type);
  }

  /// Scan a shelf's QR code to see what is on it.
  Future<void> _scan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => widget.screens.scanner()));
    if (code == null || !mounted) return;
    final location = _vm.items.where((s) => s.code == code).firstOrNull;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Bn.unknownQr)));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => widget.screens.productList(location: location)));
  }

  /// Rename or delete the types the shop made up; the list here follows.
  Future<void> _manageTypes() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => widget.screens.locationTypes()));
    if (mounted) await _vm.load();
  }

  Future<void> _edit(StorageLocation s) async {
    final result = await askEditLocation(context, s, existing: _vm.items);
    if (result != null) await _vm.update(s, result.name, result.type);
  }

  Future<void> _delete(StorageLocation s) async {
    // The screen already blocks locations known to hold stock; this covers the
    // rare case where stock arrived since the list was loaded.
    final stillStocked = await _vm.delete(s);
    if (stillStocked > 0 && mounted) {
      await showInfoDialog(context, message: Bn.locationNotEmpty(stillStocked));
    }
  }

  @override
  Widget build(BuildContext context) => ManageListScaffold<StorageLocation>(
        title: Bn.locations,
        addLabel: Bn.newLocation,
        listenable: _vm,
        items: () => _vm.items,
        titleOf: (s) => '${s.name} (${s.type.label})',
        subtitleOf: (s) => _vm.stockedProducts(s) > 0 ? Bn.productsCount(_vm.stockedProducts(s)) : Bn.locationEmpty,
        deleteBlockedMessage: (s) =>
            _vm.stockedProducts(s) > 0 ? Bn.locationNotEmpty(_vm.stockedProducts(s)) : null,
        leadingOf: (s) => Icon(s.type.icon),
        onTap: (s) => Navigator.push(context, MaterialPageRoute(builder: (_) => widget.screens.locationQr(s))),
        actions: [
          IconButton(onPressed: _manageTypes, icon: const Icon(Icons.label_outline), tooltip: Bn.locationTypesTitle),
          IconButton(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), tooltip: Bn.scanQr),
        ],
        onAdd: _add,
        onEdit: _edit,
        onDelete: _delete,
      );
}

class LocationQrPage extends StatelessWidget {
  final StorageLocation location;
  final ScreenFactory screens;
  const LocationQrPage({super.key, required this.location, required this.screens});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(location.name)),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrCard(title: location.name, data: location.code, caption: Bn.locationQrHelp),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => screens.productList(location: location)),
                  ),
                  icon: const Icon(Icons.list),
                  label: Text(Bn.productsOnLocation),
                ),
              ],
            ),
          ),
        ),
      );
}
