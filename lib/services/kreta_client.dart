import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show DateUtils;
import 'package:http/http.dart' as http;
import 'package:kreta_api/kreta_api.dart';
import 'package:path_provider/path_provider.dart';

import '../core/kreta_auth_config.dart';
import 'demo_data_service.dart';
import 'token_storage_service.dart';

/// Represents a downloadable file attachment on a Kréta e-Ügyintézés message.
class KretaMessageAttachment {
  final String id;
  final String fileName;

  const KretaMessageAttachment({
    required this.id,
    required this.fileName,
  });

  factory KretaMessageAttachment.fromJson(Map<String, dynamic> json) {
    final id = (json['azonosito'] ??
            json['Azonosito'] ??
            json['id'] ??
            json['Uid'] ??
            '')
        .toString()
        .trim();
    final fileName = (json['fajlNev'] ??
            json['FajlNev'] ??
            json['nev'] ??
            json['Nev'] ??
            json['fileName'] ??
            'csatolmany')
        .toString()
        .trim();
    return KretaMessageAttachment(
      id: id,
      fileName: fileName.isEmpty ? 'csatolmany' : fileName,
    );
  }

  Map<String, dynamic> toJson() => {
        'azonosito': id,
        'fajlNev': fileName,
      };
}

/// Represents a Kréta e-Ügyintézés message or school notice/system message.
class KretaMessage {
  final String uid;
  final String? messageId;
  final String sender;
  final String? senderTitle;
  final List<String> recipients;
  final String subject;
  final String body;
  final DateTime sentAt;
  final bool isRead;
  final bool isSent;
  final bool isSystemMessage;
  final bool hasAttachments;
  final List<KretaMessageAttachment> attachments;
  final bool detailsLoaded;

  const KretaMessage({
    required this.uid,
    this.messageId,
    required this.sender,
    this.senderTitle,
    this.recipients = const [],
    required this.subject,
    required this.body,
    required this.sentAt,
    this.isRead = false,
    this.isSent = false,
    this.isSystemMessage = false,
    this.hasAttachments = false,
    this.attachments = const [],
    this.detailsLoaded = true,
  });

  String get cleanBody => body
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .trim();

  KretaMessage copyWith({
    String? uid,
    String? messageId,
    String? sender,
    String? senderTitle,
    List<String>? recipients,
    String? subject,
    String? body,
    DateTime? sentAt,
    bool? isRead,
    bool? isSent,
    bool? isSystemMessage,
    bool? hasAttachments,
    List<KretaMessageAttachment>? attachments,
    bool? detailsLoaded,
  }) {
    return KretaMessage(
      uid: uid ?? this.uid,
      messageId: messageId ?? this.messageId,
      sender: sender ?? this.sender,
      senderTitle: senderTitle ?? this.senderTitle,
      recipients: recipients ?? this.recipients,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      sentAt: sentAt ?? this.sentAt,
      isRead: isRead ?? this.isRead,
      isSent: isSent ?? this.isSent,
      isSystemMessage: isSystemMessage ?? this.isSystemMessage,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      attachments: attachments ?? this.attachments,
      detailsLoaded: detailsLoaded ?? this.detailsLoaded,
    );
  }

  factory KretaMessage.fromJson(
    Map<String, dynamic> json, {
    bool? forceSent,
    bool isSystemMessage = false,
    bool? detailsLoaded,
  }) {
    final nestedMsg = json['uzenet'] is Map<String, dynamic>
        ? json['uzenet'] as Map<String, dynamic>
        : (json['Uzenet'] is Map<String, dynamic>
            ? json['Uzenet'] as Map<String, dynamic>
            : json);

    final uid = (json['Uid'] ??
            json['azonosito'] ??
            json['Azonosito'] ??
            nestedMsg['azonosito'] ??
            json['id'] ??
            DateTime.now().microsecondsSinceEpoch)
        .toString()
        .trim();

    final rawMsgId = json['uzenetAzonosito'] ??
        json['UzenetAzonosito'] ??
        (json.containsKey('uzenet') || json.containsKey('Uzenet')
            ? (nestedMsg['azonosito'] ?? nestedMsg['Azonosito'])
            : null);
    final parsedMsgId = rawMsgId?.toString().trim();
    final messageId =
        (parsedMsgId == null || parsedMsgId.isEmpty) ? null : parsedMsgId;

    final sender = (json['FeladoNev'] ??
            json['uzenetFeladoNev'] ??
            nestedMsg['feladoNev'] ??
            json['feladoNev'] ??
            json['RogzitoNeve'] ??
            json['KeszitoTanarNeve'] ??
            'Iskolai értesítés')
        .toString()
        .trim();

    final rawTitle = (json['uzenetFeladoTitulus'] ??
            nestedMsg['feladoTitulus'] ??
            json['feladoTitulus'] ??
            json['FeladoTitulus'] ??
            '')
        .toString()
        .trim();
    final senderTitle = rawTitle.isEmpty ? null : rawTitle;

    final recipients = <String>[];
    final rawRecips = json['CimzettLista'] ??
        nestedMsg['cimzettLista'] ??
        json['cimzettLista'] ??
        json['Cimzettek'];
    if (rawRecips is List) {
      for (final r in rawRecips) {
        if (r is Map) {
          final name =
              (r['Nev'] ?? r['nev'] ?? r['CimzettNev'] ?? '').toString().trim();
          if (name.isNotEmpty) recipients.add(name);
        } else if (r != null) {
          final name = r.toString().trim();
          if (name.isNotEmpty) recipients.add(name);
        }
      }
    }

    final subject = (json['Targy'] ??
            json['uzenetTargy'] ??
            nestedMsg['targy'] ??
            json['targy'] ??
            json['Cim'] ??
            'Üzenet')
        .toString()
        .trim();

    final body = (json['Szoveg'] ??
            nestedMsg['szoveg'] ??
            json['uzenetSzoveg'] ??
            json['TartalomFormazott'] ??
            json['TartalomText'] ??
            json['Tartalom'] ??
            '')
        .toString();

    final rawDate = (json['KuldesDatuma'] ??
            json['uzenetKuldesDatum'] ??
            nestedMsg['kuldesDatum'] ??
            json['kuldesDatum'] ??
            json['KeszitesDatuma'] ??
            json['Datum'] ??
            json['ErvenyessegKezdete'] ??
            '')
        .toString();
    final sentAt = DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now();

    final isRead = json['IsElolvasva'] == true ||
        json['isElolvasva'] == true ||
        json['elolvasva'] == true ||
        json['isOlvasott'] == true ||
        json['isRead'] == true;

    final tipusObj = json['tipus'] is Map
        ? json['tipus'] as Map
        : (json['Tipus'] is Map ? json['Tipus'] as Map : null);
    final rawType = [
      tipusObj?['kod'],
      tipusObj?['nev'],
      tipusObj?['Nev'],
      tipusObj?['Leiras'],
      json['Tipus'],
      json['tipus'],
      json['Mappa'],
      json['mappa'],
    ]
        .where((e) => e != null)
        .map((e) => e.toString().toLowerCase())
        .join(' ');
    final isSent = forceSent ??
        (json['isSent'] == true ||
            rawType.contains('elkuldott') ||
            rawType.contains('kuldott') ||
            rawType.contains('küldött') ||
            rawType.contains('sent'));

    final attachments = <KretaMessageAttachment>[];
    final rawAttachments = json['csatolmanyok'] ??
        nestedMsg['csatolmanyok'] ??
        json['Csatolmanyok'] ??
        nestedMsg['Csatolmanyok'];
    if (rawAttachments is List) {
      for (final a in rawAttachments) {
        if (a is Map<String, dynamic>) {
          final att = KretaMessageAttachment.fromJson(a);
          if (att.id.isNotEmpty || att.fileName.isNotEmpty) {
            attachments.add(att);
          }
        } else if (a is Map) {
          final att =
              KretaMessageAttachment.fromJson(Map<String, dynamic>.from(a));
          if (att.id.isNotEmpty || att.fileName.isNotEmpty) {
            attachments.add(att);
          }
        }
      }
    }

    final hasAttachments = json['hasCsatolmany'] == true ||
        json['HasCsatolmany'] == true ||
        nestedMsg['hasCsatolmany'] == true ||
        attachments.isNotEmpty;

    final isSummary = json.containsKey('uzenetTargy') ||
        json.containsKey('uzenetKuldesDatum') ||
        (json['uzenet'] is Map && json['detailsLoaded'] != true);
    final resolvedIsSystem =
        isSystemMessage || json['isSystemMessage'] == true;
    final resolvedDetailsLoaded =
        detailsLoaded ??
        (json['detailsLoaded'] is bool
            ? json['detailsLoaded'] as bool
            : (resolvedIsSystem || !isSummary));

    return KretaMessage(
      uid: uid,
      messageId: messageId,
      sender: sender,
      senderTitle: senderTitle,
      recipients: recipients,
      subject: subject,
      body: body,
      sentAt: sentAt,
      isRead: isRead,
      isSent: isSent,
      isSystemMessage: resolvedIsSystem,
      hasAttachments: hasAttachments,
      attachments: attachments,
      detailsLoaded: resolvedDetailsLoaded,
    );
  }

