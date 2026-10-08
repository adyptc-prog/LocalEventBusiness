import 'package:flutter/material.dart';

import 'whist_snapshot.dart';

/// „Tabelul pe o foaie” al unei partide de Whist: un rând per rundă, o
/// coloană per jucător, cu licitația/levatele luate și scorul (plus totalul
/// cumulat) — actualizat live pe măsură ce rundele se încheie.
class WhistScoresheetScreen extends StatelessWidget {
  final WhistSnapshot snapshot;
  final String myId;

  const WhistScoresheetScreen({super.key, required this.snapshot, required this.myId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF213A2B),
      appBar: AppBar(backgroundColor: const Color(0xFF152719), title: const Text('Tabel')),
      body: SafeArea(
        child: snapshot.history.isEmpty
            ? const Center(
                child: Text('Nicio rundă încheiată încă.', style: TextStyle(color: Colors.white54)),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.black26),
                    columns: [
                      const DataColumn(label: Text('Rundă', style: TextStyle(color: Colors.white70))),
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
                          DataCell(Text('${round.handSize}', style: const TextStyle(color: Colors.white70))),
                          for (final p in snapshot.players)
                            DataCell(_ScoreCell(
                              bid: round.bids[p.id],
                              taken: round.taken[p.id],
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
  final int? bid;
  final int? taken;
  final int? roundScore;
  final int? total;

  const _ScoreCell({required this.bid, required this.taken, required this.roundScore, required this.total});

  @override
  Widget build(BuildContext context) {
    if (bid == null) return const Text('—', style: TextStyle(color: Colors.white38));
    final scoreColor = (roundScore ?? 0) >= 0 ? Colors.lightGreenAccent : Colors.orangeAccent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$bid/$taken', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(
          '${(roundScore ?? 0) >= 0 ? '+' : ''}$roundScore ($total)',
          style: TextStyle(color: scoreColor, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
