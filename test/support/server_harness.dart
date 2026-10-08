import 'package:flutter_test/flutter_test.dart';
import 'package:local_event_business/core/blocked_users_store.dart';
import 'package:local_event_business/core/event_config_store.dart';
import 'package:local_event_business/core/moderation_log_store.dart';
import 'package:local_event_business/core/muted_users_store.dart';
import 'package:local_event_business/core/organizer_key_store.dart';
import 'package:local_event_business/network/event_server_service_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_channel.dart';

/// Lasă să ruleze toate microtask-urile/evenimentele în așteptare — mesajele
/// trimise pe un [FakeChannel] ajung la server asincron.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Inițializează store-urile serverului pe un `shared_preferences` gol și
/// întoarce un [EventServerService] nepornit (fără HTTP/UDP) — conexiunile
/// se fac prin [connect].
Future<EventServerService> createTestServer() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await EventConfigStore.instance.init();
  await BlockedUsersStore.instance.init();
  await MutedUsersStore.instance.init();
  await ModerationLogStore.instance.init();
  await OrganizerKeyStore.instance.init();
  // Store-urile sunt singleton-uri: curățăm ce ar fi rămas de la alt test.
  for (final id in BlockedUsersStore.instance.blocked.keys.toList()) {
    await BlockedUsersStore.instance.unblock(id);
  }
  for (final id in MutedUsersStore.instance.muted.keys.toList()) {
    await MutedUsersStore.instance.unmute(id);
  }
  return EventServerService(serverName: 'test');
}

Future<FakeChannel> connect(EventServerService server) async {
  final channel = FakeChannel();
  server.acceptClient(channel);
  await settle();
  return channel;
}

/// Creează o cameră [gameId] pe o conexiune nouă și întoarce canalul +
/// codul camerei.
Future<(FakeChannel, String)> createRoom(
  EventServerService server, {
  required String secret,
  String gameId = 'macao',
  String name = 'Gazda',
  Object? tableStake = 0,
}) async {
  final channel = await connect(server);
  channel.send({
    'type': 'create_room',
    'gameId': gameId,
    'roomName': 'Masa 1',
    'tableStake': tableStake,
    'name': name,
    'profileId': secret,
  });
  await settle();
  final joined = channel.lastOfType('joined');
  if (joined == null) {
    throw StateError('create_room a eșuat: ${channel.lastOfType('error')}');
  }
  return (channel, joined['code'] as String);
}

Future<FakeChannel> joinRoom(
  EventServerService server, {
  required String code,
  required String secret,
  String name = 'Jucător',
  FakeChannel? on,
}) async {
  final channel = on ?? await connect(server);
  channel.send({'type': 'join_room', 'code': code, 'name': name, 'profileId': secret});
  await settle();
  return channel;
}
