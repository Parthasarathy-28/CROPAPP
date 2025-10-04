// PROJECT: Smart Curriculum Activity & Attendance - Flutter MVP
// This textdoc contains the key files for a minimal Flutter MVP that you can open
// in VS Code and run. It implements:
// - Teacher side: start/stop session, rotating QR code
// - Student side: view timetable, scan QR to mark attendance
// - Simple rule-based activity recommendations for free periods
// - Local persistence using shared_preferences (for demo)
//
// Files included below as concatenated content. Create a Flutter project
// (flutter create smart_curriculum) and replace the contents of lib/main.dart
// and pubspec.yaml with the respective sections from this document.

/* ------------------ pubspec.yaml ------------------
name: smart_curriculum
description: A minimal MVP for Smart Curriculum Activity & Attendance
publish_to: 'none'
version: 0.1.0+1
environment:
  sdk: '>=2.18.0 <3.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.2
  qr_flutter: ^4.0.0
  qr_code_scanner: ^1.0.0
  shared_preferences: ^2.1.1
  uuid: ^3.0.6

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^2.0.0

flutter:
  uses-material-design: true

-------------------------------------------------- */

/* ------------------ lib/main.dart ------------------ */

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SmartCurriculumApp());
}

class SmartCurriculumApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Curriculum MVP',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [TeacherPage(), StudentPage(), AdminPage()];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Smart Curriculum MVP'),
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.meeting_room), label: 'Teacher'),
          BottomNavigationBarItem(icon: Icon(Icons.school), label: 'Student'),
          BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings), label: 'Admin'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

/* ---------- Simple in-memory & local storage models ---------- */

class Session {
  String id; // uuid
  String room;
  DateTime startedAt;
  bool active;
  String salt; // for QR generation

  Session({required this.id, required this.room, required this.startedAt, required this.active, required this.salt});

  Map<String, dynamic> toJson() => {
        'id': id,
        'room': room,
        'startedAt': startedAt.toIso8601String(),
        'active': active,
        'salt': salt,
      };

  static Session fromJson(Map<String, dynamic> j) => Session(
      id: j['id'],
      room: j['room'],
      startedAt: DateTime.parse(j['startedAt']),
      active: j['active'],
      salt: j['salt']);
}

class AttendanceRecord {
  String studentId;
  String studentName;
  String sessionId;
  DateTime ts;

  AttendanceRecord({required this.studentId, required this.studentName, required this.sessionId, required this.ts});

  Map<String, dynamic> toJson() => {
        'studentId': studentId,
        'studentName': studentName,
        'sessionId': sessionId,
        'ts': ts.toIso8601String()
      };

  static AttendanceRecord fromJson(Map<String, dynamic> j) => AttendanceRecord(
      studentId: j['studentId'], studentName: j['studentName'], sessionId: j['sessionId'], ts: DateTime.parse(j['ts']));
}

/* ---------- Storage helpers ---------- */

class LocalStore {
  static const String _kSessions = 'sessions_v1';
  static const String _kAttendance = 'attendance_v1';
  static const String _kStudentProfile = 'student_profile_v1';

  static Future<void> saveSession(Session s) async {
    final sp = await SharedPreferences.getInstance();
    List<String> list = sp.getStringList(_kSessions) ?? [];
    list.removeWhere((e) => jsonDecode(e)['id'] == s.id);
    list.add(jsonEncode(s.toJson()));
    await sp.setStringList(_kSessions, list);
  }

  static Future<List<Session>> getSessions() async {
    final sp = await SharedPreferences.getInstance();
    List<String> list = sp.getStringList(_kSessions) ?? [];
    return list.map((e) => Session.fromJson(jsonDecode(e))).toList();
  }

  static Future<void> saveAttendance(AttendanceRecord a) async {
    final sp = await SharedPreferences.getInstance();
    List<String> list = sp.getStringList(_kAttendance) ?? [];
    list.add(jsonEncode(a.toJson()));
    await sp.setStringList(_kAttendance, list);
  }

