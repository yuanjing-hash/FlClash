package com.follow.clash.core

interface CoreBackend {
    fun invokeMethod(
        data: String,
        callback: (ByteArray?) -> Unit,
    )

    fun updateEventListener(callback: ((ByteArray) -> Unit)?)

    fun restoreState(calls: List<String>)

    fun quickSetup(
        initParams: String,
        setupParams: String,
        callback: (String?) -> Unit,
    )

    fun forceGC()

    fun updateDNS(dns: String)

    fun updateDnsCapture(dns: String)

    fun resetNetwork()

    fun startListener()

    fun stopListener()

    fun getTraffic(onlyStatisticsProxy: Boolean): String

    fun getTotalTraffic(onlyStatisticsProxy: Boolean): String

    fun close()
}
