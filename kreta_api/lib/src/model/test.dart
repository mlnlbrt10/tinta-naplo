import '../extensions.dart';
import 'generic.dart';
import 'subject.dart';

class Test extends UidObj {
  final DateTime date;
  final DateTime reportDate;
  final String teacherName;
  final int lessonNumber;
  final Subject subject;
  final String subjectName;
  final String? theme;
  final NameUidDesc method;
  final UidObj classGroup;

  Test({
    required super.uid,
    required this.date,
    required this.reportDate,
    required this.teacherName,
    required this.lessonNumber,
    required this.subject,
    required this.subjectName,
    required this.theme,
    required this.method,
    required this.classGroup,
  });

  factory Test.fromJson(Map<String, dynamic> json) {
    final rawSubject = json['Tantargy'];
    final fallbackSubjectName = (json['TantargyNeve'] ??
            (rawSubject is Map ? rawSubject['Nev'] : null) ??
            '')
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
    final date =
        json.localDate('Datum') ?? json.localDate('BejelentesDatuma') ?? DateTime.now();
    final reportDate = json.localDate('BejelentesDatuma') ?? date;

    return Test(
      uid: (json['Uid'] ?? '').toString(),
      date: date,
      reportDate: reportDate,
      teacherName: (json['RogzitoTanarNeve'] ?? '').toString(),
      lessonNumber: (json['OrarendiOraOraszama'] as num?)?.toInt() ?? 0,
      subject: subject,
      subjectName:
          fallbackSubjectName.isNotEmpty ? fallbackSubjectName : subject.name,
      theme: json['Temaja'] as String?,
      method: json.nameUidDesc('Modja') ?? NameUidDesc.EMPTY,
      classGroup: json.uid('OsztalyCsoport') ?? UidObj(uid: ''),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'Uid': uid,
        'Datum': date.toUtc().toIso8601String(),
        'BejelentesDatuma': reportDate.toUtc().toIso8601String(),
        'RogzitoTanarNeve': teacherName,
        'OrarendiOraOraszama': lessonNumber,
        'Tantargy': subject.toJson(),
        'TantargyNeve': subjectName,
        'Temaja': theme,
        'Modja': method.toJson(),
        'OsztalyCsoport': classGroup.toJson(),
      };

  @override
  String toString() {
    return 'Test('
        'uid: "$uid", '
        'date: $date, '
        'reportDate: $reportDate, '
        'teacherName: "$teacherName", '
        'lessonNumber: $lessonNumber, '
        'subject: $subject, '
        'subjectName: "$subjectName", '
        'theme: "$theme", '
        'method: $method, '
        'classGroup: $classGroup'
        ')';
  }
}
