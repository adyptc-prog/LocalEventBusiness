import 'package:flutter/material.dart';

import '../l10n/tr.dart';

/// Butonul de limbă din bara de sus a fiecărui ecran — arată limba curentă
/// („RO"/„EN") și trece la cealaltă la apăsare. Schimbarea se aplică
/// imediat în toată aplicația (vezi `LanguageRebuilder` din `main.dart`),
/// fără să părăsești ecranul sau partida curentă.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final current = LanguageController.instance.language;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 36),
        ),
        icon: const Icon(Icons.translate, size: 18),
        label: Text(current.shortLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
        onPressed: LanguageController.instance.toggle,
      ),
    );
  }
}

/// Reconstruiește tot arborele de widget-uri când se schimbă limba —
/// fiecare `tr(...)` se reevaluează, dar starea ecranelor (rute deschise,
/// partida în curs, câmpuri completate) rămâne neatinsă, spre deosebire de
/// o recreare a aplicației.
class LanguageRebuilder extends StatefulWidget {
  final Widget child;
  const LanguageRebuilder({super.key, required this.child});

  @override
  State<LanguageRebuilder> createState() => _LanguageRebuilderState();
}

class _LanguageRebuilderState extends State<LanguageRebuilder> {
  @override
  void initState() {
    super.initState();
    LanguageController.instance.addListener(_onLanguageChanged);
  }

  @override
  void dispose() {
    LanguageController.instance.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    void markAll(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markAll);
    }

    (context as Element).visitChildren(markAll);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
