/*
 * Smart Clinic – ESP32 WiFi → Cloud Backend (template)
 * Copy to esp32_wifi_cloud.ino and set WIFI_SSID, WIFI_PASS, BACKEND_HOST.
 */

#include <WiFi.h>
#include <HTTPClient.h>

const char* WIFI_SSID    = "YOUR_WIFI_SSID";
const char* WIFI_PASS    = "YOUR_WIFI_PASSWORD";
const char* BACKEND_HOST = "octocare-production.up.railway.app";

const int    BACKEND_PORT = 443;
const char*  INGEST_PATH  = "/sensors/live/ingest/batch";
const int    FLUSH_INTERVAL_MS = 500;
const int    MAX_BATCH_SIZE    = 10;

String pendingLines[MAX_BATCH_SIZE];
int    pendingCount = 0;
unsigned long lastFlush = 0;

String uartBuffer = "";

void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;

  Serial.print("Connecting to WiFi");
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 40) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println();
    Serial.print("Connected! IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println();
    Serial.println("WiFi connection failed. Will retry...");
  }
}

void postBatch() {
  if (pendingCount == 0) return;
  if (WiFi.status() != WL_CONNECTED) {
    connectWiFi();
    if (WiFi.status() != WL_CONNECTED) return;
  }

  String json = "{\"lines\":[";
  for (int i = 0; i < pendingCount; i++) {
    if (i > 0) json += ",";
    json += "\"";
    json += pendingLines[i];
    json += "\"";
  }
  json += "]}";

  String url = "https://";
  url += BACKEND_HOST;
  url += INGEST_PATH;

  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(5000);

  int httpCode = http.POST(json);

  if (httpCode > 0) {
    Serial.printf("POST %d lines → HTTP %d\n", pendingCount, httpCode);
  } else {
    Serial.printf("POST failed: %s\n", http.errorToString(httpCode).c_str());
  }

  http.end();
  pendingCount = 0;
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

        if (pendingCount < MAX_BATCH_SIZE) {
          pendingLines[pendingCount] = uartBuffer;
          pendingCount++;
        }

        Serial.print("RX: ");
        Serial.println(uartBuffer);
      }
      uartBuffer = "";
    } else {
      uartBuffer += c;
    }
  }
}

void setup() {
  Serial.begin(115200);
  Serial2.begin(9600, SERIAL_8N1, 16, 17);

  Serial.println("Smart Clinic ESP32 Cloud Bridge");
  Serial.println("===============================");

  connectWiFi();
  lastFlush = millis();
}

void loop() {
  readArduinoUart();

  unsigned long now = millis();
  if (pendingCount >= MAX_BATCH_SIZE || (pendingCount > 0 && (now - lastFlush) >= FLUSH_INTERVAL_MS)) {
    postBatch();
    lastFlush = now;
  }

  delay(1);
}
