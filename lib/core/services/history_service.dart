import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../data/models/generation_model.dart';
import 'storage_service.dart';

/// Service for persisting generation history using SharedPreferences.
///
/// Stores a JSON-encoded list of [GenerationModel] records under a single key.
/// This is a lightweight solution suitable for moderate history sizes.
/// For large-scale history, consider SQLite (e.g., drift, sqflite).
class HistoryService {
  final StorageService _storage;

  HistoryService({required StorageService storage}) : _storage = storage;

  /// Key used to store the history list in SharedPreferences.
  static const String _historyKey = 'generation_history';

  /// Retrieve all generation records from local storage.
  List<GenerationModel> getHistory() {
    final jsonStr = _storage.getString(_historyKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
      return jsonList
          .map((e) => GenerationModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('HistoryService: failed to decode history — $e');
      return [];
    }
  }

  /// Add a new generation record to history (prepends to maintain reverse-chronological order).
  Future<void> addGeneration(GenerationModel model) async {
    final history = getHistory();
    history.insert(0, model);

    // Keep only the last 100 entries to conserve storage
    if (history.length > 100) {
      history.removeRange(100, history.length);
    }

    await _saveHistory(history);
  }

  /// Update an existing generation record (e.g., when status changes from pending to completed).
  Future<void> updateGeneration(GenerationModel updated) async {
    final history = getHistory();
    final index = history.indexWhere((g) => g.id == updated.id);
    if (index != -1) {
      history[index] = updated;
      await _saveHistory(history);
    }
  }

  /// Delete a specific generation record by id and cleans up its local files.
  Future<void> deleteGeneration(String id) async {
    final history = getHistory();
    final index = history.indexWhere((g) => g.id == id);
    if (index != -1) {
      final item = history[index];
      await _deleteLocalFile(item.resultImageUrl);
      await _deleteLocalFile(item.personImageUrl);
      await _deleteLocalFile(item.clothesImageUrl);
      history.removeAt(index);
      await _saveHistory(history);
    }
  }

  Future<void> _deleteLocalFile(String? path) async {
    if (path == null || path.isEmpty || path.startsWith('http')) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Clear all generation history and removes local history files.
  Future<void> clearHistory() async {
    final history = getHistory();
    for (final item in history) {
      await _deleteLocalFile(item.resultImageUrl);
      await _deleteLocalFile(item.personImageUrl);
      await _deleteLocalFile(item.clothesImageUrl);
    }
    await _storage.removeKey(_historyKey);
  }

  /// Serialize and persist the history list.
  Future<void> _saveHistory(List<GenerationModel> history) async {
    final jsonList = history.map((g) => g.toMap()).toList();
    await _storage.setString(_historyKey, jsonEncode(jsonList));
  }
}
