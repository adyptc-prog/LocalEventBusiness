import 'package:flutter/material.dart';

import '../core/platform_support.dart';
import '../widgets/language_button.dart';
import '../widgets/menu_card.dart';
import 'activity_config_screen.dart';
import 'event_connect_screen.dart';
import 'event_server_screen.dart';
import 'leaderboard_screen.dart';
import 'menu_editor_screen.dart';
import 'orders_dashboard_screen.dart';
import 'participants_screen.dart';
import 'room_monitor_screen.dart';
import 'tables_screen.dart';
import '../l10n/tr.dart';

/// Ecranul de start al aplicației. Butonul principal duce la conectarea la
/// serverul localului curent — meniul de-acolo (`EventMenuScreen`) e dictat
/// de organizator, nu static. Cardurile de organizator (Server local,
/// Activități, Produse meniu, Mese, Comenzi la bar) și clasamentul rămân
/// accesibile direct, fără conexiune — organizatorul trebuie să poată porni
/// serverul fără să depindă de conexiunea la el însuși.
class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Butoanele stau pe rândul iconiței, ca titlul să aibă toată
                  // lățimea ecranului pentru el.
                  Row(
                    children: [
                      const Icon(Icons.hub, size: 44, color: Colors.white),
                      const Spacer(),
                      const LanguageButton(),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.leaderboard),
                        tooltip: tr('mainMenu.leaderboard'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Pe un ecran îngust titlul se micșorează, nu se rupe.
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('LocalEventBusiness',
                        maxLines: 1,
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(height: 4),
                  Text(tr('mainMenu.tagline'), style: const TextStyle(color: Colors.white54)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    MenuCard(
                      icon: Icons.wifi,
                      title: tr('mainMenu.join.title'),
                      subtitle: tr('mainMenu.join.subtitle'),
                      color: const Color(0xFF0B5E3B),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const EventConnectScreen()),
                      ),
                    ),
                    if (canHostEventServer) ...[
                      const SizedBox(height: 20),
                      MenuCard(
                        icon: Icons.dns,
                        title: tr('mainMenu.server.title'),
                        subtitle: tr('mainMenu.server.subtitle'),
                        color: const Color(0xFF3A2E0E),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => const EventServerScreen()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      MenuCard(
                        icon: Icons.point_of_sale,
                        title: tr('mainMenu.orders.title'),
                        subtitle: tr('mainMenu.orders.subtitle'),
                        color: const Color(0xFF6B3F1D),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => const OrdersDashboardScreen()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.checklist),
                              label: Text(tr('mainMenu.activities')),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => const ActivityConfigScreen()),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.restaurant_menu),
                              label: Text(tr('mainMenu.menuProducts')),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => const MenuEditorScreen()),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.qr_code),
                          label: Text(tr('mainMenu.tables')),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const TablesScreen()),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.people),
                          label: Text(tr('mainMenu.participants')),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const ParticipantsScreen()),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.visibility),
                          label: Text(tr('mainMenu.monitor')),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (context) => const RoomMonitorScreen()),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
