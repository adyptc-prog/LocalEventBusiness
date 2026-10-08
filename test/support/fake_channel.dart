import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Un [WebSocketChannel] fals, în memorie — partea „server" a unei conexiuni
/// de client. Testul trimite mesaje ca și cum ar veni de la client ([send])
/// și citește ce i-a trimis serverul ([received]), fără nicio rețea reală.
class FakeChannel with StreamChannelMixin implements WebSocketChannel {
  final _incoming = StreamController<dynamic>();
  late final _FakeSink _sink = _FakeSink(this);

  /// Mesajele trimise de server pe acest canal, decodate din JSON.
  final List<Map<String, dynamic>> received = [];
  bool closedByServer = false;

  /// Simulează un mesaj trimis de client.
  void send(Map<String, dynamic> message) => _incoming.add(jsonEncode(message));

  void sendRaw(Object raw) => _incoming.add(raw);

  /// Simulează plecarea clientului (conexiune închisă din partea lui).
  void disconnect() => unawaited(_incoming.close());

  Iterable<Map<String, dynamic>> ofType(String type) => received.where((m) => m['type'] == type);

  Map<String, dynamic>? lastOfType(String type) {
    final list = ofType(type).toList();
    return list.isEmpty ? null : list.last;
  }

  @override
  Stream get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();
}

class _FakeSink implements WebSocketSink {
  final FakeChannel _channel;
  final _done = Completer<void>();

  _FakeSink(this._channel);

  @override
  void add(dynamic data) {
    if (_channel.closedByServer) return;
    _channel.received.add(jsonDecode(data as String) as Map<String, dynamic>);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) => stream.forEach(add);

  @override
  Future close([int? closeCode, String? closeReason]) async {
    if (_channel.closedByServer) return;
    _channel.closedByServer = true;
    // La un WebSocket real, închiderea de către server încheie și fluxul de
    // intrare — `onDone` pe server se declanșează.
    if (!_channel._incoming.isClosed) unawaited(_channel._incoming.close());
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future get done => _done.future;
}
