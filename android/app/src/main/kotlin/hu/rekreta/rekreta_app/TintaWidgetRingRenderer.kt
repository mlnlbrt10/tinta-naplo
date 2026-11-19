package hu.rekreta.rekreta_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.util.TypedValue
import kotlin.math.roundToInt

/**
 * Renders an anti-aliased high-DPI circular progress ring + bold tabular center
 * label (`1.`, `4.`, `•`, `✓`) for Home Screen Widgets, matching Tinta Napló's
 * in-app [PeriodCountdownBadge] styling.
 */
object TintaWidgetRingRenderer {
    fun renderRingBitmap(
        context: Context,
        centerLabel: String,
        remainingFraction: Float,
        ringColorArgb: Int,
        showActiveArc: Boolean,
        sizeDp: Float = 50f,
    ): Bitmap {
        val dm = context.resources.displayMetrics
        val sizePx = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, sizeDp, dm)
            .roundToInt()
            .coerceIn(96, 220)
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val strokePx = sizePx * 0.088f
        val inset = strokePx * 0.9f
        val ringRect = RectF(inset, inset, sizePx - inset, sizePx - inset)
        val cx = sizePx * 0.5f
        val cy = sizePx * 0.5f

        // Subtle inner OLED circle fill + hairline accent ring
        val innerRadius = (sizePx * 0.5f) - strokePx * 1.45f
        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = 0xFF141822.toInt()
        }
        canvas.drawCircle(cx, cy, innerRadius, fillPaint)

        // Muted full track ring
        val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = strokePx
            strokeCap = Paint.Cap.ROUND
            color = withAlpha(ringColorArgb, 42)
        }
        canvas.drawOval(ringRect, trackPaint)

        if (showActiveArc) {
            val clamped = remainingFraction.coerceIn(0f, 1f)
            if (clamped > 0.004f) {
                // Soft ambient glow underneath active arc
                val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = strokePx * 1.75f
                    strokeCap = Paint.Cap.ROUND
                    color = withAlpha(ringColorArgb, 60)
                }
                val sweep = 360f * clamped
                canvas.drawArc(ringRect, -90f, sweep, false, glowPaint)

                // Crisp foreground countdown arc
                val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = strokePx
                    strokeCap = Paint.Cap.ROUND
                    color = ringColorArgb
                }
                canvas.drawArc(ringRect, -90f, sweep, false, arcPaint)
            }
        }

        // Bold tabular period number centered visually inside the ring
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFF8FAFC.toInt()
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            fontFeatureSettings = "tnum"
            textSize = when {
                centerLabel.length >= 3 -> sizePx * 0.30f
                else -> sizePx * 0.36f
            }
        }
        val fontMetrics = textPaint.fontMetrics
        val baselineY = cy - (fontMetrics.ascent + fontMetrics.descent) * 0.5f
        canvas.drawText(centerLabel, cx, baselineY, textPaint)

        return bitmap
    }

    private fun withAlpha(argb: Int, alpha: Int): Int =
        Color.argb(
            alpha.coerceIn(0, 255),
            Color.red(argb),
            Color.green(argb),
            Color.blue(argb),
        )
}
