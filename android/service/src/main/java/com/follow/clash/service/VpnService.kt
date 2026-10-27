package com.follow.clash.service

import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.ProxyInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.content.getSystemService
import com.follow.clash.common.GlobalState
import com.follow.clash.common.R as CommonR
import com.follow.clash.core.Core
import com.follow.clash.service.models.CIDR
import com.follow.clash.service.models.VpnOptions
import com.follow.clash.service.models.appRules
import com.follow.clash.service.models.getIpv4RouteAddress
import com.follow.clash.service.models.getIpv6RouteAddress
import com.follow.clash.service.models.ownsTunnel
import com.follow.clash.service.models.toCIDR
import com.follow.clash.service.modules.ServiceModules
import org.json.JSONObject
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap
import android.net.VpnService as SystemVpnService

class VpnService : SystemVpnService(), ManagedService {
    private val modules = ServiceModules(this)
    private val binder = LocalBinder()
    private val tunLock = Any()
    private var tunRunning = false
    private var openVpn: OpenVpn? = null

    override fun onDestroy() {
        try {
            cleanup()
        } finally {
            super.onDestroy()
        }
    }

    private val connectivity by lazy {
        getSystemService<ConnectivityManager>()
    }
    private val uidPackageNameMap = ConcurrentHashMap<Int, String>()

