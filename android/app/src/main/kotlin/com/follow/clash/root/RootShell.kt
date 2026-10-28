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

internal class RootShell(
    private val outputLimit: Int = 1024 * 1024,
) {
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
            } catch (error: Exception) {
                return ShellResult(127, "", "Executable unavailable: ${error.javaClass.simpleName}: ${error.message}")
                    .also { record(arguments, it) }
            }
        check(active.compareAndSet(null, process)) { "Concurrent shell invocation" }
        val readers =
            Executors.newFixedThreadPool(3) { runnable ->
                Thread(runnable, "root-tun-shell").apply { isDaemon = true }
            }
        val stdoutBuffer = ByteArrayOutputStream()
        val stderrBuffer = ByteArrayOutputStream()
        val stdout = readers.submit { capture(process.inputStream, stdoutBuffer) }
        val stderr = readers.submit { capture(process.errorStream, stderrBuffer) }
        val writer = readers.submit { runCatching { process.outputStream.use { it.write(input) } } }
        return try {
            val finished = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
            if (!finished) process.destroyForcibly()
            runCatching { stdout.get(300, TimeUnit.MILLISECONDS) }
            runCatching { stderr.get(300, TimeUnit.MILLISECONDS) }
            ShellResult(
                exitCode = if (finished) process.exitValue() else -1,
                stdout = synchronized(stdoutBuffer) { stdoutBuffer.toString("UTF-8") },
                stderr = synchronized(stderrBuffer) { stderrBuffer.toString("UTF-8") },
                timedOut = !finished,
            ).also { record(arguments, it) }
        } finally {
            active.compareAndSet(process, null)
            writer.cancel(true)
            readers.shutdownNow()
            runCatching { process.inputStream.close() }
            runCatching { process.errorStream.close() }
            runCatching { process.outputStream.close() }
        }
    }

    private fun capture(
        stream: InputStream,
        output: ByteArrayOutputStream,
    ) {
        stream.use {
            val buffer = ByteArray(8192)
            while (true) {
                val count = it.read(buffer)
                if (count < 0) break
                synchronized(output) {
                    val available = outputLimit - output.size()
                    if (available > 0) output.write(buffer, 0, minOf(available, count))
                }
            }
        }
    }

    companion object {
        private val observations = ArrayDeque<String>()

        @Synchronized
        private fun record(
            arguments: List<String>,
            result: ShellResult,
        ) {
            if (arguments.firstOrNull() != "su") return
            val operation =
                if (arguments ==
                    listOf("su", "-v")
                ) {
                    "su -v"
                } else if (arguments.lastOrNull() == "id -u") {
                    "su -c id -u"
                } else {
                    "su command"
                }
            observations.addLast(
                "${System.currentTimeMillis()} $operation exit=${result.exitCode} timeout=${result.timedOut} stderr=${result.stderr.take(
                    2048,
                )}",
            )
            if (observations.size > 64) observations.removeFirst()
        }

        @Synchronized
        fun diagnosticLog(): String = observations.joinToString("\n")

        fun quote(value: String): String {
            require('\u0000' !in value)
            return "'${value.replace("'", "'\\''")}'"
        }
    }
}
