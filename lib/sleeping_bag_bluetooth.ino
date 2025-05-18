// Update Final, Implementation PID and Bluetooth
#include <OneWire.h>
#include <DallasTemperature.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>

// Definisi pin
#define ONE_WIRE_BUS 4 // Pin Data DS18B20
#define RELAY_PIN 2    // Pin untuk kontrol relay
#define VOLTAGE_PIN 34 // Pin sensor tegangan

// Definisi UUID BLE
#define SERVICE_UUID "12345678-1234-1234-1234-123456789abc"
#define CHARACTERISTIC_TX "abcd1234-1a2b-3c4d-5e6f-123456789abc" // Notify
#define CHARACTERISTIC_RX "abcd5678-1a2b-3c4d-5e6f-123456789abc" // Write

// Definisi objek OneWire dan sensor suhu
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature sensors(&oneWire);

// Definisi objek LCD 16x2
LiquidCrystal_I2C lcd(0x27, 16, 2);

// Definisi objek BLE
BLEServer *pServer = NULL;
BLECharacteristic *txCharacteristic;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Variabel untuk relay status
bool relayStatus = false;

// Variabel untuk suhu
float temperature1 = 0.0;   // Suhu real dari sensor
float temperature2 = 0.0;   // Suhu dummy 1
float temperature3 = 0.0;   // Suhu dummy 2
float temperature4 = 0.0;   // Suhu dummy 3
float avgTemperature = 0.0; // Rata-rata suhu

float voltage = 0.0;

// Variabel untuk timer
unsigned long sendDataPrevMillis = 0;
unsigned long displayToggleMillis = 0;
unsigned long pidComputeMillis = 0; // Timer untuk kalkulasi PID
bool displayState = true;

// Variabel untuk PID
float setPoint = 30.0;   // Suhu target yang diinginkan
float pidOutput = 0.0;   // Output dari PID (0-100%)
bool pidEnabled = false; // Status PID aktif atau tidak

// Parameter PID
float Kp = 5.0;  // Dikurangi untuk mengurangi overshoot
float Ki = 0.2;  // Ditingkatkan untuk mengurangi steady-state error
float Kd = 50.0; // Dikurangi untuk mengurangi noise sensitivity

// Variabel internal PID
float lastError = 0.0;              // Error sebelumnya untuk komponen derivative
float integral = 0.0;               // Akumulasi error untuk komponen integral
unsigned long pidInterval = 1000;   // Interval kalkulasi PID (ms)
unsigned long relayInterval = 5000; // Interval PWM relay (ms)
unsigned long relayOnTime = 0;      // Waktu relay ON dalam interval PWM
unsigned long lastRelayToggle = 0;  // Waktu terakhir relay toggle

String mode = "auto"; // Mode operasi: "auto" atau "manual"

// Fungsi untuk menghasilkan suhu dummy yang logis berdasarkan suhu real
float generateDummyTemp(float baseTemp)
{
  // Variasi random antara -1.5 dan +1.5 derajat dari suhu dasar
  return baseTemp + random(-15, 16) / 10.0;
}

// Fungsi untuk menghitung output PID
float computePID(float input)
{
  // Hitung error
  float error = setPoint - input;

  // Komponen Proportional
  float pOutput = Kp * error;

  // Komponen Integral
  integral += Ki * error;
  // Anti-windup: batasi integral agar tidak terlalu besar
  if (integral > 100.0)
    integral = 100.0;
  if (integral < 0.0)
    integral = 0.0;

  // Komponen Derivative
  float derivative = error - lastError;
  float dOutput = Kd * derivative;

  // Hitung total output
  float output = pOutput + integral + dOutput;

  // Batasi output antara 0-100%
  if (output > 100.0)
    output = 100.0;
  if (output < 0.0)
    output = 0.0;

  // Simpan error saat ini untuk kalkulasi derivative berikutnya
  lastError = error;

  return output;
}

// Fungsi untuk menerapkan kontrol PWM pada relay berdasarkan output PID
void applyPIDtoRelay()
{
  unsigned long currentMillis = millis();

  // Jika PID diaktifkan, hitung berapa lama relay harus ON dalam satu interval PWM
  if (pidEnabled)
  {
    relayOnTime = (unsigned long)(pidOutput * relayInterval / 100.0);

    // Implementasi PWM "manual" untuk relay
    if (currentMillis - lastRelayToggle >= relayInterval)
    {
      // Mulai siklus baru
      lastRelayToggle = currentMillis;

      if (relayOnTime > 0)
      {
        // Nyalakan relay di awal siklus jika waktu ON > 0
        digitalWrite(RELAY_PIN, HIGH);
        relayStatus = true;
      }
      else
      {
        // Jika waktu ON = 0, relay tetap mati
        digitalWrite(RELAY_PIN, LOW);
        relayStatus = false;
      }
    }
    else if (currentMillis - lastRelayToggle >= relayOnTime && relayStatus)
    {
      // Matikan relay setelah waktu ON tercapai
      digitalWrite(RELAY_PIN, LOW);
      relayStatus = false;
    }
  }
}

