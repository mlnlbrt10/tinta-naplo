package hu.rekreta.rekreta_app.wear.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.ExperimentalWearFoundationApi
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.ScalingLazyListState
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.foundation.pager.HorizontalPager
import androidx.wear.compose.foundation.pager.rememberPagerState
import androidx.wear.compose.foundation.requestFocusOnHierarchyActive
import androidx.wear.compose.foundation.rotary.RotaryScrollableDefaults
import androidx.wear.compose.foundation.rotary.rotaryScrollable
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.CompactChip
import androidx.wear.compose.material.HorizontalPageIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.PageIndicatorState
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import hu.rekreta.rekreta_app.wear.R
import hu.rekreta.rekreta_app.wear.auth.RemoteAuthStatus
import hu.rekreta.rekreta_app.wear.auth.WearRemoteAuthManager
import hu.rekreta.rekreta_app.wear.data.Grade
import hu.rekreta.rekreta_app.wear.data.GradeAnalytics
import hu.rekreta.rekreta_app.wear.data.Homework
import hu.rekreta.rekreta_app.wear.data.InvalidGrantException
import hu.rekreta.rekreta_app.wear.data.KretaDateParser
import hu.rekreta.rekreta_app.wear.data.KretaWearApiClient
import hu.rekreta.rekreta_app.wear.data.Lesson
import hu.rekreta.rekreta_app.wear.data.SecureTokenStorage
import hu.rekreta.rekreta_app.wear.data.StoredSession
import hu.rekreta.rekreta_app.wear.data.SubjectAverageSummary
import hu.rekreta.rekreta_app.wear.data.TimetablePhase
import hu.rekreta.rekreta_app.wear.data.TimetableStatus
import hu.rekreta.rekreta_app.wear.data.TimetableStatusEvaluator
import hu.rekreta.rekreta_app.wear.data.TokenExpiredException
import hu.rekreta.rekreta_app.wear.sync.KretaSyncScheduler
import hu.rekreta.rekreta_app.wear.sync.KretaSyncWorker
import hu.rekreta.rekreta_app.wear.ui.theme.TintaColors
import hu.rekreta.rekreta_app.wear.ui.theme.TintaWearTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

@Composable
fun TintaWearApp(resumeEpoch: Int = 0) {
    val context = LocalContext.current
    val tokenStore = remember { SecureTokenStorage(context) }
    val apiClient = remember { KretaWearApiClient(tokenStore) }
    val remoteAuth = remember { WearRemoteAuthManager.getInstance(context) }
    val authStatus by remoteAuth.status.collectAsState()
    val scope = rememberCoroutineScope()

    var session by remember { mutableStateOf<StoredSession?>(tokenStore.loadSession()) }
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
        val loaded = tokenStore.loadSession()
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
            WearDashboardPager(
                session = activeSession,
                tokenStore = tokenStore,
                apiClient = apiClient,
                resumeEpoch = resumeEpoch,
                onLogout = { message ->
                    val key = SecureTokenStorage.accountKeyFor(activeSession)
                    tokenStore.clearWearDataCache(key)
                    tokenStore.clearSession()
                    apiClient.resetMemoryCache()
                    KretaSyncWorker.requestTileUpdate(context)
                    remoteAuth.resetStatusToIdle()
                    session = null
                    loginNotice = message
                },
            )
        }
    }
}

