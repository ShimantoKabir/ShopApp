import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/sync.dart';

/// Talks to the shop's log (the Cloudflare Worker) over HTTPS.
///
/// Anything that means "could not get through" (no signal, a slow or
/// unreachable server, a server error) becomes [SyncProblem.offline]; a refused
/// key becomes [SyncProblem.unauthorized].
class HttpSyncTransport implements SyncTransport {
  final String _base;
  final String _key;
  final http.Client _client;
  final Duration _timeout;

  HttpSyncTransport(SyncConfig config, {http.Client? client, this._timeout = const Duration(seconds: 20)})
      : _base = config.url.endsWith('/') ? config.url.substring(0, config.url.length - 1) : config.url,
        _key = config.key,
        _client = client ?? http.Client();

  Future<Map<String, dynamic>> _send(String method, String path, {Object? body}) async {
    final http.Response response;
    try {
      final request = http.Request(method, Uri.parse('$_base$path'))
        ..headers['authorization'] = 'Bearer $_key'
        ..headers['content-type'] = 'application/json';
      if (body != null) request.body = jsonEncode(body);
      response = await http.Response.fromStream(await _client.send(request).timeout(_timeout)).timeout(_timeout);
    } on TimeoutException {
      throw const SyncException(SyncProblem.offline);
    } on SocketException {
      throw const SyncException(SyncProblem.offline);
    } on http.ClientException {
      throw const SyncException(SyncProblem.offline);
    } on HandshakeException {
      throw const SyncException(SyncProblem.offline);
    }

    if (response.statusCode == 401) throw const SyncException(SyncProblem.unauthorized);
    if (response.statusCode == 404) throw const SyncException(SyncProblem.badSettings); // wrong address
    if (response.statusCode != 200) throw const SyncException(SyncProblem.offline);
    try {
      return (jsonDecode(utf8.decode(response.bodyBytes)) as Map).cast<String, dynamic>();
    } on FormatException {
      throw const SyncException(SyncProblem.badSettings); // not our server
    }
  }

  @override
  Future<int> head() async => (await _send('GET', '/v1/ping'))['head'] as int;

  @override
  Future<({List<RemoteOp> ops, int head})> fetch(int after, {int limit = 500}) async {
    final body = await _send('GET', '/v1/ops?after=$after&limit=$limit');
    return (
      ops: [
        for (final o in (body['ops'] as List))
          RemoteOp(
            seq: (o as Map)['seq'] as int,
            opId: o['opId'] as String,
            device: o['device'] as String,
            at: o['at'] as int,
            payload: o['payload'] as String,
          ),
      ],
      head: body['head'] as int,
    );
  }

  @override
  Future<int> append({required String opId, required String device, required int at, required String payload}) async {
    final body = await _send('POST', '/v1/ops', body: {'opId': opId, 'device': device, 'at': at, 'payload': payload});
    return body['seq'] as int;
  }

  @override
  Future<int> erase({required String opId, required String device, required int at, required String payload}) async {
    final Map<String, dynamic> body;
    try {
      body = await _send('POST', '/v1/erase', body: {'opId': opId, 'device': device, 'at': at, 'payload': payload});
    } on SyncException catch (e) {
      // The key was accepted (or it would have been "unauthorized"), so a
      // missing address here means the server has not been updated.
      if (e.problem == SyncProblem.badSettings) throw const SyncException(SyncProblem.serverOutdated);
      rethrow;
    }
    return body['seq'] as int;
  }
}
