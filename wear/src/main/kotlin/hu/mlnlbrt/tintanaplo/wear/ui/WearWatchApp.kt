package hu.mlnlbrt.tintanaplo.wear.ui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.ExperimentalWearFoundationApi
import androidx.wear.compose.foundation.hierarchicalFocusGroup
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.ScalingLazyColumnDefaults
import androidx.wear.compose.foundation.lazy.ScalingLazyListState
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.foundation.pager.HorizontalPager
import androidx.wear.compose.foundation.pager.PagerDefaults
import androidx.wear.compose.foundation.pager.rememberPagerState
import androidx.wear.compose.foundation.requestFocusOnHierarchyActive
import androidx.wear.compose.foundation.rotary.RotaryScrollableDefaults
import androidx.wear.compose.foundation.rotary.rotaryScrollable
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.HorizontalPageIndicator
import androidx.wear.compose.material.PageIndicatorState
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import hu.mlnlbrt.tintanaplo.wear.auth.RemoteAuthStatus
import hu.mlnlbrt.tintanaplo.wear.auth.WearRemoteAuthManager
import hu.mlnlbrt.tintanaplo.wear.data.Exam
import hu.mlnlbrt.tintanaplo.wear.data.Grade
import hu.mlnlbrt.tintanaplo.wear.data.InvalidGrantException
import hu.mlnlbrt.tintanaplo.wear.data.KretaDateParser
import hu.mlnlbrt.tintanaplo.wear.data.KretaWearApiClient
import hu.mlnlbrt.tintanaplo.wear.data.Lesson
import hu.mlnlbrt.tintanaplo.wear.data.RolloverTimetableState
import hu.mlnlbrt.tintanaplo.wear.data.SecureTokenStorage
import hu.mlnlbrt.tintanaplo.wear.data.StoredSession
import hu.mlnlbrt.tintanaplo.wear.data.TimetableDayFilter
import hu.mlnlbrt.tintanaplo.wear.data.TimetableDaySelectionState
import hu.mlnlbrt.tintanaplo.wear.data.TimetablePhase
import hu.mlnlbrt.tintanaplo.wear.data.TimetableStatus
import hu.mlnlbrt.tintanaplo.wear.data.TimetableStatusEvaluator
import hu.mlnlbrt.tintanaplo.wear.data.TokenExpiredException
import hu.mlnlbrt.tintanaplo.wear.sync.KretaSyncScheduler
import hu.mlnlbrt.tintanaplo.wear.sync.KretaSyncWorker
import hu.mlnlbrt.tintanaplo.wear.ui.theme.TintaColors
import hu.mlnlbrt.tintanaplo.wear.ui.theme.TintaWearTheme
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.ZoneId
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

private val LessonCardShape = RoundedCornerShape(22.dp)
private val TnumSubtitleStyle = TextStyle(
    fontSize = 9.5.sp,
    color = TintaColors.TextSecondary,
    fontFeatureSettings = "tnum",
)

@Immutable
private data class TimetableLessonRowUi(
    val stableKey: String,
    val periodBadgeText: String,
    val subjectTitle: String,
    val metaLine: String,
    val statusLabel: String?,
    val isCancelled: Boolean,
    val badgeBg: Color,
    val badgeTextColor: Color,
    val cardBg: Color,
    val borderColor: Color,
    val borderWidth: Dp,
    val statusFg: Color,
    val statusBg: Color,
    val cardAlpha: Float,
)

@Immutable
private data class GradeRowUi(
    val stableKey: String,
    val gradeBadgeText: String,
    val subjectTitle: String,
    val metaLine: String,
    val badgeBg: Color,
    val badgeTextColor: Color,
    val borderColor: Color,
)

@Immutable
private data class ExamRowUi(
    val stableKey: String,
    val dateBadgeText: String,
    val subjectTitle: String,
    val detailLine: String,
    val badgeBg: Color,
    val badgeFg: Color,
    val borderColor: Color,
)

@Composable
fun TintaWearApp(resumeEpoch: Int = 0) {
    val context = LocalContext.current
    val tokenStore = remember { SecureTokenStorage(context) }
    val remoteAuth = remember { WearRemoteAuthManager.getInstance(context) }
    val apiClient = remember {
        KretaWearApiClient(
            tokenStore = tokenStore,
            onSessionRefreshed = { refreshed ->
                remoteAuth.pushRefreshedSessionToPhone(refreshed)
            },
        )
    }
    val authStatus by remoteAuth.status.collectAsState()
    val dashboardSyncEpoch by remoteAuth.dashboardSyncEpoch.collectAsState()
    val scope = rememberCoroutineScope()

    var session by remember {
        mutableStateOf(runCatching { tokenStore.loadSession() }.getOrNull())
    }
    var loginNotice by remember { mutableStateOf<String?>(null) }

    DisposableEffect(Unit) {
        remoteAuth.startForegroundListening()
        onDispose {
            remoteAuth.stopForegroundListening()
        }
    }

    LaunchedEffect(authStatus) {
        if (authStatus is RemoteAuthStatus.Succeeded) {
            val newSession = (authStatus as RemoteAuthStatus.Succeeded).session
            session = newSession
            loginNotice = null
            remoteAuth.resetStatusToIdle()
            KretaSyncScheduler.ensurePeriodicSync(context)
        }
    }

    LaunchedEffect(resumeEpoch) {
        val loaded = withContext(Dispatchers.IO) {
            runCatching { tokenStore.loadSession() }.getOrNull()
        }
        if (loaded != null) {
            session = loaded
        }
    }

    TintaWearTheme {
        val activeSession = session
        if (activeSession == null) {
            WearLoginScreen(
                authStatus = authStatus,
                noticeMessage = loginNotice,
                onStartPhoneLogin = {
                    loginNotice = null
                    scope.launch {
                        remoteAuth.startPhoneLogin()
                    }
                },
            )
        } else {
            WearThreePageWatchUi(
                session = activeSession,
                tokenStore = tokenStore,
                apiClient = apiClient,
                resumeEpoch = resumeEpoch,
                dashboardSyncEpoch = dashboardSyncEpoch,
            )
        }
    }
}

