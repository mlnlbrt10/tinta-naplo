package hu.rekreta.rekreta_app.wear.ui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
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
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.ExperimentalWearFoundationApi
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.ScalingLazyColumnDefaults
import androidx.wear.compose.foundation.lazy.ScalingLazyListState
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.foundation.pager.PagerDefaults
import androidx.wear.compose.foundation.pager.VerticalPager
import androidx.wear.compose.foundation.pager.rememberPagerState
import androidx.wear.compose.foundation.requestFocusOnHierarchyActive
import androidx.wear.compose.foundation.rotary.RotaryScrollableDefaults
import androidx.wear.compose.foundation.rotary.rotaryScrollable
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import hu.rekreta.rekreta_app.wear.auth.RemoteAuthStatus
import hu.rekreta.rekreta_app.wear.auth.WearRemoteAuthManager
import hu.rekreta.rekreta_app.wear.data.InvalidGrantException
import hu.rekreta.rekreta_app.wear.data.KretaDateParser
import hu.rekreta.rekreta_app.wear.data.KretaWearApiClient
import hu.rekreta.rekreta_app.wear.data.Lesson
import hu.rekreta.rekreta_app.wear.data.RolloverTimetableState
import hu.rekreta.rekreta_app.wear.data.SecureTokenStorage
import hu.rekreta.rekreta_app.wear.data.StoredSession
import hu.rekreta.rekreta_app.wear.data.TimetablePhase
import hu.rekreta.rekreta_app.wear.data.TimetableStatus
import hu.rekreta.rekreta_app.wear.data.TimetableStatusEvaluator
import hu.rekreta.rekreta_app.wear.data.TokenExpiredException
import hu.rekreta.rekreta_app.wear.sync.KretaSyncScheduler
import hu.rekreta.rekreta_app.wear.sync.KretaSyncWorker
import hu.rekreta.rekreta_app.wear.ui.theme.TintaColors
import hu.rekreta.rekreta_app.wear.ui.theme.TintaWearTheme
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

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
        val loaded = withContext(Dispatchers.IO) {
            tokenStore.loadSession()
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
            WearTwoPageWatchUi(
                session = activeSession,
                tokenStore = tokenStore,
                apiClient = apiClient,
                resumeEpoch = resumeEpoch,
            )
        }
    }
}

