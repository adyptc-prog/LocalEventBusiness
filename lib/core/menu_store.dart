import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'menu_item.dart';

const String _prefsKey = 'menu_store_v1';

/// Banca de categorii/produse a localului — persistată cu
/// `shared_preferences` pe telefonul-server, șablon identic celorlalte bănci
/// editabile ale organizatorului (ex: `VoteCategoryStore`, azi șters).
/// Trebuie inițializat (`await init()`) atât în isolate-ul UI (pentru
/// `MenuEditorScreen`), cât și în isolate-ul serverului (`MenuEngine` citește
/// meniul curent din același isolate al serverului) — o editare trebuie
/// trimisă explicit serverului deja pornit prin canalul de comenzi
/// (`EventServerRunner.syncMenu`), la fel ca restul bărcilor editabile.
///
/// Pozele produselor NU sunt ținute în `shared_preferences` (prea mari) —
/// sunt fișiere reale pe disc, într-un folder dedicat din directorul de
/// documente al aplicației. Fiindcă editorul de meniu rulează pe același
/// dispozitiv ca serverul, scrierea fișierului se face direct, fără upload
/// prin rețea; serverul le citește de pe disc la cerere
/// (`GET /menu/photos/<fișier>`, vezi `EventServerService`).
class MenuStore {
  MenuStore._();
  static final MenuStore instance = MenuStore._();

  List<MenuCategory> _categories = [];
  List<MenuItem> _items = [];
  SharedPreferences? _prefs;
  Directory? _photosDir;

  List<MenuCategory> get categories => List.unmodifiable(_categories);
  List<MenuItem> get items => List.unmodifiable(_items);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _categories = (decoded['categories'] as List)
            .map((c) => MenuCategory.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList();
        _items = (decoded['items'] as List)
            .map((i) => MenuItem.fromJson(Map<String, dynamic>.from(i as Map)))
            .toList();
      } catch (_) {
        _categories = [];
        _items = [];
      }
    }
    final docs = await getApplicationDocumentsDirectory();
    _photosDir = Directory('${docs.path}/menu_photos');
    if (!await _photosDir!.exists()) {
      await _photosDir!.create(recursive: true);
    }
  }

  Future<void> addCategory(String name) async {
    final id = _newId();
    _categories.add(MenuCategory(id: id, name: name));
    await _save();
  }

  Future<void> renameCategory(String id, String name) async {
    final index = _categories.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _categories[index] = MenuCategory(id: id, name: name);
    await _save();
  }

  /// Șterge categoria și toate produsele ei (inclusiv pozele de pe disc).
  Future<void> removeCategory(String id) async {
    _categories.removeWhere((c) => c.id == id);
    final orphaned = _items.where((i) => i.categoryId == id).toList();
    for (final item in orphaned) {
      if (item.photoFile != null) await deletePhotoFile(item.photoFile!);
    }
    _items.removeWhere((i) => i.categoryId == id);
    await _save();
  }

  Future<void> addItem({
    required String categoryId,
    required String name,
    String? description,
    String? photoFile,
  }) async {
    _items.add(MenuItem(
      id: _newId(),
      categoryId: categoryId,
      name: name,
      description: description,
      photoFile: photoFile,
    ));
    await _save();
  }

  Future<void> updateItem(MenuItem updated) async {
    final index = _items.indexWhere((i) => i.id == updated.id);
    if (index == -1) return;
    _items[index] = updated;
    await _save();
  }

  Future<void> removeItem(String id) async {
    final matches = _items.where((i) => i.id == id);
    if (matches.isNotEmpty && matches.first.photoFile != null) {
      await deletePhotoFile(matches.first.photoFile!);
    }
    _items.removeWhere((i) => i.id == id);
    await _save();
  }

  /// Salvează bytes-ii unei poze ca fișier nou și întoarce numele lui —
  /// apelantul (`MenuEditorScreen`) îl pune pe `MenuItem.photoFile`.
  Future<String> savePhotoFile(Uint8List bytes) async {
    final dir = _photosDir;
    if (dir == null) throw StateError('MenuStore nu a fost inițializat.');
    final fileName = '${_newId()}.jpg';
    await File('${dir.path}/$fileName').writeAsBytes(bytes);
    return fileName;
  }

  Future<void> deletePhotoFile(String fileName) async {
    final dir = _photosDir;
    if (dir == null) return;
    final file = File('${dir.path}/$fileName');
    if (await file.exists()) await file.delete();
  }

  /// Fișierul de pe disc al unei poze de produs — folosit de server ca să-l
  /// servească la cerere (`GET /menu/photos/<fișier>`). Necesită `init()`
  /// apelat deja (adevărat în ambele isolate-uri, vezi documentația clasei).
  ///
  /// [fileName] vine direct dintr-un segment de URL controlat de client —
  /// respinge orice valoare cu `/`, `\` sau `..`, ca un client rău-
  /// intenționat să nu poată evada din `menu_photos/` și citi alte fișiere
  /// din directorul de documente al aplicației (path traversal).
  Future<File?> photoFileHandle(String fileName) async {
    if (fileName.contains('/') || fileName.contains('\\') || fileName.contains('..')) return null;
    final dir = _photosDir;
    if (dir == null) return null;
    final file = File('${dir.path}/$fileName');
    return await file.exists() ? file : null;
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(9999)}';

  Future<void> _save() async {
    await _prefs?.setString(_prefsKey, jsonEncode({
      'categories': _categories.map((c) => c.toJson()).toList(),
      'items': _items.map((i) => i.toJson()).toList(),
    }));
  }

  /// Aplică o listă primită de la isolate-ul UI, prin canalul de comenzi —
  /// fără asta, o editare din `MenuEditorScreen` nu ajunge niciodată la
  /// isolate-ul serverului deja pornit (fiecare are propria copie în
  /// memorie, la fel ca `EventConfigStore`). Nu rescrie pe disc — UI-ul deja
  /// a persistat-o.
  void applyRemote(List<MenuCategory> categories, List<MenuItem> items) {
    _categories = categories;
    _items = items;
  }
}