@OptIn(ExperimentalWearFoundationApi::class)
@Composable
private fun WearThreePageWatchUi(
    session: StoredSession,
    tokenStore: SecureTokenStorage,
    apiClient: KretaWearApiClient,
    resumeEpoch: Int,
    dashboardSyncEpoch: Long,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pagerState = rememberPagerState(pageCount = { 3 })
    val timetableListState = rememberScalingLazyListState()
    val gradesExamsListState = rememberScalingLazyListState()

    val instituteKey = remember(session.instituteCode) {
        session.instituteCode.trim().lowercase()
    }
    val accountKey = remember(session.instituteCode, session.userName) {
        SecureTokenStorage.accountKeyFor(session)
    }

    val initialCache = remember(instituteKey) {
        runCatching {
            tokenStore.loadWearDataCache(accountKey, KretaDateParser.dateKeyFor())
        }.getOrNull()
    }

    var lessons by remember(instituteKey) {
        mutableStateOf(initialCache?.lessons ?: emptyList())
    }
    var grades by remember(instituteKey) {
        mutableStateOf(initialCache?.grades ?: emptyList())
    }
    var exams by remember(instituteKey) {
        mutableStateOf(initialCache?.exams ?: emptyList())
    }
    var isSyncing by remember(instituteKey) { mutableStateOf(false) }
    var hasLoadedOnce by remember(instituteKey) { mutableStateOf(initialCache != null) }

    var boundaryNowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var liveNowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val liveNowMsProvider = remember { { liveNowMs } }

    // Boundary ticker updates only at lesson start/end/midnight transitions so
    // the pager, day-rollover calculation, and list items never recompose on 1s ticks.
    LaunchedEffect(lessons, resumeEpoch) {
        while (true) {
            val now = System.currentTimeMillis()
            boundaryNowMs = now
            liveNowMs = now
            val delayMs = TimetableStatusEvaluator.millisUntilNextTransition(lessons, now)
            delay(delayMs)
        }
    }

    val rolloverState = remember(lessons, boundaryNowMs) {
        TimetableStatusEvaluator.evaluateWithRollover(lessons, boundaryNowMs)
    }
    val todayDate = remember(boundaryNowMs) {
        KretaDateParser.localDateFor(boundaryNowMs)
    }

    var manualDayOverride by remember(instituteKey) {
        mutableStateOf<TimetableDayFilter?>(null)
    }
    LaunchedEffect(todayDate) {
        manualDayOverride = null
    }

    val effectiveDayFilter = manualDayOverride ?: if (rolloverState.isRolledOverToNextDay) {
        TimetableDayFilter.NEXT_SCHOOL_DAY
    } else {
        TimetableDayFilter.TODAY
    }

    val daySelection = remember(lessons, effectiveDayFilter, boundaryNowMs) {
        TimetableStatusEvaluator.selectTimetableDay(lessons, effectiveDayFilter, boundaryNowMs)
    }

    val timetableRows = remember(
        daySelection.lessons,
        daySelection.isShowingToday,
        rolloverState.todayStatus.currentLesson,
        boundaryNowMs,
    ) {
        buildTimetableRowModels(
            lessons = daySelection.lessons,
            isShowingToday = daySelection.isShowingToday,
            currentLesson = rolloverState.todayStatus.currentLesson,
            boundaryNowMs = boundaryNowMs,
        )
    }

    val recentGradeRows = remember(grades) {
        buildGradeRowModels(grades)
    }
    val upcomingExamRows = remember(exams, boundaryNowMs) {
        buildExamRowModels(exams, boundaryNowMs)
    }

    val isLiveCountdownPhase = !rolloverState.isRolledOverToNextDay && (
        rolloverState.todayStatus.phase == TimetablePhase.ACTIVE_LESSON ||
            rolloverState.todayStatus.phase == TimetablePhase.BREAK ||
            rolloverState.todayStatus.phase == TimetablePhase.BEFORE_FIRST_LESSON
        )
    val isOnPage0 by remember { derivedStateOf { pagerState.currentPage == 0 } }

    // 1-second ticker runs only while Page 0 is visible and counting down, and is read
    // exclusively inside leaf progress-ring / countdown composables.
    LaunchedEffect(isOnPage0, isLiveCountdownPhase, resumeEpoch) {
        if (!isOnPage0 || !isLiveCountdownPhase) return@LaunchedEffect
        while (true) {
            liveNowMs = System.currentTimeMillis()
            delay(1_000L)
        }
    }

    // Reload offline cache immediately when DataLayer pushes new grades/exams from phone.
    LaunchedEffect(instituteKey, dashboardSyncEpoch) {
        if (dashboardSyncEpoch <= 0L) return@LaunchedEffect
        val cached = withContext(Dispatchers.IO) {
            runCatching {
                tokenStore.loadWearDataCache(accountKey, KretaDateParser.dateKeyFor())
            }.getOrNull()
        }
        if (cached != null) {
            if (cached.lessons.isNotEmpty() || lessons.isEmpty()) {
                lessons = cached.lessons
            }
            grades = cached.grades
            exams = cached.exams
            hasLoadedOnce = true
        }
    }

    // Reload freshest cache on resume and refresh silently against KRÉTA in the background.
    // Never clear session or cached timetable data on network/token errors.
    LaunchedEffect(instituteKey, resumeEpoch) {
        val cached = withContext(Dispatchers.IO) {
            runCatching {
                tokenStore.loadWearDataCache(accountKey, KretaDateParser.dateKeyFor())
            }.getOrNull()
        }
        if (cached != null) {
            lessons = cached.lessons
            grades = cached.grades
            exams = cached.exams
            hasLoadedOnce = true
        }
        if (isSyncing) return@LaunchedEffect
        isSyncing = true
        scope.launch {
            try {
                val latestSession = withContext(Dispatchers.IO) {
                    runCatching { tokenStore.loadSession() }.getOrNull()
                } ?: session
                val synced = apiClient.syncAll(latestSession)
                lessons = synced.lessons
                grades = synced.grades
                exams = synced.exams
                hasLoadedOnce = true
                KretaSyncScheduler.ensurePeriodicSync(context)
                KretaSyncScheduler.scheduleNextTransitionUpdate(context, synced.lessons)
                KretaSyncWorker.requestTileUpdate(context)
            } catch (ce: CancellationException) {
                throw ce
            } catch (_: TokenExpiredException) {
                hasLoadedOnce = true
            } catch (_: InvalidGrantException) {
                hasLoadedOnce = true
            } catch (_: Throwable) {
                hasLoadedOnce = true
            } finally {
                isSyncing = false
            }
        }
    }

    val overlayAlpha by remember {
        derivedStateOf {
            (pagerState.currentPage + pagerState.currentPageOffsetFraction).coerceIn(0f, 1f)
        }
    }
    val showSecondaryOverlay by remember {
        derivedStateOf { pagerState.currentPage > 0 || pagerState.currentPageOffsetFraction > 0.02f }
    }
    val pagerFlingBehavior = PagerDefaults.snapFlingBehavior(
        state = pagerState,
        snapAnimationSpec = spring(
            dampingRatio = Spring.DampingRatioNoBouncy,
            stiffness = Spring.StiffnessMediumLow,
        ),
    )
    val pageIndicatorState = remember(pagerState) {
        object : PageIndicatorState {
            override val pageCount: Int get() = 3
            override val selectedPage: Int get() = pagerState.currentPage
            override val pageOffset: Float get() = pagerState.currentPageOffsetFraction
        }
    }

    Scaffold(
        timeText = {
            if (showSecondaryOverlay) {
                TimeText(
                    modifier = Modifier.graphicsLayer { alpha = overlayAlpha },
                )
            }
        },
        positionIndicator = {
            if (showSecondaryOverlay) {
                val activeListState = if (pagerState.currentPage >= 2) {
                    gradesExamsListState
                } else {
                    timetableListState
                }
                PositionIndicator(
                    scalingLazyListState = activeListState,
                    modifier = Modifier.graphicsLayer { alpha = overlayAlpha },
                )
            }
        },
        pageIndicator = {
            HorizontalPageIndicator(
                pageIndicatorState = pageIndicatorState,
                selectedColor = TintaColors.AccentBlue,
                unselectedColor = TintaColors.PillBorder,
                indicatorSize = 4.5.dp,
                spacing = 4.dp,
                modifier = Modifier.padding(bottom = 3.dp),
            )
        },
    ) {
        HorizontalPager(
            state = pagerState,
            beyondViewportPageCount = 1,
            flingBehavior = pagerFlingBehavior,
            rotaryScrollableBehavior = null,
            key = { it },
            modifier = Modifier
                .fillMaxSize()
                .background(TintaColors.PureBlack),
        ) { page ->
            val pageModifier = Modifier
                .fillMaxSize()
                .hierarchicalFocusGroup(active = pagerState.currentPage == page)
                .graphicsLayer {
                    val pageOffset = ((pagerState.currentPage - page) + pagerState.currentPageOffsetFraction)
                        .coerceIn(-1f, 1f)
                    val visibility = (1f - abs(pageOffset)).coerceIn(0f, 1f)
                    val inv = 1f - visibility
                    val cubicEased = 1f - (inv * inv * inv)
                    val scale = 0.92f + 0.08f * cubicEased
                    scaleX = scale
                    scaleY = scale
                    alpha = 0.35f + 0.65f * cubicEased
                }

            when (page) {
                0 -> CurrentLessonBezelPage(
                    rolloverState = rolloverState,
                    isLoadingInitial = !hasLoadedOnce && isSyncing,
                    nowMsProvider = liveNowMsProvider,
                    modifier = pageModifier,
                )

                1 -> TimetablePage(
                    listState = timetableListState,
                    daySelection = daySelection,
                    rows = timetableRows,
                    isLoadingInitial = !hasLoadedOnce && isSyncing,
                    onSelectDay = { nextFilter ->
                        manualDayOverride = nextFilter
                        scope.launch {
                            runCatching { timetableListState.scrollToItem(0) }
                        }
                    },
                    modifier = pageModifier,
                )

                else -> GradesAndExamsPage(
                    listState = gradesExamsListState,
                    examRows = upcomingExamRows,
                    gradeRows = recentGradeRows,
                    isLoadingInitial = !hasLoadedOnce && isSyncing,
                    modifier = pageModifier,
                )
            }
        }
    }
}

