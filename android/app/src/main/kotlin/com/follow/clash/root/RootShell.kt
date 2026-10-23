package com.follow.clash.root

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

internal data class ShellResult(
    val exitCode: Int,
    val stdout: String,
    val stderr: String,
    val timedOut: Boolean = false,
) {
    val success: Boolean get() = exitCode == 0 && !timedOut
}

internal class RootShell {
    private val active = AtomicReference<Process?>()

    fun cancel() {
        active.getAndSet(null)?.destroyForcibly()
    }

    fun root(
        script: String,
        timeoutMs: Long = 2_000,
        input: ByteArray = byteArrayOf(),
    ): ShellResult = execute(listOf("su", "-c", script), timeoutMs, input)

    fun execute(
        arguments: List<String>,
        timeoutMs: Long = 2_000,
        input: ByteArray = byteArrayOf(),
    ): ShellResult {
        val process =
            try {
                ProcessBuilder(arguments).start()
            } catch (_: Exception) {
                return ShellResult(127, "", "Executable unavailable")
            }
        check(active.compareAndSet(null, process)) { "Concurrent shell invocation" }
        val readers =
            Executors.newFixedThreadPool(3) { runnable ->
                Thread(runnable, "root-tun-shell").apply { isDaemon = true }
            }
        val stdout = readers.submit<String> { capture(process.inputStream) }
        val stderr = readers.submit<String> { capture(process.errorStream) }
        val writer = readers.submit { runCatching { process.outputStream.use { it.write(input) } } }
        return try {
            val finished = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
            if (!finished) process.destroyForcibly()
            ShellResult(
                exitCode = if (finished) process.exitValue() else -1,
                stdout = runCatching { stdout.get(300, TimeUnit.MILLISECONDS) }.getOrDefault(""),
                stderr = runCatching { stderr.get(300, TimeUnit.MILLISECONDS) }.getOrDefault(""),
                timedOut = !finished,
            )
        } finally {
            active.compareAndSet(process, null)
            writer.cancel(true)
            readers.shutdownNow()
            runCatching { process.inputStream.close() }
            runCatching { process.errorStream.close() }
            runCatching { process.outputStream.close() }
        }
    }

    private fun capture(stream: InputStream): String =
        stream.use {
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = it.read(buffer)
                if (count < 0) break
                val available = MAX_OUTPUT - output.size()
                if (available > 0) output.write(buffer, 0, minOf(available, count))
            }
            output.toString("UTF-8")
        }

    companion object {
        private const val MAX_OUTPUT = 1024 * 1024

        fun quote(value: String): String {
            require('\u0000' !in value)
            return "'${value.replace("'", "'\\''")}'"
        }
    }
}
