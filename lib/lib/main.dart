import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'dart:ui';
import 'fraud_scoring_engine.dart';
import 'storage_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    String? smsBody = inputData?['sms_body'];
    if (smsBody != null) {
      await FraudScoringEngine.initModel();
      final result = await FraudScoringEngine.analyzeSms(smsBody);
      if (result != null && result.isFraud) {
        await StorageService.saveRecord("Background Sync", smsBody, result.score, true, result.category);
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await FraudScoringEngine.initModel();
  runApp(const LinkGuardApp());
}

class LinkGuardApp extends StatelessWidget {
  const LinkGuardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinkGuard Security',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
        primaryColor: Colors.blue.shade700,
        colorScheme: ColorScheme.light(primary: Colors.blue.shade700, secondary: Colors.red.shade600),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontFamily: 'Roboto', color: Colors.black87),
          titleLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white, elevation: 1, iconTheme: IconThemeData(color: Colors.black87)),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const EventChannel _smsChannel = EventChannel('com.example.smshealth/sms');
  static const MethodChannel _notifyChannel = MethodChannel('com.example.smshealth/notify');

  List<ScanRecord> history = [];
  bool _isScanning = false;
  late AnimationController _pulseController;
  final FlutterTts _flutterTts = FlutterTts();

  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = "";
  AppLifecycleState _appState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _initVoiceEngine();
    _loadHistory();
    _initSmsListener();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appState = state;
  }

  Future<void> _initVoiceEngine() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _triggerVoiceAlarm(String category) async {
    await _flutterTts.speak("Warning. High risk $category threat intercepted and neutralized.");
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _flutterTts.stop();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final data = await StorageService.getHistory();
    setState(() => history = data);
  }

  List<ScanRecord> get _filteredHistory {
    if (_searchQuery.isEmpty) return history;
    return history.where((e) => e.sender.toLowerCase().contains(_searchQuery) || e.body.toLowerCase().contains(_searchQuery)).toList();
  }

  Future<void> _scanHistoricalMessages() async {
    setState(() => _isScanning = true);

    final SmsQuery query = SmsQuery();
    List<SmsMessage> messages = await query.querySms(kinds: [SmsQueryKind.inbox], count: 50);

    int threatsFound = 0;

    for (var msg in messages) {
      if (msg.body == null || msg.address == null) continue;

      String rawSms = msg.body!;
      String sender = msg.address!;

      if (history.any((e) => e.body == rawSms || e.body.contains("MALICIOUS LINK DISABLED"))) continue;

      final result = await FraudScoringEngine.analyzeSms(rawSms);

      if (result != null && result.isFraud) {
        String safeDisplaySms = rawSms.replaceAll(result.originalUrl, "🛑 [MALICIOUS LINK DISABLED BY LINKGUARD]");
        await StorageService.saveRecord(sender, safeDisplaySms, result.score, true, result.category);
        threatsFound++;
      }
    }

    await _loadHistory();
    setState(() => _isScanning = false);

    if (threatsFound > 0) {
      _triggerVoiceAlarm("Multiple");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Scan Complete: $threatsFound prior threats neutralized."), backgroundColor: Colors.red.shade700));
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text("Scan Complete: Inbox is clean."), backgroundColor: Colors.green.shade700));
    }
  }

  void _initSmsListener() async {
    await [Permission.sms, Permission.notification, Permission.contacts].request();

    _smsChannel.receiveBroadcastStream().listen((dynamic event) async {
      setState(() => _isScanning = true);
      final Map<Object?, Object?> data = event as Map<Object?, Object?>;
      String sender = data['sender']?.toString() ?? "Unknown";
      String rawSms = data['body']?.toString() ?? "";

      final result = await FraudScoringEngine.analyzeSms(rawSms);
      bool isFraud = result?.isFraud ?? false;
      int score = result?.score ?? 10;
      String category = result?.category ?? "Safe";

      String safeDisplaySms = rawSms;
      if (isFraud && result != null) {
        safeDisplaySms = rawSms.replaceAll(result.originalUrl, "🛑 [MALICIOUS LINK DISABLED BY LINKGUARD]");
      }

      await StorageService.saveRecord(sender, safeDisplaySms, score, isFraud, category);
      await _loadHistory();

      setState(() => _isScanning = false);

      if (isFraud && result != null) {
        _triggerVoiceAlarm(category);
        if (_appState == AppLifecycleState.resumed) {
          _showPremiumThreatDialog(result, sender);
        } else {
          _notifyChannel.invokeMethod('showNotification', {'sender': sender, 'body': safeDisplaySms});
        }
      }
    });
  }

  void _confirmResetApp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Wipe System Logs", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        content: const Text("This will permanently delete all scanned SMS history. Proceed?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () async {
              await StorageService.clearHistory();
              setState(() {
                history.clear();
                _searchQuery = "";
                _searchController.clear();
                _isSearching = false;
              });
              Navigator.pop(ctx);
            },
            child: const Text("WIPE DATA", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _showPremiumThreatDialog(FraudAlertResult result, String sender) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.shade300, width: 2), boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.15), blurRadius: 25, spreadRadius: 5)]),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.gpp_bad_rounded, color: Colors.red.shade600, size: 60),
                  const SizedBox(height: 16),
                  Text("THREAT NEUTRALIZED", style: TextStyle(color: Colors.red.shade700, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 24),
                  _buildDetailRow(Icons.person, "Originating ID", sender),
                  _buildDetailRow(Icons.category, "Classification", result.category),
                  _buildDetailRow(Icons.speed, "XAI Threat Score", "${result.score}/100", color: Colors.red.shade700),
                  Divider(color: Colors.grey.shade200, height: 30, thickness: 1.5),
                  Align(alignment: Alignment.centerLeft, child: Text("Explainable AI Diagnosis:", style: TextStyle(color: Colors.blue.shade700, fontSize: 14, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: Text("• ${result.reason.replaceAll('\n• ', '\n• ')}", style: TextStyle(color: Colors.grey.shade800, fontSize: 13, height: 1.5))),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Quarantined Link:", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(result.neutralizedUrl, style: TextStyle(color: Colors.red.shade600, fontSize: 13, decoration: TextDecoration.lineThrough)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.blue.shade50.withOpacity(0.5), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, size: 18, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(fontSize: 11, color: Colors.blue.shade900, height: 1.4),
                              children: const [
                                TextSpan(text: "Check again to be safe: ", style: TextStyle(fontWeight: FontWeight.bold)),
                                TextSpan(text: "Verify links manually using external tools like "),
                                TextSpan(text: "urlscan.io", style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                                TextSpan(text: " or "),
                                TextSpan(text: "SSLLabs.com", style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                                TextSpan(text: ". We recommend checking with a second source before trusting any suspicious link completely."),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade50, elevation: 0, side: BorderSide(color: Colors.blue.shade700), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () {
                        _flutterTts.stop();
                        Navigator.pop(context);
                      },
                      child: Text("RESTORE SHIELD", style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey.shade500, size: 20),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
          const SizedBox(width: 16),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: TextStyle(color: color ?? Colors.black87, fontSize: 15, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildAnalyticsHeader() {
    int total = _filteredHistory.length;
    int threats = _filteredHistory.where((e) => e.isFraud).length;
    int safe = total - threats;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStatCard("TOTAL MSGS", total.toString(), Colors.blue.shade600),
          _buildStatCard("QUARANTINED", threats.toString(), Colors.red.shade600),
          _buildStatCard("SAFE MSGS", safe.toString(), Colors.green.shade600),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String count, Color accentColor) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, spreadRadius: 0)]),
        child: Column(
          children: [
            Text(count, style: TextStyle(color: accentColor, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildThreatChart() {
    if (_filteredHistory.isEmpty) return const SizedBox.shrink();

    int total = _filteredHistory.length;
    int safe = _filteredHistory.where((e) => !e.isFraud).length;
    int financial = _filteredHistory.where((e) => e.isFraud && e.category == "Financial").length;
    int legal = _filteredHistory.where((e) => e.isFraud && e.category == "Legal").length;
    int scam = _filteredHistory.where((e) => e.isFraud && e.category == "Scam").length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, spreadRadius: 0)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("THREAT DISTRIBUTION", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.5)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (safe > 0) Expanded(flex: safe, child: Container(color: Colors.green.shade500)),
                  if (financial > 0) Expanded(flex: financial, child: Container(color: Colors.red.shade600)),
                  if (legal > 0) Expanded(flex: legal, child: Container(color: Colors.orange.shade500)),
                  if (scam > 0) Expanded(flex: scam, child: Container(color: Colors.purple.shade500)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildLegendItem("Safe", Colors.green.shade500, safe, total),
              _buildLegendItem("Financial", Colors.red.shade600, financial, total),
              _buildLegendItem("Legal", Colors.orange.shade500, legal, total),
              _buildLegendItem("Scam", Colors.purple.shade500, scam, total),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildLegendItem(String title, Color color, int count, int total) {
    if (count == 0) return const SizedBox.shrink();
    double percent = (count / total) * 100;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 4, backgroundColor: color),
        const SizedBox(width: 6),
        Text("$title (${percent.toStringAsFixed(0)}%)", style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: _isSearching
              ? TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(hintText: "Search chats...", border: InputBorder.none, hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
            style: const TextStyle(color: Colors.black87, fontSize: 14),
            onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
          )
              : Row(
            children: [
              AnimatedBuilder(animation: _pulseController, builder: (context, child) => Icon(Icons.shield, color: _isScanning ? Colors.orange.shade500 : Colors.blue.shade600.withOpacity(0.5 + (_pulseController.value * 0.5)))),
              const SizedBox(width: 12),
              Text(_isScanning ? "INTERCEPTING..." : "SYSTEM SECURE", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: _isScanning ? Colors.orange.shade700 : Colors.blue.shade700)),
            ],
          ),
          actions: [
            IconButton(icon: Icon(Icons.document_scanner, color: Colors.blue.shade700), tooltip: "Deep Scan Inbox", onPressed: _scanHistoricalMessages),
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.blue.shade700),
              onPressed: () => setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _searchQuery = "";
                } else {
                  _isSearching = true;
                }
              }),
            ),
            IconButton(icon: Icon(Icons.delete_sweep, color: Colors.red.shade400), onPressed: _confirmResetApp),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            indicatorColor: Colors.blue.shade700, indicatorWeight: 3, labelColor: Colors.blue.shade700, unselectedLabelColor: Colors.grey.shade500, labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            tabs: const [Tab(text: "ALL CHATS"), Tab(text: "QUARANTINE"), Tab(text: "SAFE INBOX")],
          ),
        ),
        body: Column(
          children: [
            _buildAnalyticsHeader(),
            _buildThreatChart(),
            Expanded(
              child: TabBarView(
                children: [
                  _buildGroupedList(_filteredHistory),
                  _buildGroupedList(_filteredHistory.where((e) => e.isFraud).toList()),
                  _buildGroupedList(_filteredHistory.where((e) => !e.isFraud).toList()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedList(List<ScanRecord> list) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.speaker_notes_off_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(_isSearching ? "No matches found." : "Inbox is empty.", style: TextStyle(color: Colors.grey.shade500, letterSpacing: 1)),
          ],
        ),
      );
    }

    Map<String, List<ScanRecord>> grouped = {};
    for (var item in list) {
      grouped.putIfAbsent(item.sender, () => []).add(item);
    }

    List<String> senders = grouped.keys.toList();
    senders.sort((a, b) => grouped[b]!.first.time.compareTo(grouped[a]!.first.time));

    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      itemCount: senders.length,
      separatorBuilder: (_, __) => Divider(color: Colors.grey.shade200, height: 1, indent: 70),
      itemBuilder: (ctx, i) {
        String sender = senders[i];
        List<ScanRecord> msgs = grouped[sender]!;
        ScanRecord latestMsg = msgs.first;
        int threatCount = msgs.where((m) => m.isFraud).length;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: threatCount > 0 ? Colors.red.shade50 : Colors.blue.shade50,
            child: Icon(
              threatCount > 0 ? Icons.warning_amber_rounded : Icons.person,
              color: threatCount > 0 ? Colors.red.shade600 : Colors.blue.shade600,
              size: 28,
            ),
          ),
          title: Text(
            sender,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              latestMsg.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.3),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                  latestMsg.time.length > 10 ? latestMsg.time.substring(11, 16) : latestMsg.time,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w500)
              ),
              const SizedBox(height: 6),
              if (threatCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(12)),
                  child: Text("$threatCount Threats", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                )
            ],
          ),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => ConversationScreen(sender: sender)
            )).then((_) => _loadHistory());
          },
        );
      },
    );
  }
}

