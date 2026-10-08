import 'package:flutter/material.dart';

import '../../widgets/language_button.dart';

import 'rent_categories.dart';
import 'rent_snapshot.dart';
import '../../l10n/tr.dart';

/// „Tabelul pe o foaie” al unei partide de Rent: un rând per categorie
/// jucată, o coloană per jucător, cu scorul acelei categorii și totalul
/// cumulat — actualizat live pe măsură ce categoriile se încheie.
class RentScoresheetScreen extends StatelessWidget {
  final RentSnapshot snapshot;
  final String myId;

  const RentScoresheetScreen({super.key, required this.snapshot, required this.myId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3A1F1F),
      appBar: AppBar(backgroundColor: const Color(0xFF241010), title: Text(tr('game.scoresheet')), actions: const [LanguageButton()]),
      body: SafeArea(
        child: snapshot.history.isEmpty
            ? Center(
                child: Text(tr('rent.noCategories'), style: const TextStyle(color: Colors.white54)),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.black26),
                    columns: [
                      DataColumn(label: Text(tr('rent.categoryColumn'), style: const TextStyle(color: Colors.white70))),
                      for (final p in snapshot.players)
                        DataColumn(
                          label: Text(
                            p.id == myId ? tr('game.nameYou', {'name': p.name}) : p.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                    rows: [
                      for (final round in snapshot.history)
                        DataRow(cells: [
                          DataCell(Text(rentCategoryLabel(round.category),
                              style: const TextStyle(color: Colors.white70))),
                          for (final p in snapshot.players)
                            DataCell(_ScoreCell(
                              roundScore: round.roundScores[p.id],
                              total: round.totals[p.id],
                            )),
                        ]),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _ScoreCell extends StatelessWidget {
  final int? roundScore;
  final int? total;

  const _ScoreCell({required this.roundScore, required this.total});

  @override
  Widget build(BuildContext context) {
    if (roundScore == null) return const Text('—', style: TextStyle(color: Colors.white38));
    final color = roundScore! >= 0 ? Colors.lightGreenAccent : Colors.orangeAccent;
    return Text(
      '${roundScore! >= 0 ? '+' : ''}$roundScore ($total)',
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
    );
  }
}
