import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Thermostat',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8BD8BD), // Cool pastel green
          brightness: Brightness.light,
          primary: const Color(0xFF8BD8BD), // Cool pastel green
          onPrimary: const Color(0xFF333333), // Black text on primary
          primaryContainer: const Color(0xFFB8E6D2), // Lighter pastel green
          onPrimaryContainer: const Color(0xFF333333), // Black text
          secondary: const Color(0xFF5D9B88), // Darker green
          onSecondary: const Color(0xFFEFEFEF), // White text on secondary
          surface: const Color(0xFFEFEFEF), // White surface
          onSurface: const Color(0xFF333333), // Black text on surface
          background: const Color(0xFFEFEFEF), // White background
          onBackground: const Color(0xFF333333), // Black text on background
          error: const Color(0xFFE57373), // Keep a reddish error color
          onError: const Color(0xFFEFEFEF), // White text on error
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF8BD8BD), // Cool pastel green
          linearMinHeight: 6,
        ),
        textTheme: GoogleFonts.poppinsTextTheme().apply(
          bodyColor: const Color(0xFF333333),
          displayColor: const Color(0xFF333333),
        ),
      ),
      home: const BleHome(),
    );
  }
}

class BleHome extends StatefulWidget {
  const BleHome({super.key});
  @override
  State<BleHome> createState() => _BleHomeState();
}

class _BleHomeState extends State<BleHome> {
  BluetoothDevice? device;
  BluetoothCharacteristic? txChar;
  BluetoothCharacteristic? rxChar;
  String status = "Belum Terhubung";

  // Temperature data
  double temp1 = 0.0;
  double temp2 = 0.0;
  double temp3 = 0.0;
  double temp4 = 0.0;
  double avgTemp = 0.0;
  double voltage = 0.0;

  // Control parameters
  bool relayStatus = false;
  double pidOutput = 0.0;
  bool pidEnabled = false;
  double setPoint = 30.0;
  double kp = 10.0;
  double ki = 0.1;
  double kd = 100.0;
  String mode = "auto";