private fun buildTimetableRowModels(
    lessons: List<Lesson>,
    isShowingToday: Boolean,
    currentLesson: Lesson?,
    boundaryNowMs: Long,
): List<TimetableLessonRowUi> {
    if (lessons.isEmpty()) return emptyList()
    val seenKeys = HashMap<String, Int>(lessons.size)
    return lessons.map { lesson ->
        val baseKey = "${lesson.uid}_${lesson.startEpochMs}"
        val occ = (seenKeys[baseKey] ?: 0) + 1
        seenKeys[baseKey] = occ
        val stableKey = if (occ == 1) baseKey else "${baseKey}_$occ"

        val isActive = isShowingToday &&
            currentLesson?.uid == lesson.uid &&
            currentLesson.startEpochMs == lesson.startEpochMs
        val isFinished = isShowingToday &&
            !isActive &&
            boundaryNowMs >= lesson.endEpochMs
        val isCancelled = lesson.isCancelled
        val isSubstituted = lesson.isSubstituted

        val badgeBg = when {
            isCancelled -> TintaColors.Crimson
            isSubstituted -> TintaColors.Amber
            isActive -> TintaColors.AccentBlue
            else -> TintaColors.SmokedSurfaceAlt
        }
        val badgeTextColor = if (isCancelled || isSubstituted || isActive) {
            TintaColors.PureBlack
        } else {
            TintaColors.TextSecondary
        }
        val borderColor = when {
            isActive -> TintaColors.AccentBlue
            isCancelled -> TintaColors.CrimsonBorder
            isSubstituted -> TintaColors.AmberBorder
            else -> TintaColors.SubtleBorder
        }
        val statusLabel = when {
            isCancelled -> "Elmaradt"
            isSubstituted -> "Helyettesítés: ${lesson.cleanSubstituteTeacher}"
            else -> null
        }
        val room = lesson.cleanRoomName
        val metaLine = if (room != null) {
            "${lesson.compactTimeRangeLabel} • $room"
        } else {
            lesson.compactTimeRangeLabel
        }

        TimetableLessonRowUi(
            stableKey = stableKey,
            periodBadgeText = lesson.lessonNumber?.let { "$it." } ?: "•",
            subjectTitle = lesson.displaySubject,
            metaLine = metaLine,
            statusLabel = statusLabel,
            isCancelled = isCancelled,
            badgeBg = badgeBg,
            badgeTextColor = badgeTextColor,
            cardBg = if (isActive) TintaColors.ActiveHeroSurface else TintaColors.SmokedSurface,
            borderColor = borderColor,
            borderWidth = if (isActive) 1.5.dp else 1.dp,
            statusFg = if (isCancelled) TintaColors.Crimson else TintaColors.Amber,
            statusBg = if (isCancelled) TintaColors.CrimsonSoft else TintaColors.AmberSoft,
            cardAlpha = if (isFinished || isCancelled) 0.56f else 1f,
        )
    }
}

