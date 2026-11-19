package hu.mlnlbrt.tintanaplo.wear.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.MaterialTheme

object TintaColors {
    val PureBlack = Color(0xFF000000)
    val SmokedSurface = Color(0xFF141820)
    val SmokedSurfaceAlt = Color(0xFF101318)
    val ActiveHeroSurface = Color(0xFF0B192B)
    val IndigoHeroSurface = Color(0xFF12162A)
    val PillBorder = Color(0xFF28303D)
    val SubtleBorder = Color(0xFF1E242E)
    val TrackBorderMuted = Color(0x6B28303D)
    val LoaderTrack = Color(0x6628303D)

    val AccentBlue = Color(0xFF4DA3FF)
    val AccentBlueGlowOuter = Color(0x1F4DA3FF)
    val AccentBlueGlowMid = Color(0x3D4DA3FF)
    val AccentTeal = Color(0xFF26D0A8)
    val AccentTealSoft = Color(0xFF0D2620)
    val AccentTealBorder = Color(0x7326D0A8)
    val AccentIndigo = Color(0xFF7B9CFF)
    val AccentIndigoBorder = Color(0x8C7B9CFF)
    val AccentIndigoSoft = Color(0xFF151A30)

    val Amber = Color(0xFFFFB74D)
    val AmberSoft = Color(0xFF261D0D)
    val AmberBorder = Color(0x8CFFB74D)

    val Coral = Color(0xFFFF8A65)
    val CoralSoft = Color(0xFF291811)
    val CoralBorder = Color(0x73FF8A65)

    val Crimson = Color(0xFFFF6B6B)
    val CrimsonSoft = Color(0xFF2B1212)
    val CrimsonBorder = Color(0x73FF6B6B)

    val AccentBlueBorder = Color(0x734DA3FF)

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
