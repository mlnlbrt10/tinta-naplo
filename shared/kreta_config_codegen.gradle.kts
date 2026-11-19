import groovy.json.JsonSlurper
import org.gradle.api.DefaultTask
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction
import java.io.File

abstract class GenerateKretaSharedConfigTask : DefaultTask() {
    @get:InputFile
    abstract val configFile: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun generate() {
        val jsonFile = configFile.get().asFile
        @Suppress("UNCHECKED_CAST")
        val root = JsonSlurper().parse(jsonFile) as Map<String, Any>
        @Suppress("UNCHECKED_CAST")
        val endpoints = root["endpoints"] as Map<String, Any>
        @Suppress("UNCHECKED_CAST")
        val wearRelay = root["wearRelay"] as Map<String, Any>

        fun escapeKotlin(value: Any?): String =
            (value?.toString() ?: "")
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("$", "\\$")

        val outFile = File(
            outputDir.get().asFile,
            "hu/mlnlbrt/tintanaplo/shared/KretaSharedConfig.kt",
        )
        outFile.parentFile.mkdirs()
        outFile.writeText(
            """
            |package hu.mlnlbrt.tintanaplo.shared
            |
            |/**
            | * Generated from shared/kreta_config.json so the Flutter phone app and
            | * native Wear OS companion module share one canonical KRÉTA configuration.
            | */
            |object KretaSharedConfig {
            |    const val IDP_BASE_URL: String = "${escapeKotlin(root["idpBaseUrl"])}"
            |    const val AUTHORIZE_ENDPOINT: String = "${escapeKotlin(root["authorizeEndpoint"])}"
            |    const val LOGIN_ENDPOINT: String = "${escapeKotlin(root["loginEndpoint"])}"
            |    const val TOKEN_ENDPOINT: String = "${escapeKotlin(root["tokenEndpoint"])}"
            |    const val INSTITUTE_SELECTOR_PATH: String = "${escapeKotlin(root["instituteSelectorPath"])}"
            |    const val CLIENT_ID_IOS: String = "${escapeKotlin(root["clientIdIos"])}"
            |    const val CLIENT_ID_ANDROID: String = "${escapeKotlin(root["clientIdAndroid"])}"
            |    const val REDIRECT_URI: String = "${escapeKotlin(root["redirectUri"])}"
            |    const val SCOPES: String = "${escapeKotlin(root["scopes"])}"
            |    const val USER_AGENT: String = "${escapeKotlin(root["userAgent"])}"
            |    const val API_KEY: String = "${escapeKotlin(root["apiKey"])}"
            |    const val KRETA_BASE_DOMAIN: String = "${escapeKotlin(root["kretaBaseDomain"])}"
            |
            |    const val ENDPOINT_TIMETABLE: String = "${escapeKotlin(endpoints["timetable"])}"
            |    const val ENDPOINT_GRADES: String = "${escapeKotlin(endpoints["grades"])}"
            |    const val ENDPOINT_HOMEWORKS: String = "${escapeKotlin(endpoints["homeworks"])}"
            |    const val ENDPOINT_TESTS: String = "${escapeKotlin(endpoints["tests"])}"
            |    const val ENDPOINT_STUDENT: String = "${escapeKotlin(endpoints["student"])}"
            |
            |    const val WEAR_DEEP_LINK_SCHEME: String = "${escapeKotlin(wearRelay["deepLinkScheme"])}"
            |    const val WEAR_DEEP_LINK_HOST: String = "${escapeKotlin(wearRelay["deepLinkHost"])}"
            |    const val WEAR_DEEP_LINK_URI: String = "${escapeKotlin(wearRelay["deepLinkUri"])}"
            |    const val WEAR_MSG_REQUEST_AUTH: String = "${escapeKotlin(wearRelay["messagePathRequestAuth"])}"
            |    const val WEAR_DATA_AUTH_SESSION: String = "${escapeKotlin(wearRelay["dataPathAuthSession"])}"
            |    const val WEAR_DATA_DASHBOARD_SYNC: String = "${escapeKotlin(wearRelay["dataPathDashboardSync"])}"
            |}
            |""".trimMargin(),
        )
    }
}

val generateKretaSharedConfig by tasks.registering(GenerateKretaSharedConfigTask::class) {
    configFile.set(rootProject.file("../shared/kreta_config.json"))
    outputDir.set(layout.buildDirectory.dir("generated/kreta/kotlin"))
}

extra["generateKretaSharedConfigTask"] = generateKretaSharedConfig
