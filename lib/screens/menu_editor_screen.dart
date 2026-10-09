import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/menu_item.dart';
import '../core/menu_store.dart';
import '../network/event_server_runner.dart';
import '../l10n/money.dart';
import '../widgets/language_button.dart';
import '../l10n/tr.dart';

/// Ecran de organizator: categoriile și produsele sunt libere — fiecare
/// local își denumește categoriile cum vrea, produsele au poză opțională
/// (din galerie sau cameră) și un comutator disponibil/indisponibil, util
/// când un produs se termină în timpul zilei. Sincronizează serverul deja
/// pornit după fiecare schimbare (`EventServerRunner.syncMenu`) — fără asta,
/// o editare de-aici n-ar ajunge niciodată la isolate-ul serverului, la fel
/// ca `ActivityConfigScreen`.
class MenuEditorScreen extends StatefulWidget {
  const MenuEditorScreen({super.key});

  @override
  State<MenuEditorScreen> createState() => _MenuEditorScreenState();
}

class _MenuEditorScreenState extends State<MenuEditorScreen> {
  void _sync() => EventServerRunner.syncMenu(
    MenuStore.instance.categories,
    MenuStore.instance.items,
    currency: MenuStore.instance.currency,
  );

  /// Moneda afișată lângă prețuri — aleasă de local („lei", „€", „$"…),
  /// fiindcă aplicația poate fi folosită în orice țară.
  Future<void> _editCurrency() async {
    final controller = TextEditingController(text: MenuStore.instance.currency);
    final currency = await _promptText(
      context,
      title: tr('menuEditor.currency'),
      controller: controller,
      hint: tr('menuEditor.currencyHint'),
    );
    if (currency == null) return;
    await MenuStore.instance.setCurrency(currency);
    _sync();
    setState(() {});
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await _promptText(context, title: tr('menuEditor.newCategory'), controller: controller);
    if (name == null || name.isEmpty) return;
    await MenuStore.instance.addCategory(name);
    _sync();
    setState(() {});
  }

  Future<void> _renameCategory(MenuCategory category) async {
    final controller = TextEditingController(text: category.name);
    final name = await _promptText(context, title: tr('menuEditor.renameCategory'), controller: controller);
    if (name == null || name.isEmpty) return;
    await MenuStore.instance.renameCategory(category.id, name);
    _sync();
    setState(() {});
  }

  Future<void> _removeCategory(MenuCategory category) async {
    if (!await _confirm(
      context,
      tr('menuEditor.deleteTitle', {'name': category.name}),
      tr('menuEditor.deleteCategoryBody'),
    )) {
      return;
    }
    await MenuStore.instance.removeCategory(category.id);
    _sync();
    setState(() {});
  }

  Future<void> _addItem(MenuCategory category) async {
    await _openItemEditor(categoryId: category.id);
  }

  Future<void> _editItem(MenuItem item) async {
    await _openItemEditor(categoryId: item.categoryId, existing: item);
  }

  Future<void> _openItemEditor({required String categoryId, MenuItem? existing}) async {
    final result = await showModalBottomSheet<_ItemEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black87,
      builder: (context) => _ItemEditorSheet(existing: existing),
    );
    if (result == null) return;

    String? photoFile = existing?.photoFile;
    if (result.removePhoto && photoFile != null) {
      await MenuStore.instance.deletePhotoFile(photoFile);
      photoFile = null;
    }
    if (result.newPhotoBytes != null) {
      if (photoFile != null) await MenuStore.instance.deletePhotoFile(photoFile);
      photoFile = await MenuStore.instance.savePhotoFile(result.newPhotoBytes!);
    }

