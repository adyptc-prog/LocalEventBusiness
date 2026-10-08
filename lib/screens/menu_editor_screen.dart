import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/menu_item.dart';
import '../core/menu_store.dart';
import '../network/event_server_runner.dart';

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
  void _sync() => EventServerRunner.syncMenu(MenuStore.instance.categories, MenuStore.instance.items);

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await _promptText(context, title: 'Categorie nouă', controller: controller);
    if (name == null || name.isEmpty) return;
    await MenuStore.instance.addCategory(name);
    _sync();
    setState(() {});
  }

  Future<void> _renameCategory(MenuCategory category) async {
    final controller = TextEditingController(text: category.name);
    final name = await _promptText(context, title: 'Redenumește categoria', controller: controller);
    if (name == null || name.isEmpty) return;
    await MenuStore.instance.renameCategory(category.id, name);
    _sync();
    setState(() {});
  }

  Future<void> _removeCategory(MenuCategory category) async {
    if (!await _confirm(context, 'Ștergi „${category.name}"?', 'Se șterg și produsele din ea.')) return;
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
      await MenuStore.instance.addItem(categoryId: categoryId, name: result.name, description: result.description, photoFile: photoFile);
    } else {
      await MenuStore.instance.updateItem(existing.copyWith(name: result.name, description: result.description, photoFile: photoFile));
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
    if (!await _confirm(context, 'Ștergi „${item.name}"?', 'Nu mai poate fi comandat.')) return;
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
        title: const Text('Produse meniu'),
        actions: [IconButton(icon: const Icon(Icons.add), tooltip: 'Categorie nouă', onPressed: _addCategory)],
      ),
      body: SafeArea(
        child: categories.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Adaugă prima categorie (ex: „Băuturi calde") cu butonul + de sus.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
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
                          child: Text(category.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        IconButton(icon: const Icon(Icons.edit, color: Colors.white54, size: 20), onPressed: () => _renameCategory(category)),
                        IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20), onPressed: () => _removeCategory(category)),
                      ],
                    ),
                    for (final item in items.where((i) => i.categoryId == category.id)) _buildItemTile(item),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Produs nou'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
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
        leading: const Icon(Icons.restaurant_menu, color: Colors.white54),
        title: Text(item.name, style: const TextStyle(color: Colors.white)),
        subtitle: item.description == null ? null : Text(item.description!, style: const TextStyle(color: Colors.white54)),
        onTap: () => _editItem(item),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: item.available, onChanged: (_) => _toggleAvailable(item)),
            IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20), onPressed: () => _removeItem(item)),
          ],
        ),
      ),
    );
  }
}

Future<String?> _promptText(BuildContext context, {required String title, required TextEditingController controller}) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Renunță')),
        FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Salvează')),
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
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Renunță')),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Șterge')),
      ],
    ),
  );
  return result ?? false;
}

class _ItemEditResult {
  final String name;
  final String? description;
  final Uint8List? newPhotoBytes;
  final bool removePhoto;

  const _ItemEditResult({required this.name, this.description, this.newPhotoBytes, this.removePhoto = false});
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
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Produs nou' : 'Editează produsul',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Nume produs', labelStyle: TextStyle(color: Colors.white70)),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Introdu un nume' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Descriere (opțional)', labelStyle: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Din galerie'),
                  onPressed: () => _pickPhoto(ImageSource.gallery),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Cameră'),
                  onPressed: () => _pickPhoto(ImageSource.camera),
                ),
              ],
            ),
            if (_newPhotoBytes != null || (widget.existing?.photoFile != null && !_removePhoto))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  label: const Text('Șterge poza', style: TextStyle(color: Colors.redAccent)),
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
                Navigator.of(context).pop(_ItemEditResult(
                  name: _nameController.text.trim(),
                  description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
                  newPhotoBytes: _newPhotoBytes,
                  removePhoto: _removePhoto,
                ));
              },
              child: const Text('Salvează'),
            ),
          ],
        ),
      ),
    );
  }
}
