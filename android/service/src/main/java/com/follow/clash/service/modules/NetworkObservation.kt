package com.follow.clash.service.modules

internal data class NetworkLink(
    val handle: Long,
    val interfaceName: String?,
    val addresses: List<String>,
    val routes: List<String>,
    val dns: List<String>,
)

internal class NetworkObservation(
    private val updateDns: (String) -> Unit,
    private val updateCapture: ((String) -> Unit)?,
    private val resetNetwork: () -> Unit,
) {
    private var current: NetworkLink? = null
    private var dns = emptyList<String>()
    private var capture = emptyList<String>()

    fun update(
        preferred: NetworkLink?,
        captureDns: List<String>,
    ) {
        if (current != null && current != preferred) resetNetwork()
        current = preferred
        val nextDns = preferred?.dns.orEmpty()
        if (nextDns != dns) {
            dns = nextDns
            updateDns(nextDns.joinToString(","))
        }
        val nextCapture = captureDns.distinct().sorted()
        if (updateCapture != null && nextCapture != capture) {
            capture = nextCapture
            updateCapture(nextCapture.joinToString(","))
        }
    }

    fun clear() {
        current = null
        dns = emptyList()
        capture = emptyList()
    }
}
