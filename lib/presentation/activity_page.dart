import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';
import '../domain/activity.dart';
import 'activity_viewmodel.dart';
import 'components/components.dart';
import 'labels.dart';
import 'shell_scope.dart';

/// Who did what, newest first, grouped by day. Narrow it to one person or one
/// kind of work. The page owns (and disposes) its [viewModel].
class ActivityPage extends StatefulWidget {
  final ActivityViewModel viewModel;
  const ActivityPage({super.key, required this.viewModel});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  ActivityViewModel get _vm => widget.viewModel;

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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: menuButton(context), title: Text(Bn.activityTitle)),
        body: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => Column(
            children: [
              const SizedBox(height: 4),
              ChoiceChipBar<int>(
                allLabel: Bn.activityEveryone,
                options: [for (final u in _vm.people) ChipOption(u.id, u.name)],
                selected: _vm.userId,
                onSelected: _vm.setPerson,
              ),
              ChoiceChipBar<ActivityGroup>(
                options: [for (final g in ActivityGroup.values) ChipOption(g, activityGroupLabel(g))],
                selected: _vm.group,
                onSelected: (g) => _vm.setGroup(g ?? ActivityGroup.all),
              ),
              Expanded(child: _list(context)),
            ],
          ),
        ),
      );

  Widget _list(BuildContext context) {
    if (_vm.loading && _vm.entries.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_vm.entries.isEmpty) {
      final filtered = _vm.userId != null || _vm.group != ActivityGroup.all;
      return RefreshIndicator(
        onRefresh: _vm.refresh,
        child: ListView(
          children: [
            SizedBox(
              height: 300,
              child: EmptyState(
                message: filtered ? Bn.activityEmptyFiltered : Bn.activityEmpty,
                icon: Icons.history,
              ),
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = <Widget>[];
    DateTime? previous;
    for (final e in _vm.entries) {
      if (previous == null || !_vm.sameDay(previous, e.at)) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(
            _vm.dayHeading(e.at),
            style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
          ),
        ));
      }
      previous = e.at;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ItemCard(
          title: activitySentence(e),
          subtitle: '${e.userName.isEmpty ? Bn.activityUnknownPerson : e.userName} • ${formatTime(e.at)}',
          leading: CircleAvatar(
            backgroundColor: scheme.secondaryContainer,
            foregroundColor: scheme.onSecondaryContainer,
            child: Icon(activityIcon(e.kind)),
          ),
        ),
      ));
    }
    if (_vm.hasMore) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: OutlinedButton(onPressed: _vm.showMore, child: Text(Bn.activityMore)),
      ));
    }
    return RefreshIndicator(
      onRefresh: _vm.refresh,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: rows),
    );
  }
}
