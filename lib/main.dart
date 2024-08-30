import 'package:flutter/material.dart';
import 'package:window_size/window_size.dart';
import 'dart:io';
import 'dart:convert'; // Import for utf8.decoder
import 'package:process_run/process_run.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    setWindowTitle('Scrcpy Flutter Windows');
    setWindowMinSize(const Size(600, 400));
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scrcpy Flutter Windows',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ScrcpyPage(),
    );
  }
}

class ScrcpyPage extends StatefulWidget {
  const ScrcpyPage({Key? key}) : super(key: key);

  @override
  _ScrcpyPageState createState() => _ScrcpyPageState();
}

class _ScrcpyPageState extends State<ScrcpyPage> {
  String _scrcpyPath = '';
  String _log = '';
  Process? _scrcpyProcess;

  @override
  void initState() {
    super.initState();
    _initScrcpyPath();
  }

  Future<void> _initScrcpyPath() async {
    final appDir = await getApplicationSupportDirectory();
    setState(() {
      _scrcpyPath = '${appDir.path}\\scrcpy.exe';
    });
  }

  Future<void> _selectScrcpyExecutable() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['exe'],
    );

    if (result != null) {
      setState(() {
        _scrcpyPath = result.files.single.path!;
      });
    }
  }

  Future<void> _startScrcpy() async {
    if (!File(_scrcpyPath).existsSync()) {
      _addLog('scrcpy.exe not found. Please select the correct path.');
      return;
    }

    _addLog('Starting scrcpy...');
    try {
      _scrcpyProcess = await Process.start(_scrcpyPath, []);
      _scrcpyProcess!.stdout.transform(utf8.decoder).listen(_addLog); // Corrected here
      _scrcpyProcess!.stderr.transform(utf8.decoder).listen(_addLog); // Corrected here
      _addLog('scrcpy started.');
    } catch (e) {
      _addLog('Failed to start scrcpy: $e');
    }
  }

  void _stopScrcpy() {
    if (_scrcpyProcess != null) {
      _scrcpyProcess!.kill();
      _scrcpyProcess = null;
      _addLog('scrcpy stopped.');
    } else {
      _addLog('scrcpy is not running.');
    }
  }

  void _addLog(dynamic message) { // Updated to accept dynamic
    setState(() {
      _log += '$message\n';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scrcpy Flutter Windows')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('scrcpy path: $_scrcpyPath')),
                ElevatedButton(
                  onPressed: _selectScrcpyExecutable,
                  child: const Text('Select scrcpy.exe'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _startScrcpy,
                  child: const Text('Start scrcpy'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _stopScrcpy,
                  child: const Text('Stop scrcpy'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Log:'),
            Expanded(
              child: SingleChildScrollView(
                child: Text(_log),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
