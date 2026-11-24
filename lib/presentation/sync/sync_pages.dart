import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/sync.dart';
import '../components/components.dart';
import '../labels.dart';
import 'sync_viewmodel.dart';

String _time(DateTime? t) => t == null ? Bn.syncNever : formatDateTime(t);

Color _stateColor(BuildContext context, SyncState state) {
  final scheme = Theme.of(context).colorScheme;
  return switch (state) {
    SyncState.idle => Colors.green.shade700,
    SyncState.syncing || SyncState.off => scheme.onSurfaceVariant,
    _ => scheme.error,
  };
}

/// Address and key fields shared by the two screens that connect.
class _Connection extends StatelessWidget {
  final TextEditingController url;
  final TextEditingController shopKey;
  const _Connection({required this.url, required this.shopKey});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextFormField(
            controller: url,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: Bn.syncUrlLabel),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: shopKey,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(labelText: Bn.syncKeyLabel),
          ),
        ],
      );
}

/// The owner's place to share the shop with other phones, and to see how the
/// sharing is going: the sync database. It is a piece of a page (the settings
/// page shows it inline). It owns (and disposes) its [viewModel].
class SyncPanel extends StatefulWidget {
  final SyncViewModel viewModel;

  /// Only the owner may make this phone's data the shared shop. Everyone else
  /// sees how the sharing is going and can sync on demand.
  final bool canShare;

  const SyncPanel({super.key, required this.viewModel, this.canShare = true});

  @override
  State<SyncPanel> createState() => _SyncPanelState();
}

/// The sync database on a page of its own.
class SyncSettingsPage extends StatelessWidget {
  final SyncViewModel viewModel;
  final bool canShare;
  const SyncSettingsPage({super.key, required this.viewModel, this.canShare = true});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(Bn.syncTitle)),
        body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: SyncPanel(viewModel: viewModel, canShare: canShare)),
      );
}

class _SyncPanelState extends State<SyncPanel> {
  late final _url = TextEditingController(text: _vm.defaultUrl);
  final _key = TextEditingController();

  SyncViewModel get _vm => widget.viewModel;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share() async {
    try {
      await _vm.shareThisPhone(_url.text, _key.text);
      _key.clear();
      _say(Bn.syncShared);
    } on SyncException catch (e) {
      _say(syncProblemMessage(e.problem));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
          listenable: _vm,
          builder: (context, _) {
            final theme = Theme.of(context);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_vm.enabled && !widget.canShare)
                  SectionCard(
                    title: Bn.navSync,
                    icon: Icons.cloud_off_outlined,
                    children: [Text(Bn.syncNotConnectedStaff, style: theme.textTheme.bodyMedium)],
                  )
                else if (!_vm.enabled)
                  SectionCard(
                    title: Bn.navSync,
                    icon: Icons.cloud_upload_outlined,
                    children: [
                      Text(Bn.syncIntro, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 16),
                      _Connection(url: _url, shopKey: _key),
                      const SizedBox(height: 12),
                      Text(
                        Bn.syncShareWarning,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 16),
                      ActionButtonRow(primaryLabel: Bn.syncShareButton, onPrimary: _share, busy: _vm.working),
                    ],
                  )
                else
                  SectionCard(
                    title: Bn.syncConnected,
                    icon: Icons.cloud_done_outlined,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.circle, size: 12, color: _stateColor(context, _vm.state)),
                          const SizedBox(width: 8),
                          Text(syncStateLabel(_vm.state), style: theme.textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Bn.syncLastTime(_time(_vm.lastSynced)),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      Text(Bn.syncNeedsInternet, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      Text(Bn.syncAutomatic, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 16),
                      ActionButtonRow(primaryLabel: Bn.syncNow, onPrimary: _vm.syncNow, busy: _vm.working),
                    ],
                  ),
              ],
            );
          },
        );
}

/// A new phone joins a shop that is already shared. The page owns (and
/// disposes) its [viewModel]. It closes by itself once the shop is downloaded.
class JoinShopPage extends StatefulWidget {
  final SyncViewModel viewModel;
  const JoinShopPage({super.key, required this.viewModel});

  @override
  State<JoinShopPage> createState() => _JoinShopPageState();
}

class _JoinShopPageState extends State<JoinShopPage> {
  late final _url = TextEditingController(text: _vm.defaultUrl);
  final _key = TextEditingController();

  SyncViewModel get _vm => widget.viewModel;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    try {
      await _vm.joinShop(_url.text, _key.text);
      if (mounted) Navigator.pop(context, true);
    } on SyncException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(syncProblemMessage(e.problem))));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(Bn.joinShopTitle)),
        body: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: Bn.joinShopTitle,
                icon: Icons.cloud_download_outlined,
                children: [
                  Text(Bn.joinShopIntro, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  _Connection(url: _url, shopKey: _key),
                  const SizedBox(height: 16),
                  ActionButtonRow(primaryLabel: Bn.joinShopButton, onPrimary: _join, busy: _vm.working),
                ],
              ),
            ],
          ),
        ),
      );
}