private fun buildGradeRowModels(grades: List<Grade>): List<GradeRowUi> {
    if (grades.isEmpty()) return emptyList()
    val sorted = grades.sortedByDescending { it.recordedAtEpochMs }.take(5)
    val seenKeys = HashMap<String, Int>(sorted.size)
    return sorted.map { grade ->
        val baseKey = "${grade.uid}_${grade.recordedAtEpochMs}"
        val occ = (seenKeys[baseKey] ?: 0) + 1
        seenKeys[baseKey] = occ
        val stableKey = if (occ == 1) baseKey else "${baseKey}_$occ"

        val (badgeBg, borderColor) = when (grade.numericValue) {
            5 -> TintaColors.AccentTeal to TintaColors.AccentTealBorder
            4 -> TintaColors.AccentBlue to TintaColors.AccentBlueBorder
            3 -> TintaColors.Amber to TintaColors.AmberBorder
            2 -> TintaColors.Coral to TintaColors.CoralBorder
            1 -> TintaColors.Crimson to TintaColors.CrimsonBorder
            else -> TintaColors.AccentIndigo to TintaColors.AccentIndigoBorder
        }
        val dateStr = KretaDateParser.formatMonthDay(grade.recordedAtEpochMs)
        val weightPart = grade.weightPercentage?.takeIf { it > 0 }?.let { "$it%" }
        val topicPart = grade.topic?.trim()?.takeIf { it.isNotEmpty() }
            ?: grade.modeDescription?.trim()?.takeIf { it.isNotEmpty() }
        val metaLine = listOfNotNull(weightPart, topicPart, dateStr).joinToString(" • ")

        GradeRowUi(
            stableKey = stableKey,
            gradeBadgeText = grade.displayValue,
            subjectTitle = grade.subjectName,
            metaLine = metaLine,
            badgeBg = badgeBg,
            badgeTextColor = TintaColors.PureBlack,
            borderColor = borderColor,
        )
    }
}

private fun buildExamRowModels(
    exams: List<Exam>,
    nowEpochMs: Long,
    zoneId: ZoneId = ZoneId.systemDefault(),
): List<ExamRowUi> {
    if (exams.isEmpty()) return emptyList()
    val todayDate = KretaDateParser.localDateFor(nowEpochMs, zoneId)
    val upcoming = exams
        .filter { !KretaDateParser.localDateFor(it.dateEpochMs, zoneId).isBefore(todayDate) }
        .sortedWith(compareBy<Exam>({ it.dateEpochMs }, { it.lessonNumber ?: Int.MAX_VALUE }))
        .take(3)
    val seenKeys = HashMap<String, Int>(upcoming.size)
    return upcoming.map { exam ->
        val baseKey = "${exam.uid}_${exam.dateEpochMs}"
        val occ = (seenKeys[baseKey] ?: 0) + 1
        seenKeys[baseKey] = occ
        val stableKey = if (occ == 1) baseKey else "${baseKey}_$occ"

        val examDate = KretaDateParser.localDateFor(exam.dateEpochMs, zoneId)
        val isToday = examDate == todayDate
        val isTomorrow = examDate == todayDate.plusDays(1)
        val dateBadge = when {
            isToday -> "Ma"
            isTomorrow -> "Holnap"
            else -> KretaDateParser.formatMonthDay(examDate)
        }
        val detailLine = listOfNotNull(
            exam.method?.trim()?.takeIf { it.isNotEmpty() },
            exam.topic?.trim()?.takeIf { it.isNotEmpty() },
        ).joinToString(" • ").ifEmpty {
            exam.lessonNumber?.let { "$it. óra" } ?: "Bejelentett számonkérés"
        }

        val (badgeBg, badgeFg, borderColor) = if (isToday || isTomorrow) {
            Triple(TintaColors.AmberSoft, TintaColors.Amber, TintaColors.AmberBorder)
        } else {
            Triple(TintaColors.AccentIndigoSoft, TintaColors.AccentIndigo, TintaColors.AccentIndigoBorder)
        }

        ExamRowUi(
            stableKey = stableKey,
            dateBadgeText = dateBadge,
            subjectTitle = exam.subjectName,
            detailLine = detailLine,
            badgeBg = badgeBg,
            badgeFg = badgeFg,
            borderColor = borderColor,
        )
    }
}

