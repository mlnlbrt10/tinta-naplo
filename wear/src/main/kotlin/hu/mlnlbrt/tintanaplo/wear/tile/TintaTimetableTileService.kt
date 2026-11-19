package hu.mlnlbrt.tintanaplo.wear.tile

import android.content.Context
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.DeviceParametersBuilders
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.material.Text
import androidx.wear.protolayout.material.Typography
import androidx.wear.protolayout.material.layouts.PrimaryLayout
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture
import hu.mlnlbrt.tintanaplo.wear.MainActivity
import hu.mlnlbrt.tintanaplo.wear.auth.WearRemoteAuthManager
import hu.mlnlbrt.tintanaplo.wear.data.KretaDateParser
import hu.mlnlbrt.tintanaplo.wear.data.KretaWearApiClient
import hu.mlnlbrt.tintanaplo.wear.data.Lesson
import hu.mlnlbrt.tintanaplo.wear.data.SecureTokenStorage
import hu.mlnlbrt.tintanaplo.wear.data.StoredSession
import hu.mlnlbrt.tintanaplo.wear.data.TimetablePhase
import hu.mlnlbrt.tintanaplo.wear.data.TimetableStatus
import hu.mlnlbrt.tintanaplo.wear.data.TimetableStatusEvaluator
import hu.mlnlbrt.tintanaplo.wear.sync.KretaSyncScheduler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.guava.future

/**
 * Minimalist OLED Wear OS Tile displaying ONLY two clean pill cards:
 * 1. Current lesson (period, subject, room, remaining time / end time)
 * 2. Next lesson (next period, subject, room, start time — or "Nincs több óra")
 *
 * Tapping anywhere on the tile launches the Watch app directly.
 */
