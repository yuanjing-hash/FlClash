package com.follow.clash.root

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class RootShellTest {
    @Test
    fun busyboxBootstrapPreservesArgumentsAndStdin() {
        val directory = Files.createTempDirectory("root shell ").toFile()
        try {
            val busybox = File(directory, "busybox")
            busybox.writeText("#!/bin/sh\n[ \"\$1\" = sh ] && [ \"\$ASH_STANDALONE\" = 1 ] || exit 64\nshift\nexec sh \"\$@\"\n")
            val shell = RootShell()
            val path = busybox.path.replace('\\', '/')
            assertTrue(shell.execute(listOf("sh", "-c", "chmod +x ${RootShell.quote(path)}")).success)
            val payload = "literal ' \$(exit 9)\nsecond line"
            val command = RootShell.rootCommand("cat; printf %s ${RootShell.quote(payload)}", listOf("$path.missing", path))
            val bootstrap = File(directory, "bootstrap.sh").apply { writeText(command) }
            val result = shell.execute(listOf("sh", bootstrap.path.replace('\\', '/')), input = "stdin\n".toByteArray())
            assertTrue(result.stderr, result.success)
            assertEquals("stdin\n$payload", result.stdout)
            val fallback = RootShell.rootCommand("printf fallback", listOf("$path.missing")).replace("/system/bin/sh", "sh")
            bootstrap.writeText(fallback)
            assertEquals("fallback", shell.execute(listOf("sh", bootstrap.path.replace('\\', '/'))).stdout)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun failedCommandsKeepBoundedRedactedOutputAndTimeoutEvidence() {
        val error =
            runCatching {
                ShellResult(1, "Parse config error: invalid rule", "secret: private-value\n").requireSuccess("Validate configuration")
            }.exceptionOrNull()
        assertTrue(error is IllegalStateException)
        assertTrue(error!!.message!!.contains("Validate configuration failed: exit=1 timeout=false"))
        assertTrue(error.message!!.contains("invalid rule"))
        assertFalse(error.message!!.contains("private-value"))
        val timedOut = runCatching { ShellResult(0, "x".repeat(20_000), "", true).requireSuccess("Copy asset") }.exceptionOrNull()
        assertTrue(timedOut!!.message!!.contains("timeout=true"))
        assertTrue(timedOut.message!!.length < 8_300)
        ShellResult(0, "", "").requireSuccess("Completed command")
    }

    @Test
    fun quotesMetacharactersAsData() {
        val payload = "a'b;$(exit 9)\nsecond line"
        val result = RootShell().execute(listOf("sh", "-c", "printf %s ${RootShell.quote(payload)}"))
        assertTrue(result.success)
        assertEquals(payload, result.stdout)
    }

    @Test
    fun capturesFailureAndBothStreams() {
        val result = RootShell().execute(listOf("sh", "-c", "echo output; echo error >&2; exit 7"))
        assertEquals(7, result.exitCode)
        assertEquals("output\n", result.stdout)
        assertEquals("error\n", result.stderr)
    }

    @Test
    fun boundsOutputAndTimesOutWithoutWaitingForInheritedPipes() {
        val shell = RootShell()
        val start = System.nanoTime()
        val interrupted = shell.execute(listOf("sh", "-c", "printf critical-evidence; sleep 5"), 50)
        assertTrue(interrupted.timedOut)
        assertEquals("critical-evidence", interrupted.stdout)
        assertTrue((System.nanoTime() - start) / 1_000_000 < 2_000)
        assertTrue(shell.execute(listOf("sh", "-c", "yes x | head -c 2000000")).stdout.length <= 1048576)
        assertEquals(2_000_000, RootShell(4 * 1024 * 1024).execute(listOf("sh", "-c", "yes x | head -c 2000000")).stdout.length)
    }

    @Test
    fun snapshotIncludesExplicitNullsAndExactlyEightStates() {
        val snapshot = RootSnapshot().toMap()
        assertEquals(8, TunState.entries.size)
        assertEquals(27, RootCode.entries.size)
        assertTrue(snapshot.containsKey("lastErrorAt"))
        assertNull(snapshot["lastErrorAt"])
        assertEquals(false, snapshot["stale"])
    }
}
