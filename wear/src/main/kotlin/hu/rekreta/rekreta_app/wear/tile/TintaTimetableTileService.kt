package hu.rekreta.rekreta_app.wear.tile

import android.content.ComponentName
import android.content.Context
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.DeviceParametersBuilders
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.material.Chip
import androidx.wear.protolayout.material.ChipColors
import androidx.wear.protolayout.material.CompactChip
import androidx.wear.protolayout.material.Text
import androidx.wear.protolayout.material.Typography
import androidx.wear.protolayout.material.layouts.MultiSlotLayout
import androidx.wear.protolayout.material.layouts.PrimaryLayout
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture
import hu.rekreta.rekreta_app.wear.MainActivity
import hu.rekreta.rekreta_app.wear.R
import hu.rekreta.rekreta_app.wear.data.KretaDateParser
import hu.rekreta.rekreta_app.wear.data.KretaWearApiClient
import hu.rekreta.rekreta_app.wear.data.Lesson
import hu.rekreta.rekreta_app.wear.data.SecureTokenStorage
import hu.rekreta.rekreta_app.wear.data.StoredSession
import hu.rekreta.rekreta_app.wear.data.TimetablePhase
import hu.rekreta.rekreta_app.wear.data.TimetableStatus
import hu.rekreta.rekreta_app.wear.data.TimetableStatusEvaluator
import hu.rekreta.rekreta_app.wear.sync.KretaSyncScheduler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.guava.future

/**
 * Samsung Galaxy Watch / Wear OS One UI Watch style OLED pill Tile displaying
 * the current/next lesson hero card, up to 2 upcoming lessons in slim capsule
 * pills, and a bottom action/refresh chip.
 */
