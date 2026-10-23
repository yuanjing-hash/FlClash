package com.follow.clash.root

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.file.Files
import java.security.MessageDigest
import java.util.UUID

class RootAuthorizationTest {
    @Test
    fun requiresTwoExplicitDenialsAndResetsOnUnknownOrTimeout() {
        val authorization = RootAuthorization()
        val denied = ShellResult(1, "", "Permission denied")
        assertEquals("unknown", authorization.observe(denied))
        assertEquals("unknown", authorization.observe(ShellResult(-1, "", "Permission denied", timedOut = true)))
        assertEquals("unknown", authorization.observe(denied))
        assertEquals("unknown", authorization.observe(ShellResult(127, "", "Executable unavailable")))
        assertEquals("unknown", authorization.observe(denied))
        assertEquals("revoked", authorization.observe(denied))
        assertEquals("granted", authorization.observe(ShellResult(0, "0\n", "")))
        assertEquals("unknown", authorization.observe(denied))
    }

    @Test
    fun channelAuthenticatesCleanupAndSurvivesAppRecreation() {
        val directory = Files.createTempDirectory("root-authorization").toFile()
        try {
            val configuration =
                RootAuthorizationChannel(directory).use { channel ->
                    val parts = channel.configuration.trim().split(' ')
                    val nonce = UUID.randomUUID().toString()
                    channel.verdict = "revoked"
                    val response = exchange(parts[0].toInt(), "probe $nonce")
                    assertEquals("revoked ${digest(parts[1], nonce, "revoked")}", response)
                    exchange(parts[0].toInt(), "cleaned ROOT_PERMISSION_REVOKED $nonce bad-signature")
                    assertNull(channel.cleanupCode)
                    val signature = digest(parts[1], nonce, "ROOT_PERMISSION_REVOKED")
                    exchange(parts[0].toInt(), "cleaned ROOT_PERMISSION_REVOKED $nonce $signature")
                    assertEquals(RootCode.ROOT_PERMISSION_REVOKED, channel.cleanupCode)
                    val nextSession = channel.beginSession()
                    assertNull(channel.cleanupCode)
                    exchange(parts[0].toInt(), "cleaned ROOT_PERMISSION_REVOKED $nonce $signature")
                    assertNull(channel.cleanupCode)
                    assertEquals(nextSession, channel.configuration)
                    channel.configuration
                }
            RootAuthorizationChannel(directory).use { reopened ->
                assertEquals(configuration, reopened.configuration)
            }
        } finally {
            directory.deleteRecursively()
        }
    }

    private fun exchange(
        port: Int,
        message: String,
    ): String? =
        Socket().use { socket ->
            socket.connect(InetSocketAddress("127.0.0.1", port), 500)
            socket.soTimeout = 1_000
            socket.getOutputStream().write("$message\n".toByteArray())
            socket.getInputStream().bufferedReader().readLine()
        }

    private fun digest(
        token: String,
        nonce: String,
        value: String,
    ): String =
        MessageDigest
            .getInstance("SHA-256")
            .digest("$token:$nonce:$value".toByteArray())
            .joinToString("") { "%02x".format(it) }
}
