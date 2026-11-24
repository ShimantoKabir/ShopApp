import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/import/product_importer.dart';
import 'import_viewmodel.dart';

/// Import products from a CSV file. The page owns (and disposes) its [viewModel].
class ImportPage extends StatefulWidget {
  final ImportViewModel viewModel;
  const ImportPage({super.key, required this.viewModel});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  ImportViewModel get _vm => widget.viewModel;

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(Bn.importProducts)),
      body: ListenableBuilder(
        listenable: _vm,
        builder: (context, _) {
          final running = _vm.status == ImportStatus.running;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(Bn.importIntro),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(Bn.importWithPrices),
                subtitle: Text(Bn.importWithPricesHelp),
                value: _vm.withPricesAndStock,
                onChanged: running ? null : _vm.setWithPricesAndStock,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: running ? null : _vm.pickAndImport,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.upload_file),
                label: Text(Bn.pickFile),
              ),
              const SizedBox(height: 24),
              if (running) const Center(child: CircularProgressIndicator()),
              if (_vm.status == ImportStatus.cancelled) Text(Bn.importCancelled),
              if (_vm.result != null) _ResultCard(result: _vm.result!),
            ],
          );
        },
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ImportResult result;
  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final error = result.fatalError;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Bn.importDone, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (error != null)
              Text(error, style: const TextStyle(color: Colors.red))
            else ...[
              Text('${Bn.importAdded}: ${toBanglaDigits('${result.added}')}'),
              Text('${Bn.importSkipped}: ${toBanglaDigits('${result.skippedDuplicates}')}'),
              Text('${Bn.importFailed}: ${toBanglaDigits('${result.failures.length}')}'),
              for (final f in result.failures.take(10)) Text('• $f', style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
