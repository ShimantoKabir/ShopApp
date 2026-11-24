import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';
import '../domain/entities.dart';
import '../domain/stock.dart';
import 'components/components.dart';
import 'labels.dart';
import 'location_dialogs.dart';
import 'screen_factory.dart';
import 'viewmodels.dart';
import 'widgets/placement_editor.dart';

/// Built for speed: number keyboards, Enter moves to the next field, and
/// "save & next" keeps kind/brand/category/location/unit so repeated entries
/// need only name + prices + stock (+ size/colour for variants like paint).
class ProductFormPage extends StatefulWidget {
  final ProductFormViewModel viewModel;
  final ScreenFactory screens;
  final Product? product;
  final int? initialLocationId;

  const ProductFormPage({
    super.key,
    required this.viewModel,
    required this.screens,
    this.product,
    this.initialLocationId,
  });

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  ProductFormViewModel get _vm => widget.viewModel;

  final _formKey = GlobalKey<FormState>();
  final _nameFocus = FocusNode();
  final _name = TextEditingController();
  final _purchase = TextEditingController();
  final _selling = TextEditingController();
  final _stock = TextEditingController();
  final _brand = TextEditingController();
  final _size = TextEditingController();
  final _model = TextEditingController();
  final _finish = TextEditingController();

  ProductKind _kind = ProductKind.standard;
  int? _categoryId;
  int? _locationId;
  String _unit = ProductKind.standard.defaultUnit;
  int? _editingId;

  /// Latest saved state of the product being edited (null for a new one).
  /// Where its stock is kept is read from here.
  Product? _current;
  bool _saving = false;

