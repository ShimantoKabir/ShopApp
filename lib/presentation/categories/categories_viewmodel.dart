import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../domain/entities.dart';
import '../../domain/repositories.dart';

class CategoriesViewModel extends ChangeNotifier {
  final CategoryRepository _repo;
  CategoriesViewModel(this._repo);

  List<Category> items = [];

  Future<void> load() async {
    items = await _repo.all();
    notifyListeners();
  }

  Future<void> add(String name) async {
    await _repo.add(name);
    await load();
  }

  Future<void> update(Category c, String name) async {
    await _repo.update(c.id!, name);
    await load();
  }

  Future<void> delete(Category c) async {
    await _repo.delete(c.id!);
    await load();
  }
}
