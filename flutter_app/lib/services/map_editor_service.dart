import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/map_edit_models.dart';
import 'api_service.dart';

// ─────────────────────────────────────────────────────────────
//  MapEditorService — HTTP hacia /api/editor/*
// ─────────────────────────────────────────────────────────────

abstract final class MapEditorService {
  static const _headers = {
    'Content-Type': 'application/json',
    'ngrok-skip-browser-warning': '1',
  };

  /// Carga todas las vías del grafo como GeoJSON y las parsea a [OsmWay].
  static Future<List<OsmWay>> getWays() async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.editorGeoJsonEndpoint}',
    );
    final response = await http
        .get(uri, headers: {'ngrok-skip-browser-warning': '1'})
        .timeout(const Duration(minutes: 2));

    if (response.statusCode != 200) {
      throw ApiException(
        'Error al cargar el mapa (${response.statusCode})',
        response.statusCode,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final features =
        (data['features'] as List).cast<Map<String, dynamic>>();
    return features.map(OsmWay.fromGeoJson).toList();
  }

  /// Envía los cambios pendientes al backend y los persiste en el PBF.
  static Future<void> saveChanges(
    List<PendingWayChange> changes, {
    List<PendingRestrictionChange> restrictionChanges = const [],
  }) async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.editorSaveEndpoint}',
    );

    final body = jsonEncode({
      'changes': changes.map((c) => c.toJson()).toList(),
      'node_changes': <dynamic>[],
      'restriction_changes':
          restrictionChanges.map((r) => r.toJson()).toList(),
    });

    final response = await http
        .post(uri, headers: _headers, body: body)
        .timeout(const Duration(minutes: 2));

    if (response.statusCode != 200) {
      throw ApiException(
        'Error al guardar: ${_extractDetail(response.body)}',
        response.statusCode,
      );
    }
  }

  /// Lanza el rebuild en el servidor (devuelve inmediatamente).
  static Future<void> startRebuild() async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.editorRebuildEndpoint}',
    );
    final response = await http
        .post(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 409) {
      throw ApiException('Ya hay un rebuild en curso.', 409);
    }
    if (response.statusCode != 200) {
      throw ApiException(
        'Error al iniciar rebuild: ${_extractDetail(response.body)}',
        response.statusCode,
      );
    }
  }

  /// Consulta el estado del rebuild.
  /// Devuelve un Map con keys: running (bool), status (String), message (String).
  static Future<Map<String, dynamic>> getRebuildStatus() async {
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.editorRebuildStatusEndpoint}',
    );
    final response = await http
        .get(uri, headers: {'ngrok-skip-browser-warning': '1'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw ApiException('Error consultando estado.', response.statusCode);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static String _extractDetail(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      return (data['detail'] ?? data['error'] ?? body).toString();
    } catch (_) {
      return body;
    }
  }
}