class TintaTimetableTileService : TileService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest,
    ): ListenableFuture<TileBuilders.Tile> = serviceScope.future {
        val nowMs = System.currentTimeMillis()
        var session: StoredSession? = null
        var lessons: List<Lesson> = emptyList()

        runCatching {
            val tokenStore = SecureTokenStorage(applicationContext)
            session = tokenStore.loadSession()
            val todayKey = KretaDateParser.dateKeyFor(nowMs)
            val accountKey = SecureTokenStorage.accountKeyFor(session)

            var cached = tokenStore.loadWearDataCache(accountKey, todayKey)
            val activeSession = session
            if (activeSession != null && (cached == null || cached.lessons.isEmpty())) {
                val apiClient = KretaWearApiClient(
                    tokenStore = tokenStore,
                    onSessionRefreshed = { refreshed ->
                        WearRemoteAuthManager.getInstance(applicationContext)
                            .pushRefreshedSessionToPhone(refreshed)
                    },
                )
                val synced = runCatching { apiClient.syncAll(activeSession) }.getOrNull()
                if (synced != null) {
                    cached = synced
                }
            }

            if (activeSession != null) {
                KretaSyncScheduler.ensurePeriodicSync(applicationContext)
                cached?.lessons?.let { cachedLessons ->
                    KretaSyncScheduler.scheduleNextTransitionUpdate(applicationContext, cachedLessons, nowMs)
                }
            }
            lessons = cached?.lessons ?: emptyList()
        }

        val timeline = buildTimeline(
            context = applicationContext,
            deviceParameters = requestParams.deviceConfiguration,
            session = session,
            lessons = lessons,
            nowMs = nowMs,
        )

        TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setFreshnessIntervalMillis(FRESHNESS_INTERVAL_MS)
            .setTileTimeline(timeline)
            .build()
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest,
    ): ListenableFuture<ResourceBuilders.Resources> = serviceScope.future {
        ResourceBuilders.Resources.Builder()
            .setVersion(RESOURCES_VERSION)
            .build()
    }

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun buildTimeline(
        context: Context,
        deviceParameters: DeviceParametersBuilders.DeviceParameters,
        session: StoredSession?,
        lessons: List<Lesson>,
        nowMs: Long,
    ): TimelineBuilders.Timeline {
        val timelineBuilder = TimelineBuilders.Timeline.Builder()
        if (session == null) {
            val layout = buildUnauthenticatedLayout(context, deviceParameters)
            timelineBuilder.addTimelineEntry(
                TimelineBuilders.TimelineEntry.Builder()
                    .setLayout(
                        LayoutElementBuilders.Layout.Builder().setRoot(layout).build(),
                    )
                    .build(),
            )
            return timelineBuilder.build()
        }

        val boundaries = buildTimelineBoundaries(lessons, nowMs)
        for (i in 0 until boundaries.size - 1) {
            val start = boundaries[i]
            val end = boundaries[i + 1]
            if (end <= start) continue
            val sampleTime = start + ((end - start).coerceAtMost(2_000L) / 2L)
            val status = TimetableStatusEvaluator.evaluate(lessons, sampleTime)
            val root = buildTimetableLayout(context, deviceParameters, status)
            timelineBuilder.addTimelineEntry(
                TimelineBuilders.TimelineEntry.Builder()
                    .setValidity(
                        TimelineBuilders.TimeInterval.Builder()
                            .setStartMillis(start)
                            .setEndMillis(end)
                            .build(),
                    )
                    .setLayout(
                        LayoutElementBuilders.Layout.Builder().setRoot(root).build(),
                    )
                    .build(),
            )
        }

        val fallbackTime = boundaries.lastOrNull() ?: nowMs
        val fallbackStatus = TimetableStatusEvaluator.evaluate(lessons, fallbackTime)
        timelineBuilder.addTimelineEntry(
            TimelineBuilders.TimelineEntry.Builder()
                .setLayout(
                    LayoutElementBuilders.Layout.Builder()
                        .setRoot(buildTimetableLayout(context, deviceParameters, fallbackStatus))
                        .build(),
                )
                .build(),
        )

        return timelineBuilder.build()
    }

    private fun buildTimelineBoundaries(lessons: List<Lesson>, nowMs: Long): List<Long> {
        val horizonMs = nowMs + FRESHNESS_INTERVAL_MS
        val points = sortedSetOf(nowMs, horizonMs)
        var tick = ((nowMs / 60_000L) + 1L) * 60_000L
        while (tick < horizonMs) {
            points.add(tick)
            tick += 60_000L
        }
        lessons.filter { !it.isCancelled }.forEach { lesson ->
            if (lesson.startEpochMs in (nowMs + 1L)..(nowMs + 8L * 3_600_000L)) {
                points.add(lesson.startEpochMs)
            }
            if (lesson.endEpochMs in (nowMs + 1L)..(nowMs + 8L * 3_600_000L)) {
                points.add(lesson.endEpochMs)
            }
        }
        return points.toList()
    }

    private fun openAppClickable(context: Context): ModifiersBuilders.Clickable =
        ModifiersBuilders.Clickable.Builder()
            .setId(CLICK_ID_OPEN_APP)
            .setOnClick(
                ActionBuilders.LaunchAction.Builder()
                    .setAndroidActivity(
                        ActionBuilders.AndroidActivity.Builder()
                            .setPackageName(context.packageName)
                            .setClassName(MainActivity::class.java.name)
                            .build(),
                    )
                    .build(),
            )
            .build()

    private fun buildUnauthenticatedLayout(
        context: Context,
        deviceParameters: DeviceParametersBuilders.DeviceParameters,
    ): LayoutElementBuilders.LayoutElement {
        val openClickable = openAppClickable(context)

        val pill = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(ColorBuilders.argb(COLOR_HERO_PILL_BG))
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(DimensionBuilders.dp(24f))
                                    .build(),
                            )
                            .build(),
                    )
                    .setBorder(
                        ModifiersBuilders.Border.Builder()
                            .setWidth(DimensionBuilders.dp(1f))
                            .setColor(ColorBuilders.argb(COLOR_PILL_BORDER))
                            .build(),
                    )
                    .setPadding(
                        ModifiersBuilders.Padding.Builder()
                            .setStart(DimensionBuilders.dp(14f))
                            .setEnd(DimensionBuilders.dp(14f))
                            .setTop(DimensionBuilders.dp(14f))
                            .setBottom(DimensionBuilders.dp(14f))
                            .build(),
                    )
                    .setClickable(openClickable)
                    .build(),
            )
            .addContent(
                LayoutElementBuilders.Column.Builder()
                    .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
                    .addContent(
                        Text.Builder(context, "Jelentkezz be telefonról")
                            .setTypography(Typography.TYPOGRAPHY_BODY1)
                            .setColor(ColorBuilders.argb(COLOR_TEXT_PRIMARY))
                            .setMaxLines(2)
                            .build(),
                    )
                    .addContent(
                        LayoutElementBuilders.Spacer.Builder()
                            .setHeight(DimensionBuilders.dp(4f))
                            .build(),
                    )
                    .addContent(
                        Text.Builder(context, "Érintsd meg a megnyitáshoz")
                            .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                            .setColor(ColorBuilders.argb(COLOR_ACCENT_BLUE))
                            .setMaxLines(1)
                            .build(),
                    )
                    .build(),
            )
            .build()

        val primary = PrimaryLayout.Builder(deviceParameters)
            .setResponsiveContentInsetEnabled(true)
            .setContent(pill)
            .build()

        return wrapInPureBlackOled(primary, openClickable)
    }

    private fun buildTimetableLayout(
        context: Context,
        deviceParameters: DeviceParametersBuilders.DeviceParameters,
        status: TimetableStatus,
    ): LayoutElementBuilders.LayoutElement {
        val openClickable = openAppClickable(context)

        val contentColumn = LayoutElementBuilders.Column.Builder()
            .setWidth(DimensionBuilders.expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setClickable(openClickable)
                    .build(),
            )
            .addContent(buildCurrentLessonPill(context, status, openClickable))
            .addContent(
                LayoutElementBuilders.Spacer.Builder()
                    .setHeight(DimensionBuilders.dp(8f))
                    .build(),
            )
            .addContent(buildNextLessonPill(context, status, openClickable))
            .build()

        val primary = PrimaryLayout.Builder(deviceParameters)
            .setResponsiveContentInsetEnabled(true)
            .setContent(contentColumn)
            .build()

        return wrapInPureBlackOled(primary, openClickable)
    }

    private fun buildCurrentLessonPill(
        context: Context,
        status: TimetableStatus,
        openClickable: ModifiersBuilders.Clickable,
    ): LayoutElementBuilders.LayoutElement {
        val activeLesson = status.currentLesson
        val isActive = status.phase == TimetablePhase.ACTIVE_LESSON
        val isBreak = status.phase == TimetablePhase.BREAK
        val isBeforeFirst = status.phase == TimetablePhase.BEFORE_FIRST_LESSON
        val isSubstituted = activeLesson?.isSubstituted == true

        val badgeColor = when {
            isSubstituted -> COLOR_AMBER
            isActive -> COLOR_ACCENT_BLUE
            isBreak -> COLOR_ACCENT_TEAL
            isBeforeFirst -> COLOR_ACCENT_INDIGO
            else -> COLOR_HERO_BADGE_MUTED
        }
        val badgeTextColor = if (isActive || isBreak || isBeforeFirst || isSubstituted) {
            COLOR_PURE_BLACK
        } else {
            COLOR_TEXT_PRIMARY
        }

        val periodText = activeLesson?.lessonNumber?.let { "$it." } ?: "•"
        val remainingText = status.remainingMillis?.let {
            TimetableStatusEvaluator.formatRemainingMinutesBadge(it)
        }

        val headlineText: String
        val roomText: String?
        val subLineText: String
        val subLineColor: Int

        when {
            isActive && activeLesson != null -> {
                headlineText = activeLesson.displaySubject
                roomText = activeLesson.cleanRoomName
                val endHm = KretaDateParser.formatHm(activeLesson.endEpochMs)
                subLineText = if (remainingText != null) "$remainingText • $endHm" else endHm
                subLineColor = if (isSubstituted) COLOR_AMBER else COLOR_ACCENT_BLUE
            }

            isBreak -> {
                headlineText = "Szünet"
                roomText = null
                subLineText = listOfNotNull(remainingText, status.subtitleLabel).joinToString(" • ")
                subLineColor = COLOR_ACCENT_TEAL
            }

            isBeforeFirst -> {
                headlineText = "Tanítás előtt"
                roomText = null
                subLineText = remainingText ?: status.subtitleLabel
                subLineColor = COLOR_ACCENT_INDIGO
            }

            else -> {
                headlineText = "Nincs több óra ma"
                roomText = null
                subLineText = status.subtitleLabel
                subLineColor = COLOR_TEXT_SECONDARY
            }
        }

        val periodBadge = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.dp(26f))
            .setHeight(DimensionBuilders.dp(26f))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(ColorBuilders.argb(badgeColor))
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(DimensionBuilders.dp(13f))
                                    .build(),
                            )
                            .build(),
                    )
                    .build(),
            )
            .addContent(
                Text.Builder(context, periodText)
                    .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                    .setColor(ColorBuilders.argb(badgeTextColor))
                    .setMaxLines(1)
                    .build(),
            )
            .build()

        val titleRowBuilder = LayoutElementBuilders.Row.Builder()
            .setWidth(DimensionBuilders.expand())
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .addContent(
                LayoutElementBuilders.Box.Builder()
                    .setWidth(DimensionBuilders.weight(1f))
                    .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_START)
                    .addContent(
                        Text.Builder(context, headlineText)
                            .setTypography(Typography.TYPOGRAPHY_BODY1)
                            .setColor(ColorBuilders.argb(COLOR_TEXT_PRIMARY))
                            .setMaxLines(1)
                            .setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE)
                            .build(),
                    )
                    .build(),
            )

        if (roomText != null) {
            titleRowBuilder.addContent(
                LayoutElementBuilders.Spacer.Builder()
                    .setWidth(DimensionBuilders.dp(6f))
                    .build(),
            )
            titleRowBuilder.addContent(
                Text.Builder(context, roomText)
                    .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                    .setColor(ColorBuilders.argb(COLOR_TEXT_SECONDARY))
                    .setMaxLines(1)
                    .build(),
            )
        }

        val textColumn = LayoutElementBuilders.Column.Builder()
            .setWidth(DimensionBuilders.expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_START)
            .addContent(titleRowBuilder.build())
            .addContent(
                LayoutElementBuilders.Spacer.Builder()
                    .setHeight(DimensionBuilders.dp(2f))
                    .build(),
            )
            .addContent(
                Text.Builder(context, subLineText)
                    .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                    .setColor(ColorBuilders.argb(subLineColor))
                    .setMaxLines(1)
                    .setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE)
                    .build(),
            )
            .build()

        val row = LayoutElementBuilders.Row.Builder()
            .setWidth(DimensionBuilders.expand())
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .addContent(periodBadge)
            .addContent(
                LayoutElementBuilders.Spacer.Builder()
                    .setWidth(DimensionBuilders.dp(9f))
                    .build(),
            )
            .addContent(
                LayoutElementBuilders.Box.Builder()
                    .setWidth(DimensionBuilders.weight(1f))
                    .addContent(textColumn)
                    .build(),
            )
            .build()

        val cardBg = if (isActive) COLOR_ACTIVE_HERO_BG else COLOR_HERO_PILL_BG
        val borderColor = when {
            isSubstituted -> COLOR_AMBER
            isActive -> COLOR_ACCENT_BLUE
            isBreak -> COLOR_ACCENT_TEAL_DIM
            else -> COLOR_PILL_BORDER
        }

        return LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.expand())
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(ColorBuilders.argb(cardBg))
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(DimensionBuilders.dp(26f))
                                    .build(),
                            )
                            .build(),
                    )
                    .setBorder(
                        ModifiersBuilders.Border.Builder()
                            .setWidth(DimensionBuilders.dp(1f))
                            .setColor(ColorBuilders.argb(borderColor))
                            .build(),
                    )
                    .setPadding(
                        ModifiersBuilders.Padding.Builder()
                            .setStart(DimensionBuilders.dp(11f))
                            .setEnd(DimensionBuilders.dp(13f))
                            .setTop(DimensionBuilders.dp(11f))
                            .setBottom(DimensionBuilders.dp(11f))
                            .build(),
                    )
                    .setClickable(openClickable)
                    .build(),
            )
            .addContent(row)
            .build()
    }

    private fun buildNextLessonPill(
        context: Context,
        status: TimetableStatus,
        openClickable: ModifiersBuilders.Clickable,
    ): LayoutElementBuilders.LayoutElement {
        val next = status.nextLesson
        if (next == null) {
            return LayoutElementBuilders.Box.Builder()
                .setWidth(DimensionBuilders.expand())
                .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
                .setModifiers(
                    ModifiersBuilders.Modifiers.Builder()
                        .setBackground(
                            ModifiersBuilders.Background.Builder()
                                .setColor(ColorBuilders.argb(COLOR_SLIM_PILL_BG))
                                .setCorner(
                                    ModifiersBuilders.Corner.Builder()
                                        .setRadius(DimensionBuilders.dp(22f))
                                        .build(),
                                )
                                .build(),
                        )
                        .setBorder(
                            ModifiersBuilders.Border.Builder()
                                .setWidth(DimensionBuilders.dp(0.8f))
                                .setColor(ColorBuilders.argb(COLOR_SLIM_PILL_BORDER))
                                .build(),
                        )
                        .setPadding(
                            ModifiersBuilders.Padding.Builder()
                                .setStart(DimensionBuilders.dp(12f))
                                .setEnd(DimensionBuilders.dp(12f))
                                .setTop(DimensionBuilders.dp(10f))
                                .setBottom(DimensionBuilders.dp(10f))
                                .build(),
                        )
                        .setClickable(openClickable)
                        .build(),
                )
                .addContent(
                    Text.Builder(context, "Nincs több óra")
                        .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                        .setColor(ColorBuilders.argb(COLOR_TEXT_SECONDARY))
                        .setMaxLines(1)
                        .build(),
                )
                .build()
        }

        val periodLabel = next.lessonNumber?.let { "$it." } ?: "•"
        val startHm = KretaDateParser.formatHm(next.startEpochMs)
        val room = next.cleanRoomName
        val rightMeta = if (room != null) "$room • $startHm" else startHm

        val miniBadge = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.dp(22f))
            .setHeight(DimensionBuilders.dp(22f))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(
                                ColorBuilders.argb(
                                    if (next.isSubstituted) COLOR_AMBER else COLOR_HERO_BADGE_MUTED,
                                ),
                            )
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(DimensionBuilders.dp(11f))
                                    .build(),
                            )
                            .build(),
                    )
                    .build(),
            )
            .addContent(
                Text.Builder(context, periodLabel)
                    .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                    .setColor(
                        ColorBuilders.argb(
                            if (next.isSubstituted) COLOR_PURE_BLACK else COLOR_TEXT_PRIMARY,
                        ),
                    )
                    .setMaxLines(1)
                    .build(),
            )
            .build()

        val row = LayoutElementBuilders.Row.Builder()
            .setWidth(DimensionBuilders.expand())
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .addContent(miniBadge)
            .addContent(
                LayoutElementBuilders.Spacer.Builder()
                    .setWidth(DimensionBuilders.dp(8f))
                    .build(),
            )
            .addContent(
                LayoutElementBuilders.Box.Builder()
                    .setWidth(DimensionBuilders.weight(1f))
                    .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_START)
                    .addContent(
                        Text.Builder(context, next.displaySubject)
                            .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                            .setColor(ColorBuilders.argb(COLOR_TEXT_PRIMARY))
                            .setMaxLines(1)
                            .setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE)
                            .build(),
                    )
                    .build(),
            )
            .addContent(
                LayoutElementBuilders.Spacer.Builder()
                    .setWidth(DimensionBuilders.dp(6f))
                    .build(),
            )
            .addContent(
                Text.Builder(context, rightMeta)
                    .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                    .setColor(
                        ColorBuilders.argb(
                            if (next.isSubstituted) COLOR_AMBER else COLOR_TEXT_SECONDARY,
                        ),
                    )
                    .setMaxLines(1)
                    .build(),
            )
            .build()

        return LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.expand())
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(ColorBuilders.argb(COLOR_SLIM_PILL_BG))
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(DimensionBuilders.dp(22f))
                                    .build(),
                            )
                            .build(),
                    )
                    .setBorder(
                        ModifiersBuilders.Border.Builder()
                            .setWidth(DimensionBuilders.dp(0.8f))
                            .setColor(
                                ColorBuilders.argb(
                                    if (next.isSubstituted) COLOR_AMBER_DIM else COLOR_SLIM_PILL_BORDER,
                                ),
                            )
                            .build(),
                    )
                    .setPadding(
                        ModifiersBuilders.Padding.Builder()
                            .setStart(DimensionBuilders.dp(10f))
                            .setEnd(DimensionBuilders.dp(12f))
                            .setTop(DimensionBuilders.dp(9f))
                            .setBottom(DimensionBuilders.dp(9f))
                            .build(),
                    )
                    .setClickable(openClickable)
                    .build(),
            )
            .addContent(row)
            .build()
    }

    private fun wrapInPureBlackOled(
        inner: LayoutElementBuilders.LayoutElement,
        openClickable: ModifiersBuilders.Clickable,
    ): LayoutElementBuilders.LayoutElement =
        LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.expand())
            .setHeight(DimensionBuilders.expand())
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(ColorBuilders.argb(COLOR_PURE_BLACK))
                            .build(),
                    )
                    .setClickable(openClickable)
                    .build(),
            )
            .addContent(inner)
            .build()

    companion object {
        private const val RESOURCES_VERSION = "2"
        private const val FRESHNESS_INTERVAL_MS = 5L * 60_000L
        private const val CLICK_ID_OPEN_APP = "open_app"

        private const val COLOR_PURE_BLACK = 0xFF000000.toInt()
        private const val COLOR_HERO_PILL_BG = 0xFF141820.toInt()
        private const val COLOR_ACTIVE_HERO_BG = 0xFF0B192B.toInt()
        private const val COLOR_SLIM_PILL_BG = 0xFF101318.toInt()
        private const val COLOR_PILL_BORDER = 0xFF28303D.toInt()
        private const val COLOR_SLIM_PILL_BORDER = 0xFF1E242E.toInt()
        private const val COLOR_HERO_BADGE_MUTED = 0xFF27303F.toInt()

        private const val COLOR_ACCENT_BLUE = 0xFF4DA3FF.toInt()
        private const val COLOR_ACCENT_TEAL = 0xFF26D0A8.toInt()
        private const val COLOR_ACCENT_TEAL_DIM = 0x8026D0A8.toInt()
        private const val COLOR_ACCENT_INDIGO = 0xFF7B9CFF.toInt()
        private const val COLOR_AMBER = 0xFFFFB74D.toInt()
        private const val COLOR_AMBER_DIM = 0x66FFB74D
        private const val COLOR_TEXT_PRIMARY = 0xFFFFFFFF.toInt()
        private const val COLOR_TEXT_SECONDARY = 0xFFA4B0C2.toInt()
    }
}