@OptIn(ExperimentalWearFoundationApi::class)
@Composable
private fun WearDashboardPager(
    session: StoredSession,
    tokenStore: SecureTokenStorage,
    apiClient: KretaWearApiClient,
    resumeEpoch: Int,
    onLogout: (String?) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current

    val pagerState = rememberPagerState(pageCount = { 2 })
    val timetableListState = rememberScalingLazyListState()
    val gradesListState = rememberScalingLazyListState()

    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var lessons by remember { mutableStateOf<List<Lesson>>(emptyList()) }
    var homeworks by remember { mutableStateOf<List<Homework>>(emptyList()) }
    var grades by remember { mutableStateOf<List<Grade>>(emptyList()) }
    var lastSyncedAtMs by remember { mutableStateOf<Long?>(null) }
    var isSyncing by remember { mutableStateOf(false) }
    var hasLoadedOnce by remember { mutableStateOf(false) }
    var syncError by remember { mutableStateOf<String?>(null) }
    var inspectedLesson by remember { mutableStateOf<Lesson?>(null) }

    // 1-second live countdown clock
    LaunchedEffect(Unit) {
        while (true) {
            nowMs = System.currentTimeMillis()
            delay(1_000L)
        }
    }

    suspend fun performSync(withHaptic: Boolean) {
        if (isSyncing) return
        if (withHaptic) {
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        }
        isSyncing = true
        syncError = null
        try {
            val synced = apiClient.syncAll(session)
            lessons = synced.lessons
            homeworks = synced.homeworks
            grades = synced.grades
            lastSyncedAtMs = synced.syncedAtEpochMs
            hasLoadedOnce = true
            isSyncing = false
            KretaSyncScheduler.ensurePeriodicSync(context)
            KretaSyncScheduler.scheduleNextTransitionUpdate(context, synced.lessons)
            KretaSyncWorker.requestTileUpdate(context)
        } catch (_: TokenExpiredException) {
            isSyncing = false
            onLogout("A munkamenet lejárt, jelentkezz be újra telefonról.")
        } catch (_: InvalidGrantException) {
            isSyncing = false
            onLogout("A hozzáférés visszavonva, jelentkezz be újra.")
        } catch (_: Exception) {
            isSyncing = false
            hasLoadedOnce = true
            syncError = if (lessons.isEmpty() && grades.isEmpty()) {
                "Nem sikerült frissíteni"
            } else {
                "Offline • gyorsítótár"
            }
        }
    }

    LaunchedEffect(session.accessToken, resumeEpoch) {
        val accountKey = SecureTokenStorage.accountKeyFor(session)
        val cached = tokenStore.loadWearDataCache(accountKey, KretaDateParser.dateKeyFor())
        if (cached != null) {
            lessons = cached.lessons
            homeworks = cached.homeworks
            grades = cached.grades
            lastSyncedAtMs = cached.syncedAtEpochMs.takeIf { it > 0L }
            hasLoadedOnce = true
        }
        performSync(withHaptic = false)
    }

    // Lesson inspection overlay when user taps any lesson card
    val activeDetail = inspectedLesson
    if (activeDetail != null) {
        LessonDetailOverlay(
            lesson = activeDetail,
            homework = activeDetail.matchedHomework(homeworks),
            onClose = { inspectedLesson = null },
        )
        return
    }

    val pageIndicatorState = remember(pagerState) {
        object : PageIndicatorState {
            override val pageOffset: Float get() = pagerState.currentPageOffsetFraction
            override val selectedPage: Int get() = pagerState.currentPage
            override val pageCount: Int get() = pagerState.pageCount
        }
    }

    val activeListState = if (pagerState.currentPage == 0) timetableListState else gradesListState

    Scaffold(
        timeText = { TimeText() },
        positionIndicator = { PositionIndicator(scalingLazyListState = activeListState) },
        pageIndicator = {
            HorizontalPageIndicator(
                pageIndicatorState = pageIndicatorState,
                selectedColor = TintaColors.AccentBlue,
                unselectedColor = TintaColors.PillBorder,
                modifier = Modifier.padding(bottom = 4.dp),
            )
        },
    ) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier
                .fillMaxSize()
                .background(TintaColors.PureBlack),
        ) { page ->
            when (page) {
                0 -> TimetablePage(
                    listState = timetableListState,
                    studentLabel = session.studentName ?: session.userName,
                    instituteLabel = session.instituteName ?: session.instituteCode,
                    lessons = lessons,
                    homeworks = homeworks,
                    nowMs = nowMs,
                    lastSyncedAtMs = lastSyncedAtMs,
                    isSyncing = isSyncing,
                    hasLoadedOnce = hasLoadedOnce,
                    syncError = syncError,
                    onOpenGradesTab = { scope.launch { pagerState.animateScrollToPage(1) } },
                    onLessonClick = { inspectedLesson = it },
                    onRefresh = { scope.launch { performSync(withHaptic = true) } },
                    onLogout = { onLogout(null) },
                )

                else -> GradesPage(
                    listState = gradesListState,
                    grades = grades,
                    isSyncing = isSyncing,
                    hasLoadedOnce = hasLoadedOnce,
                    syncError = syncError,
                    onOpenTimetableTab = { scope.launch { pagerState.animateScrollToPage(0) } },
                    onRefresh = { scope.launch { performSync(withHaptic = true) } },
                )
            }
        }
    }
}