// Class untuk callback BLE Server
class MyServerCallbacks : public BLEServerCallbacks
{
  void onConnect(BLEServer *pServer)
  {
    deviceConnected = true;
    Serial.println("[BLE] Device connected");

    // Tampilkan status koneksi di LCD
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("BLE Connected");
    delay(1000);
  }

  void onDisconnect(BLEServer *pServer)
  {
    deviceConnected = false;
    Serial.println("[BLE] Device disconnected");

    // Tampilkan status koneksi di LCD
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("BLE Disconnected");
    delay(1000);
  }
};

// Class untuk callback BLE Characteristic
class MyCallbacks : public BLECharacteristicCallbacks
{
  void onWrite(BLECharacteristic *pCharacteristic)
  {
    std::string rxValue = pCharacteristic->getValue();

    if (rxValue.length() > 0)
    {
      String receivedData = String(rxValue.c_str());
      Serial.print("[BLE] Received: ");
      Serial.println(receivedData);

      // Parse JSON data dari aplikasi
      DynamicJsonDocument doc(1024);
      DeserializationError error = deserializeJson(doc, receivedData);

      if (error)
      {
        Serial.print("[JSON] Parsing failed: ");
        Serial.println(error.c_str());
        return;
      }

      // Periksa tipe perintah
      String command = doc["cmd"].as<String>();

      if (command == "relay")
      {
        // Command untuk kontrol relay manual
        bool newRelayState = doc["state"].as<bool>();
        if (mode == "manual")
        {
          relayStatus = newRelayState;
          digitalWrite(RELAY_PIN, relayStatus ? HIGH : LOW);
          Serial.print("[RELAY] Set to: ");
          Serial.println(relayStatus ? "ON" : "OFF");
        }
        else
        {
          Serial.println("[RELAY] Ignoring command, system in AUTO mode");
        }
      }
      else if (command == "pidEnable")
      {
        // Command untuk mengaktifkan/nonaktifkan PID
        pidEnabled = doc["state"].as<bool>();
        Serial.print("[PID] ");
        Serial.println(pidEnabled ? "Enabled" : "Disabled");

        // Reset integral saat PID baru diaktifkan
        if (pidEnabled)
        {
          integral = 0;
          lastError = 0;
        }
      }
      else if (command == "setPoint")
      {
        // Command untuk mengubah setPoint
        setPoint = doc["value"].as<float>();
        Serial.print("[PID] SetPoint changed to: ");
        Serial.println(setPoint);
      }
      else if (command == "pidParams")
      {
        // Command untuk mengubah parameter PID
        Kp = doc["kp"].as<float>();
        Ki = doc["ki"].as<float>();
        Kd = doc["kd"].as<float>();
        Serial.println("[PID] Parameters updated");
        Serial.print("Kp: ");
        Serial.print(Kp);
        Serial.print(" Ki: ");
        Serial.print(Ki);
        Serial.print(" Kd: ");
        Serial.println(Kd);
      }
      else if (command == "mode")
      {
        // Command untuk mengubah mode operasi
        mode = doc["value"].as<String>();
        Serial.print("[MODE] Changed to: ");
        Serial.println(mode);

        if (mode == "manual")
        {
          pidEnabled = false;
        }
      }
    }
  }
};

void setup()
{
  Serial.begin(115200);

  // Inisialisasi pin relay sebagai output
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW); // Relay off saat awal

  // Inisialisasi random seed
  randomSeed(analogRead(0));

  // Inisialisasi sensor suhu
  sensors.begin();

  // Inisialisasi LCD
  Wire.begin();
  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("System Starting");

  // Inisialisasi BLE
  BLEDevice::init("ESP32-Thermostat");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Karakteristik untuk TX (notifikasi data ke aplikasi)
  txCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_TX,
      BLECharacteristic::PROPERTY_NOTIFY);
  txCharacteristic->addDescriptor(new BLE2902());

  // Karakteristik untuk RX (menerima perintah dari aplikasi)
  BLECharacteristic *rxCharacteristic = pService->createCharacteristic(
      CHARACTERISTIC_RX,
      BLECharacteristic::PROPERTY_WRITE);
  rxCharacteristic->setCallbacks(new MyCallbacks());

  // Mulai service BLE
  pService->start();

  // Mulai advertising
  pServer->getAdvertising()->start();
  Serial.println("[BLE] Server started, waiting for connections...");

  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("BLE Started");
  lcd.setCursor(0, 1);
  lcd.print("Waiting for conn.");
  delay(2000);

  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("System Ready");
  delay(1000);
}