  Map<String, dynamic> toJson() => {
        'Uid': uid,
        if (messageId != null) 'uzenetAzonosito': messageId,
        'FeladoNev': sender,
        if (senderTitle != null) 'uzenetFeladoTitulus': senderTitle,
        'Cimzettek': recipients,
        'Targy': subject,
        'Szoveg': body,
        'KuldesDatuma': sentAt.toIso8601String(),
        'IsElolvasva': isRead,
        'isSent': isSent,
        if (isSystemMessage) 'isSystemMessage': true,
        'hasCsatolmany': hasAttachments,
        if (attachments.isNotEmpty)
          'csatolmanyok': attachments.map((a) => a.toJson()).toList(),
        'detailsLoaded': detailsLoaded,
      };
}

/// Categorized summary of student attendance, missed hours, and tardiness minutes.
class OmissionsSummary {
  final List<Omission> allOmissions;
  final List<Omission> missedLessons;
  final List<Omission> tardinessEntries;
  final int totalMissedHours;
  final int certifiedHours;
  final int uncertifiedHours;
  final int pendingHours;
  final int totalTardinessMinutes;
  final int certifiedTardinessMinutes;
  final int uncertifiedTardinessMinutes;

  const OmissionsSummary({
    required this.allOmissions,
    required this.missedLessons,
    required this.tardinessEntries,
    required this.totalMissedHours,
    required this.certifiedHours,
    required this.uncertifiedHours,
    required this.pendingHours,
    required this.totalTardinessMinutes,
    required this.certifiedTardinessMinutes,
    required this.uncertifiedTardinessMinutes,
  });

  static bool isTardiness(Omission o) {
    if (o.lateForMin != null && o.lateForMin! > 0) return true;
    final tName = o.type?.name.toLowerCase() ?? '';
    final tDesc = o.type?.description.toLowerCase() ?? '';
    return tName.contains('keses') || tDesc.contains('késés');
  }

  /// Whether an absence or late arrival requires excuse or remains unexcused.
  static bool isActionableUnexcused(Omission o) =>
      o.state != OmissionState.excused;

  /// Whether an omission is awaiting excuse (`Igazolandó` / `unknown`).
  static bool isPendingExcuse(Omission o) =>
      o.state == OmissionState.pending || o.state == OmissionState.unknown;

  /// Deterministic per-item key for dismissal tracking and deduplication.
  static String omissionIdentityKey(Omission o) {
    final uid = o.uid.trim();
    if (uid.isNotEmpty) return uid;
    return '${o.subject.name}_${o.date.toUtc().toIso8601String()}_${o.lesson?.classNo ?? 0}_${o.lateForMin ?? 0}';
  }

  /// Returns all unexcused or pending-excuse omissions/tardiness sorted newest-first.
  static List<Omission> actionableUnexcused(Iterable<Omission> omissions) {
    final items = omissions.where(isActionableUnexcused).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  factory OmissionsSummary.fromList(List<Omission> list) {
    final sorted = List<Omission>.from(list)
      ..sort((a, b) => b.date.compareTo(a.date));

    final missed = <Omission>[];
    final tardies = <Omission>[];
    int certHours = 0;
    int uncertHours = 0;
    int pendHours = 0;
    int totalLateMin = 0;
    int certLateMin = 0;
    int uncertLateMin = 0;

    for (final o in sorted) {
      if (isTardiness(o)) {
        tardies.add(o);
        final mins = o.lateForMin ?? 0;
        totalLateMin += mins;
        if (o.state == OmissionState.excused) {
          certLateMin += mins;
        } else {
          uncertLateMin += mins;
        }
      } else {
        missed.add(o);
        switch (o.state) {
          case OmissionState.excused:
            certHours++;
            break;
          case OmissionState.unexcused:
            uncertHours++;
            break;
          case OmissionState.pending:
          case OmissionState.unknown:
            pendHours++;
            break;
        }
      }
    }

    return OmissionsSummary(
      allOmissions: sorted,
      missedLessons: missed,
      tardinessEntries: tardies,
      totalMissedHours: missed.length,
      certifiedHours: certHours,
      uncertifiedHours: uncertHours,
      pendingHours: pendHours,
      totalTardinessMinutes: totalLateMin,
      certifiedTardinessMinutes: certLateMin,
      uncertifiedTardinessMinutes: uncertLateMin,
    );
  }
}

/// Normalized missing-equipment (`Felszereléshiány`) entry extracted from Kréta
/// notes (`Feljegyzesek`), evaluations (`Ertekelesek`), or omissions (`Mulasztasok`).
class MissingEquipmentItem {
  final String uid;
  final String subjectName;
  final String title;
  final String note;
  final String teacher;
  final DateTime date;
  final String source;

  const MissingEquipmentItem({
    required this.uid,
    required this.subjectName,
    required this.title,
    required this.note,
    required this.teacher,
    required this.date,
    required this.source,
  });

  static bool isMissingEquipmentText(String raw) {
    final lower = raw.toLowerCase();
    return lower.contains('felszereléshiány') ||
        lower.contains('felszereleshiany') ||
        lower.contains('felszerelés hiány') ||
        lower.contains('felszereles hiany') ||
        lower.contains('nincs felszerel');
  }

  static bool isMissingEquipmentGrade(Grade g) {
    final combined = [
      g.type.name,
      g.type.description,
      g.mode?.name ?? '',
      g.mode?.description ?? '',
      g.valueType.name,
      g.valueType.description,
      g.topic ?? '',
      g.strValue,
    ].join(' ');
    return isMissingEquipmentText(combined);
  }

