package hu.mlnlbrt.tintanaplo.wear.sync

import android.content.Context
import androidx.wear.tiles.TileService
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import hu.mlnlbrt.tintanaplo.wear.auth.WearRemoteAuthManager
import hu.mlnlbrt.tintanaplo.wear.data.InvalidGrantException
import hu.mlnlbrt.tintanaplo.wear.data.KretaDateParser
import hu.mlnlbrt.tintanaplo.wear.data.KretaWearApiClient
import hu.mlnlbrt.tintanaplo.wear.data.Lesson
import hu.mlnlbrt.tintanaplo.wear.data.SecureTokenStorage
import hu.mlnlbrt.tintanaplo.wear.data.TokenExpiredException
import hu.mlnlbrt.tintanaplo.wear.tile.TintaTimetableTileService
import java.util.concurrent.TimeUnit

class KretaSyncWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val tokenStore = runCatching { SecureTokenStorage(applicationContext) }.getOrNull()
            ?: return Result.success()
        val session = runCatching { tokenStore.loadSession() }.getOrNull()
        if (session == null) {
            requestTileUpdate(applicationContext)
            return Result.success()
        }

        val apiClient = KretaWearApiClient(
            tokenStore = tokenStore,
            onSessionRefreshed = { refreshed ->
                WearRemoteAuthManager.getInstance(applicationContext)
                    .pushRefreshedSessionToPhone(refreshed)
            },
        )
        return try {
            val synced = apiClient.syncAll(session)
            KretaSyncScheduler.scheduleNextTransitionUpdate(applicationContext, synced.lessons)
            requestTileUpdate(applicationContext)
            Result.success()
        } catch (_: TokenExpiredException) {
            requestTileUpdate(applicationContext)
            Result.failure()
        } catch (_: InvalidGrantException) {
            requestTileUpdate(applicationContext)
            Result.failure()
        } catch (_: Throwable) {
            requestTileUpdate(applicationContext)
            if (runAttemptCount < 3) Result.retry() else Result.failure()
        }
    }

    companion object {
        fun requestTileUpdate(context: Context) {
            runCatching {
                TileService.getUpdater(context.applicationContext)
                    .requestUpdate(TintaTimetableTileService::class.java)
            }
        }
    }
}

class TileTransitionWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {

    override fun doWork(): Result {
        runCatching {
            val tokenStore = SecureTokenStorage(applicationContext)
            val session = tokenStore.loadSession()
            if (session != null) {
                val accountKey = SecureTokenStorage.accountKeyFor(session)
                val cached = tokenStore.loadWearDataCache(
                    accountKey,
                    KretaDateParser.dateKeyFor(),
                )
                if (cached != null) {
                    KretaSyncScheduler.scheduleNextTransitionUpdate(applicationContext, cached.lessons)
                }
            }
        }
        KretaSyncWorker.requestTileUpdate(applicationContext)
        return Result.success()
    }
}

object KretaSyncScheduler {
    private const val PERIODIC_SYNC_WORK = "tinta_wear_periodic_sync"
    private const val IMMEDIATE_SYNC_WORK = "tinta_wear_immediate_sync"
    private const val TRANSITION_TILE_WORK = "tinta_wear_tile_transition"

    fun ensurePeriodicSync(context: Context) {
        runCatching {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
            val request = PeriodicWorkRequestBuilder<KretaSyncWorker>(30, TimeUnit.MINUTES)
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(context.applicationContext).enqueueUniquePeriodicWork(
                PERIODIC_SYNC_WORK,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }
    }

    fun triggerImmediateSync(context: Context) {
        runCatching {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
            val request = OneTimeWorkRequestBuilder<KretaSyncWorker>()
                .setConstraints(constraints)
                .build()
            WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
                IMMEDIATE_SYNC_WORK,
                ExistingWorkPolicy.REPLACE,
                request,
            )
        }
    }

    fun scheduleNextTransitionUpdate(
        context: Context,
        lessons: List<Lesson>,
        nowMs: Long = System.currentTimeMillis(),
    ) {
        runCatching {
            val nextBoundaryMs = lessons
                .filter { !it.isCancelled }
                .flatMap { listOf(it.startEpochMs, it.endEpochMs) }
                .filter { it > nowMs + 1_000L }
                .minOrNull() ?: return@runCatching

            val delayMs = (nextBoundaryMs - nowMs + 1_500L).coerceAtLeast(2_000L)
            val request = OneTimeWorkRequestBuilder<TileTransitionWorker>()
                .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
                .build()
            WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
                TRANSITION_TILE_WORK,
                ExistingWorkPolicy.REPLACE,
                request,
            )
        }
    }
}
