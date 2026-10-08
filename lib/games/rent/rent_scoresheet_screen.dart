import 'package:flutter/material.dart';

import 'rent_categories.dart';
import 'rent_snapshot.dart';

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
      appBar: AppBar(backgroundColor: const Color(0xFF241010), title: const Text('Tabel')),
      body: SafeArea(
        child: snapshot.history.isEmpty
            ? const Center(
                child: Text('Nicio categorie încheiată încă.', style: TextStyle(color: Colors.white54)),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.black26),
                    columns: [
                      const DataColumn(label: Text('Categorie', style: TextStyle(color: Colors.white70))),
                      for (final p in snapshot.players)
                        DataColumn(
                          label: Text(
                            p.id == myId ? '${p.name} (tu)' : p.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                    rows: [
                      for (final round in snapshot.history)
                        DataRow(cells: [
                          DataCell(Text(kRentCategoryLabels[round.category] ?? round.category,
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
