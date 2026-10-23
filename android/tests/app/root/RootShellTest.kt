package com.follow.clash.root

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RootShellTest {
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
        assertTrue(shell.execute(listOf("sh", "-c", "sleep 5"), 50).timedOut)
        assertTrue((System.nanoTime() - start) / 1_000_000 < 2_000)
        assertTrue(shell.execute(listOf("sh", "-c", "yes x | head -c 2000000")).stdout.length <= 1048576)
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
