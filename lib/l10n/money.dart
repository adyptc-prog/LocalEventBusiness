import 'tr.dart';

/// Prețurile se țin în **subunități** (bani, cenți…; 1 unitate = 100), ca
/// numere întregi — fără erorile de rotunjire ale numerelor cu virgulă.
///
/// Moneda nu e fixă: organizatorul o alege în editorul de meniu ([currency]
/// — „lei", „€", „$" sau nimic), ca aplicația să meargă în orice țară.
/// Separatorul zecimal urmează limba: „12,50" în română, „12.50" în engleză.
String formatPrice(int cents, String currency) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final separator = LanguageController.instance.language == AppLanguage.en ? '.' : ',';
  final value = '$sign${abs ~/ 100}$separator${(abs % 100).toString().padLeft(2, '0')}';
  final unit = currency.trim();
  return unit.isEmpty ? value : '$value $unit';
}

/// Citește un preț scris de organizator („12", „12,5", „12.50") și îl
/// întoarce în subunități; `null` dacă textul nu e un preț valid (gol,
/// negativ, absurd de mare sau cu mai mult de două zecimale).
int? parsePrice(String input) {
  final text = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,6}(\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  final units = int.parse(parts[0]);
  final cents = parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0;
  return units * 100 + cents;
}

/// Prețul în format editabil (fără monedă), pentru precompletarea câmpului.
String priceForEditing(int cents) {
  final rest = cents % 100;
  return rest == 0 ? '${cents ~/ 100}' : '${cents ~/ 100},${rest.toString().padLeft(2, '0')}';
}
