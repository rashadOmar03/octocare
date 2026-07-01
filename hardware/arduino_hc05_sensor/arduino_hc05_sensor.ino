/*
 * Smart Clinic - Arduino Uno + HC-05 + MAX30102 + LM35
 *
 * WIRING (verify against your breadboard):
 * ----------------------------------------
 * HC-05 Bluetooth:
 *   VCC  -> 5V
 *   GND  -> GND
 *   TX   -> Arduino pin 10 (SoftwareSerial RX)
 *   RX   -> Arduino pin 11 (SoftwareSerial TX)  [use 1K/2K divider if module is 3.3V]
 *
 * MAX30102 (red pulse oximeter board):
 *   VIN  -> 3.3V or 5V (follow your module label)
 *   GND  -> GND
 *   SDA  -> A4
 *   SCL  -> A5
 *
 * LM35 temperature (green 3-pin module):
 *   VCC  -> 5V
 *   GND  -> GND
 *   OUT  -> A0
 *
 * Extra red sensor board: not used if MAX30102 is connected.
 *
 * Arduino IDE libraries (Tools -> Manage Libraries):
 *   - "SparkFun MAX3010x Pulse and Proximity Sensor Library"
 *
 * Output format (must match mobile app):
 *   ATTACHED:0
 *   ATTACHED:1,HR:72,SPO2:98,TEMP:36.5
 *
 * ATTACHED:1 only when finger is on MAX30102 (IR level high enough).
 */

#include <SoftwareSerial.h>
#include <Wire.h>
#include "MAX30105.h"
#include "heartRate.h"

SoftwareSerial bt(10, 11); // RX, TX for HC-05

MAX30105 particleSensor;

const int LM35_PIN = A0;
const long FINGER_IR_THRESHOLD = 50000;

const byte RATE_SIZE = 4;
byte rates[RATE_SIZE];
byte rateSpot = 0;
long lastBeat = 0;
float beatsPerMinute = 0;
int beatAvg = 0;

unsigned long lastSend = 0;

bool fingerOnSensor() {
  return particleSensor.getIR() > FINGER_IR_THRESHOLD;
}

float readLm35Celsius() {
  int raw = analogRead(LM35_PIN);
  return raw * (5.0 / 1024.0) * 100.0;
}

int estimateSpO2() {
  long red = particleSensor.getRed();
  long ir = particleSensor.getIR();
  if (ir < 1000) return 0;
  float ratio = (float)red / (float)ir;
  int spo2 = (int)(110.0 - (ratio * 25.0));
  if (spo2 < 90) spo2 = 90;
  if (spo2 > 99) spo2 = 99;
  return spo2;
}

void setup() {
  Serial.begin(9600);
  bt.begin(9600);

  Wire.begin();

  if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
    Serial.println("MAX30102 not found. Check SDA=A4, SCL=A5, power.");
    while (true) {
      delay(1000);
    }
  }

  particleSensor.setup();
  particleSensor.setPulseAmplitudeRed(0x1F);
  particleSensor.setPulseAmplitudeIR(0x1F);
  particleSensor.setPulseAmplitudeGreen(0);

  Serial.println("Smart Clinic sensor ready.");
}

void loop() {
  if (!fingerOnSensor()) {
    beatAvg = 0;
    rateSpot = 0;
    if (millis() - lastSend > 1000) {
      bt.println("ATTACHED:0");
      Serial.println("ATTACHED:0");
      lastSend = millis();
    }
    delay(100);
    return;
  }

  long irValue = particleSensor.getIR();
  if (checkForBeat(irValue)) {
    long delta = millis() - lastBeat;
    lastBeat = millis();
    beatsPerMinute = 60.0 / (delta / 1000.0);
    if (beatsPerMinute < 255 && beatsPerMinute > 40) {
      rates[rateSpot++] = (byte)beatsPerMinute;
      rateSpot %= RATE_SIZE;
      int sum = 0;
      for (byte i = 0; i < RATE_SIZE; i++) {
        sum += rates[i];
      }
      beatAvg = sum / RATE_SIZE;
    }
  }

  if (millis() - lastSend < 500) {
    return;
  }
  lastSend = millis();

  int hr = beatAvg > 0 ? beatAvg : 0;
  int spo2 = estimateSpO2();
  float temp = readLm35Celsius();

  if (hr == 0) {
    return;
  }

  String line = "ATTACHED:1,HR:" + String(hr) +
                ",SPO2:" + String(spo2) +
                ",TEMP:" + String(temp, 1);

  bt.println(line);
  Serial.println(line);
}
