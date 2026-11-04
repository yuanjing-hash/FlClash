package com.follow.clash.service.modules

import android.app.Service
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkCapabilities.TRANSPORT_SATELLITE
import android.net.NetworkCapabilities.TRANSPORT_USB
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import androidx.core.content.getSystemService
import com.follow.clash.core.Core
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap

private data class NetworkInfo(
    @Volatile var losingUntilMillis: Long = 0,
    @Volatile var link: NetworkLink? = null,
    @Volatile var capabilities: NetworkCapabilities? = null,
) {
    val priorityPenalty: Int
        get() = if (losingUntilMillis > System.currentTimeMillis()) 10 else 0
}

class NetworkObserveModule(
    private val service: Service,
    onDnsCaptureChanged: ((String) -> Unit)? = null,
) : ServiceModule {
    private val networkInfos = ConcurrentHashMap<Network, NetworkInfo>()
    private val connectivity by lazy {
        service.getSystemService<ConnectivityManager>()
    }
    private val handler = Handler(networkObserveLooper)
    private val observation = NetworkObservation(Core::updateDNS, onDnsCaptureChanged, Core::resetNetwork)

    @Volatile private var defaultNetwork: Network? = null

    @Volatile private var observing = false
    private var registered = false
    private var defaultRegistered = false

    private val request =
        NetworkRequest
            .Builder()
            .apply {
                addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
            }.build()

    private val callback =
        object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                networkInfos.putIfAbsent(network, NetworkInfo())
                scheduleUpdateDns()
            }

            override fun onLosing(
                network: Network,
                maxMsToLive: Int,
            ) {
                val info = networkInfos[network] ?: return
                info.losingUntilMillis = System.currentTimeMillis() + maxMsToLive
                scheduleUpdateDns()
                if (maxMsToLive > 0) {
                    handler.postDelayed({
                        if (networkInfos.containsKey(network)) {
                            updateDns()
                        }
                    }, maxMsToLive.toLong() + 50)
                }
            }

            override fun onLost(network: Network) {
                networkInfos.remove(network)
                scheduleUpdateDns()
            }

            override fun onLinkPropertiesChanged(
                network: Network,
                linkProperties: LinkProperties,
            ) {
                networkInfos[network]?.link =
                    NetworkLink(
                        network.networkHandle,
                        linkProperties.interfaceName,
                        linkProperties.linkAddresses.map { it.toString() }.sorted(),
                        linkProperties.routes.map { it.toString() }.sorted(),
                        linkProperties.dnsServers.map { it.asSocketAddressText(DNS_PORT) }.distinct(),
                    )
                scheduleUpdateDns()
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) {
                networkInfos[network]?.capabilities = networkCapabilities
                scheduleUpdateDns()
            }
        }

    private val defaultCallback =
        object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                defaultNetwork = network
                scheduleUpdateDns()
            }

            override fun onLost(network: Network) {
                if (defaultNetwork == network) defaultNetwork = null
                scheduleUpdateDns()
            }
        }

    private val updateDnsTask = Runnable(::updateDns)

    // A switch arrives as a burst, and a network that just came up has no DNS
    // until its link properties follow; the Core flushes its cache per list.
    private fun scheduleUpdateDns() {
        if (!observing) return
        handler.removeCallbacks(updateDnsTask)
        handler.postDelayed(updateDnsTask, DNS_UPDATE_DELAY_MILLIS)
    }

    override fun start() {
        if (observing) return
        val manager = connectivity ?: return
        observing = true
        try {
            manager.registerNetworkCallback(request, callback)
            registered = true
            manager.registerDefaultNetworkCallback(defaultCallback)
            defaultRegistered = true
        } catch (error: Exception) {
            stop()
            throw error
        }
    }

    private fun networkPriority(entry: Map.Entry<Network, NetworkInfo>): Int {
        val capabilities = entry.value.capabilities
        return when {
            capabilities == null -> 100
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> 90
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 0
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 1
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                capabilities.hasTransport(TRANSPORT_USB) -> 2

            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> 3
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 4
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM &&
                capabilities.hasTransport(TRANSPORT_SATELLITE) -> 5

            else -> 20
        } + entry.value.priorityPenalty +
            if (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true) 0 else 30
    }

    @Synchronized
    private fun updateDns() {
        if (!observing) return
        val networks = networkInfos.entries.filter { it.value.link != null }.sortedBy(::networkPriority)
        val preferred = networks.firstOrNull { it.key == defaultNetwork } ?: networks.firstOrNull()
        observation.update(
            preferred?.value?.link,
            networks.flatMap {
                it.value.link
                    ?.dns
                    .orEmpty()
            },
        )
    }

    override fun stop() {
        observing = false
        handler.removeCallbacksAndMessages(null)
        try {
            if (registered) connectivity?.unregisterNetworkCallback(callback)
        } finally {
            registered = false
            try {
                if (defaultRegistered) connectivity?.unregisterNetworkCallback(defaultCallback)
            } finally {
                defaultRegistered = false
                networkInfos.clear()
                synchronized(this) { observation.clear() }
                defaultNetwork = null
            }
        }
    }
}

private const val DNS_PORT = 53
private const val DNS_UPDATE_DELAY_MILLIS = 200L

private val networkObserveLooper: Looper by lazy {
    HandlerThread("NetworkObserve").apply { start() }.looper
}

private fun InetAddress.asSocketAddressText(port: Int): String =
    when (this) {
        is Inet6Address -> "[$hostAddress]:$port"
        is Inet4Address -> "$hostAddress:$port"
        else -> error("Unsupported address type: ${javaClass.name}")
    }
