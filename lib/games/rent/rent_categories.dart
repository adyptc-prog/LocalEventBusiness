import '../../l10n/tr.dart';

/// Cele 6 categorii ale jocului Rent — folosite atât de motor (validare),
/// cât și de UI (etichete), ca să nu se dubleze lista în două locuri.
const List<String> kRentCategories = [
  'popa_rosu',
  'dame',
  'romburi',
  'levate',
  'totale',
  'imperiale',
  'rent',
];

/// Numele afișat al categoriei [category], în limba curentă.
String rentCategoryLabel(String category) =>
    kRentCategories.contains(category) ? tr('rent.category.$category') : category;
