package com.mpr.chaincode

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import com.umeng.analytics.MobclickAgent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "fmlink/network_info"
    private val umengChannelName = "fmlink/umeng_page"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNetworkType" -> result.success(getNetworkType())
                    else -> result.notImplemented()
                }
            }
        // 友盟自动页面统计需要宿主 Activity 转发生命周期；
        // 只有在 Dart 侧确认用户已同意隐私政策后，才允许打开该开关。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, umengChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        umengPageEnabled = true
                        try {
                            MobclickAgent.onResume(this)
                        } catch (error: Throwable) {
                            android.util.Log.w("UmengPage", "onResume failed: $error")
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onResume() {
        super.onResume()
        if (!umengPageEnabled) return
        try {
            MobclickAgent.onResume(this)
        } catch (error: Throwable) {
            android.util.Log.w("UmengPage", "onResume failed: $error")
        }
    }

    override fun onPause() {
        if (umengPageEnabled) {
            try {
                MobclickAgent.onPause(this)
            } catch (error: Throwable) {
                android.util.Log.w("UmengPage", "onPause failed: $error")
            }
        }
        super.onPause()
    }

    companion object {
        // 用户同意隐私政策前保持 false，禁止友盟采集页面生命周期数据
        @Volatile
        private var umengPageEnabled = false
    }

    /** 获取当前网络类型：wifi / cellular / none / unknown */
    private fun getNetworkType(): String {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return "none"
        val caps = cm.getNetworkCapabilities(network) ?: return "none"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            else -> "unknown"
        }
    }
}