    private fun resolveUid(
        protocol: Int,
        source: InetSocketAddress,
        target: InetSocketAddress,
    ): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return -1
        }
        return connectivity?.getConnectionOwnerUid(protocol, source, target) ?: -1
    }

    private fun resolvePackage(uid: Int): String {
        val cached = uidPackageNameMap[uid]
        if (cached != null) return cached
        val packageName = packageManager
            .getPackagesForUid(uid)
            ?.firstOrNull()
            ?.takeIf { it.isNotEmpty() }
            .orEmpty()
        return uidPackageNameMap.putIfAbsent(uid, packageName) ?: packageName
    }

    private val VpnOptions.tunAddress
        get(): String = buildString {
            append(IPV4_ADDRESS)
            if (ipv6) {
                append(",")
                append(IPV6_ADDRESS)
            }
        }

    private val VpnOptions.tunDns
        get(): String {
            if (dnsHijacking) {
                return NET_ANY
            }
            return buildString {
                append(DNS)
                if (ipv6) {
                    append(",")
                    append(DNS6)
                }
            }
        }

    override fun onLowMemory() {
        Core.forceGC()
        super.onLowMemory()
    }

    inner class LocalBinder : Binder() {
        val service: VpnService
            get() = this@VpnService
    }

    override fun onBind(intent: Intent): IBinder? =
        if (intent.action == SystemVpnService.SERVICE_INTERFACE) {
            super.onBind(intent)
        } else {
            binder
        }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android starts always-on VPN through this callback instead of FlClash's bound-service
        // path. Notify the app layer so it can restore Core and fully initialize the VPN service.
        notifyVpnStartRequested()
        return super.onStartCommand(intent, flags, startId)
    }

    override fun onRevoke() {
        stop()
        notifyVpnRevoked()
    }

    // An owner engine that does not start leaves its server to mihomo, which carries it (Sam, 2026-10-23).
    private fun handleStart(options: VpnOptions) {
        val plan = if (options.ownsTunnel) {
            runCatching {
                Core.prepareOwner(options.core.orEmpty(), options.server.orEmpty(), options.iranDirect)
            }.getOrElse { error ->
                GlobalState.log("Owner core has no plan, mihomo carries the server: $error")
                return handleStart(options.copy(core = null))
            }
        } else {
            null
        }
        if (plan?.has(OPENVPN_PROFILE) == true) return startOpenVpn(options, plan)
        val fd = with(Builder()) {
            if (plan == null) {
                addAddressAndRoutes(options)
                addDnsServers(options)
                setMtu(MTU)
            } else {
                addOwnerTunnel(plan)
            }
            establishWith(options, owner = plan != null)
                ?: error("VPN establishment was rejected by the system")
        }
        val started = synchronized(tunLock) {
            tunRunning = true
            try {
                // A Core that fails to take the descriptor leaves the system
                // routes pointing at an interface nothing reads, and it no
                // longer keeps its own sockets out of them: every connection
                // then hangs until it times out. Tear the VPN down instead of
                // reporting a start that only looks successful.
                check(
                    if (plan != null) {
                        Core.startOwner(fd)
                    } else {
                        Core.startTun(
                            fd = fd,
                            protect = this::protect,
                            resolveUid = this::resolveUid,
                            resolvePackage = this::resolvePackage,
                            stack = options.stack,
                            address = options.tunAddress,
                            dns = options.tunDns,
                        )
                    },
                ) { "Core rejected the tun file descriptor" }
                true
            } catch (error: Exception) {
                stopTunLocked()
                if (plan == null) throw error
                GlobalState.log("Owner core did not start, mihomo carries the server: $error")
                false
            }
        }
        if (!started) handleStart(options.copy(core = null))
    }

    private fun Builder.addAddressAndRoutes(options: VpnOptions) {
        val ipv4Address = IPV4_ADDRESS.toCIDR()
        // Android sets a shorter prefix with a second ioctl that deletes and re-adds the address, and netd then
        // destroys every socket on it, the core's new TCP listener included. A /32 takes one step; the route keeps
        // the rest of the core's prefix (DNS, the system stack's NAT source) in the tun.
        addAddress(ipv4Address.address, 32)
        addRoute(IPV4_NETWORK, ipv4Address.prefixLength)
        addRoutes(
            routes = options::getIpv4RouteAddress,
            fallbackAddress = NET_ANY,
            logTag = "addRoute4",
        )

        if (options.ipv6) {
            try {
                val ipv6Address = IPV6_ADDRESS.toCIDR()
                addAddress(ipv6Address.address, ipv6Address.prefixLength)
            } catch (_: Exception) {
                GlobalState.log("IPv6 VPN address is not supported")
            }
            addRoutes(
                routes = options::getIpv6RouteAddress,
                fallbackAddress = NET_ANY6,
                logTag = "addRoute6",
            )
        }
    }

    private fun Builder.addRoutes(
        routes: () -> List<CIDR>,
        fallbackAddress: String,
        logTag: String,
    ) {
        val routeList = runCatching(routes).getOrDefault(emptyList())
        if (routeList.isEmpty()) {
            addRoute(fallbackAddress, 0)
            return
        }
        try {
            routeList.forEach { route ->
                Log.d(logTag, "address: ${route.address} prefixLength: ${route.prefixLength}")
                addRoute(route.address, route.prefixLength)
            }
        } catch (_: Exception) {
            addRoute(fallbackAddress, 0)
        }
    }

    private fun Builder.addDnsServers(options: VpnOptions) {
        addDnsServer(DNS)
        if (options.ipv6) {
            addDnsServer(DNS6)
        }
    }

    // The owner core's plan (core/shikoo_wg.go): the server's own address, DNS and MTU, and Iran's ranges kept out.
    private fun Builder.addOwnerTunnel(plan: JSONObject) {
        plan.cidrs("addresses").forEach { addAddress(it.address, it.prefixLength) }
        plan.cidrs("routes").forEach { addRoute(it.address, it.prefixLength) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            plan.cidrs("excluded").forEach { excludeRoute(IpPrefix(it.address, it.prefixLength)) }
        }
        plan.getJSONArray("dns").let { dns -> repeat(dns.length()) { addDnsServer(dns.getString(it)) } }
        setMtu(plan.getInt("mtu"))
    }

    private fun JSONObject.cidrs(key: String): List<CIDR> =
        getJSONArray(key).let { list -> List(list.length()) { list.getString(it).toCIDR() } }

    private fun Builder.establishWith(options: VpnOptions, owner: Boolean): Int? {
        configureAccessControl(options)
        setSession(getString(CommonR.string.app_name))
        setBlocking(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            setMetered(false)
        }
        if (options.allowBypass) {
            allowBypass()
        }
        // The proxy is mihomo's port, whose client of the owner's server shares its key.
        if (!owner && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && options.systemProxy) {
            GlobalState.log("Enable VPN HTTP proxy")
            setHttpProxy(
                ProxyInfo.buildDirectProxy(
                    LOCAL_HOST,
                    options.port,
                    options.bypassDomain,
                ),
            )
        }
        return establish()?.detachFd()
    }

    // OpenVPN learns the tunnel's address and routes from the server, so its VPN is built only once connected.
    private fun startOpenVpn(options: VpnOptions, plan: JSONObject) {
        val engine = OpenVpn(options.server.orEmpty(), ::protect) { spec ->
            with(Builder()) {
                addOwnerTunnel(Core.openvpnTunnel(spec))
                establishWith(options, owner = true)
            } ?: -1
        }
        synchronized(tunLock) {
            stopTunLocked()
            openVpn = engine
        }
        val failure = engine.start(
            plan.getString(OPENVPN_PROFILE),
            plan.optString("username"),
            plan.optString("password"),
        ) ?: return
        synchronized(tunLock) {
            if (openVpn === engine) stopTunLocked() else engine.stop()
        }
        if (!failure.refused) error("OpenVPN did not connect: ${failure.reason}")
        GlobalState.log("OpenVPN refused the server, mihomo carries it: ${failure.reason}")
        handleStart(options.copy(core = null))
    }

    private fun Builder.configureAccessControl(options: VpnOptions) {
        val apps = options.appRules(packageName)
        apps.allowed.forEach { name -> addApplication(name, ::addAllowedApplication) }
        apps.disallowed.forEach { name -> addApplication(name, ::addDisallowedApplication) }
    }

    // A selected package that was uninstalled since must not veto the whole tunnel.
    private fun addApplication(name: String, add: (String) -> Builder) {
        try {
            add(name)
        } catch (_: PackageManager.NameNotFoundException) {
            GlobalState.log("Access control skipped an uninstalled package: $name")
        }
    }

    override fun start() {
        try {
            modules.start()
            handleStart(requireNotNull(ServiceConfig.vpnOptions) { "VPN options are missing" })
        } catch (error: Exception) {
            stop()
            throw error
        }
    }

    override fun stop() {
        try {
            cleanup()
        } finally {
            stopSelf()
        }
    }

    private fun cleanup() {
        try {
            modules.stop()
        } finally {
            stopTun()
        }
    }

    private fun stopTun() = synchronized(tunLock) {
        stopTunLocked()
    }

    private fun stopTunLocked() {
        openVpn?.stop()
        openVpn = null
        if (tunRunning) {
            Core.stopTun()
            tunRunning = false
        }
    }

    companion object {
        private const val IPV4_ADDRESS = "172.19.0.1/30"
        private const val IPV4_NETWORK = "172.19.0.0"
        private const val IPV6_ADDRESS = "fdfe:dcba:9876::1/126"
        private const val DNS = "172.19.0.2"
        private const val DNS6 = "fdfe:dcba:9876::2"
        private const val NET_ANY = "0.0.0.0"
        private const val NET_ANY6 = "::"
        private const val LOCAL_HOST = "127.0.0.1"
        private const val MTU = 9000
    }
}