@OptIn(ExperimentalWearFoundationApi::class)
@Composable
private fun TimetablePage(
    listState: ScalingLazyListState,
    studentLabel: String?,
    instituteLabel: String?,
    lessons: List<Lesson>,
    homeworks: List<Homework>,
    nowMs: Long,
    lastSyncedAtMs: Long?,
    isSyncing: Boolean,
    hasLoadedOnce: Boolean,
    syncError: String?,
    onOpenGradesTab: () -> Unit,
    onLessonClick: (Lesson) -> Unit,
    onRefresh: () -> Unit,
    onLogout: () -> Unit,
) {
    val focusRequester = remember { FocusRequester() }
    val status = remember(lessons, nowMs) {
        TimetableStatusEvaluator.evaluate(lessons, nowMs)
    }

    PullToRefreshContainer(
        listState = listState,
        isRefreshing = isSyncing,
        onRefresh = onRefresh,
    ) {
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .requestFocusOnHierarchyActive()
                .rotaryScrollable(
                    behavior = RotaryScrollableDefaults.behavior(listState),
                    focusRequester = focusRequester,
                ),
            contentPadding = PaddingValues(horizontal = 14.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Compact page switcher pills
            item(key = "nav_pills") {
                SectionSwitchRow(
                    activePage = 0,
                    onSelectTimetable = {},
                    onSelectGrades = onOpenGradesTab,
                )
            }

            // Now / Next Hero Glance Card with live tabular countdown
            item(key = "hero_card") {
                NowNextHeroPillCard(
                    status = status,
                    homeworks = homeworks,
                )
            }

            // Section header + last sync info
            item(key = "schedule_header") {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(top = 4.dp, bottom = 2.dp),
                ) {
                    Text(
                        text = "Mai órarend",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.ExtraBold,
                        color = TintaColors.TextPrimary,
                    )
                    val meta = syncError ?: lastSyncedAtMs?.let {
                        "Frissítve ${KretaDateParser.formatHm(it)}"
                    }
                    if (meta != null) {
                        Text(
                            text = meta,
                            fontSize = 9.5.sp,
                            color = if (syncError != null) TintaColors.Amber else TintaColors.TextMuted,
                        )
                    }
                }
            }

            if (!hasLoadedOnce && isSyncing) {
                item(key = "loading_spinner") {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 12.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(
                            indicatorColor = TintaColors.AccentBlue,
                            strokeWidth = 2.5.dp,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                }
            } else if (lessons.isEmpty()) {
                item(key = "empty_lessons") {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(22.dp))
                            .background(TintaColors.SmokedSurface)
                            .border(1.dp, TintaColors.SubtleBorder, RoundedCornerShape(22.dp))
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "Ma nincs rögzített tanóra.",
                            fontSize = 11.5.sp,
                            color = TintaColors.TextSecondary,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            } else {
                items(lessons, key = { "${it.uid}_${it.startEpochMs}" }) { lesson ->
                    LessonPillCard(
                        lesson = lesson,
                        isActive = status.currentLesson?.uid == lesson.uid &&
                            status.currentLesson.startEpochMs == lesson.startEpochMs,
                        isFinished = status.currentLesson?.uid != lesson.uid && nowMs >= lesson.endEpochMs,
                        hasHomework = lesson.hasActiveHomework(homeworks),
                        onClick = { onLessonClick(lesson) },
                    )
                }
            }

            // Bottom Sync & Logout pills
            item(key = "sync_btn") {
                Spacer(Modifier.height(2.dp))
                Chip(
                    onClick = onRefresh,
                    enabled = !isSyncing,
                    modifier = Modifier.fillMaxWidth(),
                    label = {
                        Text(
                            text = if (isSyncing) "Szinkronizálás..." else "Frissítés",
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.Bold,
                        )
                    },
                    icon = {
                        if (isSyncing) {
                            CircularProgressIndicator(
                                indicatorColor = TintaColors.AccentBlue,
                                strokeWidth = 2.dp,
                                modifier = Modifier.size(16.dp),
                            )
                        } else {
                            Icon(
                                painter = painterResource(id = R.drawable.ic_refresh),
                                contentDescription = null,
                                tint = TintaColors.AccentBlue,
                                modifier = Modifier.size(16.dp),
                            )
                        }
                    },
                    colors = ChipDefaults.secondaryChipColors(
                        backgroundColor = TintaColors.SmokedSurface,
                        contentColor = TintaColors.TextPrimary,
                    ),
                )
            }

            val profileText = listOfNotNull(
                studentLabel?.takeIf { it.isNotBlank() },
                instituteLabel?.takeIf { it.isNotBlank() },
            ).joinToString(" • ")
            if (profileText.isNotBlank()) {
                item(key = "student_profile_meta") {
                    Text(
                        text = profileText,
                        fontSize = 9.5.sp,
                        color = TintaColors.TextMuted,
                        textAlign = TextAlign.Center,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                    )
                }
            }

            item(key = "logout_btn") {
                CompactChip(
                    onClick = onLogout,
                    label = {
                        Text(
                            text = "Kijelentkezés",
                            fontSize = 10.5.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    },
                    icon = {
                        Icon(
                            painter = painterResource(id = R.drawable.ic_logout),
                            contentDescription = null,
                            tint = TintaColors.Crimson,
                            modifier = Modifier.size(14.dp),
                        )
                    },
                    colors = ChipDefaults.secondaryChipColors(
                        backgroundColor = TintaColors.CrimsonSoft,
                        contentColor = TintaColors.Crimson,
                    ),
                )
            }
        }
    }
}

@Composable
private fun NowNextHeroPillCard(
    status: TimetableStatus,
    homeworks: List<Homework>,
) {
    val heroLesson = status.currentLesson ?: status.nextLesson
    val accentColor = when {
        heroLesson?.isSubstituted == true -> TintaColors.Amber
        status.phase == TimetablePhase.ACTIVE_LESSON -> TintaColors.AccentBlue
        status.phase == TimetablePhase.BREAK -> TintaColors.AccentTeal
        status.phase == TimetablePhase.BEFORE_FIRST_LESSON -> TintaColors.AccentIndigo
        else -> TintaColors.TextSecondary
    }
    val cardBg = if (status.phase == TimetablePhase.ACTIVE_LESSON) {
        TintaColors.ActiveHeroSurface
    } else {
        TintaColors.SmokedSurface
    }
    val borderColor = if (status.phase == TimetablePhase.ACTIVE_LESSON || status.phase == TimetablePhase.BREAK) {
        accentColor.copy(alpha = 0.65f)
    } else {
        TintaColors.PillBorder
    }

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(26.dp))
            .background(cardBg)
            .border(1.dp, borderColor, RoundedCornerShape(26.dp))
            .padding(horizontal = 13.dp, vertical = 11.dp),
    ) {
        // Status pill badge
        Box(
            modifier = Modifier
                .clip(CircleShape)
                .background(accentColor.copy(alpha = 0.18f))
                .border(1.dp, accentColor.copy(alpha = 0.45f), CircleShape)
                .padding(horizontal = 9.dp, vertical = 2.dp),
        ) {
            Text(
                text = status.badgeLabel,
                fontSize = 9.5.sp,
                fontWeight = FontWeight.ExtraBold,
                color = accentColor,
                maxLines = 1,
            )
        }

        Spacer(Modifier.height(6.dp))

        // Subject & Room badge (e.g., "3. Matematika • B-204")
        val headline = heroLesson?.periodSubjectRoomBadge() ?: status.titleLabel
        Text(
            text = headline,
            fontSize = 14.5.sp,
            fontWeight = FontWeight.ExtraBold,
            color = TintaColors.TextPrimary,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )

        // Live remaining countdown (tabularFigures)
        val remMs = status.remainingMillis
        if (remMs != null) {
            Spacer(Modifier.height(4.dp))
            Text(
                text = TimetableStatusEvaluator.formatTabularCountdown(remMs),
                style = TextStyle(
                    fontSize = 21.sp,
                    fontWeight = FontWeight.Black,
                    color = accentColor,
                    fontFeatureSettings = "tnum",
                ),
                maxLines = 1,
            )
        }

        Spacer(Modifier.height(2.dp))
        Text(
            text = status.subtitleLabel,
            style = TextStyle(
                fontSize = 10.sp,
                color = TintaColors.TextSecondary,
                fontFeatureSettings = "tnum",
            ),
            maxLines = 1,
        )

        // Progress capsule bar
        if (status.remainingFraction > 0f) {
            Spacer(Modifier.height(6.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth(0.76f)
                    .height(4.dp)
                    .clip(CircleShape)
                    .background(TintaColors.PillBorder),
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(status.remainingFraction)
                        .height(4.dp)
                        .clip(CircleShape)
                        .background(accentColor),
                )
            }
        }

        // Next lesson / homework indicator mini pill
        val next = status.nextLesson
        if (status.phase == TimetablePhase.ACTIVE_LESSON && next != null) {
            Spacer(Modifier.height(7.dp))
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(TintaColors.SmokedSurfaceAlt)
                    .border(1.dp, TintaColors.SubtleBorder, CircleShape)
                    .padding(horizontal = 9.dp, vertical = 3.dp),
            ) {
                Text(
                    text = "Kövi: ${next.periodSubjectRoomBadge()}",
                    fontSize = 9.5.sp,
                    color = TintaColors.TextSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        } else if (heroLesson != null && heroLesson.hasActiveHomework(homeworks)) {
            Spacer(Modifier.height(6.dp))
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(TintaColors.AccentBlue.copy(alpha = 0.16f))
                    .padding(horizontal = 8.dp, vertical = 2.dp),
            ) {
                Text(
                    text = "Aktív házi feladat",
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    color = TintaColors.AccentBlue,
                )
            }
        }
    }
}

