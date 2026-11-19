import 'generic.dart';
import 'subject.dart';

class Grade extends UidObj {
  final DateTime recordDate;
  final DateTime creationDate;
  final DateTime? ackDate;
  final Subject subject;
  final String? topic;
  final NameUidDesc type;
  final NameUidDesc? mode;
  final NameUidDesc valueType;
  final String teacher;
  final String? kind;
  final int? numericValue;
  final String strValue;
  final int? weightPercentage;
  final String? shortStrValue;
  final UidObj classGroup;
  final int sortIndex;

  Grade({
    required super.uid,
    required this.recordDate,
    required this.creationDate,
    this.ackDate,
    required this.subject,
    this.topic,
    required this.type,
    this.mode,
    required this.valueType,
    required this.teacher,
    this.kind,
    this.numericValue,
    required this.strValue,
    this.weightPercentage,
    this.shortStrValue,
    required this.classGroup,
    required this.sortIndex,
  });

  /// Returns the actual timestamp when the grade was created/recorded in Kréta
  /// (`KeszitesDatuma` / [creationDate], matching Firka's `createdAt`), falling
  /// back to [recordDate] only if [creationDate] has a `00:00:00` time while
  /// [recordDate] has a non-zero time component.
  DateTime get recordedAt {
    final createdLocal = creationDate.toLocal();
    final recordLocal = recordDate.toLocal();
    if (createdLocal.hour == 0 &&
        createdLocal.minute == 0 &&
        createdLocal.second == 0 &&
        (recordLocal.hour != 0 ||
            recordLocal.minute != 0 ||
            recordLocal.second != 0)) {
      return recordLocal;
    }
    return createdLocal;
  }

  factory Grade.fromJson(Map<String, dynamic> json) {
    final rawCreation = json['KeszitesDatuma'] != null
        ? DateTime.parse(json['KeszitesDatuma'] as String).toLocal()
        : null;
    final rawRecord = json['RogzitesDatuma'] != null
        ? DateTime.parse(json['RogzitesDatuma'] as String).toLocal()
        : null;
    final creationDate = rawCreation ?? rawRecord ?? DateTime.now();
    final recordDate = rawRecord ?? rawCreation ?? DateTime.now();

    return Grade(
      uid: (json['Uid'] ?? '').toString(),
      recordDate: recordDate,
      creationDate: creationDate,
      ackDate: json['LattamozasDatuma'] != null
          ? DateTime.parse(json['LattamozasDatuma'] as String).toLocal()
          : null,
      subject: Subject.fromJson(
        (json['Tantargy'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
      topic: json['Tema'] as String?,
      type: json.nameUidDesc('Tipus') ?? NameUidDesc.EMPTY,
      mode: json.nameUidDesc('Mod'),
      valueType: json.nameUidDesc('ErtekFajta') ?? NameUidDesc.EMPTY,
      teacher: (json['ErtekeloTanarNeve'] ?? '').toString(),
      kind: json['Jelleg'] as String?,
      numericValue: (json['SzamErtek'] as num?)?.toInt(),
      strValue: (json['SzovegesErtek'] ?? '').toString(),
      weightPercentage: (json['SulySzazalekErteke'] as num?)?.toInt(),
      shortStrValue: json['SzovegesErtekelesRovidNev'] as String?,
      classGroup: json.uid('OsztalyCsoport') ?? UidObj(uid: ''),
      sortIndex: (json['SortIndex'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Uid': uid,
      'RogzitesDatuma': recordDate.toUtc().toIso8601String(),
      'KeszitesDatuma': creationDate.toUtc().toIso8601String(),
      'LattamozasDatuma': ackDate?.toUtc().toIso8601String(),
      'Tantargy': subject.toJson(),
      'Tema': topic,
      'Tipus': type.toJson(),
      'Mod': mode?.toJson(),
      'ErtekFajta': valueType.toJson(),
      'ErtekeloTanarNeve': teacher,
      'Jelleg': kind,
      'SzamErtek': numericValue,
      'SzovegesErtek': strValue,
      'SulySzazalekErteke': weightPercentage,
      'SzovegesErtekelesRovidNev': shortStrValue,
      'OsztalyCsoport': classGroup.toJson(),
      'SortIndex': sortIndex,
    };
  }

  @override
  String toString() {
    return 'Grade('
        'uid: "$uid", '
        'recordDate: "$recordDate", '
        'creationDate: "$creationDate", '
        'ackDate: "${ackDate ?? 'null'}", '
        'subject: $subject, '
        'topic: "${topic ?? 'null'}", '
        'type: $type, '
        'mode: ${mode ?? 'null'}, '
        'valueType: $valueType, '
        'teacher: "$teacher", '
        'kind: "${kind ?? 'null'}", '
        'numericValue: ${numericValue ?? 'null'}, '
        'strValue: "$strValue", '
        'weightPercentage: ${weightPercentage ?? 'null'}, '
        'shortStrValue: "${shortStrValue ?? 'null'}", '
        'classGroup: ${classGroup}, '
        'sortIndex: $sortIndex'
        ')';
  }
}
