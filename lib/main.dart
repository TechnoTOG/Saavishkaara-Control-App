import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Snack Track Payment QR',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const DataPage(),
    );
  }
}

class DataPage extends StatefulWidget {
  const DataPage({super.key});

  @override
  _DataPageState createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  final String apiUrl = "https://snacktrack-8bng.onrender.com/api/fetch-qr";
  final String webSocketUrl = "wss://snacktrack-8bng.onrender.com";
  final String registerUrl = "https://snacktrack-8bng.onrender.com/api/register-device";

  WebSocketChannel? _webSocketChannel;
  String lastQrCode = ""; // Store the last fetched QR code
  List<dynamic> dataList = [];
  FlutterLocalNotificationsPlugin notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    initializeNotifications();
    requestNotificationPermission();
    registerDevice();
    fetchData();
    connectWebSocket();
  }

  @override
  void dispose() {
    closeWebSocket();
    super.dispose();
  }

  // Initialize notifications
  void initializeNotifications() {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: androidSettings);
    notificationsPlugin.initialize(initializationSettings);
  }

  // Request notification permission
  Future<void> requestNotificationPermission() async {
    var status = await Permission.notification.status;
    if (!status.isGranted) {
      status = await Permission.notification.request();
      if (status.isGranted) {
        print("Notification permission granted.");
      } else {
        print("Notification permission denied.");
      }
    }
  }

  // WebSocket connection
  void connectWebSocket() {
    _webSocketChannel = WebSocketChannel.connect(Uri.parse(webSocketUrl));

    _webSocketChannel?.stream.listen((message) {
      handleWebSocketMessage(message);
    }, onError: (error) {
      print("WebSocket Error: $error");
    }, onDone: () {
      print("WebSocket connection closed.");
    });
  }

  // Close WebSocket connection
  void closeWebSocket() {
    _webSocketChannel?.sink.close(status.normalClosure);
  }

  // Handle WebSocket message
  void handleWebSocketMessage(String message) {
    try {
      final data = jsonDecode(message);
      if (data is Map<String, dynamic>) {
        final newQrCode = data["qr"];
        if (newQrCode != lastQrCode) {
          dataList = [
            {
              "qr": newQrCode,
              "custname": data["custname"],
              "amount": data["amount"],
              "date": data["date"],
              "time": data["time"],
              "createdAt": DateTime.now().toString(),
            }
          ];
          lastQrCode = newQrCode;
          setState(() {});
          showNotification("New QR Code", "A new QR code has been received.");
        }
      }
    } catch (e) {
      print("Error handling WebSocket message: $e");
    }
  }

  // Show system notification
  Future<void> showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'channel_id',
      'channel_name',
      importance: Importance.high,
      priority: Priority.high,
    );
    const notificationDetails = NotificationDetails(android: androidDetails);
    await notificationsPlugin.show(0, title, body, notificationDetails);
  }

  // Fetch QR data from API
  Future<void> fetchData() async {
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final newQrCode = data["qr"];
          if (newQrCode != lastQrCode) {
            dataList = [
              {
                "qr": newQrCode,
                "custname": data["custname"],
                "amount": data["amount"],
                "date": data["date"],
                "time": data["time"],
                "createdAt": DateTime.now().toString(),
              }
            ];
            lastQrCode = newQrCode;
            setState(() {});
          }
        }
      } else {
        print("Error fetching data: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching data: $e");
    }
  }

  // Register device with backend
  Future<void> registerDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final isRegistered = prefs.getBool("isRegistered") ?? false;
    if (isRegistered) return;

    final deviceInfoPlugin = DeviceInfoPlugin();
    Map<String, dynamic> deviceData = {};
    if (Theme.of(context).platform == TargetPlatform.android) {
      final androidInfo = await deviceInfoPlugin.androidInfo;
      deviceData = {
        "id": androidInfo.id,
        "model": androidInfo.model,
        "platform": "Android",
      };
    } else if (Theme.of(context).platform == TargetPlatform.iOS) {
      final iosInfo = await deviceInfoPlugin.iosInfo;
      deviceData = {
        "id": iosInfo.identifierForVendor,
        "model": iosInfo.name,
        "platform": "iOS",
      };
    }

    final payload = {
      "uniqueId": deviceData['id'],
      "deviceName": deviceData['model'],
      "platform": deviceData['platform'],
    };

    final response = await http.post(
      Uri.parse(registerUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      prefs.setBool("isRegistered", true);
      print("Device registered successfully!");
    } else {
      print("Failed to register device: ${response.body}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Snack Track Payment QR"),
      ),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: fetchData,
            child: const Text("Refresh Now"),
          ),
          Expanded(
            child: Center(
              child: dataList.isNotEmpty && dataList[0]['qr'] != null
                  ? SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.memory(
                      base64Decode(dataList[0]['qr'].split(',')[1]),
                      fit: BoxFit.contain,
                      width: 300,
                      height: 300,
                    ),
                    const SizedBox(height: 16),
                    Text("Customer: ${dataList[0]['custname']}"),
                    Text("Amount: ₹${dataList[0]['amount']}"),
                    Text("Date: ${dataList[0]['date']}"),
                    Text("Time: ${dataList[0]['time']}"),
                    const SizedBox(height: 16),
                    Text("Created At: ${dataList[0]['createdAt']}"),
                  ],
                ),
              )
                  : const Text(
                "No QR Code Found",
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
