import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_size/window_size.dart';
import 'package:flutter/scheduler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    setWindowTitle('MirrorX');
    setWindowMinSize(const Size(800, 600));
  }
  runApp(const MyApp());
  startHttpServer(); // Start the HTTP server to listen for requests from the Android app
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MirrorX',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      home: const ScrcpyPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ScrcpyController {
  // Singleton pattern
  static final ScrcpyController _instance = ScrcpyController._internal();
  factory ScrcpyController() => _instance;
  ScrcpyController._internal();

  // Variables
  String? scrcpyPath;
  final List<String> log = [];
  Process? scrcpyProcess;
  bool isMirroring = false;
  bool isRecording = false;

  bool enableRecording = false;
  String recordingPath = '';
  bool enableWireless = false;
  String deviceIp = '';
  String windowsIp = '';

  String customRecordingName = '';
  final logStreamController = StreamController<String>.broadcast();

  // Methods
  Future<void> prepareScrcpyExecutable() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final List<String> files = [
        'adb.exe',
        'AdbWinApi.dll',
        'AdbWinUsbApi.dll',
        'scrcpy.exe',
        // Add other necessary files as needed
      ];

      for (String file in files) {
        final byteData = await rootBundle.load('assets/$file');
        final extractedFile = File('${tempDir.path}/$file');
        await extractedFile.writeAsBytes(byteData.buffer.asUint8List());
      }

      scrcpyPath = '${tempDir.path}/scrcpy.exe';

      addLog('scrcpy.exe and dependencies extracted to: ${tempDir.path}');
    } catch (e) {
      addLog('Failed to extract scrcpy.exe and dependencies: $e');
    }
  }

Future<void> startScrcpy() async {
  if (scrcpyPath == null) {
    addLog('scrcpy.exe is not ready.');
    return;
  }

  if (enableWireless) {
    await setDeviceIp();
    if (deviceIp.isEmpty) {
      addLog('Failed to detect device IP. Ensure the device is connected over Wi-Fi.');
      return;
    }

    final connectResult = await Process.run('adb', ['connect', '$deviceIp:5555']);
    if (connectResult.exitCode != 0) {
      addLog('Failed to connect to the device over Wi-Fi: ${connectResult.stderr}');
      return;
    }
    addLog('Connected to device wirelessly: $deviceIp');
  }

  if (enableRecording) {
    await setRecordingPath();
    if (recordingPath.isEmpty) {
      addLog('Recording path is not set.');
      return;
    }
  }

  // Default arguments
  List<String> arguments = ['-m1920'];

  if (enableRecording && recordingPath.isNotEmpty) {
    arguments.addAll(['--record', recordingPath]);
    addLog('Recording to: $recordingPath');
    isRecording = true;
  }

  try {
    scrcpyProcess = await Process.start(scrcpyPath!, arguments);
    addLog('scrcpy started with resolution 1920x1080.');
    isMirroring = true;

    scrcpyProcess!.stdout.transform(utf8.decoder).listen((data) {
      addLog(data);
    });

    scrcpyProcess!.stderr.transform(utf8.decoder).listen((data) {
      if (data.contains('ERROR')) {
        addLog('Encountered error: $data');
        stopScrcpy();
        addLog('Retrying with default settings...');
        // Retry with a more basic configuration
        arguments = [];
        startScrcpy(); // Retry without specific resolution
      } else {
        addLog(data);
      }
    });

    scrcpyProcess!.exitCode.then((exitCode) {
      addLog('scrcpy exited with code $exitCode.');
      isMirroring = false;
      if (isRecording) {
        addLog('Recording saved to: $recordingPath');
        isRecording = false;
      }
    });
  } catch (e) {
    addLog('Failed to start scrcpy: $e');
  }
}


  Future<void> stopScrcpy() async {
    if (scrcpyProcess != null) {
      scrcpyProcess!.kill();
      scrcpyProcess = null;
      addLog('scrcpy stopped.');
    } else {
      addLog('scrcpy is not running.');
    }
    isMirroring = false;
    isRecording = false;
  }

  Future<void> getWindowsIpAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            windowsIp = addr.address;
            addLog('Detected Windows IP: $windowsIp');
            return;
          }
        }
      }
      addLog('Could not find a valid IPv4 address.');
    } catch (e) {
      addLog('Failed to get Windows IP: $e');
    }
  }

  bool isValidRecordingName(String name) {
    final invalidCharacters = RegExp(r'[<>:"/\\|?*]');
    return !invalidCharacters.hasMatch(name) && name.isNotEmpty;
  }

  Future<void> setDeviceIp() async {
    final result = await Process.run('adb', ['shell', 'ip', 'route']);
    if (result.exitCode != 0) {
      addLog('Failed to get device IP: ${result.stderr}');
      return;
    }
    final output = result.stdout as String;
    final ipPattern = RegExp(r'src\s+(\d+\.\d+\.\d+\.\d+)');
    final match = ipPattern.firstMatch(output);
    if (match != null) {
      deviceIp = match.group(1) ?? '';
      addLog('Device IP detected: $deviceIp');
    } else {
      addLog('IP address not found in route info.');
    }
  }

  Future<void> setRecordingPath() async {
    try {
      final directory = Directory('${Platform.environment['USERPROFILE']}\\Videos');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      if (!isValidRecordingName(customRecordingName)) {
        addLog('Invalid recording name. Using default name.');
        customRecordingName = 'scrcpy_recording_${DateTime.now().millisecondsSinceEpoch}';
      }

      recordingPath = '${directory.path}\\$customRecordingName.mkv';
      addLog('Recording will be saved as: $recordingPath');
    } catch (e) {
      addLog('Failed to set recording path: $e');
    }
  }

  void addLog(String message) {
    final timestamp = DateTime.now().toLocal().toIso8601String();
    final logMessage = '[$timestamp] $message';
    log.add(logMessage);
    logStreamController.add(logMessage);
    print(logMessage); // For debugging purposes
  }

  void clearLog() {
    log.clear();
    logStreamController.add('Log cleared.');
  }
}