@Composable
private fun CurrentLessonBezelPage(
    rolloverState: RolloverTimetableState,
    isLoadingInitial: Boolean,
    nowMsProvider: () -> Long,
    modifier: Modifier = Modifier,
) {
    val status = rolloverState.todayStatus
    val previewFirst = if (rolloverState.isRolledOverToNextDay) {
        rolloverState.previewFirstLesson
    } else {
        null
    }
    val activeLesson = status.currentLesson
    val accentColor = when {
        previewFirst != null -> if (previewFirst.isSubstituted) TintaColors.Amber else TintaColors.AccentIndigo
        activeLesson?.isSubstituted == true -> TintaColors.Amber
        status.phase == TimetablePhase.ACTIVE_LESSON -> TintaColors.AccentBlue
        status.phase == TimetablePhase.BREAK -> TintaColors.AccentTeal
        status.phase == TimetablePhase.BEFORE_FIRST_LESSON -> TintaColors.AccentIndigo
        else -> TintaColors.PillBorder
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(TintaColors.PureBlack),
        contentAlignment = Alignment.Center,
    ) {
        LiveBezelProgressRing(
            status = status,
            isLoadingInitial = isLoadingInitial,
            isRolledOver = rolloverState.isRolledOverToNextDay,
            accentColor = accentColor,
            nowMsProvider = nowMsProvider,
            modifier = Modifier
                .fillMaxSize()
                .padding(3.dp),
        )

        if (isLoadingInitial) {
            CircularProgressIndicator(
                indicatorColor = TintaColors.AccentBlue,
                trackColor = TintaColors.LoaderTrack,
                strokeWidth = 2.5.dp,
                modifier = Modifier.size(24.dp),
            )
        } else {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 24.dp, vertical = 22.dp),
            ) {
                if (previewFirst != null) {
                    NextDayPreviewContent(
                        dayBadgeLabel = rolloverState.page1DayBadgeLabel ?: "Holnap",
                        firstLesson = previewFirst,
                        secondLesson = rolloverState.previewSecondLesson,
                        accentColor = accentColor,
                    )
                } else {
                    when (status.phase) {
                        TimetablePhase.ACTIVE_LESSON -> {
                            if (activeLesson != null) {
                                LessonBadgeRow(
                                    dayBadgeLabel = null,
                                    periodNumber = activeLesson.lessonNumber,
                                    roomName = activeLesson.cleanRoomName,
                                    accentColor = accentColor,
                                )

                                Text(
                                    text = activeLesson.displaySubject,
                                    fontSize = 18.sp,
                                    fontWeight = FontWeight.ExtraBold,
                                    color = TintaColors.TextPrimary,
                                    textAlign = TextAlign.Center,
                                    lineHeight = 20.sp,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis,
                                )

                                Spacer(Modifier.height(4.dp))
                                LiveRemainingMinutesText(
                                    status = status,
                                    accentColor = accentColor,
                                    nowMsProvider = nowMsProvider,
                                )

                                Spacer(Modifier.height(9.dp))
                                NextLessonCompactPill(lesson = status.nextLesson)
                            }
                        }

                        TimetablePhase.BREAK,
                        TimetablePhase.BEFORE_FIRST_LESSON,
                        -> {
                            val heroLabel = if (status.phase == TimetablePhase.BREAK) {
                                "Szünet"
                            } else {
                                "Tanítás előtt"
                            }
                            Text(
                                text = heroLabel,
                                fontSize = if (status.phase == TimetablePhase.BREAK) 20.sp else 16.5.sp,
                                fontWeight = FontWeight.ExtraBold,
                                color = TintaColors.TextPrimary,
                                textAlign = TextAlign.Center,
                                maxLines = 1,
                            )

                            Spacer(Modifier.height(4.dp))
                            LiveRemainingMinutesText(
                                status = status,
                                accentColor = accentColor,
                                nowMsProvider = nowMsProvider,
                            )

                            status.nextLesson?.let { next ->
                                Spacer(Modifier.height(9.dp))
                                NextLessonCompactPill(lesson = next)
                            }
                        }

                        TimetablePhase.AFTER_SCHOOL,
                        TimetablePhase.NO_CLASSES_TODAY,
                        -> {
                            Text(
                                text = status.titleLabel,
                                fontSize = 15.5.sp,
                                fontWeight = FontWeight.Bold,
                                color = TintaColors.TextSecondary,
                                textAlign = TextAlign.Center,
                                maxLines = 2,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun NextDayPreviewContent(
    dayBadgeLabel: String,
    firstLesson: Lesson,
    secondLesson: Lesson?,
    accentColor: Color,
) {
    LessonBadgeRow(
        dayBadgeLabel = dayBadgeLabel,
        periodNumber = firstLesson.lessonNumber ?: 1,
        roomName = firstLesson.cleanRoomName,
        accentColor = accentColor,
    )

    Text(
        text = firstLesson.displaySubject,
        fontSize = 18.sp,
        fontWeight = FontWeight.ExtraBold,
        color = TintaColors.TextPrimary,
        textAlign = TextAlign.Center,
        lineHeight = 20.sp,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
    )

    Spacer(Modifier.height(4.dp))
    Text(
        text = "Kezdés: ${KretaDateParser.formatHm(firstLesson.startEpochMs)}",
        style = TextStyle(
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            color = accentColor,
            fontFeatureSettings = "tnum",
        ),
        maxLines = 1,
    )

    Spacer(Modifier.height(9.dp))
    NextLessonCompactPill(lesson = secondLesson)
}

@Composable
private fun LessonBadgeRow(
    dayBadgeLabel: String?,
    periodNumber: Int?,
    roomName: String?,
    accentColor: Color,
) {
    if (dayBadgeLabel == null && periodNumber == null && roomName == null) return
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        if (dayBadgeLabel != null) {
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(TintaColors.ActiveHeroSurface)
                    .border(1.dp, accentColor.copy(alpha = 0.5f), CircleShape)
                    .padding(horizontal = 8.dp, vertical = 2.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = dayBadgeLabel,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = accentColor,
                    maxLines = 1,
                )
            }
        }
        if (periodNumber != null) {
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(accentColor)
                    .padding(horizontal = 7.dp, vertical = 2.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "$periodNumber.",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Black,
                    color = TintaColors.PureBlack,
                    maxLines = 1,
                )
            }
        }
        if (roomName != null) {
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(TintaColors.SmokedSurface)
                    .border(1.dp, TintaColors.PillBorder, CircleShape)
                    .padding(horizontal = 8.dp, vertical = 2.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = roomName,
                    fontSize = 10.5.sp,
                    fontWeight = FontWeight.Bold,
                    color = TintaColors.TextSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
    Spacer(Modifier.height(6.dp))
}

@Composable
private fun LiveBezelProgressRing(
    status: TimetableStatus,
    isLoadingInitial: Boolean,
    isRolledOver: Boolean,
    accentColor: Color,
    nowMsProvider: () -> Long,
    modifier: Modifier = Modifier,
) {
    val targetFraction by remember(status, isLoadingInitial, isRolledOver) {
        derivedStateOf {
            if (isLoadingInitial || isRolledOver) {
                0f
            } else {
                when (status.phase) {
                    TimetablePhase.ACTIVE_LESSON,
                    TimetablePhase.BREAK,
                    TimetablePhase.BEFORE_FIRST_LESSON,
                    -> status.remainingFractionAt(nowMsProvider())

                    TimetablePhase.AFTER_SCHOOL,
                    TimetablePhase.NO_CLASSES_TODAY,
                    -> 0f
                }
            }
        }
    }

    val animatedFractionState = animateFloatAsState(
        targetValue = targetFraction,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioNoBouncy,
            stiffness = Spring.StiffnessLow,
        ),
        label = "bezelProgress",
    )

    BezelProgressRing(
        progressProvider = { animatedFractionState.value },
        accentColor = accentColor,
        modifier = modifier,
    )
}

@Composable
private fun LiveRemainingMinutesText(
    status: TimetableStatus,
    accentColor: Color,
    nowMsProvider: () -> Long,
) {
    val badgeText by remember(status) {
        derivedStateOf {
            status.remainingMillisAt(nowMsProvider())?.let {
                TimetableStatusEvaluator.formatRemainingMinutesBadge(it)
            }
        }
    }
    val text = badgeText ?: return
    Text(
        text = text,
        style = TextStyle(
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            color = accentColor,
            fontFeatureSettings = "tnum",
        ),
        maxLines = 1,
    )
}

@Composable
private fun BezelProgressRing(
    progressProvider: () -> Float,
    accentColor: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier = modifier) {
        val progress = progressProvider().coerceIn(0f, 1f)
        val strokeWidthPx = 5.dp.toPx()
        val midGlowWidthPx = 9.dp.toPx()
        val outerGlowWidthPx = 14.dp.toPx()

        val diameter = (size.minDimension - outerGlowWidthPx).coerceAtLeast(1f)
        val topLeft = Offset(
            x = (size.width - diameter) / 2f,
            y = (size.height - diameter) / 2f,
        )
        val arcSize = Size(diameter, diameter)

        drawArc(
            color = TintaColors.TrackBorderMuted,
            startAngle = 0f,
            sweepAngle = 360f,
            useCenter = false,
            topLeft = topLeft,
            size = arcSize,
            style = Stroke(width = strokeWidthPx),
        )

        if (progress > 0.002f) {
            val sweep = (360f * progress).coerceIn(0f, 360f)

            drawArc(
                color = accentColor.copy(alpha = 0.12f),
                startAngle = -90f,
                sweepAngle = sweep,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width = outerGlowWidthPx, cap = StrokeCap.Round),
            )

            drawArc(
                color = accentColor.copy(alpha = 0.24f),
                startAngle = -90f,
                sweepAngle = sweep,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width = midGlowWidthPx, cap = StrokeCap.Round),
            )

            drawArc(
                color = accentColor,
                startAngle = -90f,
                sweepAngle = sweep,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width = strokeWidthPx, cap = StrokeCap.Round),
            )

            if (progress in 0.015f..0.985f) {
                val radius = diameter / 2f
                val endAngleRad = Math.toRadians((-90f + sweep).toDouble())
                val tipCenter = Offset(
                    x = center.x + radius * cos(endAngleRad).toFloat(),
                    y = center.y + radius * sin(endAngleRad).toFloat(),
                )
                drawCircle(
                    color = Color.White.copy(alpha = 0.9f),
                    radius = strokeWidthPx * 0.42f,
                    center = tipCenter,
                )
            }
        }
    }
}

@Composable
private fun NextLessonCompactPill(lesson: Lesson?) {
    val label = if (lesson != null) {
        "Köv: ${lesson.periodSubjectRoomBadge()}"
    } else {
        "Köv: Nincs több óra"
    }
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(TintaColors.SmokedSurface)
            .border(1.dp, TintaColors.SubtleBorder, CircleShape)
            .padding(horizontal = 10.dp, vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            fontSize = 10.sp,
            fontWeight = FontWeight.Medium,
            color = TintaColors.TextSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@OptIn(ExperimentalWearFoundationApi::class)
@Composable
private fun TimetablePage(
    listState: ScalingLazyListState,
    daySelection: TimetableDaySelectionState,
    rows: List<TimetableLessonRowUi>,
    isLoadingInitial: Boolean,
    onSelectDay: (TimetableDayFilter) -> Unit,
    modifier: Modifier = Modifier,
) {
    val focusRequester = remember { FocusRequester() }
    val scalingParams = remember {
        ScalingLazyColumnDefaults.scalingParams(
            edgeScale = 0.78f,
            edgeAlpha = 0.50f,
            minElementHeight = 0.25f,
            maxElementHeight = 0.75f,
            minTransitionArea = 0.35f,
            maxTransitionArea = 0.55f,
            scaleInterpolator = CubicBezierEasing(0.2f, 0.0f, 0.0f, 1.0f),
        )
    }

    ScalingLazyColumn(
        state = listState,
        scalingParams = scalingParams,
        rotaryScrollableBehavior = null,
        modifier = modifier
            .fillMaxSize()
            .background(TintaColors.PureBlack)
            .requestFocusOnHierarchyActive()
            .rotaryScrollable(
                behavior = RotaryScrollableDefaults.behavior(
                    scrollableState = listState,
                    hapticFeedbackEnabled = true,
                ),
                focusRequester = focusRequester,
            ),
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 30.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item(key = "header") {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier.padding(bottom = 3.dp),
            ) {
                DaySwitcherPill(
                    isShowingToday = daySelection.isShowingToday,
                    nextDayLabel = daySelection.nextDayChipLabel,
                    onSelectToday = { onSelectDay(TimetableDayFilter.TODAY) },
                    onSelectNextDay = { onSelectDay(TimetableDayFilter.NEXT_SCHOOL_DAY) },
                )

                Text(
                    text = daySelection.dateSubtitle,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (daySelection.isShowingToday) {
                        TintaColors.TextSecondary
                    } else {
                        TintaColors.AccentIndigo
                    },
                    maxLines = 1,
                )

                Text(
                    text = "Órarend",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = TintaColors.TextPrimary,
                    textAlign = TextAlign.Center,
                )
            }
        }

        if (isLoadingInitial) {
            item(key = "loading") {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(
                        indicatorColor = TintaColors.AccentBlue,
                        strokeWidth = 2.5.dp,
                        modifier = Modifier.size(22.dp),
                    )
                }
            }
        } else if (rows.isEmpty()) {
            item(key = "empty") {
                EmptyWatchCard(
                    text = if (daySelection.isShowingToday) {
                        "Ma nincs rögzített tanóra."
                    } else {
                        "Nincs rögzített tanóra a következő napra."
                    },
                )
            }
        } else {
            items(rows, key = { it.stableKey }) { row ->
                LessonPillCard(row = row)
            }
        }
    }
}

@Composable
private fun DaySwitcherPill(
    isShowingToday: Boolean,
    nextDayLabel: String,
    onSelectToday: () -> Unit,
    onSelectNextDay: () -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(CircleShape)
            .background(TintaColors.SmokedSurface)
            .border(1.dp, TintaColors.PillBorder, CircleShape)
            .padding(3.dp),
    ) {
        DaySwitcherSegment(
            label = "Ma",
            selected = isShowingToday,
            selectedColor = TintaColors.AccentBlue,
            onClick = {
                if (!isShowingToday) {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onSelectToday()
                }
            },
        )
        Spacer(Modifier.width(3.dp))
        DaySwitcherSegment(
            label = nextDayLabel,
            selected = !isShowingToday,
            selectedColor = TintaColors.AccentIndigo,
            onClick = {
                if (isShowingToday) {
                    haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onSelectNextDay()
                }
            },
        )
    }
}

