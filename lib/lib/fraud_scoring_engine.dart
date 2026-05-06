import 'sandbox_service.dart';

class FraudAlertResult {
  final bool isFraud;
  final int score;
  final String originalUrl;
  final String neutralizedUrl;
  final String reason;
  final String category;

  FraudAlertResult({
    required this.isFraud, required this.score, required this.originalUrl,
    required this.neutralizedUrl, required this.reason, required this.category,
  });
}

class FraudScoringEngine {
  static final SandboxService _sandbox = SandboxService();

  static Future<void> initModel() async { print("✅ Engine Initialized"); }

  static double getMLScore(String text) {
    String lower = text.toLowerCase();
    double p = 0.0;
    if (lower.contains('urgent') || lower.contains('immediately') || lower.contains('disconnected')) p += 0.4;
    if (lower.contains('kyc') || lower.contains('verify') || lower.contains('update')) p += 0.3;
    if (lower.contains('bank') || lower.contains('account')) p += 0.2;
    return p.clamp(0.01, 0.99);
  }

  static int urlRisk(String url) {
    String lowerUrl = url.toLowerCase();
    int score = 0;
    if (lowerUrl.startsWith("http://")) score += 20;
    if (lowerUrl.contains(RegExp(r'\d+\.\d+\.\d+\.\d+'))) score += 25;
    if (lowerUrl.contains("bit.ly") || lowerUrl.contains("tinyurl") || lowerUrl.contains("cutt.ly")) score += 20;
    return score;
  }

  static Future<FraudAlertResult?> analyzeSms(String sms) async {
    print("\n--------------------------------------------------");
    print("🔍 [LINKGUARD] ANALYZING SMS: $sms");

    RegExp urlRegex = RegExp(r"((https?:\/\/)?(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*))", caseSensitive: false);
    String? url = urlRegex.firstMatch(sms)?.group(0);

    if (url == null) {
      print("✅ [RESULT] No URL detected. Marked as Safe.");
      print("--------------------------------------------------\n");
      return null;
    }
    print("🔗 [LINK] Detected: $url");

    double mlScore = getMLScore(sms);
    int urlScore = urlRisk(url);
    double weightedMlScore = mlScore * 50;

    print("🧠 [NLP] Base Probability: $mlScore -> Weighted Score: $weightedMlScore/50");
    print("🌐 https://www.merriam-webster.com/dictionary/risk Syntax Score: $urlScore/75");

    if (weightedMlScore + urlScore < 20) {
      print("✅ [RESULT] Early Exit: Total Static Score (${weightedMlScore + urlScore}) is below 20. Safe.");
      print("--------------------------------------------------\n");
      return null;
    }

    print("⚠️ [WARNING] Suspicious baseline. Initiating Deep Sandbox Detonation...");

    List<String> reasons = [];
    SandboxResult sandbox = await _sandbox.analyzeUrlInHiddenSandbox(url);
    int behaviorScore = 0;

    if (sandbox.hasPaymentForm) { behaviorScore += 30; reasons.add("Payment form detected"); }
    if (sandbox.hasOtpField) { behaviorScore += 25; reasons.add("OTP field detected"); }
    if (sandbox.redirectCount > 2) { behaviorScore += 20; reasons.add("Suspicious redirects"); }
    if (mlScore > 0.7) reasons.add("Urgent manipulative language");

    print("🛡️ [SANDBOX] Behavior Score: $behaviorScore/75");

    int finalScore = (weightedMlScore + urlScore + behaviorScore).toInt().clamp(0, 100);
    print("🎯 [FINAL] Total Threat Score: $finalScore/100");

    if (finalScore > 60) {
      String category = _categorize(sms, reasons);
      print("🚨 [ALERT] THREAT NEUTRALIZED! Category: $category");
      print("--------------------------------------------------\n");
      return FraudAlertResult(
        isFraud: true, score: finalScore, originalUrl: url,
        neutralizedUrl: url.replaceFirst(RegExp(r'https?'), 'hxxp').replaceAll(".", "[.]"),
        reason: reasons.join("\n• "),
        category: category,
      );
    }

    print("✅ [RESULT] Survived deep analysis. Marked as Safe.");
    print("--------------------------------------------------\n");
    return null;
  }

  static String _categorize(String text, List<String> reasons) {
    String lower = text.toLowerCase();
    if (lower.contains('cbi') || lower.contains('police') || lower.contains('warrant') || lower.contains('court')) return "Legal";
    if (lower.contains('electricity') || lower.contains('bank') || lower.contains('kyc') || reasons.contains("Payment form detected")) return "Financial";
    return "Scam";
  }
}