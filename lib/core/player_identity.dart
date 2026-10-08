import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Id-ul **public** al unui jucător, derivat unidirecțional din id-ul lui
/// secret de profil (`PlayerProfile.id`). Id-ul secret pleacă de pe telefon
/// doar spre server, la `create_room`/`join_room`; tot ce circulă înapoi
/// spre ceilalți clienți (snapshot-uri, chat, comenzi, rezultate) folosește
/// exclusiv id-ul public. Cine vede id-ul public al altcuiva nu poate să-l
/// folosească să-i ia locul în cameră, fiindcă serverul cere id-ul secret
/// din care s-ar deriva.
String publicPlayerId(String secretProfileId) {
  final digest = sha256.convert(utf8.encode('leb-player:$secretProfileId'));
  return 'p${digest.toString().substring(0, 20)}';
}

/// Un id secret de profil nou — 128 de biți din generatorul criptografic,
/// imposibil de ghicit prin rețea.
String generateSecretId() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Validează forma unui id secret primit de la un client — orice altceva
/// (lipsă, prea scurt, uriaș) e respins înainte să ajungă la vreo cameră.
bool isValidSecretProfileId(Object? value) =>
    value is String && value.length >= 8 && value.length <= 128;