  static List<MissingEquipmentItem> deduplicateAndSort(
    Iterable<MissingEquipmentItem> items,
  ) {
    final seen = <String, MissingEquipmentItem>{};
    for (final item in items) {
      final normDay = DateUtils.dateOnly(item.date.toLocal()).toIso8601String();
      final dedupeKey = item.uid.trim().isNotEmpty
          ? '${item.source}:${item.uid.trim()}'
          : '$normDay:${item.subjectName.toLowerCase()}:${item.title.toLowerCase()}:${item.note.toLowerCase()}';
      seen.putIfAbsent(dedupeKey, () => item);
    }
    final list = seen.values.toList()..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  static String _stripHtml(String raw) => raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .trim();

  static MissingEquipmentItem? fromRawNoteJson(Map<String, dynamic> json) {
    final tipusObj = json['Tipus'] is Map ? json['Tipus'] as Map : null;
    final tipusStr = [
      tipusObj?['Nev'],
      tipusObj?['Leiras'],
      json['Tipus'],
    ].where((e) => e != null).map((e) => e.toString()).join(' ');
    final title = (json['Cim'] ?? json['cim'] ?? '').toString().trim();
    final rawContent = (json['Tartalom'] ??
            json['TartalomFormazott'] ??
            json['TartalomText'] ??
            json['tartalom'] ??
            '')
        .toString();
    final note = _stripHtml(rawContent);
    if (!isMissingEquipmentText('$tipusStr $title $note')) {
      return null;
    }

    final tantargy = json['Tantargy'] is Map ? json['Tantargy'] as Map : null;
    final subjectName = (tantargy?['Nev'] ??
            json['TantargyNev'] ??
            json['tantargy'] ??
            '')
        .toString()
        .trim();
    final uid = (json['Uid'] ?? json['uid'] ?? '').toString().trim();
    final rawDate = (json['Datum'] ??
            json['datum'] ??
            json['KeszitesDatuma'] ??
            '')
        .toString();
    final date = DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now();
    final teacher = (json['KeszitoTanarNeve'] ??
            json['RogzitoNeve'] ??
            json['tanar'] ??
            '')
        .toString()
        .trim();

    return MissingEquipmentItem(
      uid: uid.isNotEmpty
          ? uid
          : 'felj_${date.millisecondsSinceEpoch}_${subjectName.hashCode}',
      subjectName: subjectName.isNotEmpty ? subjectName : 'Felszereléshiány',
      title: title.isNotEmpty ? title : 'Felszereléshiány',
      note: note,
      teacher: teacher,
      date: date,
      source: 'feljegyzes',
    );
  }

  static List<MissingEquipmentItem> extractMissingEquipments({
    List<Map<String, dynamic>> rawNotes = const [],
    List<Grade> grades = const [],
    List<Omission> omissions = const [],
    List<KretaMessage> messages = const [],
  }) {
    final extracted = <MissingEquipmentItem>[];

    for (final raw in rawNotes) {
      final parsed = fromRawNoteJson(raw);
      if (parsed != null) extracted.add(parsed);
    }

    for (final msg in messages) {
      if (!msg.isSystemMessage) continue;
      final bodyClean = msg.cleanBody;
      if (!isMissingEquipmentText('${msg.subject} $bodyClean')) continue;
      extracted.add(
        MissingEquipmentItem(
          uid: msg.uid.trim().isNotEmpty
              ? msg.uid.trim()
              : 'sys_${msg.sentAt.millisecondsSinceEpoch}',
          subjectName: msg.subject.trim().isNotEmpty
              ? msg.subject.trim()
              : 'Felszereléshiány',
          title: msg.subject.trim().isNotEmpty
              ? msg.subject.trim()
              : 'Felszereléshiány',
          note: bodyClean,
          teacher: msg.sender.trim(),
          date: msg.sentAt.toLocal(),
          source: 'feljegyzes',
        ),
      );
    }

    for (final g in grades) {
      if (!isMissingEquipmentGrade(g)) continue;
      final topicClean = (g.topic ?? '').trim();
      final fallbackStr = g.strValue.trim();
      extracted.add(
        MissingEquipmentItem(
          uid: g.uid.trim().isNotEmpty
              ? g.uid.trim()
              : 'grd_${g.recordedAt.millisecondsSinceEpoch}',
          subjectName: g.subject.name.trim().isNotEmpty
              ? g.subject.name.trim()
              : 'Felszereléshiány',
          title: 'Felszereléshiány',
          note: topicClean.isNotEmpty
              ? topicClean
              : (fallbackStr.isNotEmpty ? fallbackStr : g.type.description),
          teacher: g.teacher.trim(),
          date: g.recordedAt,
          source: 'ertekeles',
        ),
      );
    }

    for (final o in omissions) {
      final combined = [
        o.type?.name ?? '',
        o.type?.description ?? '',
        o.mode?.name ?? '',
        o.mode?.description ?? '',
      ].join(' ');
      if (!isMissingEquipmentText(combined)) continue;
      extracted.add(
        MissingEquipmentItem(
          uid: o.uid.trim().isNotEmpty
              ? o.uid.trim()
              : 'om_${o.date.millisecondsSinceEpoch}',
          subjectName: o.subject.name.trim().isNotEmpty
              ? o.subject.name.trim()
              : 'Felszereléshiány',
          title: 'Felszereléshiány',
          note: o.mode?.description.trim().isNotEmpty == true
              ? o.mode!.description.trim()
              : (o.type?.description.trim() ?? ''),
          teacher: o.teacher.trim(),
          date: o.date.toLocal(),
          source: 'mulasztas',
        ),
      );
    }

    return deduplicateAndSort(extracted);
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'subjectName': subjectName,
        'title': title,
        'note': note,
        'teacher': teacher,
        'date': date.toUtc().toIso8601String(),
        'source': source,
      };

  factory MissingEquipmentItem.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('Uid') || json.containsKey('Cim')) {
      return fromRawNoteJson(json) ??
          MissingEquipmentItem(
            uid: (json['Uid'] ?? '').toString(),
            subjectName: 'Felszereléshiány',
            title: (json['Cim'] ?? 'Felszereléshiány').toString(),
            note: _stripHtml((json['Tartalom'] ?? '').toString()),
            teacher: (json['KeszitoTanarNeve'] ?? '').toString(),
            date: DateTime.tryParse((json['Datum'] ?? '').toString())?.toLocal() ??
                DateTime.now(),
            source: 'feljegyzes',
          );
    }
    return MissingEquipmentItem(
      uid: (json['uid'] ?? '').toString(),
      subjectName: (json['subjectName'] ?? 'Felszereléshiány').toString(),
      title: (json['title'] ?? 'Felszereléshiány').toString(),
      note: (json['note'] ?? '').toString(),
      teacher: (json['teacher'] ?? '').toString(),
      date: DateTime.tryParse((json['date'] ?? '').toString())?.toLocal() ??
          DateTime.now(),
      source: (json['source'] ?? 'feljegyzes').toString(),
    );
  }
}

/// Aggregated payload for the Home, Grades, Timetable, and Továbbiak screens.
class DashboardData {
  final Student? student;
  final List<Lesson> todaysLessons;
  final List<Grade> allGrades;
  final List<Grade> latestGrades;
  final List<Homework> homeworks;
  final List<Test> tests;
  final List<Omission> omissions;
  final List<KretaMessage> messages;
  final List<MissingEquipmentItem> missingEquipments;
  final StoredSession activeSession;

  const DashboardData({
    required this.student,
    required this.todaysLessons,
    required this.allGrades,
    required this.latestGrades,
    required this.homeworks,
    required this.tests,
    this.omissions = const [],
    this.messages = const [],
    this.missingEquipments = const [],
    required this.activeSession,
  });

  Map<String, dynamic> toJson() => {
        'cacheDate': DateUtils.dateOnly(DateTime.now()).toIso8601String(),
        if (student != null) 'student': student!.toJson(),
        'todaysLessons': todaysLessons.map((l) => l.toJson()).toList(),
        'allGrades': allGrades.map((g) => g.toJson()).toList(),
        'homeworks': homeworks.map((h) => h.toJson()).toList(),
        'tests': tests.map((t) => t.toJson()).toList(),
        'omissions': omissions.map((o) => o.toJson()).toList(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'missingEquipments': missingEquipments.map((e) => e.toJson()).toList(),
      };

  factory DashboardData.fromJson(
    Map<String, dynamic> json,
    StoredSession session, {
    Set<String> readMessageIds = const {},
  }) {
    List<T> parseList<T>(
      Object? raw,
      T Function(Map<String, dynamic>) parser,
    ) {
      if (raw is! List) return <T>[];
      final out = <T>[];
      for (final item in raw) {
        try {
          if (item is Map<String, dynamic>) {
            out.add(parser(item));
          } else if (item is Map) {
            out.add(parser(Map<String, dynamic>.from(item)));
          }
        } catch (_) {
          // Skip malformed individual cached item instead of dropping the whole cache.
        }
      }
      return out;
    }

    Student? student;
    final rawStudent = json['student'];
    try {
      if (rawStudent is Map<String, dynamic>) {
        student = Student.fromJson(rawStudent);
      } else if (rawStudent is Map) {
        student = Student.fromJson(Map<String, dynamic>.from(rawStudent));
      }
    } catch (_) {
      student = null;
    }

    final todayStr = DateUtils.dateOnly(DateTime.now()).toIso8601String();
    final cacheDateStr = json['cacheDate']?.toString();
    final isSameDay = cacheDateStr == todayStr;

    final allGrades = parseList(json['allGrades'], Grade.fromJson);
    final rawMessages = parseList(json['messages'], KretaMessage.fromJson);
    final omissions = parseList(json['omissions'], Omission.fromJson);
    final parsedEquipment =
        parseList(json['missingEquipments'], MissingEquipmentItem.fromJson);
    final messages = readMessageIds.isEmpty
        ? rawMessages
        : rawMessages
            .map((m) => (m.isRead ||
                    readMessageIds.contains(m.uid) ||
                    (m.messageId != null &&
                        readMessageIds.contains(m.messageId!)))
                ? (m.isRead ? m : m.copyWith(isRead: true))
                : m)
            .toList();

    return DashboardData(
      student: student,
      todaysLessons:
          isSameDay ? parseList(json['todaysLessons'], Lesson.fromJson) : const [],
      allGrades: allGrades,
      latestGrades: allGrades.take(5).toList(),
      homeworks: parseList(json['homeworks'], Homework.fromJson),
      tests: parseList(json['tests'], Test.fromJson),
      omissions: omissions,
      messages: messages,
      missingEquipments: MissingEquipmentItem.deduplicateAndSort([
        ...parsedEquipment,
        ...MissingEquipmentItem.extractMissingEquipments(
          grades: allGrades,
          omissions: omissions,
          messages: messages,
        ),
      ]),
      activeSession: session,
    );
  }
}

/// Client for E-Kréta OAuth2 token exchange, transparent background token
/// refresh interceptor, and v3 API queries.
class KretaClient {
  final http.Client _http;
  final bool _ownsHttpClient;
  final TokenStorageService _storage;
  final String clientId;

  StoredSession? _latestSession;
  Completer<bool>? _refreshCompleter;
  Object? _lastRefreshError;
  final List<KretaMessage> _localSentMessages = [];
  final Map<String, List<Lesson>> _dayTimetableCache = {};

  KretaClient({
    http.Client? httpClient,
    TokenStorageService? storage,
    this.clientId = KretaAuthConfig.clientIdIos,
  })  : _http = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _storage = storage ?? const TokenStorageService();

  TokenStorageService get storage => _storage;
  StoredSession? get latestSession => _latestSession;

