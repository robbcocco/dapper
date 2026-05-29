import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/models/navidrome_server.dart';

class ServerRepository {
  const ServerRepository(this._storage);

  final FlutterSecureStorage _storage;

  static const _serversKey = 'navidrome_servers';
  static const _selectedKey = 'selected_server_id';

  Future<List<NavidromeServer>> loadAll() async {
    final raw = await _storage.read(key: _serversKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>().map(NavidromeServer.fromJson).toList();
  }

  Future<void> _saveAll(List<NavidromeServer> servers) async {
    final raw = jsonEncode(servers.map((s) => s.toJson()).toList());
    await _storage.write(key: _serversKey, value: raw);
  }

  Future<void> upsert(NavidromeServer server) async {
    final servers = await loadAll();
    final idx = servers.indexWhere((s) => s.id == server.id);
    if (idx >= 0) {
      servers[idx] = server;
    } else {
      servers.add(server);
    }
    await _saveAll(servers);
  }

  Future<void> delete(String id) async {
    final servers = await loadAll();
    await _saveAll(servers.where((s) => s.id != id).toList());
    await _storage.delete(key: 'server_password_$id');
  }

  Future<void> savePassword(String id, String password) =>
      _storage.write(key: 'server_password_$id', value: password);

  Future<String?> loadPassword(String id) =>
      _storage.read(key: 'server_password_$id');

  Future<String?> loadSelectedId() => _storage.read(key: _selectedKey);

  Future<void> saveSelectedId(String? id) async {
    if (id == null) {
      await _storage.delete(key: _selectedKey);
    } else {
      await _storage.write(key: _selectedKey, value: id);
    }
  }
}
