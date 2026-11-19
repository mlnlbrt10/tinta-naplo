package hu.rekreta.rekreta_app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import hu.rekreta.rekreta_app.TintaLiveLessonResolver.LessonItem
import hu.rekreta.rekreta_app.TintaLiveLessonResolver.LiveLessonState
import hu.rekreta.rekreta_app.TintaLiveLessonResolver.LivePhase

/**
 * Populates [RemoteViews] for both the `2x1` compact and `2x2` expanded Tinta Napló
 * Home Screen Widgets from a single resolved [LiveLessonState].
 */
object TintaWidgetRenderer {
    private const val BREAK_ACCENT_ARGB = 0xFFF59E0B.toInt()
    private const val MUTED_RING_ARGB = 0xFF64748B.toInt()
    private const val PRIMARY_TEXT_ARGB = 0xFFF8FAFC.toInt()
    private const val SECONDARY_TEXT_ARGB = 0xFF94A3B8.toInt()

    fun hasAnyActiveWidgets(context: Context): Boolean {
        val mgr = AppWidgetManager.getInstance(context)
        val compact = mgr.getAppWidgetIds(
            ComponentName(context, TintaCompactWidgetProvider::class.java),
        )
        val expanded = mgr.getAppWidgetIds(
            ComponentName(context, TintaExpandedWidgetProvider::class.java),
        )
        return compact.isNotEmpty() || expanded.isNotEmpty()
    }

    fun updateAllWidgets(context: Context, state: LiveLessonState) {
        val mgr = AppWidgetManager.getInstance(context)
        val compactIds = mgr.getAppWidgetIds(
            ComponentName(context, TintaCompactWidgetProvider::class.java),
        )
        if (compactIds.isNotEmpty()) {
            updateCompactWidgets(context, mgr, compactIds, state)
        }
        val expandedIds = mgr.getAppWidgetIds(
            ComponentName(context, TintaExpandedWidgetProvider::class.java),
        )
        if (expandedIds.isNotEmpty()) {
            updateExpandedWidgets(context, mgr, expandedIds, state)
        }
    }

    fun updateCompactWidgets(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        state: LiveLessonState,
    ) {
        val views = buildCompactRemoteViews(context, state)
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    fun updateExpandedWidgets(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        state: LiveLessonState,
    ) {
        val views = buildExpandedRemoteViews(context, state)
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildCompactRemoteViews(context: Context, state: LiveLessonState): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.tinta_widget_2x1)
        bindHeroSection(context, views, state, ringSizeDp = 48f, compact = true)
        views.setOnClickPendingIntent(
            R.id.widget_root,
            TintaLiveLessonResolver.createOpenTimetablePendingIntent(context, 7301),
        )
        return views
    }