@Composable
private fun DaySwitcherSegment(
    label: String,
    selected: Boolean,
    selectedColor: Color,
    onClick: () -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(if (selected) selectedColor else Color.Transparent)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            )
            .padding(horizontal = 12.dp, vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            fontSize = 10.5.sp,
            fontWeight = FontWeight.ExtraBold,
            color = if (selected) TintaColors.PureBlack else TintaColors.TextSecondary,
            maxLines = 1,
        )
    }
}

@Composable
private fun LessonPillCard(row: TimetableLessonRowUi) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .graphicsLayer { alpha = row.cardAlpha }
            .clip(LessonCardShape)
            .background(row.cardBg)
            .border(row.borderWidth, row.borderColor, LessonCardShape)
            .padding(horizontal = 10.dp, vertical = 9.dp),
    ) {
        Box(
            modifier = Modifier
                .size(26.dp)
                .clip(CircleShape)
                .background(row.badgeBg),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = row.periodBadgeText,
                fontSize = 10.5.sp,
                fontWeight = FontWeight.ExtraBold,
                color = row.badgeTextColor,
            )
        }

        Spacer(Modifier.width(8.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = row.subjectTitle,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = TintaColors.TextPrimary,
                textDecoration = if (row.isCancelled) TextDecoration.LineThrough else null,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )

            Text(
                text = row.metaLine,
                style = TnumSubtitleStyle,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )

            val status = row.statusLabel
            if (status != null) {
                Spacer(Modifier.height(3.dp))
                StatusPillTag(
                    label = status,
                    fg = row.statusFg,
                    bg = row.statusBg,
                )
            }
        }
    }
}

