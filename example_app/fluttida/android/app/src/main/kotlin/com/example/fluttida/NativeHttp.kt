package com.example.fluttida

import org.json.JSONObject

object NativeHttp {
    init {
        try {
            System.loadLibrary("nativehttp")
        } catch (t: Throwable) {
            // Will be handled at call time
        }
    }

    external fun nativeHttpRequest(
        method: String,
        url: String,
        headers: Map<String, String>?,
        body: String?,
        timeoutMs: Int
    ): String

    fun perform(method: String, url: String, headers: Map<String,String>?, body: String?, timeoutMs: Int): Map<String, Any?> {
        return try {
            val json = nativeHttpRequest(method, url, headers, body, timeoutMs)
            val o = JSONObject(json)
            mapOf(
                "status" to if (o.has("status") && !o.isNull("status")) o.getInt("status") else null,
                "body" to o.optString("body"),
                "durationMs" to o.optInt("durationMs"),
                "error" to if (o.has("error") && !o.isNull("error")) o.getString("error") else null,
            )
        } catch (t: Throwable) {
            mapOf(
                "status" to null,
                "body" to "",
                "durationMs" to 0,
                "error" to ("native error: " + t.toString()),
            )
        }
    }
}
