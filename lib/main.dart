// import 
import 'package:flutter/material.dart' as flutter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestione Corsi di Sopravvivenza',
      theme: ThemeData(
        primaryColor: Color(0xFF2a4d3a),
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF2a4d3a)),
        useMaterial3: true,
      ),
      home: CourseManagementPage(),
    );
  }
}

class Course {
  final DateTime startDate;
  final DateTime endDate;
  final String course;
  final String notes;
  final List<String> instructors;

  Course({
    required this.startDate,
    required this.endDate,
    required this.course,
    required this.notes,
    required this.instructors,
  });
}

class CourseManagementPage extends StatefulWidget {
  @override
  _CourseManagementPageState createState() => _CourseManagementPageState();
}

class _CourseManagementPageState extends State<CourseManagementPage> {
  List<Course> allCourses = [];
  List<Course> filteredCourses = [];
  bool dataLoaded = false;
  bool isLoading = false;
  String? errorMessage;
  
  // Filtri
  String selectedInstructor = '';
  String selectedCourse = '';
  int selectedMonth = -1;
  
  // Vista corrente
  bool showCalendarView = false;
  DateTime currentCalendarDate = DateTime.now();
  
  // Controller per URL
  final TextEditingController urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    filteredCourses = allCourses;
  }

  // Funzione per normalizzare URL Google Sheets
  Map<String, String> normalizeGoogleSheetsUrl(String url) {
    final patterns = [
      RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)'),
      RegExp(r'/document/d/([a-zA-Z0-9-_]+)'),
      RegExp(r'id=([a-zA-Z0-9-_]+)'),
    ];
    
    String? fileId;
    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        fileId = match.group(1);
        break;
      }
    }
    
    if (fileId == null) {
      throw Exception('Non riesco a estrarre l\'ID del foglio dall\'URL fornito');
    }
    
    String gid = '0';
    final gidMatch = RegExp(r'[#&]gid=([0-9]+)').firstMatch(url);
    if (gidMatch != null) {
      gid = gidMatch.group(1)!;
    }
    
    return {
      'fileId': fileId,
      'gid': gid,
      'csvUrl': 'https://docs.google.com/spreadsheets/d/$fileId/export?format=csv&gid=$gid',
    };
  }

  // Funzione per caricare dati da Google Sheets
  Future<void> loadSheetData() async {
    if (urlController.text.trim().isEmpty) {
      setState(() {
        errorMessage = 'Inserisci il link del Google Sheet';
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final urls = normalizeGoogleSheetsUrl(urlController.text.trim());
      final response = await http.get(
        Uri.parse(urls['csvUrl']!),
        headers: {'Accept': 'text/csv,text/plain,*/*'},
      );

      if (response.statusCode != 200) {
        throw Exception('Errore HTTP: ${response.statusCode}');
      }

      final csvText = response.body;
      if (csvText.trim().isEmpty) {
        throw Exception('Il foglio sembra essere vuoto');
      }

      final courses = parseCsvData(csvText);
      
      if (courses.isEmpty) {
        throw Exception('Nessun corso valido trovato nel foglio');
      }

      setState(() {
        allCourses = courses;
        dataLoaded = true;
        isLoading = false;
      });
      
      applyFilters();
      
    } catch (error) {
      setState(() {
        isLoading = false;
        errorMessage = error.toString();
      });
    }
  }

  // Funzione per caricare file locale
  Future<void> loadLocalFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
      );

      if (result != null && result.files.single.bytes != null) {
        setState(() {
          isLoading = true;
          errorMessage = null;
        });

        final file = result.files.single;
        List<Course> courses = [];

        if (file.extension?.toLowerCase() == 'csv') {
          final csvText = String.fromCharCodes(file.bytes!);
          courses = parseCsvData(csvText);
        } else if (file.extension?.toLowerCase() == 'xlsx' || 
                   file.extension?.toLowerCase() == 'xls') {
          courses = await parseExcelData(file.bytes!);
        }

        if (courses.isEmpty) {
          throw Exception('Nessun corso valido trovato nel file');
        }

        setState(() {
          allCourses = courses;
          dataLoaded = true;
          isLoading = false;
        });
        
        applyFilters();
      }
    } catch (error) {
      setState(() {
        isLoading = false;
        errorMessage = error.toString();
      });
    }
  }

  // Funzione per parsare CSV
  List<Course> parseCsvData(String csvText) {
    final courses = <Course>[];
    final lines = const LineSplitter().convert(csvText);
    
    // Salta la prima riga (intestazioni)
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      
      final fields = const CsvToListConverter().convert(line, shouldParseNumbers: false)[0];
      
      if (fields.length < 5) continue;
      
      final startDate = fields[0]?.toString().trim() ?? '';
      final endDate = fields[1]?.toString().trim() ?? '';
      final course = fields[2]?.toString().trim() ?? '';
      final notes = fields[3]?.toString().trim() ?? '';
      
      // Estrai istruttori
      final instructors = <String>[];
      for (int j = 4; j < fields.length && j < 8; j++) {
        final instructor = fields[j]?.toString().trim();
        if (instructor != null && instructor.isNotEmpty) {
          instructors.add(instructor);
        }
      }
      
      if (course.isEmpty || instructors.isEmpty) continue;
      
      final dateToUse = startDate.isNotEmpty ? startDate : endDate;
      if (dateToUse.isEmpty) continue;
      
      try {
        final parsedStartDate = DateTime.parse(dateToUse);
        final parsedEndDate = endDate.isNotEmpty ? DateTime.parse(endDate) : parsedStartDate;
        
        courses.add(Course(
          startDate: parsedStartDate,
          endDate: parsedEndDate,
          course: course,
          notes: notes,
          instructors: instructors,
        ));
      } catch (e) {
        // Data non valida, salta questa riga
        continue;
      }
    }
    
    return courses;
  }

  // Funzione per parsare Excel
  Future<List<Course>> parseExcelData(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    final courses = <Course>[];
    
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet == null) return courses;
    
    // Salta la prima riga (intestazioni)
    for (int i = 1; i < sheet.maxRows; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty) continue;
      
      final startDate = row[0]?.value?.toString().trim() ?? '';
      final endDate = row[1]?.value?.toString().trim() ?? '';
      final course = row[2]?.value?.toString().trim() ?? '';
      final notes = row[3]?.value?.toString().trim() ?? '';
      
      // Estrai istruttori
      final instructors = <String>[];
      for (int j = 4; j < row.length && j < 8; j++) {
        final instructor = row[j]?.value?.toString().trim();
        if (instructor != null && instructor.isNotEmpty) {
          instructors.add(instructor);
        }
      }
      
      if (course.isEmpty || instructors.isEmpty) continue;
      
      final dateToUse = startDate.isNotEmpty ? startDate : endDate;
      if (dateToUse.isEmpty) continue;
      
      try {
        final parsedStartDate = DateTime.parse(dateToUse);
        final parsedEndDate = endDate.isNotEmpty ? DateTime.parse(endDate) : parsedStartDate;
        
        courses.add(Course(
          startDate: parsedStartDate,
          endDate: parsedEndDate,
          course: course,
          notes: notes,
          instructors: instructors,
        ));
      } catch (e) {
        continue;
      }
    }
    
    return courses;
  }

  // Funzione per applicare i filtri
  void applyFilters() {
    setState(() {
      filteredCourses = allCourses.where((course) {
        // Filtro istruttore
        if (selectedInstructor.isNotEmpty && 
            !course.instructors.any((instructor) => 
                instructor.toLowerCase().contains(selectedInstructor.toLowerCase()))) {
          return false;
        }
        
        // Filtro corso
        if (selectedCourse.isNotEmpty && 
            !course.course.toLowerCase().contains(selectedCourse.toLowerCase())) {
          return false;
        }
        
        // Filtro mese
        if (selectedMonth >= 0 && course.startDate.month - 1 != selectedMonth) {
          return false;
        }
        
        return true;
      }).toList();
      
      // Ordina per data
      filteredCourses.sort((a, b) => a.startDate.compareTo(b.startDate));
    });
  }

  // Widget per la sezione di caricamento dati
  Widget buildDataLoadingSection() {
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📋 Caricamento Dati',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('Incolla qui il link del tuo Google Sheet:'),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: urlController,
                    decoration: InputDecoration(
                      hintText: 'https://docs.google.com/spreadsheets/d/...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => loadSheetData(),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: isLoading ? null : loadSheetData,
                  child: Text('Carica Dati'),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text('💡 Tip: Assicurati che il foglio sia condiviso come "Chiunque abbia il link può visualizzare".'),
            Divider(),
            Text('Oppure carica un file locale:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: isLoading ? null : loadLocalFile,
              icon: Icon(Icons.file_upload),
              label: Text('Carica File (CSV/Excel)'),
            ),
            if (errorMessage != null) ...[
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  // Usa:
                  border: flutter.Border.all(color: Colors.red.shade200),
                  //border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('❌ Errore nel caricamento', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text(errorMessage!),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Widget per i controlli e filtri
  Widget buildControlsSection() {
    if (!dataLoaded) return SizedBox.shrink();
    
    final instructors = allCourses.expand((c) => c.instructors).toSet().toList()..sort();
    final courseTypes = allCourses.map((c) => c.course).toSet().toList()..sort();
    final months = [
      'Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
      'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre'
    ];

    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // Filtri
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Filtra per istruttore',
                      border: OutlineInputBorder(),
                    ),
                    value: selectedInstructor.isEmpty ? null : selectedInstructor,
                    items: [
                      DropdownMenuItem(value: '', child: Text('Tutti gli istruttori')),
                      ...instructors.map((instructor) => 
                        DropdownMenuItem(value: instructor, child: Text(instructor))),
                    ],
                    onChanged: (value) {
                      selectedInstructor = value ?? '';
                      applyFilters();
                    },
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Filtra per corso',
                      border: OutlineInputBorder(),
                    ),
                    value: selectedCourse.isEmpty ? null : selectedCourse,
                    items: [
                      DropdownMenuItem(value: '', child: Text('Tutti i corsi')),
                      ...courseTypes.map((course) => 
                        DropdownMenuItem(value: course, child: Text(course))),
                    ],
                    onChanged: (value) {
                      selectedCourse = value ?? '';
                      applyFilters();
                    },
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<int>(
                    decoration: InputDecoration(
                      labelText: 'Filtra per mese',
                      border: OutlineInputBorder(),
                    ),
                    value: selectedMonth == -1 ? null : selectedMonth,
                    items: [
                      DropdownMenuItem(value: -1, child: Text('Tutti i mesi')),
                      ...months.asMap().entries.map((entry) => 
                        DropdownMenuItem(value: entry.key, child: Text(entry.value))),
                    ],
                    onChanged: (value) {
                      selectedMonth = value ?? -1;
                      applyFilters();
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            // Toggle vista
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: showCalendarView ? () => setState(() => showCalendarView = false) : null,
                  icon: Icon(Icons.list),
                  label: Text('Lista'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !showCalendarView ? Theme.of(context).primaryColor : null,
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: !showCalendarView ? () => setState(() => showCalendarView = true) : null,
                  icon: Icon(Icons.calendar_month),
                  label: Text('Calendario'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: showCalendarView ? Theme.of(context).primaryColor : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Widget per la vista lista
  Widget buildListView() {
    if (filteredCourses.isEmpty) {
      return Center(
        child: Text('Nessun corso trovato con i filtri selezionati.',
                    style: TextStyle(fontSize: 16)),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: filteredCourses.length,
      itemBuilder: (context, index) {
        final course = filteredCourses[index];
        final dateFormatter = DateFormat('dd/MM/yyyy');
        
        final dateRange = course.startDate.isAtSameMomentAs(course.endDate)
            ? dateFormatter.format(course.startDate)
            : '${dateFormatter.format(course.startDate)} - ${dateFormatter.format(course.endDate)}';

        return Card(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        course.course,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      dateRange,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text('👨‍🏫 Istruttori:', style: TextStyle(fontWeight: FontWeight.w500)),
                SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: course.instructors.map((instructor) => 
                    Chip(
                      label: Text(instructor, style: TextStyle(fontSize: 12)),
                      backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    ),
                  ).toList(),
                ),
                if (course.notes.isNotEmpty) ...[
                  SizedBox(height: 8),
                  Text('📝 ${course.notes}', style: TextStyle(fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // Widget per la vista calendario (semplificata)
  Widget buildCalendarView() {
    final monthFormatter = DateFormat('MMMM yyyy', 'it');
    
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      currentCalendarDate = DateTime(
                        currentCalendarDate.year,
                        currentCalendarDate.month - 1,
                      );
                    });
                  },
                  icon: Icon(Icons.arrow_back),
                ),
                Text(
                  monthFormatter.format(currentCalendarDate),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      currentCalendarDate = DateTime(
                        currentCalendarDate.year,
                        currentCalendarDate.month + 1,
                      );
                    });
                  },
                  icon: Icon(Icons.arrow_forward),
                ),
              ],
            ),
            SizedBox(height: 16),
            // Lista corsi del mese corrente
            ...filteredCourses
                .where((course) => 
                    course.startDate.year == currentCalendarDate.year &&
                    course.startDate.month == currentCalendarDate.month)
                .map((course) => ListTile(
                      leading: CircleAvatar(
                        child: Text(course.startDate.day.toString()),
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      title: Text(course.course),
                      subtitle: Text(course.instructors.join(', ')),
                    ))
                .toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🏕️ Team Adventure'),
        //subtitle: Text('Pianificazione e gestione corsi per il gruppo'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (!dataLoaded) buildDataLoadingSection(),
            if (isLoading) 
              Center(child: CircularProgressIndicator()),
            buildControlsSection(),
            if (dataLoaded && !isLoading) ...[
              if (!showCalendarView) buildListView(),
              if (showCalendarView) buildCalendarView(),
            ],
          ],
        ),
      ),
    );
  }
}