// ============================================================================
// 2. CONVERSATION SCREEN (The "Chat" View)
// ============================================================================
class ConversationScreen extends StatefulWidget {
  final String sender;
  const ConversationScreen({super.key, required this.sender});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  List<ScanRecord> chatHistory = [];

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    final allData = await StorageService.getHistory();
    setState(() {
      chatHistory = allData.where((e) => e.sender == widget.sender).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.sender, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Text("Secure Conversation", style: TextStyle(fontSize: 11, color: Colors.green)),
          ],
        ),
      ),
      body: _buildDetailedChatList(chatHistory),
    );
  }

  Widget _buildDetailedChatList(List<ScanRecord> list) {
    if (list.isEmpty) return const Center(child: Text("No messages."));

    return ListView.builder(
      padding: const EdgeInsets.only(top: 10, bottom: 20),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final item = list[i];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: item.isFraud ? Colors.red.shade200 : Colors.grey.shade200, width: item.isFraud ? 2 : 1),
            boxShadow: [BoxShadow(color: item.isFraud ? Colors.red.withOpacity(0.08) : Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔥 UPDATED HEADER WITH 3-DOT MENU (Including Rescan)
              Row(
                children: [
                  Icon(item.isFraud ? Icons.gpp_bad : Icons.gpp_good, color: item.isFraud ? Colors.red.shade600 : Colors.green.shade600, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.isFraud ? "THREAT BLOCKED" : "VERIFIED SAFE",
                      style: TextStyle(color: item.isFraud ? Colors.red.shade700 : Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                    ),
                  ),
                  Text(item.time.length > 10 ? item.time.substring(11, 16) : item.time, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),

                  // 🔥 NEW: Action Menu with "Rescan" feature
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.grey.shade400, size: 20),
                    padding: EdgeInsets.zero,
                    onSelected: (value) async {
                      if (value == 'delete') {
                        await StorageService.deleteRecord(item);
                        _loadChatHistory();
                      } else if (value == 'safe') {
                        await StorageService.markAsSafe(item);
                        _loadChatHistory();
                      } else if (value == 'rescan') {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Rescanning message..."), duration: Duration(seconds: 2))
                        );

                        // Run the AI engine again
                        final result = await FraudScoringEngine.analyzeSms(item.body);
                        bool isFraud = result?.isFraud ?? false;
                        int score = result?.score ?? 10;
                        String category = result?.category ?? "Safe";

                        String safeDisplaySms = item.body;
                        // Only sanitize if it wasn't already sanitized
                        if (isFraud && result != null && !item.body.contains("MALICIOUS LINK DISABLED")) {
                          safeDisplaySms = item.body.replaceAll(result.originalUrl, "🛑 [MALICIOUS LINK DISABLED BY LINKGUARD]");
                        }

                        // Save the updated findings while keeping the timeline position
                        ScanRecord updatedRecord = ScanRecord(
                          sender: item.sender,
                          body: safeDisplaySms,
                          score: score,
                          isFraud: isFraud,
                          category: category,
                          time: item.time,
                        );

                        await StorageService.updateRecord(item, updatedRecord);
                        _loadChatHistory();
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      // 1. Rescan Message Option
                      PopupMenuItem<String>(
                        value: 'rescan',
                        child: Row(
                          children: [
                            Icon(Icons.radar, color: Colors.blue.shade600, size: 18),
                            const SizedBox(width: 8),
                            Text('Rescan Message', style: TextStyle(color: Colors.blue.shade600)),
                          ],
                        ),
                      ),
                      // 2. Mark as Safe Option (Only shows if currently marked as fraud)
                      if (item.isFraud)
                        PopupMenuItem<String>(
                          value: 'safe',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline, color: Colors.green.shade600, size: 18),
                              const SizedBox(width: 8),
                              const Text('Mark as Safe'),
                            ],
                          ),
                        ),
                      // 3. Delete Message Option
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.red.shade600, size: 18),
                            const SizedBox(width: 8),
                            Text('Delete Message', style: TextStyle(color: Colors.red.shade600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Divider(color: Colors.grey.shade200, height: 24, thickness: 1),

              Text(item.body, style: const TextStyle(color: Colors.black87, fontSize: 15, height: 1.4)),

              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                    child: Text(item.category.toUpperCase(), style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: item.isFraud ? Colors.red.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
                    child: Text("RISK SCORE: ${item.score}/100", style: TextStyle(fontSize: 11, color: item.isFraud ? Colors.red.shade700 : Colors.green.shade700, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),

              if (item.isFraud) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Check again to be safe: We recommend verifying links manually using external tools like urlscan.io or SSLLabs.com before trusting them.",
                          style: TextStyle(fontSize: 11, color: Colors.blue.shade900, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ]
            ],
          ),
        );
      },
    );
  }
}