@OptIn(ExperimentalWearFoundationApi::class)
@Composable
private fun GradesAndExamsPage(
    listState: ScalingLazyListState,
    examRows: List<ExamRowUi>,
    gradeRows: List<GradeRowUi>,
    isLoadingInitial: Boolean,
    modifier: Modifier = Modifier,
) {
    val focusRequester = remember { FocusRequester() }
    val scalingParams = remember {
        ScalingLazyColumnDefaults.scalingParams(
            edgeScale = 0.78f,
            edgeAlpha = 0.50f,
            minElementHeight = 0.25f,
            maxElementHeight = 0.75f,
            minTransitionArea = 0.35f,
            maxTransitionArea = 0.55f,
            scaleInterpolator = CubicBezierEasing(0.2f, 0.0f, 0.0f, 1.0f),
        )
    }

    ScalingLazyColumn(
        state = listState,
        scalingParams = scalingParams,
        rotaryScrollableBehavior = null,
        modifier = modifier
            .fillMaxSize()
            .background(TintaColors.PureBlack)
            .requestFocusOnHierarchyActive()
            .rotaryScrollable(
                behavior = RotaryScrollableDefaults.behavior(
                    scrollableState = listState,
                    hapticFeedbackEnabled = true,
                ),
                focusRequester = focusRequester,
            ),
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 30.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item(key = "page3_header") {
            Text(
                text = "Jegyek & Dolgozatok",
                fontSize = 13.5.sp,
                fontWeight = FontWeight.ExtraBold,
                color = TintaColors.TextPrimary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(bottom = 2.dp),
            )
        }

        if (isLoadingInitial) {
            item(key = "page3_loading") {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(
                        indicatorColor = TintaColors.AccentBlue,
                        strokeWidth = 2.5.dp,
                        modifier = Modifier.size(22.dp),
                    )
                }
            }
        } else {
            item(key = "exams_section_header") {
                SectionBadgeHeader(
                    title = "Számonkérések",
                    dotColor = TintaColors.Amber,
                )
            }

            if (examRows.isEmpty()) {
                item(key = "exams_empty") {
                    EmptyWatchCard(text = "Nincs közelgő számonkérés.")
                }
            } else {
                items(examRows, key = { "exam_${it.stableKey}" }) { exam ->
                    ExamWatchCard(row = exam)
                }
            }

            item(key = "grades_section_header") {
                Spacer(Modifier.height(2.dp))
                SectionBadgeHeader(
                    title = "Legutóbbi jegyek",
                    dotColor = TintaColors.AccentTeal,
                )
            }

            if (gradeRows.isEmpty()) {
                item(key = "grades_empty") {
                    EmptyWatchCard(text = "Nincs szinkronizált jegy.")
                }
            } else {
                items(gradeRows, key = { "grade_${it.stableKey}" }) { grade ->
                    GradeWatchCard(row = grade)
                }
            }
        }
    }
}