class TintaTimetableTileService : TileService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest,
    ): ListenableFuture<TileBuilders.Tile> = serviceScope.future {
        val tokenStore = SecureTokenStorage(applicationContext)
        val session = tokenStore.loadSession()
        val nowMs = System.currentTimeMillis()
        val todayKey = KretaDateParser.dateKeyFor(nowMs)
        val accountKey = SecureTokenStorage.accountKeyFor(session)

        val isManualRefresh = requestParams.currentState.lastClickableId == CLICK_ID_REFRESH
        var cached = tokenStore.loadWearDataCache(accountKey, todayKey)

        if (session != null && (isManualRefresh || cached == null || cached.lessons.isEmpty())) {
            val apiClient = KretaWearApiClient(tokenStore)
            val synced = runCatching { apiClient.syncAll(session) }.getOrNull()
            if (synced != null) {
                cached = synced
            }
            if (isManualRefresh) {
                getUpdater(applicationContext).requestUpdate(TintaTimetableTileService::class.java)
            }
        }

        if (session != null) {
            KretaSyncScheduler.ensurePeriodicSync(applicationContext)
            cached?.lessons?.let { lessons ->
                KretaSyncScheduler.scheduleNextTransitionUpdate(applicationContext, lessons, nowMs)
            }
        }

        val lessons = cached?.lessons ?: emptyList()
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
            .addIdToImageMapping(
                RES_ICON_REFRESH,
                ResourceBuilders.ImageResource.Builder()
                    .setAndroidResourceByResId(
                        ResourceBuilders.AndroidImageResourceByResId.Builder()
                            .setResourceId(R.drawable.ic_refresh)
                            .build(),
                    )
                    .build(),
            )
            .addIdToImageMapping(
                RES_ICON_SCHOOL,
                ResourceBuilders.ImageResource.Builder()
                    .setAndroidResourceByResId(
                        ResourceBuilders.AndroidImageResourceByResId.Builder()
                            .setResourceId(R.drawable.ic_school)
                            .build(),
                    )
                    .build(),
            )
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

        // Build per-minute or transition-aware timeline entries across the upcoming 15 minutes
        // and next lesson boundaries so countdown minutes & lesson transitions stay accurate.
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

        // Fallback entry after the last computed boundary
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
        // Step every minute within the freshness horizon for accurate remaining minutes
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

    private fun refreshClickable(): ModifiersBuilders.Clickable =
        ModifiersBuilders.Clickable.Builder()
            .setId(CLICK_ID_REFRESH)
            .setOnClick(ActionBuilders.LoadAction.Builder().build())
            .build()

    private fun buildUnauthenticatedLayout(
        context: Context,
        deviceParameters: DeviceParametersBuilders.DeviceParameters,
    ): LayoutElementBuilders.LayoutElement {
        val openClickable = openAppClickable(context)
        val primary = PrimaryLayout.Builder(deviceParameters)
            .setResponsiveContentInsetEnabled(true)
            .setPrimaryLabelTextContent(
                Text.Builder(context, "TINTA NAPLÓ")
                    .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                    .setColor(ColorBuilders.argb(COLOR_ACCENT_BLUE))
                    .build(),
            )
            .setContent(
                LayoutElementBuilders.Box.Builder()
                    .setWidth(DimensionBuilders.expand())
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
                                    .setAll(DimensionBuilders.dp(14f))
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
                                Text.Builder(context, "Érintsd meg a kezdéshez")
                                    .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                                    .setColor(ColorBuilders.argb(COLOR_TEXT_SECONDARY))
                                    .setMaxLines(1)
                                    .build(),
                            )
                            .build(),
                    )
                    .build(),
            )
            .setPrimaryChipContent(
                Chip.Builder(context, openClickable, deviceParameters)
                    .setPrimaryLabelContent("Megnyitás")
                    .setIconContent(RES_ICON_SCHOOL)
                    .setChipColors(
                        ChipColors(
                            ColorBuilders.argb(COLOR_ACCENT_BLUE),
                            ColorBuilders.argb(COLOR_PURE_BLACK),
                        ),
                    )
                    .build(),
            )
            .build()

        return wrapInPureBlackOled(primary)
    }

    private fun buildTimetableLayout(
        context: Context,
        deviceParameters: DeviceParametersBuilders.DeviceParameters,
        status: TimetableStatus,
    ): LayoutElementBuilders.LayoutElement {
        val openClickable = openAppClickable(context)
        val refreshClickable = refreshClickable()

        val headerColor = when (status.phase) {
            TimetablePhase.ACTIVE_LESSON -> COLOR_ACCENT_BLUE
            TimetablePhase.BREAK -> COLOR_ACCENT_TEAL
            TimetablePhase.BEFORE_FIRST_LESSON -> COLOR_ACCENT_INDIGO
            TimetablePhase.AFTER_SCHOOL, TimetablePhase.NO_CLASSES_TODAY -> COLOR_TEXT_SECONDARY
        }

        val contentColumn = LayoutElementBuilders.Column.Builder()
            .setWidth(DimensionBuilders.expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setClickable(openClickable)
                    .build(),
            )

        // 1. Primary Hero Pill Card
        contentColumn.addContent(buildHeroPillCard(context, status, openClickable))
        contentColumn.addContent(
            LayoutElementBuilders.Spacer.Builder()
                .setHeight(DimensionBuilders.dp(6f))
                .build(),
        )

        // 2. Secondary Compact Pill Row / List (Next 2 upcoming lessons or "Nincs több óra ma")
        if (status.upcomingLessons.isNotEmpty()) {
            val pills = status.upcomingLessons.take(2)
            pills.forEachIndexed { index, lesson ->
                contentColumn.addContent(buildUpcomingSlimPill(context, lesson, openClickable))
                if (index < pills.lastIndex) {
                    contentColumn.addContent(
                        LayoutElementBuilders.Spacer.Builder()
                            .setHeight(DimensionBuilders.dp(4f))
                            .build(),
                    )
                }
            }
        } else {
            contentColumn.addContent(buildEmptyDaySlimPill(context, status, openClickable))
        }

        val primary = PrimaryLayout.Builder(deviceParameters)
            .setResponsiveContentInsetEnabled(true)
            .setPrimaryLabelTextContent(
                Text.Builder(context, status.badgeLabel)
                    .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                    .setColor(ColorBuilders.argb(headerColor))
                    .setMaxLines(1)
                    .build(),
            )
            .setContent(contentColumn.build())
            .setPrimaryChipContent(
                CompactChip.Builder(context, refreshClickable, deviceParameters)
                    .setTextContent("Frissítés")
                    .setIconContent(RES_ICON_REFRESH)
                    .setChipColors(
                        ChipColors(
                            ColorBuilders.argb(COLOR_SLIM_PILL_BG),
                            ColorBuilders.argb(COLOR_TEXT_PRIMARY),
                        ),
                    )
                    .build(),
            )
            .build()

        return wrapInPureBlackOled(primary)
    }

    private fun buildHeroPillCard(
        context: Context,
        status: TimetableStatus,
        openClickable: ModifiersBuilders.Clickable,
    ): LayoutElementBuilders.LayoutElement {
        val heroLesson = status.currentLesson ?: status.nextLesson
        val isActive = status.phase == TimetablePhase.ACTIVE_LESSON
        val isSubstituted = heroLesson?.isSubstituted == true
        val badgeColor = when {
            isSubstituted -> COLOR_AMBER
            isActive -> COLOR_ACCENT_BLUE
            status.phase == TimetablePhase.BREAK -> COLOR_ACCENT_TEAL
            else -> COLOR_HERO_BADGE_MUTED
        }
        val badgeTextColor = if (isActive || isSubstituted || status.phase == TimetablePhase.BREAK) {
            COLOR_PURE_BLACK
        } else {
            COLOR_TEXT_PRIMARY
        }

        val periodLabel = heroLesson?.lessonNumber?.let { "$it." } ?: "•"
        val headlineText = when {
            heroLesson != null -> heroLesson.periodSubjectRoomBadge()
            else -> status.titleLabel
        }

        val remainingPart = status.remainingMillis?.let {
            TimetableStatusEvaluator.formatMinutesRemainingPill(it)
        }
        val timeWindow = heroLesson?.timeRangeLabel ?: status.subtitleLabel
        val subLineText = if (remainingPart != null) {
            "$remainingPart • $timeWindow"
        } else {
            timeWindow
        }

        val periodBadge = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.dp(24f))
            .setHeight(DimensionBuilders.dp(24f))
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(ColorBuilders.argb(badgeColor))
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(DimensionBuilders.dp(12f))
                                    .build(),
                            )
                            .build(),
                    )
                    .build(),
            )
            .addContent(
                Text.Builder(context, periodLabel)
                    .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                    .setColor(ColorBuilders.argb(badgeTextColor))
                    .setMaxLines(1)
                    .build(),
            )
            .build()

        val textColumn = LayoutElementBuilders.Column.Builder()
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_START)
            .addContent(
                Text.Builder(context, headlineText)
                    .setTypography(Typography.TYPOGRAPHY_TITLE3)
                    .setColor(ColorBuilders.argb(COLOR_TEXT_PRIMARY))
                    .setMaxLines(1)
                    .setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE_END)
                    .build(),
            )
            .addContent(
                Text.Builder(context, subLineText)
                    .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                    .setColor(
                        ColorBuilders.argb(
                            if (isActive) COLOR_ACCENT_BLUE else COLOR_TEXT_SECONDARY,
                        ),
                    )
                    .setMaxLines(1)
                    .setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE_END)
                    .build(),
            )
            .build()

        val heroRow = MultiSlotLayout.Builder()
            .setHorizontalSpacerWidth(8f)
            .addSlotContent(periodBadge)
            .addSlotContent(textColumn)
            .build()

        return LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.expand())
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(
                                ColorBuilders.argb(
                                    if (isActive) COLOR_ACTIVE_HERO_BG else COLOR_HERO_PILL_BG,
                                ),
                            )
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
                            .setColor(
                                ColorBuilders.argb(
                                    if (isActive) COLOR_ACCENT_BLUE else COLOR_PILL_BORDER,
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
            .addContent(heroRow)
            .build()
    }

    private fun buildUpcomingSlimPill(
        context: Context,
        lesson: Lesson,
        openClickable: ModifiersBuilders.Clickable,
    ): LayoutElementBuilders.LayoutElement {
        val label = lesson.periodSubjectRoomBadge()
        val time = KretaDateParser.formatHm(lesson.startEpochMs)

        val row = MultiSlotLayout.Builder()
            .setHorizontalSpacerWidth(6f)
            .addSlotContent(
                Text.Builder(context, label)
                    .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                    .setColor(ColorBuilders.argb(COLOR_TEXT_PRIMARY))
                    .setMaxLines(1)
                    .setOverflow(LayoutElementBuilders.TEXT_OVERFLOW_ELLIPSIZE_END)
                    .build(),
            )
            .addSlotContent(
                Text.Builder(context, time)
                    .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                    .setColor(
                        ColorBuilders.argb(
                            if (lesson.isSubstituted) COLOR_AMBER else COLOR_TEXT_SECONDARY,
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
                                    .setRadius(DimensionBuilders.dp(18f))
                                    .build(),
                            )
                            .build(),
                    )
                    .setBorder(
                        ModifiersBuilders.Border.Builder()
                            .setWidth(DimensionBuilders.dp(0.8f))
                            .setColor(
                                ColorBuilders.argb(
                                    if (lesson.isSubstituted) COLOR_AMBER_DIM else COLOR_SLIM_PILL_BORDER,
                                ),
                            )
                            .build(),
                    )
                    .setPadding(
                        ModifiersBuilders.Padding.Builder()
                            .setStart(DimensionBuilders.dp(12f))
                            .setEnd(DimensionBuilders.dp(12f))
                            .setTop(DimensionBuilders.dp(6f))
                            .setBottom(DimensionBuilders.dp(6f))
                            .build(),
                    )
                    .setClickable(openClickable)
                    .build(),
            )
            .addContent(row)
            .build()
    }

    private fun buildEmptyDaySlimPill(
        context: Context,
        status: TimetableStatus,
        openClickable: ModifiersBuilders.Clickable,
    ): LayoutElementBuilders.LayoutElement {
        val text = if (status.phase == TimetablePhase.NO_CLASSES_TODAY) {
            "Ma nincs tanóra"
        } else {
            "Nincs több óra ma"
        }
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
                                    .setRadius(DimensionBuilders.dp(18f))
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
                            .setTop(DimensionBuilders.dp(7f))
                            .setBottom(DimensionBuilders.dp(7f))
                            .build(),
                    )
                    .setClickable(openClickable)
                    .build(),
            )
            .addContent(
                Text.Builder(context, text)
                    .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                    .setColor(ColorBuilders.argb(COLOR_TEXT_SECONDARY))
                    .setMaxLines(1)
                    .build(),
            )
            .build()
    }

    private fun wrapInPureBlackOled(
        inner: LayoutElementBuilders.LayoutElement,
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
                    .build(),
            )
            .addContent(inner)
            .build()

    companion object {
        private const val RESOURCES_VERSION = "1"
        private const val FRESHNESS_INTERVAL_MS = 5L * 60_000L

        private const val RES_ICON_REFRESH = "icon_refresh"
        private const val RES_ICON_SCHOOL = "icon_school"

        private const val CLICK_ID_OPEN_APP = "open_app"
        private const val CLICK_ID_REFRESH = "refresh_tile"

        private const val COLOR_PURE_BLACK = 0xFF000000.toInt()
        private const val COLOR_HERO_PILL_BG = 0xFF141820.toInt()
        private const val COLOR_ACTIVE_HERO_BG = 0xFF0B192B.toInt()
        private const val COLOR_SLIM_PILL_BG = 0xFF101318.toInt()
        private const val COLOR_PILL_BORDER = 0xFF28303D.toInt()
        private const val COLOR_SLIM_PILL_BORDER = 0xFF1E242E.toInt()
        private const val COLOR_HERO_BADGE_MUTED = 0xFF27303F.toInt()

        private const val COLOR_ACCENT_BLUE = 0xFF4DA3FF.toInt()
        private const val COLOR_ACCENT_TEAL = 0xFF26D0A8.toInt()
        private const val COLOR_ACCENT_INDIGO = 0xFF7B9CFF.toInt()
        private const val COLOR_AMBER = 0xFFFFB74D.toInt()
        private const val COLOR_AMBER_DIM = 0x66FFB74D
        private const val COLOR_TEXT_PRIMARY = 0xFFFFFFFF.toInt()
        private const val COLOR_TEXT_SECONDARY = 0xFFA4B0C2.toInt()
    }
}

private fun TimetableStatusEvaluator.formatMinutesRemainingPill(remainingMs: Long): String =
    formatRemainingMinutesBadge(remainingMs)
