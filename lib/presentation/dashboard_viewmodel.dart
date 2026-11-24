import 'package:flutter/foundation.dart';

import '../domain/dashboard.dart';
import '../domain/repositories.dart';
import '../domain/sales.dart';
import '../domain/services.dart';

/// Everything the dashboard shows for the chosen [period].
class DashboardViewModel extends ChangeNotifier {
  final DashboardRepository _repository;
  final Clock _clock;

  DashboardViewModel(this._repository, this._clock);

  DashboardPeriod period = DashboardPeriod.today;
  bool loading = true;

  DaySummary summary = const DaySummary(saleCount: 0, revenue: 0, cost: 0);
  DaySummary previous = const DaySummary(saleCount: 0, revenue: 0, cost: 0);
  List<DailyTotal> trend = const [];
  List<ProductSales> topProducts = const [];
  Receivables receivables = Receivables.none;
  InventoryHealth inventory = InventoryHealth.empty;

  DateTime get _today => DateTime(_clock.now().year, _clock.now().month, _clock.now().day);

  /// First moment of the period (it ends at the end of today).
  DateTime get periodStart => DateTime(_today.year, _today.month, _today.day - (period.days - 1));

  double get averageBill => summary.saleCount == 0 ? 0 : summary.revenue / summary.saleCount;

  /// How sales compare with the period just before, as a fraction (0.25 = 25%
  /// more). Null when there is nothing to compare with.
  double? get salesChange => previous.revenue <= 0 ? null : (summary.revenue - previous.revenue) / previous.revenue;

  /// The bars: always at least a week, so "today" still shows a trend.
  int get trendDays => period.days < 7 ? 7 : period.days;

  Future<void> load() async {
    loading = true;
    notifyListeners();

    final end = DateTime(_today.year, _today.month, _today.day + 1);
    final start = periodStart;
    final before = DateTime(start.year, start.month, start.day - period.days);
    final trendStart = DateTime(_today.year, _today.month, _today.day - (trendDays - 1));

    final results = await Future.wait<Object>([
      _repository.summary(start, end),
      _repository.summary(before, start),
      _repository.dailyTotals(trendStart, trendDays),
      _repository.topProducts(start, end),
      _repository.receivables(),
      _repository.inventoryHealth(),
    ]);
    summary = results[0] as DaySummary;
    previous = results[1] as DaySummary;
    trend = results[2] as List<DailyTotal>;
    topProducts = results[3] as List<ProductSales>;
    receivables = results[4] as Receivables;
    inventory = results[5] as InventoryHealth;
    loading = false;
    notifyListeners();
  }

  Future<void> choose(DashboardPeriod chosen) {
    if (chosen == period) return Future.value();
    period = chosen;
    return load();
  }
}
