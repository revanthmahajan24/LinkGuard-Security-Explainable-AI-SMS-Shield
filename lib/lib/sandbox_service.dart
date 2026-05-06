import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class SandboxResult {
  final bool hasOtpField;
  final bool hasPaymentForm;
  final int redirectCount;
  final bool networkError; // 🔥 NEW FIELD

  SandboxResult({required this.hasOtpField, required this.hasPaymentForm, required this.redirectCount, required this.networkError});
}

class SandboxService {
  Future<SandboxResult> analyzeUrlInHiddenSandbox(String url) async {
    final Completer<SandboxResult> completer = Completer<SandboxResult>();
    HeadlessInAppWebView? headlessWebView;
    int redirects = 0;

    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      onLoadStart: (controller, url) { redirects++; },
      // 🔥 Handle WebView load errors (No Internet)
      onLoadError: (controller, url, code, message) {
        if (!completer.isCompleted) completer.complete(SandboxResult(hasOtpField: false, hasPaymentForm: false, redirectCount: redirects, networkError: true));
      },
      onLoadStop: (controller, url) async {
        String otpScript = """
          (function() {
            var inputs = document.querySelectorAll('input');
            for (var i = 0; i < inputs.length; i++) {
              var n = (inputs[i].name || "").toLowerCase();
              var p = (inputs[i].placeholder || "").toLowerCase();
              if (n.includes('otp') || p.includes('pan') || p.includes('aadhaar') || inputs[i].type === 'password') return true;
            }
            return false;
          })();
        """;

        String paymentScript = """
          (function() {
            var inputs = document.querySelectorAll('input');
            for (var i = 0; i < inputs.length; i++) {
              var n = (inputs[i].name || "").toLowerCase();
              if (n.includes('card') || n.includes('cvv') || n.includes('upi')) return true;
            }
            return document.querySelectorAll('form').length > 0;
          })();
        """;

        try {
          var otpResult = await controller.evaluateJavascript(source: otpScript);
          var payResult = await controller.evaluateJavascript(source: paymentScript);
          if (!completer.isCompleted) {
            completer.complete(SandboxResult(hasOtpField: otpResult == true, hasPaymentForm: payResult == true, redirectCount: redirects, networkError: false));
          }
        } catch (e) {
          if (!completer.isCompleted) completer.complete(SandboxResult(hasOtpField: false, hasPaymentForm: false, redirectCount: 0, networkError: true));
        }
      },
    );

    await headlessWebView.run();
    SandboxResult result;
    try {
      result = await completer.future.timeout(const Duration(seconds: 8));
    } catch (e) {
      // 🔥 Timeout means dead site or offline
      result = SandboxResult(hasOtpField: false, hasPaymentForm: false, redirectCount: redirects, networkError: true);
    } finally {
      await headlessWebView.dispose();
    }
    return result;
  }
}