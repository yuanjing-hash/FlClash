package com.follow.clash.root

import android.os.SystemClock
import java.io.File
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.SocketTimeoutException
import java.security.MessageDigest
import java.util.UUID

internal object RootRuntimeReport {
    const val MAX_AGE_MS = 8_000L

    fun fresh(
        raw: String?,
        nowMs: Long,
    ): String? {
        val bootMs =
            raw
                ?.lineSequence()
                ?.singleOrNull { it.startsWith("bootMs:") }
                ?.removePrefix("bootMs:")
                ?.toLongOrNull()
        return raw?.takeIf { bootMs != null && bootMs >= 0 && nowMs >= bootMs && nowMs - bootMs <= MAX_AGE_MS }
    }
}

internal class RootAuthorization {
    private var denials = 0
    private var nextProbeAt = 0L
    private var verdict = "unknown"

    fun probe(
        nowMs: Long,
        execute: () -> ShellResult,
    ): String {
        if (nowMs >= nextProbeAt) {
            nextProbeAt = nowMs + 5_000
            verdict = observe(execute())
        }
        return verdict
    }

    fun observe(result: ShellResult): String {
        val denied =
            !result.timedOut &&
                (
                    (
                        result.success && result.stdout
                            .trim()
                            .toIntOrNull()
                            ?.let { it != 0 } == true
                    ) ||
                        (
                            !result.success &&
                                Regex("permission denied|not allowed|access denied", RegexOption.IGNORE_CASE)
                                    .containsMatchIn(result.stderr)
                        )
                )
        denials = if (denied) denials + 1 else 0
        return when {
            result.success && result.stdout.trim() == "0" -> "granted"
            denials >= 2 -> "revoked"
            else -> "unknown"
        }
    }
}

internal class RootAuthorizationChannel(
    directory: File,
    private val elapsedRealtime: () -> Long = SystemClock::elapsedRealtime,
) : AutoCloseable {
    private val credentials = File(directory, "root-tun-auth-channel")
    private val previous = runCatching { credentials.readLines() }.getOrDefault(emptyList())

    @Volatile private var token =
        previous.getOrNull(1)?.takeIf { runCatching { UUID.fromString(it) }.isSuccess } ?: UUID.randomUUID().toString()
    private val server =
        ServerSocket().apply {
            reuseAddress = true
            val previousPort = previous.firstOrNull()?.toIntOrNull()?.takeIf { it in 1024..65535 } ?: 0
            runCatching { bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), previousPort), 2) }
                .getOrElse { bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), 0), 2) }
            soTimeout = 500
        }

    @Volatile var verdict: String = "unknown"

    @Volatile var cleanupCode: RootCode? = null
        private set

    @Volatile private var reportedRuntimeStatus: String? = null

    val runtimeStatus: String? get() = RootRuntimeReport.fresh(reportedRuntimeStatus, elapsedRealtime())

    val configuration: String get() = "${server.localPort} $token\n"

    private val thread =
        Thread({ serve() }, "root-tun-authorization").apply {
            isDaemon = true
        }

    init {
        saveCredentials()
        thread.start()
    }

    private fun saveCredentials() {
        val staged = File(credentials.parentFile, "root-tun-auth-channel.tmp")
        try {
            staged.writeText("${server.localPort}\n$token\n")
            check(staged.renameTo(credentials))
        } catch (error: Exception) {
            server.close()
            staged.delete()
            throw error
        }
    }

    @Synchronized
    fun beginSession(): String {
        token = UUID.randomUUID().toString()
        reset()
        saveCredentials()
        return configuration
    }

    fun reset() {
        cleanupCode = null
        reportedRuntimeStatus = null
        verdict = "granted"
    }

    private fun digest(
        nonce: String,
        value: String,
    ): String =
        MessageDigest
            .getInstance("SHA-256")
            .digest("$token:$nonce:$value".toByteArray())
            .joinToString("") { "%02x".format(it) }

    private fun serve() {
        while (!server.isClosed) {
            try {
                server.accept().use { socket ->
                    socket.soTimeout = 500
                    val line = StringBuilder()
                    val input = socket.getInputStream()
                    while (line.length < 1_024) {
                        val next = input.read()
                        if (next == -1 || next == 10) break
                        line.append(next.toChar())
                    }
                    val parts = line.toString().split(' ', limit = 4)
                    when {
                        parts.size in setOf(2, 4) && parts[0] == "probe" && validNonce(parts[1]) -> {
                            if (parts.size == 4) {
                                synchronized(this) {
                                    if (MessageDigest.isEqual(parts[2].toByteArray(), digest(parts[1], parts[3]).toByteArray())) {
                                        reportedRuntimeStatus = parts[3].replace('|', '\n')
                                    }
                                }
                            }
                            val current = verdict
                            socket.getOutputStream().write("$current ${digest(parts[1], current)}\n".toByteArray())
                        }
                        parts.size == 4 && parts[0] == "cleaned" && validNonce(parts[2]) -> {
                            synchronized(this) {
                                val code = runCatching { RootCode.valueOf(parts[1]) }.getOrNull()
                                if (code in setOf(RootCode.ROOT_PERMISSION_REVOKED, RootCode.AUTOSTART_ROOT_REVOKED) &&
                                    MessageDigest.isEqual(parts[3].toByteArray(), digest(parts[2], parts[1]).toByteArray())
                                ) {
                                    cleanupCode = code
                                }
                            }
                        }
                    }
                }
            } catch (_: SocketTimeoutException) {
                continue
            } catch (_: Exception) {
                if (server.isClosed) return
            }
        }
    }

    private fun validNonce(value: String): Boolean = runCatching { UUID.fromString(value).toString() == value }.getOrDefault(false)

    override fun close() {
        server.close()
        thread.join(1_000)
    }
}
