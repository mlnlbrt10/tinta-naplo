import '../extensions.dart';
import 'generic.dart';
import 'subject.dart';

class Homework extends UidObj {
  final Subject subject;
  final String subjectName;
  final String teacherName;
  final String description;
  final DateTime startDate;
  final DateTime dueDate;
  final DateTime creationDate;
  final bool isCreatedByTeacher;
  final bool isDone;
  final bool canBeSubmitted;
  final UidObj classGroup;
  final bool canAttach;

  Homework({
    required super.uid,
    required this.subject,
    required this.subjectName,
    required this.teacherName,
    required this.description,
    required this.startDate,
    required this.dueDate,
    required this.creationDate,
    required this.isCreatedByTeacher,
    required this.isDone,
    required this.canBeSubmitted,
    required this.classGroup,
    required this.canAttach,
  });

  factory Homework.fromJson(Map<String, dynamic> json) {
    final rawSubject = json["Tantargy"];
    final fallbackSubjectName = (json["TantargyNeve"] ??
            (rawSubject is Map ? rawSubject["Nev"] : null) ??
            "")
        .toString();
    final subject = rawSubject is Map<String, dynamic>
        ? Subject.fromJson(rawSubject)
        : Subject(
            uid: fallbackSubjectName,
            name: fallbackSubjectName,
            category: NameUidDesc(
              uid: fallbackSubjectName,
              name: fallbackSubjectName,
              description: fallbackSubjectName,
            ),
            sortIndex: 0,
          );
    final subjectName =
        fallbackSubjectName.isNotEmpty ? fallbackSubjectName : subject.name;

    final startDate = json.localDate("FeladasDatuma") ??
        json.localDate("RogzitesIdopontja") ??
        json.localDate("HataridoDatuma") ??
        DateTime.now();
    final dueDate = json.localDate("HataridoDatuma") ?? startDate;
    final creationDate = json.localDate("RogzitesIdopontja") ?? startDate;

    final rawText = (json["Szoveg"] ?? "").toString();

    return Homework(
      uid: (json["Uid"] ?? json["Id"] ?? "").toString(),
      subject: subject,
      subjectName: subjectName,
      teacherName: (json["RogzitoTanarNeve"] ?? "").toString(),
      description: stripHtmlTags(rawText),
      startDate: startDate,
      dueDate: dueDate,
      creationDate: creationDate,
      isCreatedByTeacher: (json["IsTanarRogzitette"] as bool?) ?? true,
      isDone: (json["IsMegoldva"] as bool?) ?? false,
      canBeSubmitted: (json["IsBeadhato"] as bool?) ?? false,
      classGroup: json.uid("OsztalyCsoport") ?? UidObj(uid: ""),
      canAttach: (json["IsCsatolasEngedelyezes"] as bool?) ?? false,
    );
  }

  static String stripHtmlTags(String input) {
    if (input.isEmpty) return '';
    final withLineBreaks = input
        .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</\s*(p|div|li)\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<\s*li[^>]*>', caseSensitive: false), '• ');
    final withoutTags = withLineBreaks.replaceAll(RegExp(r'<[^>]*>'), '');
    final decoded = withoutTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&ndash;', '–')
        .replaceAll('&mdash;', '—');
    return decoded
        .split('\n')
        .map((line) => line.trim())
        .toList()
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  @override
  String toString() {
    return 'Homework('
        'uid: "$uid", '
        'subject: $subject, '
        'subjectName: "$subjectName", '
        'teacherName: "$teacherName", '
        'description: "$description", '
        'startDate: $startDate, '
        'dueDate: $dueDate, '
        'creationDate: $creationDate, '
        'isCreatedByTeacher: $isCreatedByTeacher, '
        'isDone: $isDone, '
        'canBeSubmitted: $canBeSubmitted, '
        'classGroup: $classGroup, '
        'canAttach: $canAttach'
        ')';
  }
}