    private fun buildExpandedRemoteViews(context: Context, state: LiveLessonState): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.tinta_widget_2x2)
        bindHeroSection(context, views, state, ringSizeDp = 50f, compact = false)
        bindUpcomingSection(views, state)
        views.setOnClickPendingIntent(
            R.id.widget_root,
            TintaLiveLessonResolver.createOpenTimetablePendingIntent(context, 7302),
        )
        return views
    }

    private fun bindHeroSection(
        context: Context,
        views: RemoteViews,
        state: LiveLessonState,
        ringSizeDp: Float,
        compact: Boolean,
    ) {
        val current = state.currentLesson
        val badgeText: String
        val badgeColor: Int
        val subjectText: String
        val metaText: String
        val ringLabel: String
        val ringColor: Int
        val showArc: Boolean

        when (state.phase) {
            LivePhase.ACTIVE_LESSON -> {
                val item = current!!
                ringLabel = item.periodBadgeText
                ringColor = state.accentColorArgb
                showArc = true
                badgeColor = state.accentColorArgb
                val rem = state.remainingMinutes
                badgeText = when {
                    compact && item.substituted -> "FOLYAMATBAN • HELYETTESÍTÉS"
                    compact -> "FOLYAMATBAN • MÉG $rem PERC"
                    item.substituted -> "HELYETTESÍTÉS • MÉG $rem PERC"
                    else -> "${item.periodBadgeText} ÓRA • MÉG $rem PERC"
                }
                subjectText = item.subject
                val timeRange =
                    "${TintaLiveLessonResolver.formatHHmm(item.startMs)}–${TintaLiveLessonResolver.formatHHmm(item.endMs)}"
                metaText = listOfNotNull(
                    item.room.takeIf { it.isNotEmpty() },
                    if (compact) "Még $rem perc ($timeRange)" else timeRange,
                    if (!compact) item.teacher.takeIf { it.isNotEmpty() } else null,
                ).joinToString(" • ")
            }
            LivePhase.BREAK -> {
                val nxt = state.nextLesson ?: current!!
                ringLabel = nxt.periodBadgeText
                ringColor = BREAK_ACCENT_ARGB
                showArc = true
                badgeColor = BREAK_ACCENT_ARGB
                badgeText = "SZÜNET • MÉG ${state.remainingMinutes} PERC"
                subjectText = "Köv: ${nxt.subject}"
                val startTime = TintaLiveLessonResolver.formatHHmm(nxt.startMs)
                metaText = listOfNotNull(
                    nxt.room.takeIf { it.isNotEmpty() },
                    "Kezdés: $startTime",
                    if (!compact) nxt.teacher.takeIf { it.isNotEmpty() } else null,
                ).joinToString(" • ")
            }
            LivePhase.BEFORE_SCHOOL -> {
                val first = current!!
                ringLabel = first.periodBadgeText
                ringColor = state.accentColorArgb
                showArc = state.shouldTickPerMinute
                badgeColor = state.accentColorArgb
                val rem = state.remainingMinutes
                badgeText = if (state.shouldTickPerMinute) {
                    "KEZDÉS $rem PERC MÚLVA"
                } else {
                    "MA • ELSŐ ÓRA"
                }
                subjectText = first.subject
                val timeRange =
                    "${TintaLiveLessonResolver.formatHHmm(first.startMs)}–${TintaLiveLessonResolver.formatHHmm(first.endMs)}"
                metaText = listOfNotNull(
                    first.room.takeIf { it.isNotEmpty() },
                    timeRange,
                    if (!compact) first.teacher.takeIf { it.isNotEmpty() } else null,
                ).joinToString(" • ")
            }
            LivePhase.AFTER_SCHOOL -> {
                ringLabel = "✓"
                ringColor = state.accentColorArgb
                showArc = false
                badgeColor = SECONDARY_TEXT_ARGB
                badgeText = "TANÍTÁS VÉGE"
                subjectText = "Nincs több óra ma"
                val nxt = state.nextSchoolDayLessons.firstOrNull()
                metaText = if (nxt != null) {
                    val dayName = TintaLiveLessonResolver.formatDayHeaderLabel(nxt.startMs, state.nowMs)
                    val hhmm = TintaLiveLessonResolver.formatHHmm(nxt.startMs)
                    val roomStr = if (nxt.room.isNotEmpty()) " (${nxt.room})" else ""
                    "Köv: $dayName $hhmm • ${nxt.subject}$roomStr"
                } else {
                    "Nyisd meg az órarendet"
                }
            }
            LivePhase.NO_DATA -> {
                ringLabel = "•"
                ringColor = state.accentColorArgb
                showArc = false
                badgeColor = state.accentColorArgb
                badgeText = "TINTA NAPLÓ"
                subjectText = "Nincs szinkronizált órarend"
                metaText = "Nyisd meg az appot a frissítéshez"
            }
        }

        val ringBitmap = TintaWidgetRingRenderer.renderRingBitmap(
            context = context,
            centerLabel = ringLabel,
            remainingFraction = state.remainingFraction,
            ringColorArgb = ringColor,
            showActiveArc = showArc,
            sizeDp = ringSizeDp,
        )
        views.setImageViewBitmap(R.id.widget_ring_image, ringBitmap)
        views.setTextViewText(R.id.widget_status_badge, badgeText)
        views.setTextColor(R.id.widget_status_badge, badgeColor)
        views.setTextViewText(R.id.widget_subject, subjectText)
        views.setTextColor(R.id.widget_subject, PRIMARY_TEXT_ARGB)
        views.setTextViewText(R.id.widget_meta, metaText)
    }

    private fun bindUpcomingSection(views: RemoteViews, state: LiveLessonState) {
        val accentColor = state.accentColorArgb
        val upcomingList: List<LessonItem>
        val sectionTitle: String
        val emptyText: String

        when (state.phase) {
            LivePhase.ACTIVE_LESSON -> {
                upcomingList = state.upcomingToday
                if (upcomingList.isNotEmpty()) {
                    sectionTitle = "KÖVETKEZŐ ÓRÁK MA"
                    emptyText = ""
                } else if (state.nextSchoolDayLessons.isNotEmpty()) {
                    val nxt = state.nextSchoolDayLessons.first()
                    val dayName = TintaLiveLessonResolver.formatDayHeaderLabel(nxt.startMs, state.nowMs).uppercase()
                    sectionTitle = "KÖVETKEZŐ TANÍTÁSI NAP • $dayName"
                    emptyText = ""
                } else {
                    sectionTitle = "KÖVETKEZŐ ÓRÁK"
                    emptyText = "Ez az utolsó órád ma"
                }
            }
            LivePhase.BREAK,
            LivePhase.BEFORE_SCHOOL -> {
                val baseList = if (state.phase == LivePhase.BREAK) {
                    state.upcomingToday.drop(1)
                } else {
                    state.upcomingToday.drop(1)
                }
                upcomingList = if (baseList.isNotEmpty()) baseList else state.nextSchoolDayLessons
                sectionTitle = if (baseList.isNotEmpty()) {
                    "TOVÁBBI ÓRÁK MA"
                } else if (state.nextSchoolDayLessons.isNotEmpty()) {
                    val nxt = state.nextSchoolDayLessons.first()
                    val dayName = TintaLiveLessonResolver.formatDayHeaderLabel(nxt.startMs, state.nowMs).uppercase()
                    "KÖVETKEZŐ NAP • $dayName"
                } else {
                    "TOVÁBBI ÓRÁK"
                }
                emptyText = if (upcomingList.isEmpty()) "Nincs további óra ma" else ""
            }
            LivePhase.AFTER_SCHOOL -> {
                upcomingList = state.nextSchoolDayLessons
                if (upcomingList.isNotEmpty()) {
                    val dayName = TintaLiveLessonResolver.formatDayHeaderLabel(upcomingList.first().startMs, state.nowMs).uppercase()
                    sectionTitle = "KÖVETKEZŐ TANÍTÁSI NAP • $dayName"
                    emptyText = ""
                } else {
                    sectionTitle = "KÖVETKEZŐ ÓRÁK"
                    emptyText = "Nincs megjeleníthető további óra"
                }
            }
            LivePhase.NO_DATA -> {
                upcomingList = emptyList()
                sectionTitle = "ÓRAREND"
                emptyText = "Koppints az adatok betöltéséhez"
            }
        }

        val effectiveUpcoming = if (state.phase == LivePhase.ACTIVE_LESSON &&
            upcomingList.isEmpty() &&
            state.nextSchoolDayLessons.isNotEmpty()
        ) {
            state.nextSchoolDayLessons
        } else {
            upcomingList
        }

        views.setTextViewText(R.id.widget_upcoming_label, sectionTitle)

        val row1 = effectiveUpcoming.getOrNull(0)
        val row2 = effectiveUpcoming.getOrNull(1)

        if (row1 != null) {
            views.setViewVisibility(R.id.widget_next_row_1, View.VISIBLE)
            views.setTextViewText(R.id.widget_next1_period, row1.periodBadgeText)
            views.setTextColor(R.id.widget_next1_period, accentColor)
            views.setTextViewText(R.id.widget_next1_subject, row1.subject)
            views.setTextViewText(R.id.widget_next1_meta, formatRowMeta(row1))
        } else {
            views.setViewVisibility(R.id.widget_next_row_1, View.GONE)
        }

        if (row2 != null) {
            views.setViewVisibility(R.id.widget_next_row_2, View.VISIBLE)
            views.setTextViewText(R.id.widget_next2_period, row2.periodBadgeText)
            views.setTextColor(R.id.widget_next2_period, accentColor)
            views.setTextViewText(R.id.widget_next2_subject, row2.subject)
            views.setTextViewText(R.id.widget_next2_meta, formatRowMeta(row2))
        } else {
            views.setViewVisibility(R.id.widget_next_row_2, View.GONE)
        }

        if (row1 == null && row2 == null) {
            views.setViewVisibility(R.id.widget_empty_next, View.VISIBLE)
            views.setTextViewText(R.id.widget_empty_next, emptyText)
        } else {
            views.setViewVisibility(R.id.widget_empty_next, View.GONE)
        }
    }

    private fun formatRowMeta(lesson: LessonItem): String {
        val hhmm = TintaLiveLessonResolver.formatHHmm(lesson.startMs)
        return if (lesson.room.isNotEmpty()) "${lesson.room} • $hhmm" else hhmm
    }
}