void loop()
{
  // Baca suhu dari sensor DS18B20
  sensors.requestTemperatures();
  temperature1 = sensors.getTempCByIndex(0);

  // Jika pembacaan suhu gagal, gunakan nilai dummy
  if (temperature1 == DEVICE_DISCONNECTED_C)
  {
    temperature1 = 25.0; // Nilai default jika sensor tidak terhubung
    Serial.println("[TEMP] Sensor not connected, using default value");
  }

  // Generate suhu dummy berdasarkan suhu real
  temperature2 = generateDummyTemp(temperature1);
  temperature3 = generateDummyTemp(temperature1);
  temperature4 = generateDummyTemp(temperature1);

  // Hitung rata-rata suhu
  avgTemperature = (temperature1 + temperature2 + temperature3 + temperature4) / 4.0;

  // Baca tegangan dari sensor tegangan
  int sensorValue = analogRead(VOLTAGE_PIN);
  voltage = sensorValue * (3.3 / 4095.0) * 5.0; // Sesuaikan dengan pembagi tegangan yang digunakan

  // Kalkulasi PID setiap interval waktu tertentu
  if (millis() - pidComputeMillis >= pidInterval)
  {
    pidComputeMillis = millis();

    if (mode == "auto")
    {
      // Kalkulasi PID
      pidOutput = computePID(avgTemperature);
      applyPIDtoRelay(); // relay dikontrol oleh PID
    }
    else
    { // mode == "manual"
      pidEnabled = false;
      // Di mode manual, relay dikontrol oleh aplikasi
      // Tidak ada yang perlu dilakukan disini karena relay diatur via BLE

      // Output PID tetap disimpan untuk monitoring
      pidOutput = 0.0;
    }
  }

  // Rotasi display LCD setiap 3 detik
  if (millis() - displayToggleMillis > 3000)
  {
    displayToggleMillis = millis();
    displayState = !displayState;

    lcd.clear();
    if (displayState)
    {
      // Tampilkan suhu rata-rata dan status relay di LCD
      lcd.setCursor(0, 0);
      lcd.print(mode == "auto" ? "AUTO" : "MANUAL");
      lcd.print(" SP:");
      lcd.print(setPoint, 1);
      lcd.setCursor(0, 1);
      lcd.print("PID:");
      lcd.print(pidEnabled ? "ON" : "OFF");
      lcd.print(" ");
      lcd.print(pidOutput, 0);
      lcd.print("%");
    }
    else
    {
      // Tampilkan suhu real dan status relay di LCD
      lcd.setCursor(0, 0);
      lcd.print("Temp:");
      lcd.print(temperature1, 1);
      lcd.print("C");
      lcd.setCursor(0, 1);
      lcd.print("Relay:");
      lcd.print(relayStatus ? "ON" : "OFF");
    }
  }

  // Kirim data ke aplikasi setiap 2 detik jika terhubung
  if (deviceConnected && (millis() - sendDataPrevMillis > 2000 || sendDataPrevMillis == 0))
  {
    sendDataPrevMillis = millis();

    // Buat JSON data untuk dikirim ke aplikasi
    DynamicJsonDocument doc(1024);
    doc["temp1"] = temperature1;
    doc["temp2"] = temperature2;
    doc["temp3"] = temperature3;
    doc["temp4"] = temperature4;
    doc["avgTemp"] = avgTemperature;
    doc["voltage"] = voltage;
    doc["relayStatus"] = relayStatus;
    doc["pidOutput"] = pidOutput;
    doc["pidEnabled"] = pidEnabled;
    doc["setPoint"] = setPoint;
    doc["kp"] = Kp;
    doc["ki"] = Ki;
    doc["kd"] = Kd;
    doc["mode"] = mode;

    String jsonString;
    serializeJson(doc, jsonString);

    // Kirim data melalui BLE
    txCharacteristic->setValue(jsonString.c_str());
    txCharacteristic->notify();
    Serial.println("[BLE] Data sent: " + jsonString);
  }

  // Reconnect jika klien terputus
  if (!deviceConnected && oldDeviceConnected)
  {
    delay(500);                  // Tunggu pemrosesan BLE selesai
    pServer->startAdvertising(); // Restart advertising
    Serial.println("[BLE] Start advertising");
    oldDeviceConnected = deviceConnected;
  }

  // Jika baru tersambung
  if (deviceConnected && !oldDeviceConnected)
  {
    oldDeviceConnected = deviceConnected;
  }

  delay(100); // Delay untuk loop
}