  static Future<List<AttendanceRecord>> getAttendance() async {
    final sp = await SharedPreferences.getInstance();
    List<String> list = sp.getStringList(_kAttendance) ?? [];
    return list.map((e) => AttendanceRecord.fromJson(jsonDecode(e))).toList();
  }

  static Future<void> saveStudentProfile(Map<String, dynamic> profile) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kStudentProfile, jsonEncode(profile));
  }

  static Future<Map<String, dynamic>?> getStudentProfile() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_kStudentProfile);
    if (s == null) return null;
    return jsonDecode(s);
  }
}

/* ------------------ Teacher Page ------------------ */

class TeacherPage extends StatefulWidget {
  @override
  _TeacherPageState createState() => _TeacherPageState();
}

class _TeacherPageState extends State<TeacherPage> {
  Session? _current;
  Timer? _tick;
  List<AttendanceRecord> _attendees = [];

  @override
  void initState() {
    super.initState();
    _loadCurrent();
    _loadAttendees();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    final sessions = await LocalStore.getSessions();
    final active = sessions.where((s) => s.active).toList();
    if (active.isNotEmpty) setState(() => _current = active.last);
  }

  Future<void> _loadAttendees() async {
    final a = await LocalStore.getAttendance();
    setState(() => _attendees = a);
  }

  void _startSession() async {
    final id = Uuid().v4();
    final salt = Uuid().v4().substring(0, 8);
    final s = Session(id: id, room: 'Room A', startedAt: DateTime.now(), active: true, salt: salt);
    await LocalStore.saveSession(s);
    setState(() {
      _current = s;
    });
    _tick?.cancel();
    _tick = Timer.periodic(Duration(seconds: 1), (_) => setState(() {}));
  }

  void _stopSession() async {
    if (_current == null) return;
    final closed = Session(id: _current!.id, room: _current!.room, startedAt: _current!.startedAt, active: false, salt: _current!.salt);
    await LocalStore.saveSession(closed);
    setState(() => _current = null);
    _tick?.cancel();
  }

  String _buildQrPayload() {
    if (_current == null) return '';
    final epoch30 = (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 30000);
    final token = base64Url.encode(utf8.encode('${_current!.id}|${_current!.salt}|$epoch30'));
    return token;
  }

  Future<void> _simulateStudentScan() async {
    // For demo: open dialog to add a student name/ID
    final res = await showDialog<Map<String, String>>(context: context, builder: (ctx) {
      final idCtrl = TextEditingController(text: 'S' + DateTime.now().millisecondsSinceEpoch.toString().substring(8));
      final nameCtrl = TextEditingController(text: 'Demo Student');
      return AlertDialog(
        title: Text('Simulate student scan'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: idCtrl, decoration: InputDecoration(labelText: 'Student ID')),
          TextField(controller: nameCtrl, decoration: InputDecoration(labelText: 'Student Name')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: Text('Cancel')), TextButton(onPressed: () => Navigator.of(ctx).pop({'id': idCtrl.text, 'name': nameCtrl.text}), child: Text('Add'))],
      );
    });
    if (res == null || _current == null) return;
    final rec = AttendanceRecord(studentId: res['id']!, studentName: res['name']!, sessionId: _current!.id, ts: DateTime.now());
    await LocalStore.saveAttendance(rec);
    await _loadAttendees();
  }

  @override
  Widget build(BuildContext context) {
    final qrPayload = _buildQrPayload();
    final epoch = DateTime.now();
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            ElevatedButton.icon(onPressed: _current == null ? _startSession : _stopSession, icon: Icon(_current == null ? Icons.play_arrow : Icons.stop), label: Text(_current == null ? 'Start Session' : 'Stop Session')),
            SizedBox(width: 12),
            ElevatedButton.icon(onPressed: _simulateStudentScan, icon: Icon(Icons.person_add), label: Text('Simulate Student Scan')),
          ]),
          SizedBox(height: 12),
          if (_current != null) ...[
            Text('Session: ${_current!.id}', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Room: ${_current!.room} — started ${_current!.startedAt.toLocal()}'),
            SizedBox(height: 12),
            Center(child: Column(children: [
              Container(color: Colors.white, child: QrImage(data: qrPayload, version: QrVersions.auto, size: 220.0)),
              SizedBox(height: 8),
              Text('QR token rotates every 30s — current at ${epoch.toLocal().toIso8601String()}'),
            ])),
          ] else ...[
            Text('No active session', style: TextStyle(fontSize: 16)),
            SizedBox(height: 8),
            Text('Press Start Session to create a rotating QR that students can scan.'),
          ],
          SizedBox(height: 20),
          Text('Attendees (all-time):', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Expanded(child: _attendees.isEmpty ? Center(child: Text('No attendees yet')) : ListView.builder(itemCount: _attendees.length, itemBuilder: (ctx, i) {
            final a = _attendees[i];
            return ListTile(title: Text(a.studentName), subtitle: Text('${a.studentId} • ${a.ts.toLocal()} • session ${a.sessionId}'));
          })),
        ],
      ),
    );
  }
}