  bool get _isEdit => _editingId != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _editingId = p.id;
      _name.text = p.name;
      _purchase.text = formatNumber(p.purchasePrice);
      _selling.text = formatNumber(p.sellingPrice);
      _stock.text = formatNumber(p.stock);
      _kind = p.kind;
      _brand.text = p.brand;
      _size.text = p.size;
      _model.text = p.model;
      _finish.text = p.finish;
      _categoryId = p.categoryId;
      _current = p;
      _unit = p.unit;
    } else {
      _locationId = widget.initialLocationId;
    }
    for (final c in [_purchase, _selling]) {
      c.addListener(() => setState(() {}));
    }
    _vm.load();
  }

  @override
  void dispose() {
    _vm.dispose();
    _nameFocus.dispose();
    for (final c in [_name, _purchase, _selling, _stock, _brand, _size, _model, _finish]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onKindChanged(ProductKind? kind) {
    if (kind == null) return;
    setState(() {
      // Only swap the unit if staff haven't picked a custom one.
      if (_unit == _kind.defaultUnit) _unit = kind.defaultUnit;
      _kind = kind;
    });
  }

  void _showProblem(StockException e) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(stockProblemMessage(e.problem))));
  }

  Future<bool> _persist() async {
    if (!_formKey.currentState!.validate()) return false;
    final stock = parseNumber(_stock.text)!;
    final product = Product(
      id: _editingId,
      name: _name.text.trim(),
      kind: _kind,
      brand: _brand.text.trim(),
      size: _size.text.trim(),
      model: _model.text.trim(),
      finish: _finish.text.trim(),
      categoryId: _categoryId,
      purchasePrice: parseNumber(_purchase.text)!,
      sellingPrice: parseNumber(_selling.text)!,
      stock: stock,
      unit: _unit,
      // A new product with a chosen location keeps all its stock there. For an
      // existing product, where stock is kept is managed live in the section below.
      placements: (!_isEdit && _locationId != null && stock > 0)
          ? [StockPlacement(locationId: _locationId!, quantity: stock)]
          : const [],
    );
    // Same name + brand + size already saved? Ask before creating a likely duplicate.
    if (await _vm.isDuplicate(product)) {
      if (!mounted) return false;
      final proceed = await showConfirmDialog(
        context,
        message: Bn.duplicateWarning,
        confirmLabel: Bn.saveAnyway,
      );
      if (!proceed) return false;
    }
    if (!mounted) return false;
    setState(() => _saving = true);
    try {
      await _vm.save(product);
      return true;
    } on StockException catch (e) {
      if (mounted) _showProblem(e);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAndClose() async {
    if (await _persist() && mounted) Navigator.pop(context, true);
  }

  Future<void> _saveAndNext() async {
    if (!await _persist() || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(Bn.saved), duration: Duration(seconds: 1)));
    _editingId = null;
    _current = null;
    // Brand, kind, category, location and unit are kept: consecutive entries
    // usually share them. Everything item-specific is cleared.
    for (final c in [_name, _purchase, _selling, _stock, _size, _model, _finish]) {
      c.clear();
    }
    _formKey.currentState!.reset();
    _nameFocus.requestFocus();
    setState(() {});
  }

  Future<void> _scanLocation() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => widget.screens.scanner()));
    if (code == null) return;
    final location = await _vm.locationByCode(code);
    if (!mounted) return;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Bn.unknownQr)));
    } else {
      setState(() => _locationId = location.id);
    }
  }

  /// Makes a new location right here (no need to leave the form) and picks it.
  /// Returns it, or null if cancelled.
  Future<StorageLocation?> _newLocation() async {
    final result = await askNewLocation(context, existing: _vm.locations);
    if (result == null) return null;
    final made = await _vm.addLocation(result.name, result.type);
    if (mounted) setState(() {});
    return made;
  }

  Future<void> _addLocationAndPick() async {
    final made = await _newLocation();
    if (made != null && mounted) setState(() => _locationId = made.id);
  }

  Future<void> _addCategory() async {
    final name = await showTextPromptDialog(context, title: Bn.newCategory, hint: Bn.categoryNameHint);
    if (name == null) return;
    final c = await _vm.addCategory(name);
    setState(() => _categoryId = c.id);
  }

  // ---- Live placement editing (existing products) -------------------------

  String _locationName(int? id) =>
      _vm.locations.where((l) => l.id == id).map((l) => l.name).firstOrNull ?? '';

  /// Re-reads the product after a stock operation. [syncTotal] also refreshes
  /// the total-stock field (a recount changes the total).
  Future<void> _refresh({bool syncTotal = false}) async {
    final fresh = await _vm.reload(_editingId!);
    if (!mounted || fresh == null) return;
    setState(() {
      _current = fresh;
      if (syncTotal) _stock.text = formatNumber(fresh.stock);
    });
  }

  Future<void> _runStockOp(Future<void> Function() op, {bool syncTotal = false}) async {
    try {
      await op();
      await _refresh(syncTotal: syncTotal);
    } on StockException catch (e) {
      if (mounted) _showProblem(e);
    }
  }

  List<({int value, String label})> _locationOptions({int? except}) => [
        for (final l in _vm.locations)
          if (l.id != except) (value: l.id!, label: '${l.name} (${l.type.label})'),
      ];

  Future<void> _addPlacement({int? preselected}) async {
    final product = _current;
    if (product == null) return;
    if (_locationOptions().isEmpty) {
      // None yet: offer to make one now, then carry on placing the stock.
      final make = await showConfirmDialog(context, message: Bn.noLocationsYet, confirmLabel: Bn.newLocation);
      if (!make || !mounted) return;
      if (await _newLocation() == null || !mounted) return;
    }
    final options = _locationOptions();
    if (!mounted) return;
    final unplaced = product.unplacedQuantity;
    final result = await showChoiceNumberDialog<int>(
      context,
      title: Bn.addPlacement,
      choiceLabel: Bn.location,
      options: options,
      initialChoice: preselected ?? options.first.value,
      numberLabel: '${Bn.placementQuantity} (${Bn.unitName(product.unit)})',
      initialNumber: unplaced > 0 ? unplaced : null,
    );
    if (result == null) return;
    await _runStockOp(() => _vm.place(product.id!, result.choice, result.number));
  }

  Future<void> _scanPlacement() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => widget.screens.scanner()));
    if (code == null) return;
    final location = await _vm.locationByCode(code);
    if (!mounted) return;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Bn.unknownQr)));
      return;
    }
    await _addPlacement(preselected: location.id);
  }

  Future<void> _onPlacementAction(StockPlacement placement, PlacementAction action) async {
    final product = _current;
    if (product == null) return;
    final id = product.id!;
    switch (action) {
      case PlacementAction.recount:
        final value = await showNumberDialog(
          context,
          title: _locationName(placement.locationId),
          label: '${Bn.recountLabel} (${Bn.unitName(product.unit)})',
          initial: placement.quantity,
        );
        if (value != null) await _runStockOp(() => _vm.recount(id, placement.locationId, value), syncTotal: true);
      case PlacementAction.move:
        final options = _locationOptions(except: placement.locationId);
        if (options.isEmpty) {
          if (mounted) await showInfoDialog(context, message: Bn.noLocationsYet);
          return;
        }
        if (!mounted) return;
        final result = await showChoiceNumberDialog<int>(
          context,
          title: '${Bn.moveAction}: ${_locationName(placement.locationId)}',
          choiceLabel: Bn.moveTo,
          options: options,
          initialChoice: options.first.value,
          numberLabel: '${Bn.moveQuantity} (${Bn.unitName(product.unit)})',
          initialNumber: placement.quantity,
        );
        if (result != null) {
          await _runStockOp(() => _vm.move(id, placement.locationId, result.choice, result.number));
        }
      case PlacementAction.remove:
        if (await showConfirmDialog(context, message: Bn.confirmDelete, confirmLabel: Bn.removeFromLocation)) {
          await _runStockOp(() => _vm.place(id, placement.locationId, 0));
        }
    }
  }

  Future<void> _showHistory() async {
    final product = _current;
    if (product == null) return;
    final entries = await _vm.history(product.id!);
    if (!mounted) return;
    await showStockHistory(context, entries: entries, locationName: _locationName, unit: Bn.unitName(product.unit));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? Bn.editProduct : Bn.addProduct)),
      body: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) => Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: Bn.sectionInfo,
                icon: Icons.sell_outlined,
                children: [
                  ChoiceChipBar<ProductKind>(
                    options: [for (final k in ProductKind.values) ChipOption(k, k.label)],
                    selected: _kind,
                    scrollable: false,
                    onSelected: _onKindChanged,
                  ),
                  const SizedBox(height: 12),
                  RequiredTextFormField(
                    controller: _name,
                    label: Bn.name,
                    focusNode: _nameFocus,
                    autofocus: !_isEdit,
                  ),
                  ExpansionTile(
                    title: Text(Bn.details),
                    initiallyExpanded:
                        _brand.text.isNotEmpty || _size.text.isNotEmpty || _model.text.isNotEmpty || _finish.text.isNotEmpty,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 8, bottom: 4), // room for the floating label
                    shape: const Border(),
                    collapsedShape: const Border(),
                    children: [
                      OptionalTextFormField(controller: _brand, label: Bn.brand),
                      const SizedBox(height: 12),
                      FieldRow(children: [
                        OptionalTextFormField(controller: _size, label: Bn.size),
                        OptionalTextFormField(controller: _model, label: Bn.model),
                      ]),
                      const SizedBox(height: 12),
                      OptionalTextFormField(controller: _finish, label: Bn.finish),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: Bn.sectionPricing,
                icon: Icons.payments_outlined,
                children: [
                  FieldRow(children: [
                    NumberFormField(controller: _purchase, label: Bn.purchasePrice, prefix: Bn.taka),
                    NumberFormField(controller: _selling, label: Bn.sellingPrice, prefix: Bn.taka),
                  ]),
                  DeltaIndicator(
                    baseText: _purchase.text,
                    valueText: _selling.text,
                    gainLabel: '${Bn.profit} ${Bn.perUnit}',
                    lossLabel: '${Bn.loss} ${Bn.perUnit}',
                  ),
                  NumberFormField(
                    controller: _stock,
                    label: '${Bn.stock} ($_unit)',
                    action: TextInputAction.done,
                  ),
                  const SizedBox(height: 12),
                  ChoiceChipBar<String>(
                    options: [for (final u in Bn.units) ChipOption(u, Bn.unitName(u))],
                    selected: _unit,
                    scrollable: false,
                    onSelected: (u) => setState(() => _unit = u ?? _unit),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: _isEdit ? Bn.category : Bn.sectionPlace,
                icon: Icons.place_outlined,
                children: [
                  DropdownWithAction<int>(
                    label: Bn.category,
                    value: _categoryId,
                    items: [for (final c in _vm.categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                    onChanged: (v) => setState(() => _categoryId = v),
                    actionIcon: Icons.add,
                    actionTooltip: Bn.newCategory,
                    onAction: _addCategory,
                  ),
                  if (!_isEdit) ...[
                    const SizedBox(height: 12),
                    DropdownWithAction<int>(
                      label: Bn.location,
                      value: _locationId,
                      items: [
                        DropdownMenuItem(value: null, child: Text(Bn.noLocation)),
                        for (final s in _vm.locations)
                          DropdownMenuItem(value: s.id, child: Text('${s.name} (${s.type.label})')),
                      ],
                      onChanged: (v) => setState(() => _locationId = v),
                      actionIcon: Icons.qr_code_scanner,
                      actionTooltip: Bn.scanQr,
                      onAction: _scanLocation,
                      secondActionIcon: Icons.add,
                      secondActionTooltip: Bn.newLocation,
                      onSecondAction: _addLocationAndPick,
                    ),
                  ],
                ],
              ),
              if (_isEdit && _current != null) ...[
                const SizedBox(height: 12),
                SectionCard(
                  title: Bn.sectionLocations,
                  icon: Icons.shelves,
                  children: [
                    PlacementEditor(
                      product: _current!,
                      locationName: _locationName,
                      onAdd: _addPlacement,
                      onScan: _scanPlacement,
                      onHistory: _showHistory,
                      onAction: _onPlacementAction,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              _isEdit
                  ? ActionButtonRow(primaryLabel: Bn.save, onPrimary: _saveAndClose, busy: _saving)
                  : ActionButtonRow(
                      primaryLabel: Bn.saveAndNext,
                      onPrimary: _saveAndNext,
                      secondaryLabel: Bn.save,
                      onSecondary: _saveAndClose,
                      busy: _saving,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