@Composable
private fun LessonPillCard(
    lesson: Lesson,
    isActive: Boolean,
    isFinished: Boolean,
    hasHomework: Boolean,
    onClick: () -> Unit,
) {
    val isCancelled = lesson.isCancelled
    val isSubstituted = lesson.isSubstituted
    val badgeBg = when {
        isCancelled -> TintaColors.Crimson
        isSubstituted -> TintaColors.Amber
        isActive -> TintaColors.AccentBlue
        else -> TintaColors.SmokedSurfaceAlt
    }
    val badgeText = if (isCancelled || isSubstituted || isActive) {
        TintaColors.PureBlack
    } else {
        TintaColors.TextSecondary
    }
    val borderColor = when {
        isActive -> TintaColors.AccentBlue
        isCancelled -> TintaColors.Crimson.copy(alpha = 0.45f)
        isSubstituted -> TintaColors.Amber.copy(alpha = 0.55f)
        else -> TintaColors.SubtleBorder
    }

    val cardModifier = Modifier
        .fillMaxWidth()
        .alpha(if (isFinished || isCancelled) 0.55f else 1f)
        .clip(RoundedCornerShape(22.dp))
        .background(if (isActive) TintaColors.ActiveHeroSurface else TintaColors.SmokedSurface)
        .border(if (isActive) 1.5.dp else 1.dp, borderColor, RoundedCornerShape(22.dp))
        .clickable(onClick = onClick)
        .padding(horizontal = 10.dp, vertical = 9.dp)

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = cardModifier,
    ) {
        Box(
            modifier = Modifier
                .size(26.dp)
                .clip(CircleShape)
                .background(badgeBg),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = lesson.lessonNumber?.let { "$it." } ?: "•",
                fontSize = 10.5.sp,
                fontWeight = FontWeight.ExtraBold,
                color = badgeText,
            )
        }

        Spacer(Modifier.width(8.dp))

        Column(modifier = Modifier.weight(1f)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = lesson.displaySubject,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = TintaColors.TextPrimary,
                    textDecoration = if (isCancelled) TextDecoration.LineThrough else null,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )

                if (hasHomework && !isCancelled) {
                    Spacer(Modifier.width(4.dp))
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(TintaColors.AccentBlue.copy(alpha = 0.2f))
                            .padding(horizontal = 5.dp, vertical = 1.dp),
                    ) {
                        Text(
                            text = "HF",
                            fontSize = 8.sp,
                            fontWeight = FontWeight.ExtraBold,
                            color = TintaColors.AccentBlue,
                        )
                    }
                }
            }

            val room = lesson.cleanRoomName
            val meta = if (room != null) "${lesson.compactTimeRangeLabel} • $room" else lesson.compactTimeRangeLabel
            Text(
                text = meta,
                style = TextStyle(
                    fontSize = 9.5.sp,
                    color = TintaColors.TextSecondary,
                    fontFeatureSettings = "tnum",
                ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )

            if (isCancelled || isSubstituted) {
                Spacer(Modifier.height(3.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (isCancelled) {
                        StatusPillTag(
                            label = "Elmaradt",
                            fg = TintaColors.Crimson,
                            bg = TintaColors.CrimsonSoft,
                        )
                    } else if (isSubstituted) {
                        StatusPillTag(
                            label = "Helyettesítés: ${lesson.cleanSubstituteTeacher}",
                            fg = TintaColors.Amber,
                            bg = TintaColors.AmberSoft,
                        )
                    }
                }
            }
        }
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

@OptIn(ExperimentalWearFoundationApi::class)
@Composable
private fun GradesPage(
    listState: ScalingLazyListState,
    grades: List<Grade>,
    isSyncing: Boolean,
    hasLoadedOnce: Boolean,
    syncError: String?,
    onOpenTimetableTab: () -> Unit,
    onRefresh: () -> Unit,
) {
    val focusRequester = remember { FocusRequester() }
    val summaries = remember(grades) { GradeAnalytics.summarizeBySubject(grades) }
    val overallAvg = remember(summaries) { GradeAnalytics.computeOverallSubjectAverage(summaries) }
    val latestGrades = remember(grades) { grades.take(12) }

    PullToRefreshContainer(
        listState = listState,
        isRefreshing = isSyncing,
        onRefresh = onRefresh,
    ) {
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .requestFocusOnHierarchyActive()
                .rotaryScrollable(
                    behavior = RotaryScrollableDefaults.behavior(listState),
                    focusRequester = focusRequester,
                ),
            contentPadding = PaddingValues(horizontal = 14.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            item(key = "nav_pills") {
                SectionSwitchRow(
                    activePage = 1,
                    onSelectTimetable = onOpenTimetableTab,
                    onSelectGrades = {},
                )
            }

            item(key = "grades_hero") {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(24.dp))
                        .background(TintaColors.SmokedSurface)
                        .border(1.dp, TintaColors.PillBorder, RoundedCornerShape(24.dp))
                        .padding(horizontal = 14.dp, vertical = 11.dp),
                ) {
                    Text(
                        text = "Jegyek",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.ExtraBold,
                        color = TintaColors.TextPrimary,
                    )
                    Spacer(Modifier.height(4.dp))
                    val avgText = overallAvg?.let {
                        "Összátlag: ${String.format(Locale.forLanguageTag("hu-HU"), "%.2f", it)}"
                    } ?: "Nincs számszerű átlag"
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(TintaColors.AccentBlue.copy(alpha = 0.18f))
                            .border(1.dp, TintaColors.AccentBlue.copy(alpha = 0.4f), CircleShape)
                            .padding(horizontal = 10.dp, vertical = 3.dp),
                    ) {
                        Text(
                            text = avgText,
                            style = TextStyle(
                                fontSize = 11.sp,
                                fontWeight = FontWeight.ExtraBold,
                                color = TintaColors.AccentBlue,
                                fontFeatureSettings = "tnum",
                            ),
                        )
                    }
                    if (syncError != null) {
                        Spacer(Modifier.height(3.dp))
                        Text(
                            text = syncError,
                            fontSize = 9.sp,
                            color = TintaColors.Amber,
                        )
                    }
                }
            }

            if (!hasLoadedOnce && isSyncing) {
                item(key = "grades_loading") {
                    CircularProgressIndicator(
                        indicatorColor = TintaColors.AccentBlue,
                        strokeWidth = 2.5.dp,
                        modifier = Modifier
                            .padding(vertical = 12.dp)
                            .size(22.dp),
                    )
                }
            } else if (grades.isEmpty()) {
                item(key = "grades_empty") {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(22.dp))
                            .background(TintaColors.SmokedSurface)
                            .border(1.dp, TintaColors.SubtleBorder, RoundedCornerShape(22.dp))
                            .padding(14.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "Még nincsenek rögzített jegyek.",
                            fontSize = 11.5.sp,
                            color = TintaColors.TextSecondary,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            } else {
                item(key = "hdr_latest") {
                    Text(
                        text = "Legutóbbi jegyek",
                        fontSize = 11.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = TintaColors.TextSecondary,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }

                items(latestGrades, key = { "g_${it.uid}_${it.recordedAtEpochMs}" }) { grade ->
                    LatestGradePillCard(grade = grade)
                }

                if (summaries.isNotEmpty()) {
                    item(key = "hdr_avgs") {
                        Text(
                            text = "Tantárgyi átlagok",
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.Bold,
                            color = TintaColors.TextSecondary,
                            modifier = Modifier.padding(top = 6.dp),
                        )
                    }
                    items(summaries, key = { "avg_${it.subjectKey}" }) { summary ->
                        SubjectAveragePillCard(summary = summary)
                    }
                }
            }

            item(key = "grades_refresh_btn") {
                CompactChip(
                    onClick = onRefresh,
                    enabled = !isSyncing,
                    label = {
                        Text(
                            text = if (isSyncing) "Frissítés..." else "Frissítés",
                            fontSize = 11.sp,
                        )
                    },
                    icon = {
                        Icon(
                            painter = painterResource(id = R.drawable.ic_refresh),
                            contentDescription = null,
                            tint = TintaColors.AccentBlue,
                            modifier = Modifier.size(14.dp),
                        )
                    },
                    colors = ChipDefaults.secondaryChipColors(
                        backgroundColor = TintaColors.SmokedSurface,
                        contentColor = TintaColors.TextPrimary,
                    ),
                )
            }
        }
    }
}