/* ------------------ Student Page ------------------ */

class StudentPage extends StatefulWidget {
  @override
  _StudentPageState createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {
  Map<String, dynamic>? _profile;
  List<AttendanceRecord> _attendance = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadAttendance();
  }

  Future<void> _loadProfile() async {
    final p = await LocalStore.getStudentProfile();
    if (p == null) {
      final defaultProfile = {'studentId': 'S1001', 'name': 'You', 'interests': ['programming', 'math'], 'goals': 'Finish project'};
      await LocalStore.saveStudentProfile(defaultProfile);
      setState(() => _profile = defaultProfile);
    } else setState(() => _profile = p);
  }

  Future<void> _loadAttendance() async {
    final a = await LocalStore.getAttendance();
    setState(() => _attendance = a);
  }

  void _openScanner() async {
    final result = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => QRScannerPage()));
    if (result == null) return;
    // result is token string
    final valid = await _validateAndSaveScan(result);
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(valid ? 'Attendance marked' : 'Invalid or expired QR'), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('OK'))]));
    await _loadAttendance();
  }

  Future<bool> _validateAndSaveScan(String token) async {
    // parse token: base64Url of 'sessionId|salt|epoch30'
    try {
      final decoded = utf8.decode(base64Url.decode(token));
      final parts = decoded.split('|');
      if (parts.length != 3) return false;
      final sid = parts[0];
      final salt = parts[1];
      final epoch = int.parse(parts[2]);
      // find session with id and salt and active
      final sessions = await LocalStore.getSessions();
      final session = sessions.firstWhere((s) => s.id == sid && s.salt == salt && s.active, orElse: () => throw 'no');
      // check epoch closeness (allow ±1 interval)
      final nowEpoch = (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 30000);
      if ((nowEpoch - epoch).abs() > 1) return false; // expired
      // save attendance
      final prof = _profile ?? {'studentId': 'unknown', 'name': 'unknown'};
      final rec = AttendanceRecord(studentId: prof['studentId'], studentName: prof['name'], sessionId: sid, ts: DateTime.now());
      await LocalStore.saveAttendance(rec);
      return true;
    } catch (e) {
      return false;
    }
  }

  List<Map<String, dynamic>> _sampleTimetableForToday() {
    // Simple sample with a free slot in between
    final today = DateTime.now();
    return [
      {'from': '${today.year}-${today.month}-${today.day} 09:00', 'to': '${today.year}-${today.month}-${today.day} 10:00', 'title': 'Math'},
      {'from': '${today.year}-${today.month}-${today.day} 10:00', 'to': '${today.year}-${today.month}-${today.day} 11:00', 'title': 'CS Lab'},
      {'from': '${today.year}-${today.month}-${today.day} 11:00', 'to': '${today.year}-${today.month}-${today.day} 12:00', 'title': 'Free Slot'},
      {'from': '${today.year}-${today.month}-${today.day} 12:00', 'to': '${today.year}-${today.month}-${today.day} 13:00', 'title': 'Physics'},
    ];
  }

  List<Map<String, String>> _recommendationsForFreeSlot() {
    final interests = List<String>.from(_profile?['interests'] ?? []);
    final recs = <Map<String, String>>[];
    if (interests.contains('programming')) {
      recs.add({'title': '30-min coding kata', 'why': 'Sharpens problem solving for CS lab'});
    }
    if (interests.contains('math')) {
      recs.add({'title': '20-min challenge: number theory problems', 'why': 'Prepares for Math class'});
    }
    recs.add({'title': 'Read article: career pathways in your field (15 min)', 'why': 'Goal alignment'});
    return recs;
  }

  @override
  Widget build(BuildContext context) {
    final timetable = _sampleTimetableForToday();
    final recs = _recommendationsForFreeSlot();
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Student Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Card(child: ListTile(title: Text('${_profile?['name'] ?? ''}'), subtitle: Text('ID: ${_profile?['studentId'] ?? ''}'))),
        SizedBox(height: 12),
        Row(children: [ElevatedButton.icon(onPressed: _openScanner, icon: Icon(Icons.qr_code_scanner), label: Text('Scan QR to mark attendance')), SizedBox(width: 12), ElevatedButton.icon(onPressed: () async { await _loadAttendance(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attendance reloaded'))); }, icon: Icon(Icons.refresh), label: Text('Refresh'))]),
        SizedBox(height: 12),
        Text('Today\'s Timetable', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        ...timetable.map((t) => Card(child: ListTile(title: Text(t['title']!), subtitle: Text('${t['from']} — ${t['to']}')))),
        SizedBox(height: 8),
        Text('Recommended activities for free slots', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ...recs.map((r) => Card(child: ListTile(title: Text(r['title']!), subtitle: Text(r['why']!))))
      ]),
    );
  }
}

/* ------------------ QR Scanner Page ------------------ */

class QRScannerPage extends StatefulWidget {
  @override
  _QRScannerPageState createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  Barcode? result;
  QRViewController? controller;

  @override
  void reassemble() {
    super.reassemble();
    if (controller != null) {
      controller!.pauseCamera();
      controller!.resumeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Scan QR')),
      body: Column(children: <Widget>[
        Expanded(flex: 5, child: QRView(key: qrKey, onQRViewCreated: _onQRViewCreated)),
        Expanded(flex: 1, child: Center(child: (result != null) ? Text('Scanned: ${result!.code}') : Text('Scan a QR code')))
      ]),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      controller.pauseCamera();
      Navigator.of(context).pop(scanData.code);
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}

/* ------------------ Admin Page (simple exports) ------------------ */

class AdminPage extends StatefulWidget {
  @override
  _AdminPageState createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<AttendanceRecord> _attendance = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = await LocalStore.getAttendance();
    setState(() => _attendance = a);
  }

  String _csvContent() {
    final sb = StringBuffer();
    sb.writeln('studentId,studentName,sessionId,timestamp');
    for (final a in _attendance) {
      sb.writeln('${a.studentId},${a.studentName},${a.sessionId},${a.ts.toIso8601String()}');
    }
    return sb.toString();
  }

  void _showCsv() {
    final csv = _csvContent();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('CSV Export'), content: SingleChildScrollView(child: SelectableText(csv)), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Close'))]));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(12.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Admin Console', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      SizedBox(height: 12),
      ElevatedButton.icon(onPressed: _load, icon: Icon(Icons.refresh), label: Text('Reload Attendance')),
      SizedBox(height: 8),
      ElevatedButton.icon(onPressed: _showCsv, icon: Icon(Icons.download), label: Text('Show CSV export')),
      SizedBox(height: 12),
      Expanded(child: _attendance.isEmpty ? Center(child: Text('No attendance yet')) : ListView.builder(itemCount: _attendance.length, itemBuilder: (ctx, i) {
        final a = _attendance[i];
        return ListTile(title: Text(a.studentName), subtitle: Text('${a.studentId} • ${a.ts.toLocal()} • ${a.sessionId}'));
      }))
    ]));
  }
}

/* ------------------ End of file ------------------ */
