package hu.mlnlbrt.tintanaplo.wear.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import hu.mlnlbrt.tintanaplo.wear.R
import hu.mlnlbrt.tintanaplo.wear.auth.RemoteAuthStatus
import hu.mlnlbrt.tintanaplo.wear.ui.theme.TintaColors

@Composable
fun WearLoginScreen(
    authStatus: RemoteAuthStatus,
    noticeMessage: String?,
    onStartPhoneLogin: () -> Unit,
) {
    val isBusy = authStatus is RemoteAuthStatus.WaitingOnPhone ||
        authStatus is RemoteAuthStatus.SavingSession

    val subtitleText = when (authStatus) {
        is RemoteAuthStatus.WaitingOnPhone -> authStatus.message
        RemoteAuthStatus.SavingSession -> "Munkamenet szinkronizálása..."
        is RemoteAuthStatus.Error -> authStatus.message
        else -> noticeMessage?.takeIf { it.isNotBlank() } ?: "Nyisd meg a telefonod a csatlakozáshoz"
    }

    val subtitleColor = when {
        authStatus is RemoteAuthStatus.Error -> TintaColors.Crimson
        !noticeMessage.isNullOrBlank() && authStatus is RemoteAuthStatus.Idle -> TintaColors.Crimson
        authStatus is RemoteAuthStatus.WaitingOnPhone -> TintaColors.AccentBlue
        authStatus is RemoteAuthStatus.SavingSession -> TintaColors.AccentTeal
        else -> TintaColors.TextSecondary
    }

    Scaffold(
        timeText = { TimeText() },
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(TintaColors.PureBlack)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 24.dp),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Image(
                    painter = painterResource(id = R.drawable.ic_tinta_logo),
                    contentDescription = "Tinta Napló",
                    modifier = Modifier
                        .size(44.dp)
                        .clip(CircleShape),
                )

                Spacer(Modifier.height(10.dp))

                Chip(
                    onClick = onStartPhoneLogin,
                    enabled = !isBusy,
                    modifier = Modifier.fillMaxWidth(),
                    label = {
                        Text(
                            text = "Bejelentkezés telefonról",
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.ExtraBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    },
                    icon = {
                        if (isBusy) {
                            CircularProgressIndicator(
                                indicatorColor = TintaColors.PureBlack,
                                trackColor = TintaColors.PureBlack.copy(alpha = 0.25f),
                                strokeWidth = 2.dp,
                                modifier = Modifier.size(16.dp),
                            )
                        } else {
                            Icon(
                                painter = painterResource(id = R.drawable.ic_phone_android),
                                contentDescription = null,
                                tint = TintaColors.PureBlack,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                    },
                    colors = ChipDefaults.primaryChipColors(
                        backgroundColor = TintaColors.AccentBlue,
                        contentColor = TintaColors.PureBlack,
                    ),
                )

                Spacer(Modifier.height(8.dp))

                Text(
                    text = subtitleText,
                    fontSize = 10.5.sp,
                    color = subtitleColor,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 6.dp),
                )
            }
        }
    }
}
