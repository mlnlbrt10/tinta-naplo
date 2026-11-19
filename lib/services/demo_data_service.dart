import 'package:flutter/material.dart';
import 'package:kreta_api/kreta_api.dart';

import 'kreta_client.dart';
import 'token_storage_service.dart';

/// Generates and serves an isolated, non-destructive realistic Hungarian
/// showcase dataset ("Kovács Bence • 11.B") when Developer Options `Demó mód`
/// is enabled.
///
/// Zero real network requests are made and real `FlutterSecureStorage` tokens
/// or cached KRÉTA payloads are never overwritten or deleted.
class DemoDataService {
  DemoDataService._();

  static final DemoDataService instance = DemoDataService._();

  static const String demoInstituteCode = 'bmszc-neumann';
  static const String demoStudentName = 'Kovács Bence';
  static const String demoSchoolName =
      'Budapesti Műszaki SZC Neumann János Informatikai Technikum';
  static const String demoClassName = '11.B';

  /// Emits whenever the user taps "Demó időzítések újragenerálása (Most)" so
  /// open tabs immediately rebuild with fresh timestamps anchored to `now`.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void regenerateNow() {
    revision.value++;
  }

  static bool isDemoSession(StoredSession? session) =>
      session != null &&
      session.instituteCode == demoInstituteCode &&
      session.accessToken.startsWith('demo_access_token_');

  StoredSession buildDemoSession({DateTime? nowOverride}) {
    final now = nowOverride ?? DateTime.now();
    return StoredSession(
      accessToken: 'demo_access_token_kovacs_bence',
      refreshToken: 'demo_refresh_token_kovacs_bence',
      idToken: 'demo_id_token_kovacs_bence',
      instituteCode: demoInstituteCode,
      userName: demoStudentName,
      expiresAt: now.add(const Duration(hours: 6)),
    );
  }

  Student buildDemoStudent() {
    return Student(
      uid: 'demo-student-kovacs-bence-11b',
      name: demoStudentName,
      addressDataList: const [
        '1146 Budapest, Cházár András utca 10.',
      ],
      bankAccount: const BankAccount(
        accountNumber: null,
        isReadOnly: true,
        ownerName: demoStudentName,
        ownerType: 1,
      ),
      birthdate: DateTime(2009, 5, 14),
      emailAddress: 'kovacs.bence@neumann.bmszc.hu',
      phoneNumber: '+36 30 412 8890',
      schoolYearUID: '2026-2027',
      guardianList: const [],
      instituteCode: demoInstituteCode,
      instituteName: demoSchoolName,
      institution: Institution(
        uid: 'demo-inst-bmszc-neumann',
        shortName: 'BMSZC Neumann • $demoClassName',
        customizationSettings: const CustomizationSettings(
          delayForNotifications: 0,
          isClassAverageVisible: true,
          isLessonsThemeVisible: true,
          nextServerDeployAsString: '',
        ),
        systemModuleList: const [
          SystemModule(isActive: true, type: 'eugyintezes', url: null),
        ],
      ),
    );
  }

  static final List<_SubjectSpec> _subjects = [
    const _SubjectSpec(
      uid: 'demo-subj-mat',
      name: 'Matematika',
      categoryName: 'Matematika',
      teacher: 'Dr. Nagy Péter',
      room: 'B-204',
      sortIndex: 1,
    ),
    const _SubjectSpec(
      uid: 'demo-subj-net',
      name: 'Hálózatok I.',
      categoryName: 'Informatika',
      teacher: 'Kiss Gábor',
      room: 'Lab-3',
      sortIndex: 2,
    ),
    const _SubjectSpec(
      uid: 'demo-subj-db',
      name: 'Adatbázis-kezelés',
      categoryName: 'Informatika',
      teacher: 'Horváth Zoltán',
      room: 'Lab-3',
      sortIndex: 3,
    ),
    const _SubjectSpec(
      uid: 'demo-subj-eng',
      name: 'Angol nyelv',
      categoryName: 'Idegen nyelv',
      teacher: 'Varga Katalin',
      room: 'A-112',
      sortIndex: 4,
    ),
    const _SubjectSpec(
      uid: 'demo-subj-hist',
      name: 'Történelem',
      categoryName: 'Társadalomtudomány',
      teacher: 'Szabó Márton',
      room: 'B-204',
      sortIndex: 5,
    ),
    const _SubjectSpec(
      uid: 'demo-subj-phys',
      name: 'Fizika',
      categoryName: 'Természettudomány',
      teacher: 'Tóth László',
      room: 'B-204',
      sortIndex: 6,
    ),
    const _SubjectSpec(
      uid: 'demo-subj-hun',
      name: 'Magyar nyelv és irodalom',
      categoryName: 'Magyar nyelv',
      teacher: 'Kovácsné Szabó Éva',
      room: 'A-112',
      sortIndex: 7,
    ),
    const _SubjectSpec(
      uid: 'demo-subj-ikt',
      name: 'IKT projektmunka',
      categoryName: 'Informatika',
      teacher: 'Farkas Dániel',
      room: 'Lab-3',
      sortIndex: 8,
    ),
  ];

  static Subject _toSubject(_SubjectSpec s) => Subject(
        uid: s.uid,
        name: s.name,
        category: NameUidDesc(
          uid: s.uid,
          name: s.categoryName,
          description: s.categoryName,
        ),
        sortIndex: s.sortIndex,
      );

  static final NameUidDesc _normalState = NameUidDesc(
    uid: '1,Tervezett',
    name: 'Tervezett',
    description: 'Megtartott / tervezett tanóra',
  );

  static final NameUidDesc _cancelledState = NameUidDesc(
    uid: '2,Elmaradt',
    name: 'Elmaradt',
    description: 'Elmarad',
  );

  static final NameUidDesc _lessonType = NameUidDesc(
    uid: '1,OrarendiOra',
    name: 'Órarendi óra',
    description: 'Tanórai foglalkozás',
  );

  static final NameUid _classGroup11B = NameUid(
    uid: 'demo-cg-11b',
    name: demoClassName,
  );

  /// Computes today's 7-period timetable anchored around [now] so that one
  /// lesson is actively in progress and subsequent periods/breaks run within
  /// today (`00:05 .. 23:55`) regardless of screenshot time of day.
  List<Lesson> buildLessonsForDay(DateTime day, {DateTime? nowOverride}) {
    final now = nowOverride ?? DateTime.now();
    final targetDay = DateUtils.dateOnly(day);
    if (targetDay.weekday > 5) return const [];

    final today = DateUtils.dateOnly(now);
    final isToday = targetDay == today;
    final daySlug =
        '${targetDay.year}${targetDay.month.toString().padLeft(2, '0')}${targetDay.day.toString().padLeft(2, '0')}';

    // 7 slots: 45 min lesson + 10 min break = 55 min stride; full span = 375 min.
    final DateTime slot0Start;
    final int activeIdx;
    if (isToday) {
      final midnight = DateTime(today.year, today.month, today.day);
      final nowMinutes = now.difference(midnight).inMinutes;
      // Put active lesson ~16 minutes in, clamping 7-slot span inside [00:05, 23:55].
      const int totalSpanMinutes = 6 * 55 + 45; // 375
      const int maxBaseStartMinutes = 24 * 60 - 5 - totalSpanMinutes; // 1060
      final int desiredActiveStartMinutes = (nowMinutes - 16).clamp(5, 1435 - 45);
      // Prefer period index 3 (4th lesson) around midday/afternoon, or fit safely.
      int bestIdx = 3;
      int bestDist = 99999;
      for (int idx = 0; idx < 7; idx++) {
        final baseCandidate = desiredActiveStartMinutes - idx * 55;
        if (baseCandidate >= 5 && baseCandidate <= maxBaseStartMinutes) {
          final dist = (idx - 3).abs();
          if (dist < bestDist) {
            bestDist = dist;
            bestIdx = idx;
          }
        }
      }
      activeIdx = bestIdx;
      final clampedBaseMinutes = (desiredActiveStartMinutes - activeIdx * 55)
          .clamp(5, maxBaseStartMinutes);
      slot0Start = midnight.add(Duration(minutes: clampedBaseMinutes));
    } else {
      activeIdx = 2;
      slot0Start = DateTime(targetDay.year, targetDay.month, targetDay.day, 8, 0);
    }

    final int subSlot = isToday ? ((activeIdx + 1) < 7 ? activeIdx + 1 : 0) : 2;
    final int cancelSlot = isToday ? (activeIdx <= 4 ? 6 : 1) : 5;

    final daySchedules = <int, List<(int subjIdx, String theme, String? roomOverride)>>{
      DateTime.monday: [
        (0, 'Logaritmusos egyenletek megoldása', null),
        (1, 'VLAN és trönk portok konfigurálása', null),
        (2, 'SQL JOIN és aggregáló lekérdezések', null),
        (3, 'Academic Writing & Essay Structure', null),
        (4, 'Az 1848–49-es forradalom és szabadságharc', null),
        (5, 'Elektromágneses indukció törvényei', null),
        (6, 'Ady Endre költészetének újításai', null),
      ],
      DateTime.tuesday: [
        (7, 'Agile sprint tervezés és Git workflow', null),
        (0, 'Exponenciális függvények és grafikonok', 'B-204'),
        (2, 'Normálformák és ER diagram tervezés', 'Lab-3'),
        (6, 'Kölcsey és Vörösmarty romantikája', null),
        (3, 'Technical Vocabulary: Cloud Architecture', null),
        (1, 'OSPF dinamikus útválasztás alapjai', null),
        (4, 'A kiegyezés kora és gazdasági fellendülés', null),
      ],
      DateTime.wednesday: [
        (1, 'IPv6 címzés és alhálózat-bontás', null),
        (3, 'Listening Comprehension Practice (B2)', null),
        (0, 'Trigonometrikus azonosságok gyakorlása', null),
        (2, 'Tárolt eljárások és indexelés optimalizálás', null),
        (5, 'Váltakozó áramú áramkörök vizsgálata', null),
        (7, 'Frontend prototípus és komponens-tesztelés', null),
        (6, 'Mikszáth Kálmán elbeszélő művészete', null),
      ],
      DateTime.thursday: [
        (6, 'Stilisztikai alakzatok szövegelemzésben', null),
        (4, 'Első világháború: frontok és hátország', null),
        (0, 'Másodfokú egyenlőtlenségek ismétlés', null),
        (1, 'DHCP relay és hálózati hibakeresés', null),
        (2, 'Tranzakciókezelés és ACID tulajdonságok', null),
        (3, 'Presentation Skills & Peer Feedback', null),
        (5, 'Fénytan: fénytörés és lencsék leképezése', null),
      ],
      DateTime.friday: [
        (3, 'Use of English: Conditionals & Inversion', null),
        (7, 'Backend API integráció és kódellenőrzés', null),
        (1, 'ACL hozzáférési listák Packet Tracerben', null),
        (0, 'Valószínűségszámítás és kombinatorika', null),
        (2, 'NoSQL és dokumentum-alapú adatmodellezés', null),
        (4, 'Trianon és a két világháború közötti évek', null),
        (6, 'József Attila kései költészete', null),
      ],
    };

    final plan = daySchedules[targetDay.weekday] ?? daySchedules[DateTime.monday]!;
    final homeworks = buildDemoHomeworks(nowOverride: now);

    final lessons = <Lesson>[];
    for (int slot = 0; slot < plan.length; slot++) {
      final (subjIdx, theme, roomOverride) = plan[slot];
      final spec = _subjects[subjIdx];
      final subj = _toSubject(spec);
      final start = slot0Start.add(Duration(minutes: slot * 55));
      final end = start.add(const Duration(minutes: 45));
      final isSub = slot == subSlot;
      final isCancelled = slot == cancelSlot;

      String? hwUid;
      if (isToday && slot == activeIdx) {
        hwUid = homeworks.first.uid;
      } else if (isToday && slot == ((activeIdx + 1) < 7 ? activeIdx + 1 : 1)) {
        hwUid = homeworks[1].uid;
      }

      lessons.add(
        Lesson(
          uid: 'demo-lesson-$daySlug-${slot + 1}',
          date: targetDay.toIso8601String(),
          start: start,
          end: end,
          name: spec.name,
          lessonNumber: slot + 1,
          lessonSeqNumber: 120 + slot,
          classGroup: _classGroup11B,
          teacher: spec.teacher,
          subject: subj,
          theme: isCancelled ? 'Hivatalos rendezvény miatt elmarad' : theme,
          roomName: roomOverride ?? spec.room,
          type: _lessonType,
          state: isCancelled ? _cancelledState : _normalState,
          substituteTeacher: isSub ? 'Kovácsné Szabó Éva' : null,
          homeworkUid: hwUid,
          canStudentEditHomework: false,
          isHomeworkComplete: false,
          attachments: const [],
          isDigitalLesson: false,
          digitalSupportDeviceTypeList: const [],
          createdAt: start.subtract(const Duration(days: 7)),
          lastModifiedAt: start.subtract(const Duration(hours: 2)),
        ),
      );
    }
    return lessons;
  }

  List<Lesson> buildTimetableForRange(
    DateTime from,
    DateTime to, {
    DateTime? nowOverride,
  }) {
    final now = nowOverride ?? DateTime.now();
    final startDay = DateUtils.dateOnly(from);
    final endDay = DateUtils.dateOnly(to);
    final out = <Lesson>[];
    for (DateTime d = startDay;
        !d.isAfter(endDay);
        d = d.add(const Duration(days: 1))) {
      out.addAll(buildLessonsForDay(d, nowOverride: now));
    }
    out.sort((a, b) => a.start.toLocal().compareTo(b.start.toLocal()));
    return out;
  }

  /// Builds 28 realistic grades across the 8 subjects producing an exact
  /// **4.58** weighted overall average (`229 / 50 = 4.580`).
  List<Grade> buildDemoGrades({DateTime? nowOverride}) {
    final now = nowOverride ?? DateTime.now();
    final evalType = NameUidDesc(
      uid: 'evkozi_jegy',
      name: 'EvkoziJegy',
      description: 'Évközi jegy/értékelés',
    );
    final valueType = NameUidDesc(
      uid: 'Osztalyzat',
      name: 'Osztalyzat',
      description: 'Ötfokozatú osztályzat',
    );
    NameUidDesc modeDesc(String name) => NameUidDesc(
          uid: 'mode_$name',
          name: name,
          description: name,
        );

    final specs = [
      // Matematika (4 grades: 5@200%, 4@100%, 5@100%, 4@50%)
      (0, 5, 'Jeles (5)', '5', 200, 'Témazáró dolgozat', 'Logaritmus és exponenciális függvények', 0),
      (0, 4, 'Jó (4)', '4', 100, 'Írásbeli röpdolgozat', 'Egyenletrendszerek megoldása', 3),
      (0, 5, 'Jeles (5)', '5', 100, 'Órai munka', 'Függvénytranszformációk táblánál', 14),
      (0, 4, 'Jó (4)', '4', 50, 'Házi feladat ellenőrzése', 'Gyakorló feladatsor 4.', 21),

      // Hálózatok I. (4 grades: 5@200%, 5@100%, 4@50%, 5@50%)
      (1, 5, 'Jeles (5)', '5', 200, 'Gyakorlati témazáró', 'VLAN, trunk és router-on-a-stick lab', 0),
      (1, 5, 'Jeles (5)', '5', 100, 'Labor mérés', 'OSPF többterületes hálózat szimuláció', 1),
      (1, 4, 'Jó (4)', '4', 50, 'Röpdolgozat', 'IPv6 alhálózat-kiosztás', 12),
      (1, 5, 'Jeles (5)', '5', 50, 'Projektértékelés', 'Packet Tracer topológia dokumentáció', 19),

      // Adatbázis-kezelés (4 grades: 5@200%, 4@100%, 5@50%, 5@50%)
      (2, 5, 'Jeles (5)', '5', 200, 'Témazáró dolgozat', 'SQL JOIN, allekérdezések és nézetek', 0),
      (2, 4, 'Jó (4)', '4', 100, 'Gyakorlati feladat', '3NF normalizálás és ER tervezés', 5),
      (2, 5, 'Jeles (5)', '5', 50, 'Órai munka', 'Aggregáló függvények HAVING-gel', 16),
      (2, 5, 'Jeles (5)', '5', 50, 'Szóbeli felelet', 'Tranzakciók és ACID elvek', 23),

      // Angol nyelv (3 grades: 5@100%, 5@100%, 4@50%)
      (3, 5, 'Jeles (5)', '5', 100, 'Esszé', 'Argumentative Essay: AI in Education', 1),
      (3, 5, 'Jeles (5)', '5', 100, 'Hallásértés', 'B2 Mock Exam Listening Section', 11),
      (3, 4, 'Jó (4)', '4', 50, 'Szódolgozat', 'IT & Cloud Infrastructure Phrasal Verbs', 18),

      // Történelem (3 grades: 4@200%, 4@50%, 5@50%)
      (4, 4, 'Jó (4)', '4', 200, 'Témazáró dolgozat', 'Az 1848–49-es szabadságharc és dualizmus', 4),
      (4, 4, 'Jó (4)', '4', 50, 'Forráselemzés', 'Áprilisi törvények szövegelemzése', 13),
      (4, 5, 'Jeles (5)', '5', 50, 'Kiselőadás', 'Ipari forradalom és magyar vasútépítés', 20),

      // Fizika (3 grades: 4@100%, 4@50%, 4@50%)
      (5, 4, 'Jó (4)', '4', 100, 'Írásbeli dolgozat', 'Elektromágneses indukció és transzformátorok', 6),
      (5, 4, 'Jó (4)', '4', 50, 'Mérési jegyzőkönyv', 'Ohm törvénye váltakozó áramkörben', 15),
      (5, 4, 'Jó (4)', '4', 50, 'Számolási feladat', 'Lorentz-erő alkalmazásai', 24),

      // Magyar nyelv és irodalom (4 grades: 4@100%, 4@100%, 5@50%, 4@50%)
      (6, 4, 'Jó (4)', '4', 100, 'Műelemzés', 'Ady Endre: Új versek ciklus elemzése', 2),
      (6, 4, 'Jó (4)', '4', 100, 'Nyelvtani dolgozat', 'Szövegkohézió és stílusrétegek', 10),
      (6, 5, 'Jeles (5)', '5', 50, 'Versmondás', 'Kosztolányi Dezső: Boldog, szomorú dal', 17),
      (6, 4, 'Jó (4)', '4', 50, 'Órai munka', 'Retorikai érvelés gyakorlat', 25),

      // IKT projektmunka (3 grades: 5@100%, 5@50%, 5@50%)
      (7, 5, 'Jeles (5)', '5', 100, 'Sprint bemutató', 'Mobil webshop prototípus és REST API', 1),
      (7, 5, 'Jeles (5)', '5', 50, 'Kódminőség', 'Pull request review és egységtesztek', 8),
      (7, 5, 'Jeles (5)', '5', 50, 'Dokumentáció', 'Rendszerterv és felhasználói kézikönyv', 22),
    ];

    final out = <Grade>[];
    for (int i = 0; i < specs.length; i++) {
      final (
        subjIdx,
        val,
        strVal,
        shortVal,
        weight,
        modeName,
        topic,
        daysAgo,
      ) = specs[i];
      final spec = _subjects[subjIdx];
      final subj = _toSubject(spec);
      final ts = DateTime(
        now.year,
        now.month,
        now.day,
        10 + (i % 5),
        15 + ((i * 7) % 40),
      ).subtract(Duration(days: daysAgo));
      out.add(
        Grade(
          uid: 'demo-grade-$i',
          recordDate: ts,
          creationDate: ts,
          subject: subj,
          topic: topic,
          type: evalType,
          mode: modeDesc(modeName),
          valueType: valueType,
          teacher: spec.teacher,
          numericValue: val,
          strValue: strVal,
          weightPercentage: weight,
          shortStrValue: shortVal,
          classGroup: UidObj(uid: _classGroup11B.uid),
          sortIndex: i,
        ),
      );
    }
    out.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return out;
  }

  List<Test> buildDemoTests({DateTime? nowOverride}) {
    final now = nowOverride ?? DateTime.now();
    final today = DateUtils.dateOnly(now);
    final items = [
      (0, 1, 2, 'Írásbeli témazáró dolgozat', 'Exponenciális és logaritmikus egyenletek'),
    ];
    return [
      for (int i = 0; i < items.length; i++)
        () {
          final (subjIdx, inDays, period, method, theme) = items[i];
          final spec = _subjects[subjIdx];
          final examDate = today.add(Duration(days: inDays, hours: 8 + period));
          return Test(
            uid: 'demo-test-$i',
            date: examDate,
            reportDate: today.subtract(Duration(days: 5 - i)),
            teacherName: spec.teacher,
            lessonNumber: period,
            subject: _toSubject(spec),
            subjectName: spec.name,
            theme: theme,
            method: NameUidDesc(
              uid: 'test-method-$i',
              name: method,
              description: method,
            ),
            classGroup: UidObj(uid: _classGroup11B.uid),
          );
        }(),
    ];
  }

  List<Homework> buildDemoHomeworks({DateTime? nowOverride}) {
    final now = nowOverride ?? DateTime.now();
    final today = DateUtils.dateOnly(now);
    final specs = [
      (
        0,
        1,
        'Gyakorló feladatlap 12–18. feladat (logaritmikus egyenletek megoldása füzetben).',
        false,
      ),
      (
        2,
        0,
        'Írj 5 db összetett SELECT JOIN lekérdezést a webshop adatbázis sémához (GROUP BY + HAVING).',
        true,
      ),
      (
        3,
        -1,
        'Prepare a 180-word Opinion Essay on remote teamwork tools (Student Book p. 64).',
        true,
      ),
      (
        1,
        -2,
        'VLAN IPv4 címzési táblázat kitöltése és feltöltése PDF-ben.',
        true,
      ),
    ];

    return [
      for (int i = 0; i < specs.length; i++)
        () {
          final (subjIdx, dueInDays, desc, done) = specs[i];
          final spec = _subjects[subjIdx];
          final due = today.add(Duration(days: dueInDays, hours: 16));
          final start = due.subtract(const Duration(days: 3));
          return Homework(
            uid: 'demo-hw-$i',
            subject: _toSubject(spec),
            subjectName: spec.name,
            teacherName: spec.teacher,
            description: desc,
            startDate: start,
            dueDate: due,
            creationDate: start,
            isCreatedByTeacher: true,
            isDone: done,
            canBeSubmitted: false,
            classGroup: UidObj(uid: _classGroup11B.uid),
            canAttach: false,
          );
        }(),
    ];
  }

  List<Omission> buildDemoOmissions({DateTime? nowOverride}) {
    final now = nowOverride ?? DateTime.now();
    final today = DateUtils.dateOnly(now);
    final items = [
      (5, 6, 4, 'Orvosi igazolás'),
      (6, 12, 1, 'Orvosi igazolás'),
    ];
    return [
      for (int i = 0; i < items.length; i++)
        () {
          final (subjIdx, daysAgo, period, proofDesc) = items[i];
          final spec = _subjects[subjIdx];
          final d = today.subtract(Duration(days: daysAgo));
          final start = DateTime(d.year, d.month, d.day, 7 + period, 0);
          return Omission(
            uid: 'demo-omission-$i',
            subject: _toSubject(spec),
            lesson: OmittedLesson(
              start: start,
              end: start.add(const Duration(minutes: 45)),
              classNo: period,
            ),
            date: d,
            teacher: spec.teacher,
            type: NameUidDesc(
              uid: 'Mul',
              name: 'Orarendihiany',
              description: 'Tanórai hiányzás',
            ),
            mode: null,
            lateForMin: null,
            createdAt: start.add(const Duration(minutes: 20)),
            state: OmissionState.excused,
            proofType: NameUidDesc(
              uid: 'orvosi',
              name: proofDesc,
              description: proofDesc,
            ),
            classGroup: UidObj(uid: _classGroup11B.uid),
          );
        }(),
    ];
  }

  List<KretaMessage> buildDemoMessages({DateTime? nowOverride}) {
    final now = nowOverride ?? DateTime.now();
    return [
      KretaMessage(
        uid: 'demo-msg-1',
        messageId: 'demo-msg-1',
        sender: 'Kovácsné Szabó Éva',
        senderTitle: 'Osztályfőnök • 11.B',
        recipients: const [demoStudentName],
        subject: 'Nyílt nap és pályaorientációs műhely — jövő hét csütörtök',
        body:
            'Kedves 11.B!\n\nJövő hét csütörtökön 10:00 órától az auditóriumban kerül megrendezésre az őszi informatikai pályaorientációs nap. A 4. óra után közösen megyünk át.',
        sentAt: now.subtract(const Duration(hours: 5)),
        isRead: false,
        isSent: false,
        detailsLoaded: true,
      ),
      KretaMessage(
        uid: 'demo-msg-2',
        messageId: 'demo-msg-2',
        sender: 'Kiss Gábor',
        senderTitle: 'Szaktanár',
        recipients: const [demoStudentName],
        subject: 'Cisco Hálózati Akadémia — gyakorló feladatsor elérhető',
        body:
            'Szia Bence!\n\nFeltöltöttem az OSPF és IPv6 gyakorló Packet Tracer fájlokat a pénteki mérés előkészítéséhez.',
        sentAt: now.subtract(const Duration(days: 2)),
        isRead: true,
        isSent: false,
        detailsLoaded: true,
      ),
      KretaMessage(
        uid: 'demo-msg-3',
        messageId: 'demo-msg-3',
        sender: 'Iskolai Értesítő',
        senderTitle: 'Rendszerüzenet',
        recipients: const ['11.B osztály'],
        subject: 'Tanterem-változás a héten',
        body:
            'Felhívjuk a figyelmet, hogy a labor-karbantartás ideje alatt egyes gyakorlatok a B-204 és Lab-3 termek között kerülnek megtartásra.',
        sentAt: now.subtract(const Duration(days: 4)),
        isRead: true,
        isSent: false,
        isSystemMessage: true,
        detailsLoaded: true,
      ),
    ];
  }

  DashboardData buildDashboardData({DateTime? nowOverride}) {
    final now = nowOverride ?? DateTime.now();
    final allGrades = buildDemoGrades(nowOverride: now);
    return DashboardData(
      student: buildDemoStudent(),
      todaysLessons: buildLessonsForDay(now, nowOverride: now),
      allGrades: allGrades,
      latestGrades: allGrades.take(5).toList(),
      homeworks: buildDemoHomeworks(nowOverride: now),
      tests: buildDemoTests(nowOverride: now),
      omissions: buildDemoOmissions(nowOverride: now),
      messages: buildDemoMessages(nowOverride: now),
      activeSession: buildDemoSession(nowOverride: now),
    );
  }
}