@Composable
private fun LatestGradePillCard(grade: Grade) {
    val gradeColor = gradeTint(grade.numericValue?.toDouble())
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(TintaColors.SmokedSurface)
            .border(1.dp, TintaColors.SubtleBorder, RoundedCornerShape(20.dp))
            .padding(horizontal = 10.dp, vertical = 8.dp),
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(gradeColor.copy(alpha = 0.2f))
                .border(1.dp, gradeColor.copy(alpha = 0.55f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = grade.displayValue,
                fontSize = 12.sp,
                fontWeight = FontWeight.ExtraBold,
                color = gradeColor,
            )
        }

        Spacer(Modifier.width(8.dp))

        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = grade.subjectName,
                    fontSize = 11.5.sp,
                    fontWeight = FontWeight.Bold,
                    color = TintaColors.TextPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                val weight = grade.weightPercentage
                if (weight != null && weight != 100) {
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "$weight%",
                        fontSize = 8.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = TintaColors.Amber,
                    )
                }
            }
            val desc = listOfNotNull(
                grade.topic?.takeIf { it.isNotBlank() } ?: grade.modeDescription,
                KretaDateParser.formatMonthDay(grade.recordedAtEpochMs),
            ).joinToString(" • ")
            Text(
                text = desc,
                style = TextStyle(
                    fontSize = 9.5.sp,
                    color = TintaColors.TextSecondary,
                    fontFeatureSettings = "tnum",
                ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun SubjectAveragePillCard(summary: SubjectAverageSummary) {
    val avg = summary.weightedAverage
    val pillColor = gradeTint(avg)
    val avgLabel = avg?.let { String.format(Locale.forLanguageTag("hu-HU"), "%.2f", it) } ?: "–"

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(CircleShape)
            .background(TintaColors.SmokedSurfaceAlt)
            .border(1.dp, TintaColors.SubtleBorder, CircleShape)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = summary.subjectName,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = TintaColors.TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = "${summary.gradeCount} jegy",
                fontSize = 9.sp,
                color = TintaColors.TextMuted,
            )
        }

        Spacer(Modifier.width(6.dp))

        Box(
            modifier = Modifier
                .clip(CircleShape)
                .background(pillColor.copy(alpha = 0.2f))
                .border(1.dp, pillColor.copy(alpha = 0.5f), CircleShape)
                .padding(horizontal = 8.dp, vertical = 3.dp),
        ) {
            Text(
                text = avgLabel,
                style = TextStyle(
                    fontSize = 11.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = pillColor,
                    fontFeatureSettings = "tnum",
                ),
            )
        }
    }
}

