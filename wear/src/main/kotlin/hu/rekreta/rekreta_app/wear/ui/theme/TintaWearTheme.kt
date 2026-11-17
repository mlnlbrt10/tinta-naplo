package hu.rekreta.rekreta_app.wear.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.MaterialTheme

object TintaColors {
    val PureBlack = Color(0xFF000000)
    val SmokedSurface = Color(0xFF141820)
    val SmokedSurfaceAlt = Color(0xFF101318)
    val ActiveHeroSurface = Color(0xFF0B192B)
    val PillBorder = Color(0xFF28303D)
    val SubtleBorder = Color(0xFF1E242E)

    val AccentBlue = Color(0xFF4DA3FF)
    val AccentTeal = Color(0xFF26D0A8)
    val AccentIndigo = Color(0xFF7B9CFF)
    val Amber = Color(0xFFFFB74D)
    val Crimson = Color(0xFFFF6B6B)
    val CrimsonSoft = Color(0xFF2B1212)
    val AmberSoft = Color(0xFF261D0D)

    val TextPrimary = Color(0xFFFFFFFF)
    val TextSecondary = Color(0xFFA4B0C2)
    val TextMuted = Color(0xFF6B778A)
}

private val TintaWearColors = Colors(
    primary = TintaColors.AccentBlue,
    primaryVariant = TintaColors.AccentIndigo,
    secondary = TintaColors.AccentTeal,
    secondaryVariant = TintaColors.AccentTeal,
    background = TintaColors.PureBlack,
    surface = TintaColors.SmokedSurface,
    error = TintaColors.Crimson,
    onPrimary = TintaColors.PureBlack,
    onSecondary = TintaColors.PureBlack,
    onBackground = TintaColors.TextPrimary,
    onSurface = TintaColors.TextPrimary,
    onSurfaceVariant = TintaColors.TextSecondary,
    onError = TintaColors.PureBlack,
)

@Composable
fun TintaWearTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colors = TintaWearColors,
        content = content,
    )
}