class _SubjectSpec {
  final String uid;
  final String name;
  final String categoryName;
  final String teacher;
  final String room;
  final int sortIndex;

  const _SubjectSpec({
    required this.uid,
    required this.name,
    required this.categoryName,
    required this.teacher,
    required this.room,
    required this.sortIndex,
  });
}

/// Clean local/bundled student avatar graphic for Showcase Demo Mode
/// (zero external network dependency).
class DemoStudentAvatar extends StatelessWidget {
  final double size;
  final Color? accentColor;
  final bool showClassBadge;

  const DemoStudentAvatar({
    super.key,
    required this.size,
    this.accentColor,
    this.showClassBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = accentColor ?? scheme.primary;
    final secondary = Color.lerp(primary, const Color(0xFF38BDF8), 0.45)!;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  primary.withValues(alpha: 0.92),
                  secondary.withValues(alpha: 0.85),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.25),
                  blurRadius: size * 0.22,
                  offset: Offset(0, size * 0.06),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: -size * 0.14,
                  right: -size * 0.10,
                  child: Container(
                    width: size * 0.6,
                    height: size * 0.6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                ),
                Text(
                  'KB',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: size * 0.36,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
          if (showClassBadge)
            Positioned(
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                    width: 1,
                  ),
                ),
                child: const Text(
                  '11.B',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
