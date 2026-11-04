package com.follow.clash.root

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RootProxyStateTest {
    private val own = RootProxyState.Value("127.0.0.1", 7890, listOf("*.local", "localhost"), "")
    private val foreign = RootProxyState.Value("192.168.1.2", 8080, emptyList(), "")

    private class Backend(
        var cachedProxy: RootProxyState.Value?,
        var storedProxy: RootProxyState.Value?,
        var syncStored: Boolean = true,
        var ignoreRequest: Boolean = false,
        var ignoreStored: Boolean = false,
    ) : RootProxyState.Backend {
        var requests = 0
        var repairs = 0

        override fun cached(): RootProxyState.Value? = cachedProxy

        override fun stored(): RootProxyState.Value? = storedProxy

        override fun request(target: RootProxyState.Value?) {
            requests++
            if (ignoreRequest) return
            cachedProxy = target
            if (syncStored) storedProxy = target
        }

        override fun repairStored(target: RootProxyState.Value?) {
            repairs++
            if (!ignoreStored) storedProxy = target
        }
    }

    private fun restore(
        backend: Backend,
        previous: RootProxyState.Value? = null,
        lease: Boolean = true,
        legacy: RootProxyState.Value? = null,
    ) {
        val record = if (lease) RootProxyState.Lease(previous, own) else null
        RootProxyState.restore(backend, RootProxyState.plan(backend.cached(), backend.stored(), record, legacy))
    }

    @Test
    fun removesOwnedProxyAndPreservesThePriorUserProxy() {
        val backend = Backend(own, own)
        restore(backend, foreign)
        assertEquals(foreign, backend.cachedProxy)
        assertEquals(foreign, backend.storedProxy)
    }

    @Test
    fun cyclicPreviousSnapshotCannotRestoreOurOwnProxy() {
        val backend = Backend(own, own)
        restore(backend, own)
        assertNull(backend.cachedProxy)
        assertNull(backend.storedProxy)
    }

    @Test
    fun stoppedCoreWithNoJournalStillRepairsTheVerifiedLegacyLaunchProxy() {
        val backend = Backend(null, own)
        restore(backend, lease = false, legacy = own)
        assertEquals(1, backend.requests)
        assertEquals(0, backend.repairs)
        assertNull(backend.storedProxy)
    }

    @Test
    fun serviceNoOpDoesNotHidePersistedProxyResidue() {
        val backend = Backend(own, own, syncStored = false)
        restore(backend)
        assertEquals(1, backend.requests)
        assertEquals(1, backend.repairs)
        assertNull(backend.cachedProxy)
        assertNull(backend.storedProxy)
    }

    @Test
    fun aFailedServiceWriteDoesNotReportSuccessfulCleanup() {
        val backend = Backend(own, own, ignoreRequest = true)
        assertTrue(runCatching { restore(backend) }.isFailure)
        assertEquals(own, backend.cachedProxy)
        assertEquals(0, backend.repairs)
    }

    @Test
    fun aFailedSettingsWriteDoesNotReportSuccessfulCleanup() {
        val backend = Backend(null, own, syncStored = false, ignoreStored = true)
        assertTrue(runCatching { restore(backend) }.isFailure)
        assertEquals(own, backend.storedProxy)
    }

    @Test
    fun foreignProxyIsNeverCleared() {
        val backend = Backend(foreign, foreign)
        restore(backend)
        assertEquals(0, backend.requests)
        assertEquals(0, backend.repairs)
        assertEquals(foreign, backend.cachedProxy)
    }

    @Test
    fun aMissingOwnershipRecordDoesNotClaimAProxyFromItsPort() {
        val backend = Backend(own, own)
        restore(backend, lease = false)
        assertEquals(0, backend.requests)
        assertEquals(0, backend.repairs)
    }

    @Test
    fun keepsAForeignServiceProxyWhileRepairingOurStaleSettings() {
        val backend = Backend(foreign, own)
        restore(backend)
        assertEquals(foreign, backend.cachedProxy)
        assertEquals(foreign, backend.storedProxy)
        assertEquals(1, backend.requests)
    }

    @Test
    fun keepsForeignSettingsWhileRemovingOurStaleServiceProxy() {
        val backend = Backend(own, foreign)
        restore(backend)
        assertEquals(foreign, backend.cachedProxy)
        assertEquals(foreign, backend.storedProxy)
    }

    @Test
    fun concurrentForeignOwnershipChangePreventsAnyMutation() {
        val backend = Backend(own, own)
        val plan = RootProxyState.plan(own, own, RootProxyState.Lease(null, own), null)
        backend.cachedProxy = foreign
        backend.storedProxy = foreign
        RootProxyState.restore(backend, plan)
        assertEquals(0, backend.requests)
        assertEquals(0, backend.repairs)
    }

    @Test
    fun preservesAForeignServiceProxyInstalledAfterPlanning() {
        val backend = Backend(own, own)
        val plan = RootProxyState.plan(own, own, RootProxyState.Lease(null, own), null)
        backend.cachedProxy = foreign
        RootProxyState.restore(backend, plan)
        assertEquals(foreign, backend.cachedProxy)
        assertEquals(foreign, backend.storedProxy)
    }

    @Test
    fun preservesForeignSettingsInstalledAfterPlanning() {
        val backend = Backend(own, own)
        val plan = RootProxyState.plan(own, own, RootProxyState.Lease(null, own), null)
        backend.storedProxy = foreign
        RootProxyState.restore(backend, plan)
        assertEquals(foreign, backend.cachedProxy)
        assertEquals(foreign, backend.storedProxy)
    }

    @Test
    fun canonicalizesFrameworkEmptyValuesAndExclusionOrder() {
        assertNull(RootProxyState.value("", 0, emptyList(), ""))
        assertEquals(own, RootProxyState.value("127.0.0.1", 7890, listOf("LOCALHOST", "*.local", "localhost"), ""))
        assertFalse(RootProxyState.plan(null, null, null, null).owned)
    }

    @Test
    fun aLegacyServiceNoOpStillRepairsSettingsWhenItsCacheIsAlreadyEmpty() {
        val backend = Backend(null, own, syncStored = false)
        restore(backend, lease = false, legacy = own)
        assertEquals(1, backend.requests)
        assertEquals(1, backend.repairs)
        assertNull(backend.storedProxy)
    }

    @Test
    fun restoresAnExistingPacProxy() {
        val pac = RootProxyState.Value("", 0, emptyList(), "https://proxy.example/proxy.pac")
        val backend = Backend(own, own)
        restore(backend, pac)
        assertEquals(pac, backend.cachedProxy)
        assertEquals(pac, backend.storedProxy)
    }
}
