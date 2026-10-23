package com.follow.clash.root

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootDiagnosticsTest {
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