  void startScan() async {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.name == "ESP32-Thermostat") {
          FlutterBluePlus.stopScan();
          connectToDevice(r.device);
          break;
        }
      }
    });
  }

  void connectToDevice(BluetoothDevice d) async {
    try {
      await d.connect(timeout: const Duration(seconds: 10));
      device = d;
      setState(() => status = "Terhubung ke ${d.name}");

      List<BluetoothService> services = await d.discoverServices();
      for (var s in services) {
        if (s.uuid.toString().toLowerCase() ==
            "12345678-1234-1234-1234-123456789abc") {
          for (var c in s.characteristics) {
            if (c.uuid.toString().toLowerCase() ==
                "abcd1234-1a2b-3c4d-5e6f-123456789abc") {
              txChar = c;
              await txChar!.setNotifyValue(true);
              txChar!.onValueReceived.listen((value) {
                final data = utf8.decode(value);
                updateDataFromJson(data);
              });
            }
            if (c.uuid.toString().toLowerCase() ==
                "abcd5678-1a2b-3c4d-5e6f-123456789abc") {
              rxChar = c;
            }
          }
        }
      }
    } catch (e) {
      setState(() => status = "Error: ${e.toString()}");
    }
  }

  void updateDataFromJson(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      setState(() {
        temp1 = data['temp1']?.toDouble() ?? 0.0;
        temp2 = data['temp2']?.toDouble() ?? 0.0;
        temp3 = data['temp3']?.toDouble() ?? 0.0;
        temp4 = data['temp4']?.toDouble() ?? 0.0;
        avgTemp = data['avgTemp']?.toDouble() ?? 0.0;
        voltage = data['voltage']?.toDouble() ?? 0.0;
        relayStatus = data['relayStatus'] ?? false;
        pidOutput = data['pidOutput']?.toDouble() ?? 0.0;
        pidEnabled = data['pidEnabled'] ?? false;
        setPoint = data['setPoint']?.toDouble() ?? 30.0;
        kp = data['kp']?.toDouble() ?? 10.0;
        ki = data['ki']?.toDouble() ?? 0.1;
        kd = data['kd']?.toDouble() ?? 100.0;
        mode = data['mode'] ?? "auto";
      });
    } catch (e) {
      print("Error parsing JSON: $e");
    }
  }

  void sendCommand(String jsonCommand) async {
    if (rxChar != null) {
      try {
        await rxChar!.write(utf8.encode(jsonCommand), withoutResponse: false);
        print("Command sent: $jsonCommand");
      } catch (e) {
        print("Error sending command: $e");
      }
    }
  }

  void setRelayState(bool state) {
    final Map<String, dynamic> params = {"cmd": "relay", "state": state};
    sendCommand(jsonEncode(params));
  }

  void setPIDEnabled(bool enabled) {
    final Map<String, dynamic> params = {"cmd": "pidEnable", "state": enabled};
    sendCommand(jsonEncode(params));
  }

  void setTemperatureSetPoint(double temp) {
    final Map<String, dynamic> params = {"cmd": "setPoint", "value": temp};
    sendCommand(jsonEncode(params));
  }

  void setMode(String newMode) {
    final Map<String, dynamic> params = {"cmd": "mode", "value": newMode};
    sendCommand(jsonEncode(params));
  }

  @override
  void initState() {
    super.initState();
    startScan();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Thermostat'),
        centerTitle: true,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 0,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: colorScheme.secondary,
        ),
        toolbarHeight: 80,
        shadowColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          if (device == null)
            _buildDisconnectedState(context)
          else
            _buildConnectedState(context),
        ],
      ),
    );
  }

  Widget _buildDisconnectedState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            const Color(0xFFEFEFEF),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_disabled_rounded,
              size: 80,
              color: const Color(0xFF333333).withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Connecting to ESP32 Thermostat',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF333333),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Searching for nearby devices...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF333333).withOpacity(0.7),
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: startScan,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Search Devices'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: const Color(0xFFEFEFEF),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Temperature Display
            Card(
              margin: EdgeInsets.zero,
              color: const Color(0xFFEFEFEF),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: colorScheme.primary.withOpacity(0.2),
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.thermostat, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          "Temperature Sensors",
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: const Color(0xFF333333),
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTemperatureGrid(context),
                    Divider(
                      height: 32,
                      color: const Color(0xFF333333).withOpacity(0.1),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.device_thermostat,
                          color: colorScheme.secondary),
                      title: const Text(
                        "Average Temperature",
                        style: TextStyle(color: Color(0xFF333333)),
                      ),
                      trailing: Text(
                        "${avgTemp.toStringAsFixed(1)}°C",
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: colorScheme.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.battery_charging_full,
                          color: colorScheme.secondary),
                      title: const Text(
                        "Battery Voltage",
                        style: TextStyle(color: Color(0xFF333333)),
                      ),
                      trailing: Text(
                        "${voltage.toStringAsFixed(1)}V",
                        style: TextStyle(
                          color: colorScheme.secondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Control Panel
            Card(
              margin: EdgeInsets.zero,
              color: const Color(0xFFEFEFEF),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: colorScheme.primary.withOpacity(0.2),
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.tune, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              "Control Panel",
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: const Color(0xFF333333),
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                        Text(
                          "Relay ${relayStatus ? 'ON' : 'OFF'}",
                          style: TextStyle(
                            color: relayStatus
                                ? colorScheme.primary
                                : colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Mode Switch
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        "Control Mode",
                        style: TextStyle(color: Color(0xFF333333)),
                      ),
                      subtitle: Text(
                        mode == "auto" ? "Automatic Control" : "Manual Control",
                        style: TextStyle(
                            color: const Color(0xFF333333).withOpacity(0.7)),
                      ),
                      value: mode == "auto",
                      activeColor: colorScheme.primary,
                      activeTrackColor: colorScheme.primaryContainer,
                      onChanged: (value) {
                        final newMode = value ? "auto" : "manual";
                        setMode(newMode);
                        setState(() {
                          mode = newMode;
                        });
                      },
                    ),

                    // PID Controls
                    if (mode == "auto") ...[
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          "PID Control",
                          style: TextStyle(color: Color(0xFF333333)),
                        ),
                        subtitle: Text(
                          "PID Output: ${pidOutput.toStringAsFixed(1)}%",
                          style: TextStyle(
                              color: const Color(0xFF333333).withOpacity(0.7)),
                        ),
                        value: pidEnabled,
                        activeColor: colorScheme.primary,
                        activeTrackColor: colorScheme.primaryContainer,
                        onChanged: setPIDEnabled,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Temperature Setpoint",
                        style: TextStyle(
                          color: Color(0xFF333333),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            "20°C",
                            style: TextStyle(
                                color:
                                    const Color(0xFF333333).withOpacity(0.7)),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                activeTrackColor: colorScheme.primary,
                                inactiveTrackColor:
                                    colorScheme.primary.withOpacity(0.2),
                                thumbColor: colorScheme.primary,
                                overlayColor:
                                    colorScheme.primary.withOpacity(0.1),
                                trackHeight: 4,
                              ),
                              child: Slider(
                                value: setPoint,
                                min: 20,
                                max: 40,
                                divisions: 40,
                                label: "${setPoint.toStringAsFixed(1)}°C",
                                onChanged: (value) {
                                  setState(() {
                                    setPoint = value;
                                  });
                                },
                                onChangeEnd: setTemperatureSetPoint,
                              ),
                            ),
                          ),
                          Text(
                            "40°C",
                            style: TextStyle(
                                color:
                                    const Color(0xFF333333).withOpacity(0.7)),
                          ),
                        ],
                      ),
                    ],

                    // Manual Controls
                    if (mode == "manual") ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => setRelayState(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: relayStatus
                                    ? colorScheme.primary
                                    : const Color(0xFFEFEFEF),
                                foregroundColor: relayStatus
                                    ? const Color(0xFF333333)
                                    : const Color(0xFF333333).withOpacity(0.7),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.power_settings_new),
                              label: const Text("Turn ON"),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => setRelayState(false),
                              style: FilledButton.styleFrom(
                                backgroundColor: !relayStatus
                                    ? colorScheme.error
                                    : const Color(0xFFEFEFEF),
                                foregroundColor: !relayStatus
                                    ? const Color(0xFFEFEFEF)
                                    : const Color(0xFF333333).withOpacity(0.7),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.power_settings_new),
                              label: const Text("Turn OFF"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemperatureGrid(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildTempCard(context, "Sensor 1", temp1, colorScheme),
        _buildTempCard(context, "Sensor 2", temp2, colorScheme),
        _buildTempCard(context, "Sensor 3", temp3, colorScheme),
        _buildTempCard(context, "Sensor 4", temp4, colorScheme),
      ],
    );
  }

  Widget _buildTempCard(BuildContext context, String title, double temp,
      ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer.withOpacity(0.5),
            colorScheme.primaryContainer.withOpacity(0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              color: const Color(0xFF333333).withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "${temp.toStringAsFixed(1)}°C",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}