@Composable
private fun SectionBadgeHeader(
    title: String,
    dotColor: Color,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 2.dp, bottom = 1.dp),
    ) {
        Box(
            modifier = Modifier
                .size(6.dp)
                .clip(CircleShape)
                .background(dotColor),
        )
        Spacer(Modifier.width(6.dp))
        Text(
            text = title,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = TintaColors.TextSecondary,
            maxLines = 1,
        )
    }
}

@Composable
private fun ExamWatchCard(row: ExamRowUi) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(LessonCardShape)
            .background(TintaColors.SmokedSurface)
            .border(1.dp, row.borderColor, LessonCardShape)
            .padding(horizontal = 10.dp, vertical = 9.dp),
    ) {
        Box(
            modifier = Modifier
                .clip(CircleShape)
                .background(row.badgeBg)
                .padding(horizontal = 8.dp, vertical = 4.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = row.dateBadgeText,
                fontSize = 9.5.sp,
                fontWeight = FontWeight.ExtraBold,
                color = row.badgeFg,
                maxLines = 1,
            )
        }

        Spacer(Modifier.width(8.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = row.subjectTitle,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = TintaColors.TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = row.detailLine,
                fontSize = 9.5.sp,
                color = TintaColors.TextSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun GradeWatchCard(row: GradeRowUi) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(LessonCardShape)
            .background(TintaColors.SmokedSurface)
            .border(1.dp, row.borderColor, LessonCardShape)
            .padding(horizontal = 10.dp, vertical = 9.dp),
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(row.badgeBg),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = row.gradeBadgeText,
                fontSize = 12.sp,
                fontWeight = FontWeight.Black,
                color = row.badgeTextColor,
                maxLines = 1,
            )
        }

        Spacer(Modifier.width(9.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = row.subjectTitle,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = TintaColors.TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = row.metaLine,
                style = TnumSubtitleStyle,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun EmptyWatchCard(text: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(LessonCardShape)
            .background(TintaColors.SmokedSurface)
            .border(1.dp, TintaColors.SubtleBorder, LessonCardShape)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            fontSize = 11.sp,
            color = TintaColors.TextSecondary,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun StatusPillTag(label: String, fg: Color, bg: Color) {
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(bg)
            .padding(horizontal = 6.dp, vertical = 1.5.dp),
    ) {
        Text(
            text = label,
            fontSize = 8.5.sp,
            fontWeight = FontWeight.Bold,
            color = fg,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