@Composable
private fun SectionSwitchRow(
    activePage: Int,
    onSelectTimetable: () -> Unit,
    onSelectGrades: () -> Unit,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.fillMaxWidth(0.92f),
    ) {
        NavPillTab(
            label = "Órarend",
            selected = activePage == 0,
            onClick = onSelectTimetable,
            modifier = Modifier.weight(1f),
        )
        NavPillTab(
            label = "Jegyek",
            selected = activePage == 1,
            onClick = onSelectGrades,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun NavPillTab(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .clip(CircleShape)
            .background(if (selected) TintaColors.AccentBlue else TintaColors.SmokedSurfaceAlt)
            .border(
                width = 1.dp,
                color = if (selected) TintaColors.AccentBlue else TintaColors.SubtleBorder,
                shape = CircleShape,
            )
            .clickable(onClick = onClick)
            .padding(vertical = 5.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            fontSize = 10.sp,
            fontWeight = FontWeight.ExtraBold,
            color = if (selected) TintaColors.PureBlack else TintaColors.TextSecondary,
            maxLines = 1,
        )
    }
}

@OptIn(ExperimentalWearFoundationApi::class)
@Composable
private fun LessonDetailOverlay(
    lesson: Lesson,
    homework: Homework?,
    onClose: () -> Unit,
) {
    val listState = rememberScalingLazyListState()
    val focusRequester = remember { FocusRequester() }

    Scaffold(
        timeText = { TimeText() },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .background(TintaColors.PureBlack)
                .requestFocusOnHierarchyActive()
                .rotaryScrollable(
                    behavior = RotaryScrollableDefaults.behavior(listState),
                    focusRequester = focusRequester,
                ),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.spacedBy(7.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            item {
                Text(
                    text = lesson.periodAndSubjectLabel(),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = TintaColors.TextPrimary,
                    textAlign = TextAlign.Center,
                )
            }

            item {
                val room = lesson.cleanRoomName
                Text(
                    text = if (room != null) "${lesson.timeRangeLabel} • $room" else lesson.timeRangeLabel,
                    style = TextStyle(
                        fontSize = 11.sp,
                        color = TintaColors.AccentBlue,
                        fontFeatureSettings = "tnum",
                    ),
                    textAlign = TextAlign.Center,
                )
            }

            if (lesson.isCancelled) {
                item {
                    StatusPillTag("Elmaradt óra", TintaColors.Crimson, TintaColors.CrimsonSoft)
                }
            }
            if (lesson.isSubstituted) {
                item {
                    StatusPillTag(
                        "Helyettesítés: ${lesson.cleanSubstituteTeacher}",
                        TintaColors.Amber,
                        TintaColors.AmberSoft,
                    )
                }
            }

            val teacher = lesson.cleanTeacher
            if (teacher != null) {
                item {
                    DetailPillBox(title = "Tanár", body = teacher)
                }
            }

            val theme = lesson.theme?.takeIf { it.isNotBlank() }
            if (theme != null) {
                item {
                    DetailPillBox(title = "Tananyag", body = theme)
                }
            }

            if (homework != null) {
                item {
                    DetailPillBox(
                        title = if (homework.isDone) "Házi feladat (kész)" else "Házi feladat",
                        body = homework.description.ifBlank { "Rögzített házi feladat" },
                        accentBorder = TintaColors.AccentBlue.copy(alpha = 0.5f),
                    )
                }
            } else if (lesson.hasHomeworkReference) {
                item {
                    DetailPillBox(
                        title = "Házi feladat",
                        body = "Aktív házi feladat van rögzítve ehhez az órához.",
                        accentBorder = TintaColors.AccentBlue.copy(alpha = 0.5f),
                    )
                }
            }

            item {
                Spacer(Modifier.height(2.dp))
                CompactChip(
                    onClick = onClose,
                    label = { Text("Bezárás", fontSize = 11.sp, fontWeight = FontWeight.Bold) },
                    colors = ChipDefaults.primaryChipColors(
                        backgroundColor = TintaColors.AccentBlue,
                        contentColor = TintaColors.PureBlack,
                    ),
                )
            }
        }
    }
}

@Composable
private fun DetailPillBox(
    title: String,
    body: String,
    accentBorder: Color = TintaColors.SubtleBorder,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(TintaColors.SmokedSurface)
            .border(1.dp, accentBorder, RoundedCornerShape(18.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Text(
            text = title,
            fontSize = 9.5.sp,
            fontWeight = FontWeight.Bold,
            color = TintaColors.TextSecondary,
        )
        Spacer(Modifier.height(2.dp))
        Text(
            text = body,
            fontSize = 11.sp,
            color = TintaColors.TextPrimary,
        )
    }
}

@Composable
private fun PullToRefreshContainer(
    listState: ScalingLazyListState,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    content: @Composable () -> Unit,
) {
    val density = LocalDensity.current
    val triggerThresholdPx = with(density) { 46.dp.toPx() }
    var pullDistancePx by remember { mutableFloatStateOf(0f) }

    val connection = remember(listState, isRefreshing, triggerThresholdPx) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput && pullDistancePx > 0f && available.y < 0f) {
                    val consumed = maxOf(available.y, -pullDistancePx)
                    pullDistancePx += consumed
                    return Offset(0f, consumed)
                }
                return Offset.Zero
            }

            override fun onPostScroll(
                consumed: Offset,
                available: Offset,
                source: NestedScrollSource,
            ): Offset {
                if (source == NestedScrollSource.UserInput &&
                    !isRefreshing &&
                    !listState.canScrollBackward &&
                    available.y > 0f
                ) {
                    pullDistancePx = (pullDistancePx + available.y * 0.55f).coerceAtMost(triggerThresholdPx * 1.4f)
                    return Offset(0f, available.y)
                }
                return Offset.Zero
            }

            override suspend fun onPreFling(available: Velocity): Velocity {
                if (pullDistancePx >= triggerThresholdPx && !isRefreshing) {
                    pullDistancePx = 0f
                    onRefresh()
                } else {
                    pullDistancePx = 0f
                }
                return Velocity.Zero
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .nestedScroll(connection),
    ) {
        content()

        AnimatedVisibility(
            visible = pullDistancePx > 8f || isRefreshing,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 24.dp),
        ) {
            Box(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(TintaColors.SmokedSurface)
                    .border(1.dp, TintaColors.AccentBlue.copy(alpha = 0.5f), CircleShape)
                    .padding(horizontal = 10.dp, vertical = 4.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(
                        indicatorColor = TintaColors.AccentBlue,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(12.dp),
                    )
                    Spacer(Modifier.width(5.dp))
                    Text(
                        text = when {
                            isRefreshing -> "Frissítés..."
                            pullDistancePx >= triggerThresholdPx -> "Engedd el"
                            else -> "Húzd le"
                        },
                        fontSize = 9.5.sp,
                        fontWeight = FontWeight.Bold,
                        color = TintaColors.TextPrimary,
                    )
                }
            }
        }
    }
}

private fun gradeTint(value: Double?): Color {
    if (value == null) return TintaColors.TextSecondary
    return when {
        value >= 4.5 -> TintaColors.AccentTeal
        value >= 3.5 -> TintaColors.AccentBlue
        value >= 2.5 -> TintaColors.Amber
        else -> TintaColors.Crimson
    }
}
