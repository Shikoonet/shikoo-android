package com.follow.clash.service

import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.ProxyInfo
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
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
    @Volatile
    private var openVpn: OpenVpn? = null

    @Volatile
    private var startAbandoned = false

    // Each VPN, lent to its engine as a copy: one that ends leaves traffic blocked, not leaking, and a switch needs no
    // blocking VPN of its own, so one interface change fewer, each of which leaks for a moment (establishWith).
    private val mainHandler = Handler(Looper.getMainLooper())
    private val heldTun = HeldTun<ParcelFileDescriptor>(
        { task, millis -> mainHandler.postDelayed(task, millis) },
        mainHandler::removeCallbacks,
    )

    @Volatile
    private var switchAskedAt = 0L

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
        // Another app holds the VPN now and Android denies our protect: a switch's stop would have kept it.
        Core.setOwnerProtector(null)
        notifyVpnRevoked()
    }

    // An owner engine that does not start leaves its server to mihomo (Sam, 2026-10-23); OpenVPN fails (2026-10-30).
    private fun handleStart(options: VpnOptions) {
        if (options.ownsTunnel) Core.setOwnerProtector(::protect)
        val held = heldTun.take()
        if (!held && options.ownsTunnel) holdBlocked(options)
        val plan = if (options.ownsTunnel) {
            runCatching {
                // A VPN a switch holds answers no DNS: Go reuses the last start's address for the server's name.
                Core.prepareOwner(options.core.orEmpty(), options.server.orEmpty(), options.iranDirect, held)
            }.getOrElse { error ->
                if (options.core == OPENVPN_CORE) error("OpenVPN has no plan: $error")
                GlobalState.log("Owner core has no plan, mihomo carries the server: $error")
                return handleStart(options.copy(core = null))
            }
        } else {
            null
        }
        if (plan?.has(OPENVPN_PROFILE) == true) return startOpenVpn(options, plan)
        val tun = with(Builder()) {
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
        val fd = lend(tun)
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

    // Android 9+ keeps the network across VPNs only for the same apps and neither bypassable, else it builds a new one;
    // even then the new interface's routes land after the old leaves, a moment traffic takes the mobile network.
    private fun Builder.establishWith(options: VpnOptions, owner: Boolean): ParcelFileDescriptor? {
        configureAccessControl(options)
        setSession(getString(CommonR.string.app_name))
        setBlocking(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            setMetered(false)
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
        return establish()
    }

    private fun holdBlocked(options: VpnOptions) {
        val tun = runCatching {
            with(Builder()) {
                addAddress(BLOCK_ADDRESS, 32)
                addRoute(NET_ANY, 0)
                addRoute(NET_ANY6, 0)
                establishWith(options, owner = true)
            }
        }.onFailure { GlobalState.log("Blocking VPN not built: $it") }.getOrNull()
        tun?.let(heldTun::hold)
    }

    private fun lend(tun: ParcelFileDescriptor): Int {
        heldTun.hold(tun)
        return tun.dup().detachFd()
    }

    // OpenVPN learns the tunnel's address and routes from the server, so its VPN is built only once connected.
    private fun startOpenVpn(options: VpnOptions, plan: JSONObject) {
        val engine = OpenVpn(options.server.orEmpty(), ::protect) { spec ->
            with(Builder()) {
                addOwnerTunnel(Core.openvpnTunnel(spec))
                establishWith(options, owner = true)
            }?.let(::lend) ?: -1
        }
        synchronized(tunLock) {
            stopTunLocked()
            openVpn = engine
        }
        if (startAbandoned) engine.abandon()
        val failure = engine.start(
            plan.getString(OPENVPN_PROFILE),
            plan.optString("username"),
            plan.optString("password"),
        ) ?: return
        synchronized(tunLock) {
            if (openVpn === engine) stopTunLocked() else engine.stop()
        }
        // OpenVPN runs on this engine alone, never on mihomo (Sam, 2026-10-30).
        error("OpenVPN did not connect: ${failure.reason}")
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

    override fun holdForSwitch() {
        switchAskedAt = SystemClock.elapsedRealtime()
    }

    override fun abandonStart() {
        startAbandoned = true
        openVpn?.abandon()
    }

    override fun stop() {
        val switching = SystemClock.elapsedRealtime() - switchAskedAt < SWITCH_ASK_MILLIS
        switchAskedAt = 0L
        if (switching && !heldTun.holds()) ServiceConfig.vpnOptions?.let(::holdBlocked)
        try {
            cleanup(keepHeld = switching)
        } finally {
            stopSelf()
        }
    }

    private fun cleanup(keepHeld: Boolean = false) {
        try {
            modules.stop()
        } finally {
            stopTun()
            if (keepHeld) {
                heldTun.releaseIn(SWITCH_HOLD_MILLIS)
            } else {
                heldTun.hold(null)
                Core.setOwnerProtector(null)
            }
            startAbandoned = false
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
        private const val BLOCK_ADDRESS = "172.19.0.1"
        private const val SWITCH_ASK_MILLIS = 3_000L
        private const val SWITCH_HOLD_MILLIS = 5_000L
        private const val LOCAL_HOST = "127.0.0.1"
        private const val MTU = 9000
    }
}