  void clearLocalState() {
    _latestSession = null;
    _localSentMessages.clear();
    _dayTimetableCache.clear();
  }

  void close() {
    if (_ownsHttpClient) {
      _http.close();
    }
  }

  bool _isDemoActive(StoredSession? session) =>
      UserProfilePrefs.activeDemoModeEnabled ||
      DemoDataService.isDemoSession(session);

  Map<String, String> get _idpHeaders => const {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Accept': '*/*',
        'User-Agent': KretaAuthConfig.userAgent,
      };

  Map<String, String> _apiHeaders(String accessToken) => {
        'Accept': 'application/json, */*',
        'User-Agent': KretaAuthConfig.userAgent,
        'Authorization': 'Bearer $accessToken',
        'apiKey': KretaAuthConfig.apiKey,
      };

  Map<String, String> _eugyintezesHeaders(String accessToken) => {
        'Accept': 'application/json, text/plain, */*',
        'User-Agent': KretaAuthConfig.userAgent,
        'Authorization': 'Bearer $accessToken',
      };

  static const Duration defaultRequestTimeout = Duration(seconds: 12);

  /// Exchanges the intercepted OAuth2 authorization [code] and PKCE
  /// [codeVerifier] at `/connect/token` and persists the resulting tokens.
  Future<StoredSession> exchangeCodeForTokens({
    required String code,
    required String codeVerifier,
    String? fallbackInstituteCode,
  }) async {
    final response = await _http.post(
      Uri.parse(KretaAuthConfig.tokenEndpoint),
      headers: _idpHeaders,
      body: {
        'code': code,
        'code_verifier': codeVerifier,
        'redirect_uri': KretaAuthConfig.redirectUri,
        'client_id': clientId,
        'grant_type': 'authorization_code',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 400) {
      throw const TokenExpiredException();
    }
    if (response.statusCode == 401) {
      throw const InvalidGrantException();
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Token exchange failed (HTTP ${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw Exception('Unexpected non-JSON-object token exchange response.');
    }
    final jsonMap = Map<String, dynamic>.from(decoded);
    final grant = TokenGrantResponse.fromJson(jsonMap);
    final session = StoredSession.fromTokenGrant(
      grant,
      fallbackInstituteCode: fallbackInstituteCode,
    );
    _latestSession = session;
    await _storage.saveSession(session);
    return session;
  }

  /// Refreshes an expired [StoredSession] using `TokenStorageService.refreshToken()`,
  /// enforcing a strict single-flight [Completer] lock across concurrent callers.
  Future<StoredSession> refreshSession(
    StoredSession current, {
    bool force = false,
  }) async {
    if (_isDemoActive(current)) {
      return DemoDataService.instance.buildDemoSession();
    }
    final existingCompleter = _refreshCompleter;
    if (existingCompleter != null) {
      final ok = await existingCompleter.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () => false,
      );
      StoredSession? storedAfterWait;
      try {
        storedAfterWait = await _storage.loadSession();
      } catch (_) {}
      final latest = TokenStorageService.pickNewestSession([
            storedAfterWait,
            TokenStorageService.latestSession,
            _latestSession,
            current,
          ]) ??
          current;
      if (ok || !latest.isExpired) {
        _latestSession = latest;
        return latest;
      }
      final leaderErr = _lastRefreshError;
      if (leaderErr is VerifiedInvalidGrantException) {
        throw leaderErr;
      }
      throw Exception('Concurrent token refresh failed.');
    }

    if (!force) {
      final newer = TokenStorageService.pickNewestSession([
        TokenStorageService.latestSession,
        _latestSession,
      ]);
      if (newer != null &&
          !newer.isExpired &&
          newer.accessToken != current.accessToken) {
        _latestSession = newer;
        return newer;
      }
    }

    final completer = Completer<bool>();
    _refreshCompleter = completer;
    _lastRefreshError = null;

    try {
      final newestInput = TokenStorageService.pickNewestSession([
            TokenStorageService.latestSession,
            _latestSession,
            current,
          ]) ??
          current;
      final refreshed = await _storage.refreshToken(
        session: newestInput,
        httpClient: _http,
        clientId: clientId,
      );
      _latestSession = refreshed;
      if (!completer.isCompleted) {
        completer.complete(true);
      }
      return refreshed;
    } catch (e) {
      _lastRefreshError = e;
      rethrow;
    } finally {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      if (identical(_refreshCompleter, completer)) {
        _refreshCompleter = null;
      }
    }
  }

  /// Ensures the session has a valid (non-expired) access token, refreshing if needed.
  Future<StoredSession> ensureValidSession(StoredSession session) async {
    if (_isDemoActive(session)) {
      return DemoDataService.instance.buildDemoSession();
    }
    StoredSession? stored;
    try {
      stored = await _storage.loadSession();
    } catch (_) {
      stored = null;
    }
    final candidate = TokenStorageService.pickNewestSession([
          stored,
          TokenStorageService.latestSession,
          _latestSession,
          session,
        ]) ??
        session;
    if (!candidate.isExpired) {
      _latestSession = candidate;
      return candidate;
    }
    return refreshSession(candidate);
  }

  /// Transparent Token Refresh Interceptor:
  /// Wraps any authorized HTTP request with serialized single-flight token refresh
  /// and bounded request timeouts. Never logs out directly on 401/403/5xx/timeouts.
  Future<http.Response> _sendWithRetryInterceptor(
    StoredSession session,
    Future<http.Response> Function(String accessToken) sendRequest,
  ) async {
    StoredSession active = TokenStorageService.pickNewestSession([
          TokenStorageService.latestSession,
          _latestSession,
          session,
        ]) ??
        session;
    VerifiedInvalidGrantException? preemptiveInvalidGrant;
    if (active.isExpired) {
      try {
        active = await ensureValidSession(active);
      } on VerifiedInvalidGrantException catch (e) {
        if (DateTime.now().isAfter(active.expiresAt)) {
          rethrow;
        }
        preemptiveInvalidGrant = e;
        // Still within nominal pre-expiry margin: try current token cleanly first.
      } catch (_) {
        // Transient network/5xx/storage error during pre-emptive refresh: keep session
        // and attempt request so offline errors never force a logout.
      }
    }

    final usedAccessToken = active.accessToken;
    var response =
        await sendRequest(usedAccessToken).timeout(defaultRequestTimeout);
    if (response.statusCode != 401) {
      return response;
    }

    final concurrentLatest = TokenStorageService.pickNewestSession([
      TokenStorageService.latestSession,
      _latestSession,
    ]);
    if (concurrentLatest != null &&
        concurrentLatest.accessToken != usedAccessToken &&
        !concurrentLatest.isExpired) {
      active = concurrentLatest;
    } else if (preemptiveInvalidGrant != null) {
      throw preemptiveInvalidGrant;
    } else {
      active = await refreshSession(active, force: true);
    }

    response =
        await sendRequest(active.accessToken).timeout(defaultRequestTimeout);
    return response;
  }

  Future<dynamic> _getAuthenticatedJson(
    StoredSession session,
    String url,
  ) async {
    final response = await _sendWithRetryInterceptor(
      session,
      (accessToken) => _http.get(
        Uri.parse(url),
        headers: _apiHeaders(accessToken),
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('GET $url failed (HTTP ${response.statusCode})');
    }

    final text = utf8.decode(response.bodyBytes).trim();
    if (text.isEmpty) {
      return const [];
    }
    try {
      return jsonDecode(text);
    } catch (e) {
      throw FormatException('Invalid JSON from $url: $e');
    }
  }

  Future<dynamic> _getEugyintezesJson(
    StoredSession session,
    String url,
  ) async {
    final response = await _sendWithRetryInterceptor(
      session,
      (accessToken) => _http.get(
        Uri.parse(url),
        headers: _eugyintezesHeaders(accessToken),
      ),
    );

    if (response.statusCode != 200) {
      return null;
    }

    final text = utf8.decode(response.bodyBytes).trim();
    if (text.isEmpty) {
      return const [];
    }
    return jsonDecode(text);
  }

  Future<bool> _postOrPutEugyintezes(
    StoredSession session,
    String url,
    Map<String, dynamic> payload,
  ) async {
    final encodedBody = utf8.encode(jsonEncode(payload));
    var response = await _sendWithRetryInterceptor(
      session,
      (accessToken) => _http.post(
        Uri.parse(url),
        headers: {
          ..._eugyintezesHeaders(accessToken),
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: encodedBody,
      ),
    );

    if (response.statusCode == 405) {
      response = await _sendWithRetryInterceptor(
        session,
        (accessToken) => _http.put(
          Uri.parse(url),
          headers: {
            ..._eugyintezesHeaders(accessToken),
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: encodedBody,
        ),
      );
    }

    return response.statusCode >= 200 && response.statusCode < 300;
  }

  String _dayCacheKey(StoredSession session, DateTime date) {
    final norm = DateUtils.dateOnly(date);
    final acct = _isDemoActive(session)
        ? 'demo'
        : TokenStorageService.accountKeyForSession(session);
    final m = norm.month.toString().padLeft(2, '0');
    final d = norm.day.toString().padLeft(2, '0');
    return '$acct|${norm.year}-$m-$d';
  }

  /// Returns cached lessons for the exact calendar [date], or `null` if not
  /// yet cached in memory for [session].
  List<Lesson>? getCachedTimetableForDate(
    StoredSession session,
    DateTime date,
  ) {
    return _dayTimetableCache[_dayCacheKey(session, date)];
  }

  /// Returns all cached timetable lessons currently stored across dates for [session].
  List<Lesson> getAllCachedTimetableLessons(StoredSession session) {
    final userName = (session.userName ?? '').trim();
    final acct = userName.isNotEmpty
        ? userName
        : TokenStorageService.accountKeyForSession(session);
    final prefix = '$acct|';
    final seen = <String>{};
    final out = <Lesson>[];
    for (final entry in _dayTimetableCache.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      for (final lesson in entry.value) {
        final key = lesson.uid.trim().isNotEmpty
            ? lesson.uid.trim()
            : '${lesson.lessonNumber ?? ''}_${lesson.start.toIso8601String()}_${lesson.name}';
        if (seen.add(key)) {
          out.add(lesson);
        }
      }
    }
    return out;
  }

  void _cacheTimetableLessons(
    StoredSession session,
    List<Lesson> lessons, {
    Iterable<DateTime> explicitEmptyDates = const <DateTime>[],
  }) {
    final byDay = <DateTime, List<Lesson>>{};
    for (final lesson in lessons) {
      final day = DateUtils.dateOnly(lesson.start.toLocal());
      byDay.putIfAbsent(day, () => <Lesson>[]).add(lesson);
    }

    for (final entry in byDay.entries) {
      final deduped = <String, Lesson>{};
      for (final lesson in entry.value) {
        final key = lesson.uid.trim().isNotEmpty
            ? lesson.uid.trim()
            : '${lesson.lessonNumber ?? ''}_${lesson.start.toIso8601String()}_${lesson.name}';
        deduped[key] = lesson;
      }
      final sorted = deduped.values.toList()
        ..sort((a, b) {
          final nCmp = (a.lessonNumber ?? 999).compareTo(b.lessonNumber ?? 999);
          if (nCmp != 0) return nCmp;
          return a.start.toLocal().compareTo(b.start.toLocal());
        });
      _dayTimetableCache[_dayCacheKey(session, entry.key)] =
          List<Lesson>.unmodifiable(sorted);
    }

    for (final date in explicitEmptyDates) {
      final norm = DateUtils.dateOnly(date);
      if (!byDay.containsKey(norm)) {
        _dayTimetableCache[_dayCacheKey(session, norm)] = const <Lesson>[];
      }
    }
  }

  /// Fetches timetable lessons between [from] and [to] (inclusive) using
  /// [KretaEndpoints.getTimeTable] and parses each item with [Lesson.fromJson].
  Future<List<Lesson>> fetchTimetableForRange(
    StoredSession session, {
    required DateTime from,
    required DateTime to,
  }) async {
    if (_isDemoActive(session)) {
      final demo = DemoDataService.instance.buildTimetableForRange(from, to);
      _cacheTimetableLessons(session, demo);
      return demo;
    }
    final startDay = DateTime(from.year, from.month, from.day);
    final endDay = DateTime(to.year, to.month, to.day);
    final url = KretaEndpoints.getTimeTable(
      session.instituteCode,
      startDay,
      endDay,
    );

    final raw = await _getAuthenticatedJson(session, url);
    if (raw is! List) {
      return const [];
    }

    final lessons = <Lesson>[];
    for (final item in raw) {
      if (item is Map) {
        try {
          lessons.add(Lesson.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // Skip malformed KRÉTA lesson item without crashing the whole week.
        }
      }
    }
    lessons.sort((a, b) => a.start.toLocal().compareTo(b.start.toLocal()));
    _cacheTimetableLessons(session, lessons);

    return lessons;
  }

  /// Fetches the complete timetable for a single calendar [date], returning any
  /// cached day schedule immediately or fetching the enclosing week cleanly.
  Future<List<Lesson>> fetchTimetableForDate(
    StoredSession session,
    DateTime date, {
    bool forceRefresh = false,
  }) async {
    final target = DateUtils.dateOnly(date);
    if (!forceRefresh) {
      final cached = getCachedTimetableForDate(session, target);
      if (cached != null) {
        return cached;
      }
    }
    if (_isDemoActive(session)) {
      final demo = DemoDataService.instance.buildTimetableForRange(
        target,
        target,
      );
      final dayOnly = demo
          .where((l) => DateUtils.dateOnly(l.start.toLocal()) == target)
          .toList();
      _cacheTimetableLessons(
        session,
        dayOnly,
        explicitEmptyDates: [target],
      );
      return _dayTimetableCache[_dayCacheKey(session, target)] ??
          const <Lesson>[];
    }

    final monday = target.subtract(Duration(days: target.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final weekLessons = await fetchTimetableForRange(
      session,
      from: monday,
      to: sunday,
    );
    _cacheTimetableLessons(
      session,
      weekLessons,
      explicitEmptyDates: [target],
    );
    return _dayTimetableCache[_dayCacheKey(session, target)] ??
        const <Lesson>[];
  }

  /// Fetches today's timetable lessons using [KretaEndpoints.getTimeTable].
  Future<List<Lesson>> fetchTodaysTimetable(
    StoredSession session, {
    DateTime? date,
  }) async {
    final target = DateUtils.dateOnly(date ?? DateTime.now());
    // Query a two-day window (the upstream upper bound is exclusive-ish and
    // timezone sensitive) and keep only entries that fall on the target day.
    final lessons = await fetchTimetableForRange(
      session,
      from: target,
      to: target.add(const Duration(days: 1)),
    );
    return lessons
        .where((l) => DateUtils.dateOnly(l.start.toLocal()) == target)
        .toList();
  }

  /// Returns September 1 of the current school year (matching Firka's `getFirstSchoolDay()`).
  static DateTime getFirstSchoolDay([DateTime? reference]) {
    final now = reference ?? DateTime.now();
    final sept1 = DateTime(now.year, 9, 1);
    if (now.isBefore(sept1)) {
      return DateTime(now.year - 1, 9, 1);
    }
    return sept1;
  }

  /// Fetches all student evaluations via [KretaEndpoints.getGrades] sorted
  /// newest-first by `recordedAt` (`KeszitesDatuma` / `RogzitesDatuma`).
  Future<List<Grade>> fetchAllGrades(StoredSession session) async {
    if (_isDemoActive(session)) {
      return DemoDataService.instance.buildDemoGrades();
    }
    final url = KretaEndpoints.getGrades(session.instituteCode);
    final raw = await _getAuthenticatedJson(session, url);
    if (raw is! List) {
      return const [];
    }

    final grades = <Grade>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        try {
          grades.add(Grade.fromJson(item));
        } catch (_) {}
      }
    }
    grades.sort((a, b) {
      final cmp = b.recordedAt.compareTo(a.recordedAt);
      if (cmp != 0) return cmp;
      return b.recordDate.compareTo(a.recordDate);
    });

    return grades;
  }

  /// Fetches homework assignments via [KretaEndpoints.getHomework] using
  /// Firka's exact query parameters (`datumTol` = first school day, `datumIg` = null),
  /// sorted newest-first.
  Future<List<Homework>> fetchHomeworks(
    StoredSession session, {
    DateTime? from,
    DateTime? to,
  }) async {
    if (_isDemoActive(session)) {
      return DemoDataService.instance.buildDemoHomeworks();
    }
    try {
      DateTime? effectiveFrom = from;
      final DateTime? effectiveTo = to;
      if (effectiveFrom == null && effectiveTo == null) {
        effectiveFrom = getFirstSchoolDay();
      }
      final url = KretaEndpoints.getHomework(
        session.instituteCode,
        effectiveFrom,
        effectiveTo,
      );
      final raw = await _getAuthenticatedJson(session, url);
      if (raw is! List) return const [];

      final list = <Homework>[];
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          try {
            list.add(Homework.fromJson(item));
          } catch (_) {}
        }
      }
      list.sort((a, b) => b.creationDate.compareTo(a.creationDate));
      return list;
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  /// Fetches a single homework entry by its `HaziFeladatUid` (`/ellenorzo/v3/sajat/HaziFeladatok/{uid}`)
  /// when referenced by a timetable [Lesson].
  Future<Homework?> fetchHomeworkByUid(
    StoredSession session,
    String homeworkUid,
  ) async {
    final trimmed = homeworkUid.trim();
    if (trimmed.isEmpty) return null;
    if (_isDemoActive(session)) {
      for (final hw in DemoDataService.instance.buildDemoHomeworks()) {
        if (hw.uid == trimmed) return hw;
      }
      return null;
    }
    final cleanId = trimmed.split(',').first.trim();
    if (cleanId.isEmpty) return null;
    try {
      final base = KretaEndpoints.getHomework(session.instituteCode);
      final url = '$base/${Uri.encodeComponent(cleanId)}';
      final raw = await _getAuthenticatedJson(session, url);
      if (raw is Map<String, dynamic>) {
        return Homework.fromJson(raw);
      }
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {}
    return null;
  }

  /// Matches a [Lesson] to its corresponding [Homework] from [homeworks]
  /// using Firka's `UidObj.id` (`homeworkUid`) or subject+date matching.
  static Homework? findHomeworkForLesson(
    Lesson lesson,
    Iterable<Homework> homeworks,
  ) {
    final hwUid = lesson.homeworkUid?.trim() ?? '';
    if (hwUid.isNotEmpty) {
      final targetId = UidObj(uid: hwUid).id;
      final targetLead = hwUid.split(',').first.trim();
      for (final hw in homeworks) {
        final hwLead = hw.uid.split(',').first.trim();
        if (hw.uid == hwUid ||
            (targetLead.isNotEmpty && hwLead == targetLead) ||
            hw.id == targetId) {
          return hw;
        }
      }
    }

    // Fallback: match by subject and lesson date (assigned on or due on this lesson's date)
    final lessonDay = DateUtils.dateOnly(lesson.start.toLocal());
    final lessonSubjUid = lesson.subject?.uid.trim() ?? '';
    final lessonSubjName =
        (lesson.subject?.name ?? lesson.name).trim().toLowerCase();
    if (lessonSubjUid.isEmpty && lessonSubjName.isEmpty) return null;

    for (final hw in homeworks) {
      final sameSubj = (lessonSubjUid.isNotEmpty &&
              hw.subject.uid.trim() == lessonSubjUid) ||
          (lessonSubjName.isNotEmpty &&
              (hw.subject.name.trim().toLowerCase() == lessonSubjName ||
                  hw.subjectName.trim().toLowerCase() == lessonSubjName));
      if (!sameSubj) continue;
      final startDay = DateUtils.dateOnly(hw.startDate.toLocal());
      final dueDay = DateUtils.dateOnly(hw.dueDate.toLocal());
      if (startDay == lessonDay || dueDay == lessonDay) {
        return hw;
      }
    }
    return null;
  }

  /// Returns all announced [tests] scheduled on the local calendar date of [day],
  /// sorted by period number (`lessonNumber`) and timestamp.
  static List<Test> findTestsForDay(
    DateTime day,
    Iterable<Test> tests,
  ) {
    final targetDay = DateUtils.dateOnly(day.toLocal());
    final matches = tests
        .where((t) => DateUtils.dateOnly(t.date.toLocal()) == targetDay)
        .toList();
    matches.sort((a, b) {
      final lnCmp = a.lessonNumber.compareTo(b.lessonNumber);
      if (lnCmp != 0) return lnCmp;
      return a.date.toLocal().compareTo(b.date.toLocal());
    });
    return matches;
  }

  /// Matches [lesson] to scheduled [tests] on the same calendar day by period
  /// number (`lessonNumber`) or subject identity when period number is absent.
  static List<Test> findTestsForLesson(
    Lesson lesson,
    Iterable<Test> tests,
  ) {
    final lessonDay = DateUtils.dateOnly(lesson.start.toLocal());
    final lessonNum = lesson.lessonNumber;
    final lessonSubjUid = lesson.subject?.uid.trim() ?? '';
    final lessonSubjName =
        (lesson.subject?.name ?? lesson.name).trim().toLowerCase();

    bool subjectMatches(Test test) {
      if (lessonSubjUid.isNotEmpty &&
          test.subject.uid.trim().isNotEmpty &&
          test.subject.uid.trim() == lessonSubjUid) {
        return true;
      }
      final testSubjName = (test.subject.name.isNotEmpty
              ? test.subject.name
              : test.subjectName)
          .trim()
          .toLowerCase();
      return lessonSubjName.isNotEmpty && testSubjName == lessonSubjName;
    }

    final exactMatches = <Test>[];
    final periodOnlyMatches = <Test>[];
    for (final test in tests) {
      if (DateUtils.dateOnly(test.date.toLocal()) != lessonDay) continue;
      if (test.lessonNumber > 0 &&
          lessonNum != null &&
          lessonNum == test.lessonNumber) {
        if (subjectMatches(test)) {
          exactMatches.add(test);
        } else {
          periodOnlyMatches.add(test);
        }
      } else if (test.lessonNumber <= 0 && subjectMatches(test)) {
        exactMatches.add(test);
      }
    }
    return exactMatches.isNotEmpty ? exactMatches : periodOnlyMatches;
  }

  /// Matches a timetable [lesson] with an absence or late arrival [Omission]
  /// on the same calendar date by period number, start time, or subject.
  static Omission? findOmissionForLesson(
    Lesson lesson,
    Iterable<Omission> omissions,
  ) {
    final lessonDay = DateUtils.dateOnly(lesson.start.toLocal());
    final lessonStartLocal = lesson.start.toLocal();
    final lessonNum = lesson.lessonNumber;
    final lessonSubjUid = lesson.subject?.uid.trim() ?? '';
    final lessonSubjName =
        (lesson.subject?.name ?? lesson.name).trim().toLowerCase();

    bool subjectMatches(Omission o) {
      if (lessonSubjUid.isNotEmpty &&
          o.subject.uid.trim().isNotEmpty &&
          o.subject.uid.trim() == lessonSubjUid) {
        return true;
      }
      final omSubj = o.subject.name.trim().toLowerCase();
      return lessonSubjName.isNotEmpty && omSubj == lessonSubjName;
    }

    Omission? periodSubjectMatch;
    Omission? periodOnlyMatch;
    Omission? timeMatch;
    Omission? subjectOnlyMatch;

    for (final o in omissions) {
      if (DateUtils.dateOnly(o.date.toLocal()) != lessonDay) continue;
      final omClassNo = o.lesson?.classNo;
      if (lessonNum != null && omClassNo != null && omClassNo == lessonNum) {
        if (subjectMatches(o)) {
          periodSubjectMatch ??= o;
        } else {
          periodOnlyMatch ??= o;
        }
        continue;
      }
      if (o.lesson != null) {
        final omStart = o.lesson!.start.toLocal();
        if (omStart.difference(lessonStartLocal).inMinutes.abs() <= 5) {
          timeMatch ??= o;
          continue;
        }
      }
      if (omClassNo == null && subjectMatches(o)) {
        subjectOnlyMatch ??= o;
      }
    }

    return periodSubjectMatch ??
        periodOnlyMatch ??
        timeMatch ??
        subjectOnlyMatch;
  }

  /// Fetches announced tests/exams via [KretaEndpoints.getTests], sorted newest-first.
  Future<List<Test>> fetchTests(StoredSession session) async {
    if (_isDemoActive(session)) {
      return DemoDataService.instance.buildDemoTests();
    }
    try {
      final url = KretaEndpoints.getTests(session.instituteCode);
      final raw = await _getAuthenticatedJson(session, url);
      if (raw is! List) return const [];

      final list = <Test>[];
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          try {
            list.add(Test.fromJson(item));
          } catch (_) {}
        }
      }
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  /// Fetches student attendance omissions & tardiness via `/ellenorzo/v3/sajat/Mulasztasok`.
  Future<List<Omission>> fetchOmissions(StoredSession session) async {
    if (_isDemoActive(session)) {
      return DemoDataService.instance.buildDemoOmissions();
    }
    try {
      final url = KretaEndpoints.getOmissions(session.instituteCode);
      final raw = await _getAuthenticatedJson(session, url);
      if (raw is! List) return const [];

      final list = <Omission>[];
      for (final item in raw) {
        if (item is Map) {
          try {
            list.add(Omission.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {
            // Skip malformed KRÉTA omission item without discarding the list.
          }
        }
      }
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, dynamic>> _extractMessageMaps(dynamic raw) {
    final Iterable<dynamic> items;
    if (raw is List) {
      items = raw;
    } else if (raw is Map) {
      final list = raw['lista'] ??
          raw['uzenetek'] ??
          raw['postaladaElemek'] ??
          raw['items'] ??
          raw['data'] ??
          raw['result'];
      items = list is List ? list : const [];
    } else {
      items = const [];
    }
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['isToroltElem'] != true)
        .toList();
  }

  KretaMessage _mergeMessages(KretaMessage existing, KretaMessage incoming) {
    final preferIncomingBody =
        incoming.cleanBody.length > existing.cleanBody.length ||
            (incoming.body.isNotEmpty && existing.body.isEmpty);
    return existing.copyWith(
      messageId: existing.messageId ?? incoming.messageId,
      sender: existing.sender == 'Iskolai értesítés' && incoming.sender.isNotEmpty
          ? incoming.sender
          : existing.sender,
      senderTitle:
          (existing.senderTitle == null || existing.senderTitle!.isEmpty)
              ? incoming.senderTitle
              : existing.senderTitle,
      recipients: incoming.recipients.length > existing.recipients.length
          ? incoming.recipients
          : existing.recipients,
      subject: (existing.subject == 'Üzenet' && incoming.subject.isNotEmpty)
          ? incoming.subject
          : existing.subject,
      body: preferIncomingBody ? incoming.body : existing.body,
      sentAt: incoming.sentAt.isAfter(existing.sentAt)
          ? incoming.sentAt
          : existing.sentAt,
      isRead: existing.isRead || incoming.isRead,
      isSent: existing.isSent || incoming.isSent,
      hasAttachments: existing.hasAttachments || incoming.hasAttachments,
      attachments: incoming.attachments.length > existing.attachments.length
          ? incoming.attachments
          : existing.attachments,
      detailsLoaded: existing.detailsLoaded || incoming.detailsLoaded,
    );
  }

  Future<List<KretaMessage>> _safeFetchEugyintezesFolder(
    StoredSession session,
    String url, {
    bool? forceSent,
    bool rethrowAuthErrors = false,
  }) async {
    try {
      final raw = await _getEugyintezesJson(session, url);
      if (raw == null) return const [];
      return _extractMessageMaps(raw)
          .map(
            (m) => KretaMessage.fromJson(
              m,
              forceSent: forceSent,
              detailsLoaded: false,
            ),
          )
          .toList();
    } on TokenExpiredException {
      if (rethrowAuthErrors) rethrow;
      return const [];
    } on InvalidGrantException {
      if (rethrowAuthErrors) rethrow;
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<List<KretaMessage>> _safeFetchSystemBoard(
    StoredSession session,
    String url,
  ) async {
    try {
      final raw = await _getAuthenticatedJson(session, url);
      return _extractMessageMaps(raw)
          .map(
            (m) => KretaMessage.fromJson(
              m,
              forceSent: false,
              isSystemMessage: true,
              detailsLoaded: true,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetches ALL student messages by combining Kréta e-Ügyintézés mailbox
  /// endpoints (`/postaladaelemek/sajat`, `/beerkezett`, `/elkuldott`) with
  /// school noticeboard and infoboard system messages (`FaliujsagElemek` and
  /// `Feljegyzesek`), deduplicating, applying local read persistence, and
  /// sorting newest-first chronologically.
  Future<List<KretaMessage>> fetchMessages(StoredSession session) async {
    if (_isDemoActive(session)) {
      return DemoDataService.instance.buildDemoMessages();
    }
    final sources = await Future.wait<List<KretaMessage>>([
      _safeFetchEugyintezesFolder(
        session,
        KretaEndpoints.getEugyintezesSajatMessages(),
        rethrowAuthErrors: false,
      ),
      _safeFetchEugyintezesFolder(
        session,
        KretaEndpoints.getEugyintezesInboxMessages(),
        forceSent: false,
      ),
      _safeFetchEugyintezesFolder(
        session,
        KretaEndpoints.getEugyintezesSentMessages(),
        forceSent: true,
      ),
      _safeFetchSystemBoard(
        session,
        KretaEndpoints.getNoticeBoard(session.instituteCode),
      ),
      _safeFetchSystemBoard(
        session,
        KretaEndpoints.getInfoBoard(session.instituteCode),
      ),
    ]);

    final byKey = <String, KretaMessage>{};
    void putMessage(String key, KretaMessage msg) {
      final existing = byKey[key];
      byKey[key] = existing == null ? msg : _mergeMessages(existing, msg);
    }

    for (final msg in [...sources[0], ...sources[1], ...sources[2]]) {
      putMessage('msg:${msg.uid}', msg);
    }
    for (final sysMsg in [...sources[3], ...sources[4]]) {
      putMessage('sys:${sysMsg.uid}', sysMsg);
    }

    final accountKey = TokenStorageService.accountKeyForSession(session);
    final localReadIds =
        await _storage.loadReadMessageIds(accountKey: accountKey);

    final results = <KretaMessage>[];
    for (final msg in byKey.values) {
      final isLocallyRead = localReadIds.contains(msg.uid) ||
          (msg.messageId != null && localReadIds.contains(msg.messageId)) ||
          (msg.isSystemMessage && localReadIds.contains('sys:${msg.uid}'));
      results.add(
        isLocallyRead && !msg.isRead ? msg.copyWith(isRead: true) : msg,
      );
    }

    for (final sent in _localSentMessages) {
      if (!results.any((m) => m.uid == sent.uid)) {
        results.add(sent);
      }
    }

    results.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return results;
  }

  /// Fetches full body, recipients, and attachment metadata for a single
  /// e-Ügyintézés mailbox item (`/postaladaelemek/{id}`).
  Future<KretaMessage> fetchMessageDetail(
    StoredSession session,
    KretaMessage message,
  ) async {
    if (message.isSystemMessage || _isDemoActive(session)) {
      return message.copyWith(detailsLoaded: true);
    }

    dynamic raw;
    try {
      raw = await _getEugyintezesJson(
        session,
        KretaEndpoints.getEugyintezesMessageDetail(message.uid),
      );
      if (raw is! Map) {
        raw = await _getEugyintezesJson(
          session,
          KretaEndpoints.getEugyintezesMessageDetailV1(message.uid),
        );
      }
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      raw = null;
    }

    if (raw is! Map) {
      return message;
    }

    final detailed = KretaMessage.fromJson(
      Map<String, dynamic>.from(raw),
      forceSent: message.isSent,
      detailsLoaded: true,
    );
    return _mergeMessages(
      message,
      detailed.copyWith(detailsLoaded: true),
    );
  }

  /// Marks [message] as read both locally in persistent secure storage and on
  /// the Kréta e-Ügyintézés server (`/kommunikacio/uzenetek/olvasott`).
  Future<void> markMessageAsRead(
    StoredSession session,
    KretaMessage message,
  ) async {
    if (_isDemoActive(session)) {
      return;
    }
    final accountKey = TokenStorageService.accountKeyForSession(session);
    final localKeys = <String>[
      message.uid,
      if (message.messageId != null && message.messageId!.isNotEmpty)
        message.messageId!,
      if (message.isSystemMessage) 'sys:${message.uid}',
    ];
    await _storage.markMessagesReadLocally(
      localKeys,
      accountKey: accountKey,
    );

    if (message.isSystemMessage || message.isSent) {
      return;
    }

    final rawTargetId = (message.messageId?.trim().isNotEmpty == true)
        ? message.messageId!.trim()
        : message.uid.trim();
    if (rawTargetId.isEmpty) return;

    final serializedId = int.tryParse(rawTargetId) ?? rawTargetId;
    final payload = <String, dynamic>{
      'isOlvasott': true,
      'uzenetAzonositoLista': [serializedId],
    };

    try {
      final ok = await _postOrPutEugyintezes(
        session,
        KretaEndpoints.getMarkMessagesReadUrl(),
        payload,
      );
      if (!ok) {
        await _postOrPutEugyintezes(
          session,
          KretaEndpoints.getMarkMessagesReadV1Url(),
          payload,
        );
      }
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      // Persistent local read state already saved above.
    }
  }

  /// Marks all unread inbox and system messages in [messages] as read both
  /// locally and in batches via Kréta's `/kommunikacio/uzenetek/olvasott` endpoint.
  /// Returns the number of newly read messages.
  Future<int> markAllMessagesAsRead(
    StoredSession session,
    Iterable<KretaMessage> messages,
  ) async {
    final unread = messages.where((m) => !m.isRead && !m.isSent).toList();
    if (unread.isEmpty) return 0;
    if (_isDemoActive(session)) return unread.length;

    final accountKey = TokenStorageService.accountKeyForSession(session);
    final localKeys = <String>[];
    final serverIds = <Object>[];
    final seenServerIds = <String>{};

    for (final msg in unread) {
      if (msg.uid.trim().isNotEmpty) {
        localKeys.add(msg.uid.trim());
      }
      if (msg.messageId != null && msg.messageId!.trim().isNotEmpty) {
        localKeys.add(msg.messageId!.trim());
      }
      if (msg.isSystemMessage) {
        localKeys.add('sys:${msg.uid}');
        continue;
      }
      final rawTargetId = (msg.messageId?.trim().isNotEmpty == true)
          ? msg.messageId!.trim()
          : msg.uid.trim();
      if (rawTargetId.isNotEmpty && seenServerIds.add(rawTargetId)) {
        serverIds.add(int.tryParse(rawTargetId) ?? rawTargetId);
      }
    }

    if (localKeys.isNotEmpty) {
      await _storage.markMessagesReadLocally(
        localKeys,
        accountKey: accountKey,
      );
    }

    if (serverIds.isEmpty) return unread.length;

    const batchSize = 50;
    try {
      for (var i = 0; i < serverIds.length; i += batchSize) {
        final end =
            (i + batchSize < serverIds.length) ? i + batchSize : serverIds.length;
        final chunk = serverIds.sublist(i, end);
        final payload = <String, dynamic>{
          'isOlvasott': true,
          'uzenetAzonositoLista': chunk,
        };
        final ok = await _postOrPutEugyintezes(
          session,
          KretaEndpoints.getMarkMessagesReadUrl(),
          payload,
        );
        if (!ok) {
          await _postOrPutEugyintezes(
            session,
            KretaEndpoints.getMarkMessagesReadV1Url(),
            payload,
          );
        }
      }
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      // Local read state already saved above.
    }

    return unread.length;
  }

  /// Downloads an attachment from Kréta e-Ügyintézés into temporary cache storage.
  Future<File> downloadMessageAttachment(
    StoredSession session,
    KretaMessageAttachment attachment, {
    Directory? targetDirectory,
  }) async {
    final urls = [
      KretaEndpoints.getEugyintezesAttachmentUrl(attachment.id),
      KretaEndpoints.getEugyintezesAttachmentMobileUrl(attachment.id),
    ];

    http.Response? successfulResponse;
    int lastStatus = 0;
    for (final url in urls) {
      final response = await _sendWithRetryInterceptor(
        session,
        (accessToken) => _http.get(
          Uri.parse(url),
          headers: _eugyintezesHeaders(accessToken),
        ),
      );
      lastStatus = response.statusCode;
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        successfulResponse = response;
        break;
      }
    }

    if (successfulResponse == null) {
      throw Exception(
        'Csatolmány letöltése sikertelen (HTTP $lastStatus)',
      );
    }

    final dir = targetDirectory ?? await getTemporaryDirectory();
    final rawName =
        attachment.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
    final safeName = rawName.isEmpty ? 'csatolmany.bin' : rawName;
    final safeId =
        attachment.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final prefix = safeId.isEmpty ? 'att' : 'att_$safeId';
    final file = File('${dir.path}/${prefix}_$safeName');
    await file.writeAsBytes(successfulResponse.bodyBytes, flush: true);
    return file;
  }

  /// Sends a new message or reply via e-Ügyintézés and adds it to sent history.
  Future<KretaMessage> sendMessage(
    StoredSession session, {
    required String recipient,
    required String subject,
    required String body,
    String? senderName,
  }) async {
    final msg = KretaMessage(
      uid: 'sent-${DateTime.now().millisecondsSinceEpoch}',
      sender: senderName ?? session.userName ?? 'Tanuló',
      recipients: [recipient.trim()],
      subject: subject.trim(),
      body: body.trim(),
      sentAt: DateTime.now(),
      isRead: true,
      isSent: true,
      detailsLoaded: true,
    );

    final trimmedRecipient = recipient.trim();
    final payload = <String, dynamic>{
      'targy': msg.subject,
      'szoveg': msg.body,
      'cimzettLista': trimmedRecipient.isEmpty
          ? const []
          : [
              {'nev': trimmedRecipient},
            ],
      'csatolmanyok': const [],
    };
    if (_isDemoActive(session)) {
      _localSentMessages.insert(0, msg);
      return msg;
    }
    try {
      final ok = await _postOrPutEugyintezes(
        session,
        KretaEndpoints.getSendEugyintezesMessageUrl(),
        payload,
      );
      if (!ok) {
        await _postOrPutEugyintezes(
          session,
          KretaEndpoints.getSendEugyintezesMessageV1Url(),
          payload,
        );
      }
    } catch (_) {
      // Retain in local sent messages if direct free-text POST is unsupported.
    }

    _localSentMessages.insert(0, msg);
    return msg;
  }

  /// Fetches the student profile via [KretaEndpoints.getStudent].
  Future<Student?> fetchStudentProfile(StoredSession session) async {
    if (_isDemoActive(session)) {
      return DemoDataService.instance.buildDemoStudent();
    }
    try {
      final url = KretaEndpoints.getStudent(session.instituteCode);
      final raw = await _getAuthenticatedJson(session, url);
      if (raw is Map<String, dynamic>) {
        return Student.fromJson(raw);
      }
    } catch (_) {
      // Student profile is supplementary if endpoint fails.
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _safeFetchRawInfoBoard(
    StoredSession session,
  ) async {
    try {
      final raw = await _getAuthenticatedJson(
        session,
        KretaEndpoints.getInfoBoard(session.instituteCode),
      );
      return _extractMessageMaps(raw);
    } catch (_) {
      return const [];
    }
  }

  /// Fetches today's timetable, all grades, homeworks, announced tests,
  /// omissions, messages, and student profile in parallel, using the
  /// transparent token refresh interceptor.
  Future<DashboardData> fetchDashboardData(
    StoredSession initialSession, {
    DateTime? date,
  }) async {
    if (_isDemoActive(initialSession)) {
      return DemoDataService.instance.buildDashboardData(nowOverride: date);
    }
    final session = await ensureValidSession(initialSession);

    final results = await Future.wait<Object?>([
      fetchTodaysTimetable(session, date: date),
      fetchAllGrades(session),
      fetchStudentProfile(session),
      fetchHomeworks(session),
      fetchTests(session),
      fetchOmissions(session),
      fetchMessages(session),
      _safeFetchRawInfoBoard(session),
    ]);

    final todaysLessons = results[0] as List<Lesson>;
    final allGrades = results[1] as List<Grade>;
    final homeworks = List<Homework>.from(results[3] as List<Homework>);

    // Ensure any homeworkUid referenced on today's lessons is hydrated
    final missingHwUids = <String>{};
    for (final lesson in todaysLessons) {
      final hwUid = lesson.homeworkUid?.trim() ?? '';
      if (hwUid.isNotEmpty && findHomeworkForLesson(lesson, homeworks) == null) {
        missingHwUids.add(hwUid);
      }
    }
    if (missingHwUids.isNotEmpty) {
      final fetched = await Future.wait(
        missingHwUids.map((uid) => fetchHomeworkByUid(session, uid)),
      ).timeout(
        const Duration(seconds: 8),
        onTimeout: () => const <Homework?>[],
      );
      for (final hw in fetched) {
        if (hw != null && !homeworks.any((h) => h.uid == hw.uid || h.id == hw.id)) {
          homeworks.add(hw);
        }
      }
      homeworks.sort((a, b) => b.creationDate.compareTo(a.creationDate));
    }

    final omissions = results[5] as List<Omission>;
    final messages = results[6] as List<KretaMessage>;
    final rawInfoNotes = results[7] as List<Map<String, dynamic>>;
    final missingEquipments = MissingEquipmentItem.extractMissingEquipments(
      rawNotes: rawInfoNotes,
      grades: allGrades,
      omissions: omissions,
      messages: messages,
    );

    final payload = DashboardData(
      todaysLessons: todaysLessons,
      allGrades: allGrades,
      latestGrades: allGrades.take(5).toList(),
      student: results[2] as Student?,
      homeworks: homeworks,
      tests: results[4] as List<Test>,
      omissions: omissions,
      messages: messages,
      missingEquipments: missingEquipments,
      activeSession: _latestSession ?? session,
    );
    await saveCachedDashboard(payload);
    return payload;
  }

  /// Loads cached dashboard payload from secure local storage so Főoldal can
  /// render cached cards immediately while background API sync completes.
  Future<DashboardData?> loadCachedDashboard(StoredSession session) async {
    if (_isDemoActive(session)) {
      return DemoDataService.instance.buildDashboardData();
    }
    try {
      final acctKey = TokenStorageService.accountKeyForSession(session);
      final raw = await _storage.loadDashboardCacheJson(acctKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final readIds = await _storage.loadReadMessageIds(accountKey: acctKey);
      final data = DashboardData.fromJson(
        Map<String, dynamic>.from(decoded),
        session,
        readMessageIds: readIds,
      );
      if (data.todaysLessons.isNotEmpty) {
        _cacheTimetableLessons(session, data.todaysLessons);
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Persists [data] per account for zero-wait startup rendering.
  Future<void> saveCachedDashboard(DashboardData data) async {
    if (_isDemoActive(data.activeSession)) return;
    try {
      final acctKey =
          TokenStorageService.accountKeyForSession(data.activeSession);
      await _storage.saveDashboardCacheJson(acctKey, jsonEncode(data.toJson()));
    } catch (_) {}
  }
}