@OptIn(ExperimentalWearFoundationApi::class)
@Composable
private fun WearTwoPageWatchUi(
    session: StoredSession,
    tokenStore: SecureTokenStorage,
    apiClient: KretaWearApiClient,
    resumeEpoch: Int,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pagerState = rememberPagerState(pageCount = { 2 })
    val timetableListState = rememberScalingLazyListState()

    val instituteKey = remember(session.instituteCode) {
        session.instituteCode.trim().lowercase()
    }
    val accountKey = remember(session.instituteCode, session.userName) {
        SecureTokenStorage.accountKeyFor(session)
    }

    val initialCache = remember(instituteKey) {
        tokenStore.loadWearDataCache(accountKey, KretaDateParser.dateKeyFor())
    }

    var lessons by remember(instituteKey) {
        mutableStateOf(initialCache?.lessons ?: emptyList())
    }
    var isSyncing by remember(instituteKey) { mutableStateOf(false) }
    var hasLoadedOnce by remember(instituteKey) { mutableStateOf(initialCache != null) }

    var boundaryNowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var liveNowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val liveNowMsProvider = remember { { liveNowMs } }

    // Boundary ticker updates only at lesson start/end/midnight transitions so
    // the pager, day-rollover calculation, and Page 2 list never recompose on 1s ticks.
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

    val isLiveCountdownPhase = !rolloverState.isRolledOverToNextDay && (
        rolloverState.todayStatus.phase == TimetablePhase.ACTIVE_LESSON ||
            rolloverState.todayStatus.phase == TimetablePhase.BREAK ||
            rolloverState.todayStatus.phase == TimetablePhase.BEFORE_FIRST_LESSON
        )
    val isOnPage0 by remember { derivedStateOf { pagerState.currentPage == 0 } }

    // 1-second ticker runs only while Page 1 is visible and counting down, and is read
    // exclusively inside leaf progress-ring / countdown composables.
    LaunchedEffect(isOnPage0, isLiveCountdownPhase, resumeEpoch) {
        if (!isOnPage0 || !isLiveCountdownPhase) return@LaunchedEffect
        while (true) {
            liveNowMs = System.currentTimeMillis()
            delay(1_000L)
        }
    }

    // Reload freshest cache on resume and refresh silently against KRÉTA in the background.
    // Never clear session or cached timetable data on network/token errors.
    LaunchedEffect(instituteKey, resumeEpoch) {
        val cached = withContext(Dispatchers.IO) {
            tokenStore.loadWearDataCache(accountKey, KretaDateParser.dateKeyFor())
        }
        if (cached != null) {
            lessons = cached.lessons
            hasLoadedOnce = true
        }
        if (isSyncing) return@LaunchedEffect
        isSyncing = true
        scope.launch {
            try {
                val latestSession = withContext(Dispatchers.IO) {
                    tokenStore.loadSession()
                } ?: session
                val synced = apiClient.syncAll(latestSession)
                lessons = synced.lessons
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
            } catch (_: Exception) {
                hasLoadedOnce = true
            } finally {
                isSyncing = false
            }
        }
    }

    val showPage2Overlay by remember {
        derivedStateOf { pagerState.currentPage > 0 || pagerState.currentPageOffsetFraction > 0.02f }
    }
    val pagerFlingBehavior = PagerDefaults.snapFlingBehavior(
        state = pagerState,
        snapAnimationSpec = spring(
            dampingRatio = Spring.DampingRatioNoBouncy,
            stiffness = Spring.StiffnessMediumLow,
        ),
    )

    Scaffold(
        timeText = {
            if (showPage2Overlay) {
                TimeText(
                    modifier = Modifier.graphicsLayer {
                        alpha = (pagerState.currentPage + pagerState.currentPageOffsetFraction)
                            .coerceIn(0f, 1f)
                    },
                )
            }
        },
        positionIndicator = {
            if (showPage2Overlay) {
                PositionIndicator(
                    scalingLazyListState = timetableListState,
                    modifier = Modifier.graphicsLayer {
                        alpha = (pagerState.currentPage + pagerState.currentPageOffsetFraction)
                            .coerceIn(0f, 1f)
                    },
                )
            }
        },
    ) {
        VerticalPager(
            state = pagerState,
            beyondViewportPageCount = 1,
            flingBehavior = pagerFlingBehavior,
            key = { it },
            modifier = Modifier
                .fillMaxSize()
                .background(TintaColors.PureBlack),
        ) { page ->
            val pageTransitionModifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    val pageOffset = ((pagerState.currentPage - page) + pagerState.currentPageOffsetFraction)
                        .coerceIn(-1f, 1f)
                    val visibility = (1f - abs(pageOffset)).coerceIn(0f, 1f)
                    val inv = 1f - visibility
                    val cubicEased = 1f - (inv * inv * inv)
                    val scale = 0.90f + 0.10f * cubicEased
                    scaleX = scale
                    scaleY = scale
                    alpha = 0.35f + 0.65f * cubicEased
                }

            when (page) {
                0 -> CurrentLessonBezelPage(
                    rolloverState = rolloverState,
                    isLoadingInitial = !hasLoadedOnce && isSyncing,
                    nowMsProvider = liveNowMsProvider,
                    modifier = pageTransitionModifier,
                )

                else -> TodayTimetablePage(
                    listState = timetableListState,
                    rolloverState = rolloverState,
                    boundaryNowMs = boundaryNowMs,
                    isLoadingInitial = !hasLoadedOnce && isSyncing,
                    modifier = pageTransitionModifier,
                )
            }
        }
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
                trackColor = TintaColors.PillBorder.copy(alpha = 0.4f),
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
            color = TintaColors.PillBorder.copy(alpha = 0.42f),
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
private fun TodayTimetablePage(
    listState: ScalingLazyListState,
    rolloverState: RolloverTimetableState,
    boundaryNowMs: Long,
    isLoadingInitial: Boolean,
    modifier: Modifier = Modifier,
) {
    val focusRequester = remember { FocusRequester() }
    val scalingParams = remember {
        ScalingLazyColumnDefaults.scalingParams(
            edgeScale = 0.72f,
            edgeAlpha = 0.45f,
            minElementHeight = 0.25f,
            maxElementHeight = 0.75f,
            minTransitionArea = 0.35f,
            maxTransitionArea = 0.55f,
            scaleInterpolator = CubicBezierEasing(0.2f, 0.0f, 0.0f, 1.0f),
        )
    }
    val displayLessons = rolloverState.displayLessons
    val status = rolloverState.todayStatus
    val isRolledOver = rolloverState.isRolledOverToNextDay

    ScalingLazyColumn(
        state = listState,
        scalingParams = scalingParams,
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
                verticalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier.padding(bottom = 3.dp),
            ) {
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(
                            if (isRolledOver) {
                                TintaColors.ActiveHeroSurface
                            } else {
                                TintaColors.SmokedSurface
                            },
                        )
                        .border(
                            1.dp,
                            if (isRolledOver) {
                                TintaColors.AccentIndigo.copy(alpha = 0.55f)
                            } else {
                                TintaColors.PillBorder
                            },
                            CircleShape,
                        )
                        .padding(horizontal = 10.dp, vertical = 2.5.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = rolloverState.displayDayPillLabel,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (isRolledOver) {
                            TintaColors.AccentIndigo
                        } else {
                            TintaColors.TextSecondary
                        },
                        maxLines = 1,
                    )
                }

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
        } else if (displayLessons.isEmpty()) {
            item(key = "empty") {
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
                        text = "Nincs rögzített tanóra.",
                        fontSize = 11.5.sp,
                        color = TintaColors.TextSecondary,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        } else {
            items(displayLessons, key = { "${it.uid}_${it.startEpochMs}" }) { lesson ->
                val isActive = !isRolledOver &&
                    status.currentLesson?.uid == lesson.uid &&
                    status.currentLesson.startEpochMs == lesson.startEpochMs
                val isFinished = !isRolledOver &&
                    !isActive &&
                    boundaryNowMs >= lesson.endEpochMs
                LessonPillCard(
                    lesson = lesson,
                    isActive = isActive,
                    isFinished = isFinished,
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

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (isFinished || isCancelled) 0.55f else 1f)
            .clip(RoundedCornerShape(22.dp))
            .background(if (isActive) TintaColors.ActiveHeroSurface else TintaColors.SmokedSurface)
            .border(if (isActive) 1.5.dp else 1.dp, borderColor, RoundedCornerShape(22.dp))
            .padding(horizontal = 10.dp, vertical = 9.dp),
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
            Text(
                text = lesson.displaySubject,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = TintaColors.TextPrimary,
                textDecoration = if (isCancelled) TextDecoration.LineThrough else null,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )

            val room = lesson.cleanRoomName
            val meta = if (room != null) {
                "${lesson.compactTimeRangeLabel} • $room"
            } else {
                lesson.compactTimeRangeLabel
            }
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
                if (isCancelled) {
                    StatusPillTag(
                        label = "Elmaradt",
                        fg = TintaColors.Crimson,
                        bg = TintaColors.CrimsonSoft,
                    )
                } else {
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
