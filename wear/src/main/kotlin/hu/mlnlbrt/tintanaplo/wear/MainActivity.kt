package hu.mlnlbrt.tintanaplo.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import hu.mlnlbrt.tintanaplo.wear.sync.KretaSyncScheduler
import hu.mlnlbrt.tintanaplo.wear.ui.TintaWearApp

class MainActivity : ComponentActivity() {
    private var resumeEpoch by mutableIntStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        runCatching {
            KretaSyncScheduler.ensurePeriodicSync(applicationContext)
        }
        setContent {
            TintaWearApp(resumeEpoch = resumeEpoch)
        }
    }

    override fun onResume() {
        super.onResume()
        resumeEpoch++
    }
}
