/*
 * Smart Clinic – ESP32 WiFi → Local TCP Server (for local testing)
 *
 * This is the LOCAL version. It creates a TCP server that the Flutter app
 * or the esp32_tcp_bridge.py connects to. Use this when testing on your PC.
 *
 * For CLOUD deployment, use esp32_wifi_cloud.ino instead.
 *
 * WIRING:
 *   ESP32 RX2 (GPIO 16) ← Arduino TX (SoftwareSerial pin 11 or HC-05 TX)
 *   ESP32 TX2 (GPIO 17) → Arduino RX  [optional]
 *   GND ↔ GND
 *
 * CONFIGURATION:
 *   1. Set WIFI_SSID and WIFI_PASS to your local WiFi network
 *   2. Upload to ESP32 via Arduino IDE
 *   3. Note the IP address printed in Serial Monitor
 *   4. Run: python backend/tools/esp32_tcp_bridge.py --esp32 <IP> --port 5000
 */

#include <WiFi.h>

const char* WIFI_SSID = "YOUR_WIFI_SSID";
const char* WIFI_PASS = "YOUR_WIFI_PASSWORD";

const int TCP_PORT = 5000;

WiFiServer server(TCP_PORT);
WiFiClient client;

String latestData = "";
String uartBuffer = "";

void connectWiFi() {
  Serial.print("Connecting to WiFi");
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.print("Connected! IP: ");
  Serial.println(WiFi.localIP());
  Serial.printf("TCP server on port %d\n", TCP_PORT);
}

void readArduinoUart() {
  while (Serial2.available()) {
    char c = Serial2.read();
    if (c == '\n' || c == '\r') {
      uartBuffer.trim();
      if (uartBuffer.length() > 0) {
        if (uartBuffer.startsWith("RECEIVED:")) {
          uartBuffer = uartBuffer.substring(9);
          uartBuffer.trim();
        }
        latestData = uartBuffer;
        Serial.print("RX: ");
        Serial.println(latestData);
      }
      uartBuffer = "";
    } else {
      uartBuffer += c;
    }
  }
}

void setup() {
  Serial.begin(115200);
  Serial2.begin(115200, SERIAL_8N1, 16, 17);

  Serial.println("Smart Clinic ESP32 Local TCP Bridge");
  Serial.println("===================================");

  connectWiFi();
  server.begin();
}

void loop() {
  readArduinoUart();

  if (WiFi.status() != WL_CONNECTED) {
    delay(100);
    return;
  }

  if (!client || !client.connected()) {
    client = server.available();
    if (client) {
      Serial.println("Client connected!");
    }
  }

  static String lastSent = "";
  if (client && client.connected() && latestData.length() > 0 && latestData != lastSent) {
    client.println(latestData);
    lastSent = latestData;
  }

  delay(1);
}
