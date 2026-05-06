# 🛡️ LinkGuard Security: Explainable AI SMS Shield

### Developed for the FINTECH Cybersecurity Hackathon at IIT Ropar

LinkGuard Security is a pro-active, on-device cybersecurity solution designed to protect users from sophisticated SMS-based phishing (smishing) and financial fraud. Developed as a high-impact Fintech tool, LinkGuard leverages on-device Machine Learning and **Explainable AI (XAI)** to interpret, analyze, and neutralize malicious links within SMS traffic, even when the app is completely closed.

---

## 🏆 Project Context: IIT Ropar FINTECH Cybersecurity Hackathon

This solution was developed specifically to address the surge in financial fraud within the Indian digital ecosystem, as identified during the **IIT Ropar Fintech Cybersecurity Hackathon**. LinkGuard bridges the gap between passive fraud detection and pro-active, user-centric threat intelligence by providing transparent, *explainable* AI metrics to the user.

---

## 🚀 Key Features & Visual Walkthrough

LinkGuard has been designed with a "Security-First" UI/UX, prioritizing professional aesthetics and crystal-clear threat communication.

### 1. Seamless Security from Boot
The app features a distinct branding strategy from the moment of launch. The persistent "Shield Active" foreground notification provides psychological assurance to the user that LinkGuard is vigilantly monitoring SMS traffic without draining battery.

| ![App Icon](screenshots/app_icon.png) | ![Persistent Foreground Notification](screenshots/foreground_notification.png) |
| :---: | :---: |
| **Secure App Icon** | **Foreground Shield Active** |

### 2. The Smart Dashboard
The main dashboard provides an intuitive summary of the system’s health. Users can see a high-level overview of total messages scanned vs threats neutralized. The interactive **Threat Distribution Chart** visually represents the AI's classification metrics (Financial, Legal, Scam).

| ![Dashboard Overview](screenshots/dashboard.png) | ![Threat Distribution Chart](screenshots/threat_chart.png) |
| :---: | :---: |
| **LinkGuard Dashboard** | **Real-Time Threat Distribution** |

### 3. Explainable AI (XAI): Forensic Breakdown
This is our flagship feature, directly aligning with advanced PhD research on transparency in machine learning. Instead of just marking a message as "Scam," LinkGuard uses an "XAI forensic Breakdown" card. We provide visual "Risk DNA" bars (Linguistic Pressure, URL Metadata Risk) to *explain* why the model calculated a high risk score. This builds crucial user trust and digital literacy.

| ![XAI Safe Message](screenshots/chat_safe.png) | ![🔥 XAI Threat Intercepted](screenshots/chat_fraud_xai.png) |
| :---: | :---: |
| **XAI Verified Safe Message** | **XAI Forensic Breakdown of a Threat** |

### 4. Community Defense: One-Tap Reporting
Close the loop on cybersecurity. If LinkGuard detects a threat, it doesn't just block it—it helps the authorities. Users can report the incident to the **National Cyber Crime Reporting Portal (1930)** or PhishTank with a single tap.

| ![Report to Authorities](screenshots/report_menu.png) | ![Pre-filled Report Generation](screenshots/1930_report.png) |
| :---: | :---: |
| **Report Options Menu** | **Generating Report to Authorities** |

---

## 🛠️ Technical Architecture

| Component | Technology | Description |
| :--- | :--- | :--- |
| **Framework** | Flutter/Dart | Cross-platform UI development. |
| **Operating System** | Kotlin/Android | Native SMS Broadcast and Notification listeners. |
| **AI Engine** | TensorFlow Lite | On-device, privacy-preserving ML inference. |
| ** Explainability** | Custom XAI Interpretation | Interprets model weights into user-friendly "Risk DNA" metrics. |
| **Background Services** | Workmanager | Periodic Deep-Scanning and AI Model optimization. |
| **Data Security** | FLAG_SECURE / SQLite | Prevents screenshots of sensitive data and secures message logs. |

---

## 🚀 Getting Started

To run this project, make sure you are using a demo phone with the following native settings configured:

1.  Disable Google Spam Protection (so the system allows your listener to trigger).
2.  Set Battery Optimization to "Unrestricted" for the LinkGuard app.
3.  Grant "RECEIVE_SMS" and "POST_NOTIFICATIONS" permissions manually.

***

**LinkGuard Security** - Developed by [Team Innovexa.].
Submitted for the **FINTECH Cybersecurity Hackathon at IIT Ropar**.
