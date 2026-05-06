import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ScanRecord {
  final String sender;
  final String body;
  final int score;
  final bool isFraud;
  final String category;
  final String time;

  ScanRecord({
    required this.sender,
    required this.body,
    required this.score,
    required this.isFraud,
    required this.category,
    required this.time
  });

  Map<String, dynamic> toJson() => {
    'sender': sender,
    'body': body,
    'score': score,
    'isFraud': isFraud,
    'category': category,
    'time': time
  };

  factory ScanRecord.fromJson(Map<String, dynamic> json) => ScanRecord(
      sender: json['sender'] ?? "Unknown",
      body: json['body'] ?? "",
      score: json['score'] ?? 0,
      isFraud: json['isFraud'] ?? false,
      category: json['category'] ?? "Safe",
      time: json['time'] ?? ""
  );
}

class StorageService {
  static Future<void> saveRecord(String sender, String sms, int score, bool isFraud, String category) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> logs = prefs.getStringList('scan_history') ?? [];
    logs.insert(0, jsonEncode(ScanRecord(
        sender: sender,
        body: sms,
        score: score,
        isFraud: isFraud,
        category: category,
        time: DateTime.now().toString().substring(0, 16)
    ).toJson()));

    if (logs.length > 50) logs = logs.sublist(0, 50);
    await prefs.setStringList('scan_history', logs);
  }

  static Future<List<ScanRecord>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('scan_history') ?? []).map((item) => ScanRecord.fromJson(jsonDecode(item))).toList();
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('scan_history');
  }

  static Future<void> deleteRecord(ScanRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> logs = prefs.getStringList('scan_history') ?? [];

    logs.removeWhere((itemStr) {
      final item = ScanRecord.fromJson(jsonDecode(itemStr));
      return item.sender == record.sender && item.body == record.body && item.time == record.time;
    });

    await prefs.setStringList('scan_history', logs);
  }

  static Future<void> markAsSafe(ScanRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> logs = prefs.getStringList('scan_history') ?? [];

    int index = logs.indexWhere((itemStr) {
      final item = ScanRecord.fromJson(jsonDecode(itemStr));
      return item.sender == record.sender && item.body == record.body && item.time == record.time;
    });

    if (index != -1) {
      ScanRecord updatedRecord = ScanRecord(
          sender: record.sender,
          body: record.body,
          score: 10,
          isFraud: false,
          category: "Safe",
          time: record.time
      );
      logs[index] = jsonEncode(updatedRecord.toJson());
      await prefs.setStringList('scan_history', logs);
    }
  }

  // 🔥 NEW: Update a record after Rescanning!
  static Future<void> updateRecord(ScanRecord oldRecord, ScanRecord newRecord) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> logs = prefs.getStringList('scan_history') ?? [];

    int index = logs.indexWhere((itemStr) {
      final item = ScanRecord.fromJson(jsonDecode(itemStr));
      return item.sender == oldRecord.sender && item.body == oldRecord.body && item.time == oldRecord.time;
    });

    if (index != -1) {
      logs[index] = jsonEncode(newRecord.toJson());
      await prefs.setStringList('scan_history', logs);
    }
  }
}