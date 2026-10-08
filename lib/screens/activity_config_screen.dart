import 'package:flutter/material.dart';

import '../core/activity_catalog.dart';
import '../core/event_config_store.dart';
import '../network/event_server_runner.dart';

/// Ecran de organizator: alege ce activități apar în meniul invitaților
/// pentru evenimentul curent. Salvează instant la fiecare comutare și
/// trimite selecția și serverului deja pornit (`EventServerRunner.syncActivities`
/// — fără asta, schimbarea n-ar ajunge niciodată la el, vezi
/// `EventConfigStore`) — invitații care se conectează de acum înainte văd
/// selecția nouă (cei deja aflați pe ecranul de meniu o văd la următoarea
/// reconectare, vezi `EventConnectScreen`).
class ActivityConfigScreen extends StatefulWidget {
  const ActivityConfigScreen({super.key});

  @override
  State<ActivityConfigScreen> createState() => _ActivityConfigScreenState();
}

class _ActivityConfigScreenState extends State<ActivityConfigScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      appBar: AppBar(backgroundColor: Colors.black26, title: const Text('Activități')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                'Alege ce vede un client în meniul lui.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: activityCatalog.length,
                separatorBuilder: (_, _) => const Divider(color: Colors.white12, height: 1),
                itemBuilder: (context, index) {
                  final activity = activityCatalog[index];
                  return SwitchListTile(
                    value: EventConfigStore.instance.isEnabled(activity.id),
                    onChanged: (value) {
                      // `setEnabled` mută sincron setul intern înainte de primul
                      // `await` — apelăm setState după, ca rebuild-ul să vadă
                      // deja valoarea nouă (persistarea pe disc continuă în fundal).
                      EventConfigStore.instance.setEnabled(activity.id, value);
                      setState(() {});
                      EventServerRunner.syncActivities(EventConfigStore.instance.enabledActivityIds);
                    },
                    activeThumbColor: activity.accentColor,
                    secondary: Icon(activity.icon, color: Colors.white70),
                    title: Text(activity.title, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(activity.subtitle, style: const TextStyle(color: Colors.white54)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
