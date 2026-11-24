import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/entities.dart';
import '../components/components.dart';
import 'categories_viewmodel.dart';

class CategoriesPage extends StatefulWidget {
  final CategoriesViewModel viewModel;
  const CategoriesPage({super.key, required this.viewModel});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  CategoriesViewModel get _vm => widget.viewModel;

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
    final name = await showTextPromptDialog(context, title: Bn.newCategory, hint: Bn.categoryNameHint);
    if (name != null) await _vm.add(name);
  }

  Future<void> _edit(Category c) async {
    final name = await showTextPromptDialog(
      context,
      title: Bn.editCategory,
      hint: Bn.categoryNameHint,
      initialText: c.name,
      confirmLabel: Bn.save,
    );
    if (name != null) await _vm.update(c, name);
  }

  @override
  Widget build(BuildContext context) => ManageListScaffold<Category>(
        title: Bn.categories,
        addLabel: Bn.newCategory,
        listenable: _vm,
        items: () => _vm.items,
        titleOf: (c) => c.name,
        onAdd: _add,
        onEdit: _edit,
        onDelete: _vm.delete,
      );
}
