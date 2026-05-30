import 'dart:convert';

import '../../domain/models/lidarr_instance.dart';
import '../datasources/local/credential_store.dart';

class LidarrRepository {
  const LidarrRepository(this._storage);
  final CredentialStore _storage;

  static const _instancesKey = 'lidarr_instances';
  static const _selectedIdKey = 'lidarr_selected_instance_id';
  static String _apiKeyFor(String id) => 'lidarr_api_key_$id';

  Future<List<LidarrInstance>> loadAll() async {
    final raw = await _storage.read(key: _instancesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => LidarrInstance.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> upsert(LidarrInstance instance) async {
    final all = await loadAll();
    final idx = all.indexWhere((i) => i.id == instance.id);
    if (idx >= 0) {
      all[idx] = instance;
    } else {
      all.add(instance);
    }
    await _storage.write(
      key: _instancesKey,
      value: jsonEncode(all.map((i) => i.toJson()).toList()),
    );
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((i) => i.id == id);
    await _storage.write(
      key: _instancesKey,
      value: jsonEncode(all.map((i) => i.toJson()).toList()),
    );
    await _storage.delete(key: _apiKeyFor(id));
  }

  Future<void> saveApiKey(String id, String apiKey) async {
    await _storage.write(key: _apiKeyFor(id), value: apiKey);
  }

  Future<String?> loadApiKey(String id) async {
    return _storage.read(key: _apiKeyFor(id));
  }

  Future<String?> loadSelectedId() async {
    return _storage.read(key: _selectedIdKey);
  }

  Future<void> saveSelectedId(String? id) async {
    if (id == null) {
      await _storage.delete(key: _selectedIdKey);
    } else {
      await _storage.write(key: _selectedIdKey, value: id);
    }
  }
}