    if (existing == null) {
      await MenuStore.instance.addItem(
        categoryId: categoryId,
        name: result.name,
        description: result.description,
        photoFile: photoFile,
        priceCents: result.priceCents,
      );
    } else {
      await MenuStore.instance.updateItem(
        existing.copyWith(
          name: result.name,
          description: result.description,
          photoFile: photoFile,
          priceCents: result.priceCents,
        ),
      );
    }
    _sync();
    setState(() {});
  }

  Future<void> _toggleAvailable(MenuItem item) async {
    await MenuStore.instance.updateItem(item.copyWith(available: !item.available));
    _sync();
    setState(() {});
  }

  Future<void> _removeItem(MenuItem item) async {
    if (!await _confirm(context, tr('menuEditor.deleteTitle', {'name': item.name}), tr('menuEditor.deleteItemBody'))) {
      return;
    }
    await MenuStore.instance.removeItem(item.id);
    _sync();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final categories = MenuStore.instance.categories;
    final items = MenuStore.instance.items;

    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(
        backgroundColor: Colors.black26,
        title: Text(tr('mainMenu.menuProducts')),
        actions: [
          IconButton(icon: const Icon(Icons.payments), tooltip: tr('menuEditor.currency'), onPressed: _editCurrency),
          IconButton(icon: const Icon(Icons.add), tooltip: tr('menuEditor.newCategory'), onPressed: _addCategory),
          const LanguageButton(),
        ],
      ),
      body: SafeArea(
        child: categories.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    tr('menuEditor.empty'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final category in categories) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            category.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white54, size: 20),
                          onPressed: () => _renameCategory(category),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                          onPressed: () => _removeCategory(category),
                        ),
                      ],
                    ),
                    for (final item in items.where((i) => i.categoryId == category.id)) _buildItemTile(item),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(tr('menuEditor.newItem')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      onPressed: () => _addItem(category),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildItemTile(MenuItem item) {
    return Card(
      color: Colors.white10,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: _ItemPhoto(photoFile: item.photoFile, size: 52),
        title: Text(item.name, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          [
            item.priceCents == null
                ? tr('menuEditor.noPrice')
                : formatPrice(item.priceCents!, MenuStore.instance.currency),
            if (item.description != null) item.description!,
          ].join(' · '),
          style: TextStyle(color: item.priceCents == null ? Colors.orangeAccent : Colors.white54),
        ),
        onTap: () => _editItem(item),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: item.available, onChanged: (_) => _toggleAvailable(item)),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
              onPressed: () => _removeItem(item),
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura pozei unui produs, citită direct de pe disc (editorul rulează pe
/// telefonul-server, unde sunt salvate pozele) — sau o iconiță, dacă
/// produsul n-are poză.
class _ItemPhoto extends StatelessWidget {
  final String? photoFile;
  final Uint8List? bytes;
  final double size;

  const _ItemPhoto({this.photoFile, this.bytes, required this.size});

  @override
  Widget build(BuildContext context) {
    final placeholder = SizedBox(
      width: size,
      height: size,
      child: const ColoredBox(
        color: Colors.white12,
        child: Icon(Icons.restaurant_menu, color: Colors.white38),
      ),
    );
    Widget? image;
    if (bytes != null) {
      image = Image.memory(bytes!, width: size, height: size, fit: BoxFit.cover);
    } else if (photoFile != null) {
      final file = MenuStore.instance.localPhotoFile(photoFile!);
      if (file != null) {
        image = Image.file(file, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);
      }
    }
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: image ?? placeholder);
  }
}

Future<String?> _promptText(
  BuildContext context, {
  required String title,
  required TextEditingController controller,
  String? hint,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('common.cancel'))),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(tr('common.save')),
        ),
      ],
    ),
  );
}

Future<bool> _confirm(BuildContext context, String title, String content) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('common.cancel'))),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(tr('common.delete'))),
      ],
    ),
  );
  return result ?? false;
}

class _ItemEditResult {
  final String name;
  final String? description;
  final int priceCents;
  final Uint8List? newPhotoBytes;
  final bool removePhoto;

  const _ItemEditResult({
    required this.name,
    this.description,
    required this.priceCents,
    this.newPhotoBytes,
    this.removePhoto = false,
  });
}

class _ItemEditorSheet extends StatefulWidget {
  final MenuItem? existing;

  const _ItemEditorSheet({this.existing});

  @override
  State<_ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<_ItemEditorSheet> {
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _descController = TextEditingController(text: widget.existing?.description ?? '');
  late final _priceController = TextEditingController(
    text: widget.existing?.priceCents == null ? '' : priceForEditing(widget.existing!.priceCents!),
  );
  final _formKey = GlobalKey<FormState>();
  Uint8List? _newPhotoBytes;
  bool _removePhoto = false;

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1280, imageQuality: 70);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _newPhotoBytes = bytes;
      _removePhoto = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null ? tr('menuEditor.newItem') : tr('menuEditor.editItem'),
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: tr('menuEditor.itemName'),
                  labelStyle: const TextStyle(color: Colors.white70),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? tr('rooms.enterAName') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: tr('menuEditor.price'),
                  suffixText: MenuStore.instance.currency.isEmpty ? null : MenuStore.instance.currency,
                  hintText: tr('menuEditor.priceHint'),
                  hintStyle: const TextStyle(color: Colors.white24),
                  labelStyle: const TextStyle(color: Colors.white70),
                ),
                validator: (v) => parsePrice(v ?? '') == null ? tr('menuEditor.priceInvalid') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: tr('menuEditor.description'),
                  labelStyle: const TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: _ItemPhoto(
                  photoFile: _removePhoto ? null : widget.existing?.photoFile,
                  bytes: _newPhotoBytes,
                  size: 140,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library),
                    label: Text(tr('menuEditor.fromGallery')),
                    onPressed: () => _pickPhoto(ImageSource.gallery),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: Text(tr('menuEditor.camera')),
                    onPressed: () => _pickPhoto(ImageSource.camera),
                  ),
                ],
              ),
              if (_newPhotoBytes != null || (widget.existing?.photoFile != null && !_removePhoto))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    label: Text(tr('menuEditor.deletePhoto'), style: const TextStyle(color: Colors.redAccent)),
                    onPressed: () => setState(() {
                      _newPhotoBytes = null;
                      _removePhoto = true;
                    }),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  if (!(_formKey.currentState?.validate() ?? false)) return;
                  Navigator.of(context).pop(
                    _ItemEditResult(
                      name: _nameController.text.trim(),
                      description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
                      priceCents: parsePrice(_priceController.text)!,
                      newPhotoBytes: _newPhotoBytes,
                      removePhoto: _removePhoto,
                    ),
                  );
                },
                child: Text(tr('common.save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
