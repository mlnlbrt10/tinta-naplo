import '../extensions.dart';
import 'generic.dart';
import 'subject.dart';

class Omission extends UidObj {
  final Subject subject;
  final OmittedLesson? lesson;
  final DateTime date;
  final String teacher;
  final NameUidDesc? type;
  final NameUidDesc? mode;
  final int? lateForMin;
  final DateTime createdAt;
  final OmissionState state;
  final NameUidDesc? proofType;
  final UidObj? classGroup;

  Omission({
    required super.uid,
    required this.subject,
    required this.lesson,
    required this.date,
    required this.teacher,
    this.type,
    this.mode,
    this.lateForMin,
    required this.createdAt,
    required this.state,
    required this.proofType,
    this.classGroup,
  });

  factory Omission.fromJson(Map<String, dynamic> json) {
    final rawSubject = json['Tantargy'];
    final subject = rawSubject is Map<String, dynamic>
        ? Subject.fromJson(rawSubject)
        : Subject(
            uid: '',
            name: (json['TantargyNev'] ?? 'Tanóra').toString(),
            category: NameUidDesc(uid: '', name: '', description: ''),
            sortIndex: 0,
          );
    return Omission(
      uid: (json['Uid'] ?? '').toString(),
      subject: subject,
      lesson: json['Ora'] is Map<String, dynamic>
          ? OmittedLesson.fromJson(json['Ora'] as Map<String, dynamic>)
          : null,
      date: json.localDate('Datum') ?? DateTime.now(),
      teacher: (json['RogzitoTanarNeve'] ?? '').toString(),
      type: json.nameUidDesc('Tipus'),
      mode: json.nameUidDesc('Mod'),
      lateForMin: (json['KesesPercben'] as num?)?.toInt(),
      createdAt: json.localDate('KeszitesDatuma') ?? DateTime.now(),
      state: OmissionState.fromString(
        (json['IgazolasAllapota'] ?? '').toString(),
      ),
      proofType: json.nameUidDesc('IgazolasTipusa'),
      classGroup: json.uid('OsztalyCsoport'),
    );
  }

  @override
  String toString() {
    return 'Omission('
        'uid: "$uid", '
        'subject: $subject, '
        'c: $lesson, '
        'date: $date, '
        'teacher: "$teacher", '
        'type: $type, '
        'mode: $mode, '
        'lateForMin: $lateForMin, '
        'createdAt: $createdAt, '
        'state: "$state", '
        'proofType: $proofType, '
        'classGroup: $classGroup'
        ')';
  }
}

enum OmissionState {
  excused("Igazolt"),
  unexcused("Igazolatlan"),
  pending("Igazolando"),
  unknown("");

  final String key;
  const OmissionState(this.key);

  static fromString(String string) {
    for (final state in OmissionState.values) {
      if (state.key == string) {
        return state;
      }
    }
    print("Unknown omission state: ${string}");
    return OmissionState.unknown;
  }
}

class OmittedLesson {
  final DateTime start;
  final DateTime end;
  final int? classNo;

  const OmittedLesson({
    required this.start,
    required this.end,
    required this.classNo,
  });

  factory OmittedLesson.fromJson(Map<String, dynamic> json) {
    return OmittedLesson(
      start: json.localDate('KezdoDatum') ?? DateTime.now(),
      end: json.localDate('VegDatum') ?? DateTime.now(),
      classNo: (json['Oraszam'] as num?)?.toInt(),
    );
  }

  @override
  String toString() {
    return 'OmittedLesson('
        'start: "$start", '
        'end: "$end", '
        'classNo: $classNo'
        ')';
  }
}
