package com.follow.clash.service

import android.app.Service
import com.follow.clash.common.BroadcastAction
import com.follow.clash.common.GlobalState
import com.follow.clash.common.sendBroadcast

interface ManagedService {
    fun start()

    fun stop()

    // Shikoo: a start still waiting on its tunnel gives up, so a newer stop is not held behind it.
    fun abandonStart() {}
}

internal fun Service.notifyVpnStartRequested() {
    GlobalState.log("VPN start requested")
    BroadcastAction.VPN_START_REQUESTED.sendBroadcast()
}

internal fun Service.notifyVpnRevoked() {
    GlobalState.log("VPN permission revoked")
    BroadcastAction.VPN_REVOKED.sendBroadcast()
}
