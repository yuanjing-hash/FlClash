package com.follow.clash.root

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.zip.ZipFile

class RootDiagnosticsTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test
    fun exportReturnsPrivateZipPathExactByteCountAndMimeType() {
        val cache = temporary.newFolder("cache")
        File(cache, "root-tun-restore-diff.txt").writeText("retained rule difference")
        val evidence = RootDiagnosticEvidence("PAGE_SIZE=16384", "network evidence", null)
        val archive = RootDiagnostics.archive(cache, "Android 17\n${evidence.device}", RootSnapshot(), emptyMap(), evidence)
        val result = RootDiagnostics.result(archive)
        assertEquals(setOf("path", "sizeBytes", "mimeType"), result.keys)
        assertEquals(archive.absolutePath, result["path"])
        assertTrue(archive.canonicalPath.startsWith(cache.canonicalPath + File.separator))
        assertEquals(archive.length(), result["sizeBytes"])
        assertTrue((result["sizeBytes"] as Long) > 0)
        assertEquals("application/zip", result["mimeType"])
        ZipFile(archive).use { zip ->
            assertTrue(
                zip
                    .getInputStream(zip.getEntry("device.txt"))
                    .reader()
                    .readText()
                    .contains("PAGE_SIZE=16384"),
            )
            assertEquals("retained rule difference", zip.getInputStream(zip.getEntry("logs/restore-diff.txt")).reader().readText())
        }
    }

    @Test
    fun collectorSectionsKeepDeviceAndLiveRestorationEvidenceInZip() {
        val output =
            "[FLCLASH:device:BEGIN]\nuname evidence\n[FLCLASH:device:END]\n" +
                "[FLCLASH:restore-diff:BEGIN]\nlive difference\n[FLCLASH:restore-diff:END]\n" +
                "[FLCLASH:network:BEGIN]\nnetwork evidence\n[FLCLASH:network:END]\n"
        val evidence = RootDiagnosticEvidence.parse(ShellResult(0, output, ""))
        assertTrue(evidence.device.contains("uname evidence"))
        assertTrue(evidence.network.contains("network evidence"))
        assertEquals("live difference", evidence.restoreDiff)
        val archive = RootDiagnostics.archive(temporary.newFolder(), evidence.device, RootSnapshot(), emptyMap(), evidence)
        ZipFile(archive).use { zip ->
            assertEquals("live difference", zip.getInputStream(zip.getEntry("logs/restore-diff.txt")).reader().readText())
        }
    }

    @Test
    fun requestIdMustBeAUuid() {
        val requestId = "7fb480b6-08a9-4113-8505-912671462d51"
        assertEquals(requestId, requireRequestId(requestId))
        listOf(null, "", "invalid", 1).forEach { assertTrue(runCatching { requireRequestId(it) }.isFailure) }
    }

    @Test
    fun removesAuthorizationQuotedSecretsAndSubscriptionQueries() {
        val scrubbed =
            RootDiagnostics.redact(
                "Authorization: Bearer sensitive\npassword: 'multiple words'\nhttps://host/profile?access=opaque\ntrojan://credentials@host:443",
            )
        listOf("sensitive", "multiple", "words", "opaque", "credentials").forEach { assertFalse(scrubbed.contains(it)) }
        assertTrue(scrubbed.contains("[redacted]"))
    }
}
