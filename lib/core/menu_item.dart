/// O categorie liberă din meniul localului (ex: „Cafele", „Limonade") —
/// denumirea o alege fiecare afacere, nu e fixă în aplicație.
class MenuCategory {
  final String id;
  final String name;

  const MenuCategory({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory MenuCategory.fromJson(Map<String, dynamic> json) =>
      MenuCategory(id: json['id'] as String, name: json['name'] as String);
}

/// Un produs din meniu. [photoFile] e doar numele fișierului salvat pe disc
/// (`MenuStore.savePhotoFile`) — clientul construiește singur URL-ul de
/// descărcare (`$serverOrigin/menu/photos/$photoFile`), la fel cum face deja
/// pentru poze de arhivă în alte activități.
class MenuItem {
  final String id;
  final String categoryId;
  final String name;
  final String? description;
  final String? photoFile;
  final bool available;

  const MenuItem({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description,
    this.photoFile,
    this.available = true,
  });

  MenuItem copyWith({
    String? name,
    String? categoryId,
    Object? description = _unset,
    Object? photoFile = _unset,
    bool? available,
  }) =>
      MenuItem(
        id: id,
        categoryId: categoryId ?? this.categoryId,
        name: name ?? this.name,
        description: description == _unset ? this.description : description as String?,
        photoFile: photoFile == _unset ? this.photoFile : photoFile as String?,
        available: available ?? this.available,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'name': name,
        'description': description,
        'photoFile': photoFile,
        'available': available,
      };

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'] as String,
        categoryId: json['categoryId'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        photoFile: json['photoFile'] as String?,
        available: json['available'] as bool? ?? true,
      );
}

// Sentinel intern pentru `copyWith`, ca să pot distinge „nu schimb câmpul" de
// „îl setez explicit la null" (ex: șterg poza unui produs).
const Object _unset = Object();
