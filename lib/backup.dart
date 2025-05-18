// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// void main() {
//   runApp(const MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'ESP32 BLE Control',
//       theme: ThemeData(primarySwatch: Colors.blue),
//       home: const BleHome(),
//     );
//   }
// }

// class BleHome extends StatefulWidget {
//   const BleHome({super.key});
//   @override
//   State<BleHome> createState() => _BleHomeState();
// }

// class _BleHomeState extends State<BleHome> {
//   BluetoothDevice? device;
//   BluetoothCharacteristic? txChar;
//   BluetoothCharacteristic? rxChar;
//   String receivedData = "";
//   String status = "Belum Terhubung";

//   void startScan() async {
//     FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
//     FlutterBluePlus.scanResults.listen((results) {
//       for (ScanResult r in results) {
//         if (r.device.name == "ESP32-BLE-Relay") {
//           FlutterBluePlus.stopScan();
//           connectToDevice(r.device);
//           break;
//         }
//       }
//     });
//   }

//   void connectToDevice(BluetoothDevice d) async {
//     await d.connect(timeout: const Duration(seconds: 10));
//     device = d;
//     setState(() => status = "Terhubung ke ${d.name}");

//     List<BluetoothService> services = await d.discoverServices();
//     for (var s in services) {
//       if (s.uuid.toString().toLowerCase() ==
//           "12345678-1234-1234-1234-123456789abc") {
//         for (var c in s.characteristics) {
//           if (c.uuid.toString().toLowerCase() ==
//               "abcd1234-1a2b-3c4d-5e6f-123456789abc") {
//             txChar = c;
//             await txChar!.setNotifyValue(true);
//             txChar!.onValueReceived.listen((value) {
//               setState(() {
//                 receivedData = utf8.decode(value);
//               });
//             });
//           }
//           if (c.uuid.toString().toLowerCase() ==
//               "abcd5678-1a2b-3c4d-5e6f-123456789abc") {
//             rxChar = c;
//           }
//         }
//       }
//     }
//   }

//   void sendCommand(String command) async {
//     if (rxChar != null) {
//       try {
//         await rxChar!.write(utf8.encode(command), withoutResponse: false);
//         print("Command sent: $command");
//       } catch (e) {
//         print("Error sending command: $e");
//       }
//     }
//   }

//   @override
//   void initState() {
//     super.initState();
//     startScan();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('BLE Monitoring & Kontrol')),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           children: [
//             Text("Status: $status", style: const TextStyle(fontSize: 16)),
//             const SizedBox(height: 20),
//             Text("Data dari ESP32:\n$receivedData",
//                 style: const TextStyle(fontSize: 18)),
//             const SizedBox(height: 20),
//             Row(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 ElevatedButton(
//                   onPressed: () => sendCommand("ON"),
//                   child: const Text("Relay ON"),
//                 ),
//                 const SizedBox(width: 10),
//                 ElevatedButton(
//                   onPressed: () => sendCommand("OFF"),
//                   child: const Text("Relay OFF"),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