class ScrcpyPage extends StatefulWidget {
  const ScrcpyPage({Key? key}) : super(key: key);

  @override
  _ScrcpyPageState createState() => _ScrcpyPageState();
}

class _ScrcpyPageState extends State<ScrcpyPage> {
  final ScrcpyController _controller = ScrcpyController();
  late StreamSubscription<String> _logSubscription;

  @override
  void initState() {
    super.initState();
    _controller.prepareScrcpyExecutable();
    _controller.getWindowsIpAddress();

    _logSubscription = _controller.logStreamController.stream.listen((log) {
      setState(() {}); // Update UI when new log arrives
    });
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        SchedulerBinding.instance!.window.platformBrightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MirrorX'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode),
            onPressed: () {
              final newThemeMode =
                  isDarkMode ? ThemeMode.light : ThemeMode.dark;
              setState(() {
                SystemChrome.setSystemUIOverlayStyle(
                  isDarkMode
                      ? SystemUiOverlayStyle.dark
                      : SystemUiOverlayStyle.light,
                );
              });
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          children: [
            _buildIpDisplay(),
            const SizedBox(height: 10),
            _buildRecordingNameInput(),
            const SizedBox(height: 10),
            _buildSwitches(),
            const SizedBox(height: 20),
            _buildControlButtons(),
            const SizedBox(height: 20),
            _buildLogSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildIpDisplay() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: TextEditingController(
                text: _controller.windowsIp.isNotEmpty
                    ? _controller.windowsIp
                    : 'Detecting...'),
            decoration: const InputDecoration(
              labelText: 'Windows IP Address',
              border: OutlineInputBorder(),
            ),
            readOnly: true,
          ),
        ),
        const SizedBox(width: 10),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            _controller.getWindowsIpAddress();
          },
          tooltip: 'Refresh IP Address',
        ),
      ],
    );
  }

  Widget _buildRecordingNameInput() {
    return TextField(
      decoration: const InputDecoration(
        labelText: 'Custom Recording Name',
        hintText: 'Enter recording name',
        border: OutlineInputBorder(),
      ),
      onChanged: (value) {
        _controller.customRecordingName = value;
      },
    );
  }

  Widget _buildSwitches() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Enable Wireless Mode'),
          value: _controller.enableWireless,
          onChanged: (value) {
            setState(() {
              _controller.enableWireless = value;
            });
          },
        ),
        SwitchListTile(
          title: const Text('Enable Recording'),
          value: _controller.enableRecording,
          onChanged: (value) {
            setState(() {
              _controller.enableRecording = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Mirroring'),
          onPressed:
              _controller.isMirroring ? null : () => _controller.startScrcpy(),
          style: ElevatedButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          ),
        ),
        const SizedBox(width: 20),
        ElevatedButton.icon(
          icon: const Icon(Icons.stop),
          label: const Text('Stop Mirroring'),
          onPressed:
              _controller.isMirroring ? () => _controller.stopScrcpy() : null,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            backgroundColor: Colors.red, // Updated
          ),
        ),
        const SizedBox(width: 20),
        ElevatedButton.icon(
          icon: const Icon(Icons.clear_all),
          label: const Text('Clear Log'),
          onPressed: () => _controller.clearLog(),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            backgroundColor: Colors.green, // Updated
           )
        ),
      ],
    );
  }

  Widget _buildLogSection() {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.grey),
        ),
        padding: const EdgeInsets.all(10),
        child: SingleChildScrollView(
          child: Text(
            _controller.log.join('\n'),
            style: const TextStyle(
              color: Colors.greenAccent,
              fontFamily: 'Courier',
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> startHttpServer() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
  print('HTTP Server running on http://${server.address.address}:${server.port}');
  final controller = ScrcpyController();

  await for (HttpRequest request in server) {
    if (request.method == 'POST') {
      request.response.headers.contentType = ContentType.json;
      final requestData = await utf8.decoder.bind(request).join();
      try {
        final data = jsonDecode(requestData);
        final action = data['action'];
        switch (action) {
          case 'connect':
            await controller.setDeviceIp();
            if (controller.deviceIp.isNotEmpty) {
              request.response.write(jsonEncode({
                'status': 'success',
                'message': 'Device IP set to ${controller.deviceIp}'
              }));
            } else {
              request.response.write(jsonEncode({
                'status': 'error',
                'message': 'Failed to set device IP'
              }));
            }
            break;
          case 'start':
            SchedulerBinding.instance!.addPostFrameCallback((_) async {
              controller.enableRecording = data['enableRecording'] ?? false;
              controller.enableWireless = data['enableWireless'] ?? false;
              controller.customRecordingName =
                  data['recordingName'] ?? 'scrcpy_recording';
              await controller.startScrcpy();
            });
            request.response.write(jsonEncode({
              'status': 'success',
              'message': 'Started mirroring'
            }));
            break;
          case 'stop':
            SchedulerBinding.instance!.addPostFrameCallback((_) async {
              await controller.stopScrcpy();
            });
            request.response.write(jsonEncode({
              'status': 'success',
              'message': 'Stopped mirroring'
            }));
            break;
          case 'enable_tcpip':
            final result = await Process.run('adb', ['tcpip', '5555']);
            if (result.exitCode == 0) {
              request.response.write(jsonEncode({
                'status': 'success',
                'message': 'TCP/IP mode enabled on port 5555'
              }));
            } else {
              request.response.write(jsonEncode({
                'status': 'error',
                'message': 'Failed to enable TCP/IP mode: ${result.stderr}'
              }));
            }
            break;
          default:
            request.response.write(jsonEncode({
              'status': 'error',
              'message': 'Unknown action: $action'
            }));
        }
      } catch (e) {
        request.response.write(jsonEncode({
          'status': 'error',
          'message': 'Invalid request data: $e'
        }));
      }
      await request.response.close();
    } else {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..write('Unsupported request: ${request.method}.');
      await request.response.close();
    }
  }
}
