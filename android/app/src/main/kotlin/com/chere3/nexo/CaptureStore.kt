package com.chere3.nexo

import android.content.Context
import java.util.concurrent.Executors
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persistent, process-shared state for AutoCapture: the captured-notification
 * buffer, the user's allowlist + flags (discovery / confirm-notify), and the
 * Sí/No decisions taken from the confirm notification. The listener writes here
 * (it can run while the Flutter UI is dead); the app drains on its next run.
 *
 * Backed by SharedPreferences; buffer writes happen on a single background
 * thread so the listener callback (main thread) is never blocked.
 *
 * INVARIANT: the listener service, the action receiver and the Activity all run
 * in the SAME process (no android:process), so getSharedPreferences returns one
 * coherent instance. If the listener is ever isolated, replace with a
 * ContentProvider/SQLite-backed store.
 */
object CaptureStore {
    private const val PREFS = "nexo_capture"
    private const val KEY_BUFFER = "buffer"
    private const val KEY_ALLOWLIST = "allowlist"
    private const val KEY_DECISIONS = "decisions"
    private const val KEY_NOTIFIED = "notified"
    private const val KEY_DISCOVERY = "discovery"
    private const val KEY_CONFIRM_NOTIFY = "confirm_notify"
    private const val MAX_BUFFER = 500
    private const val MAX_NOTIFIED = 400
    private val lock = Any()
    private val writer = Executors.newSingleThreadExecutor()

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ── Allowlist + flags ────────────────────────────────────────────────────
    fun setAllowlist(ctx: Context, packages: List<String>) {
        val arr = JSONArray()
        packages.forEach { arr.put(it) }
        prefs(ctx).edit().putString(KEY_ALLOWLIST, arr.toString()).apply()
    }

    fun allowlist(ctx: Context): Set<String> {
        val raw = prefs(ctx).getString(KEY_ALLOWLIST, "") ?: ""
        if (raw.isBlank()) return emptySet()
        return try {
            val arr = JSONArray(raw)
            val set = HashSet<String>(arr.length())
            for (i in 0 until arr.length()) set.add(arr.getString(i))
            set
        } catch (e: Exception) {
            emptySet()
        }
    }

    fun setFlags(ctx: Context, discovery: Boolean, confirmNotify: Boolean) {
        prefs(ctx).edit()
            .putBoolean(KEY_DISCOVERY, discovery)
            .putBoolean(KEY_CONFIRM_NOTIFY, confirmNotify)
            .apply()
    }

    fun discoveryEnabled(ctx: Context) = prefs(ctx).getBoolean(KEY_DISCOVERY, false)
    fun confirmNotifyEnabled(ctx: Context) = prefs(ctx).getBoolean(KEY_CONFIRM_NOTIFY, false)

    // ── Stable id (FNV-1a) ────────────────────────────────────────────────────
    // When the OS gives a notification key, that IS the stable identity of an
    // updatable notification ("Procesando…" → "Compra aprobada"), so the id is
    // keyed on package+key only. postTime/text are used only as a fallback when
    // there is no key, so an in-place update doesn't get re-captured/re-notified.
    fun stableId(pkg: String, key: String?, postedAt: Long, title: String?, text: String?): String {
        val basis = if (!key.isNullOrBlank()) {
            "$pkg|$key"
        } else {
            "$pkg|$postedAt|${title ?: ""}|${text ?: ""}"
        }
        var hash = 0x811c9dc5L
        for (c in basis) {
            hash = hash xor c.code.toLong()
            hash = (hash * 0x01000193L) and 0xFFFFFFFFL
        }
        return "cap_${hash.toString(16)}"
    }

    // ── Buffer ───────────────────────────────────────────────────────────────
    fun add(
        ctx: Context,
        id: String,
        pkg: String,
        appName: String?,
        title: String?,
        text: String?,
        postedAt: Long,
        key: String?,
        amount: Double?,
        last4: String?,
        direction: String?,
    ) {
        val app = ctx.applicationContext
        writer.execute {
            synchronized(lock) {
                val p = prefs(app)
                val arr = try {
                    JSONArray(p.getString(KEY_BUFFER, "[]") ?: "[]")
                } catch (e: Exception) {
                    JSONArray()
                }
                val obj = JSONObject()
                obj.put("id", id)
                obj.put("package", pkg)
                obj.put("appName", appName ?: JSONObject.NULL)
                obj.put("title", title ?: JSONObject.NULL)
                obj.put("text", text ?: JSONObject.NULL)
                obj.put("postedAt", postedAt)
                obj.put("key", key ?: JSONObject.NULL)
                obj.put("amount", amount ?: JSONObject.NULL)
                obj.put("last4", last4 ?: JSONObject.NULL)
                obj.put("direction", direction ?: JSONObject.NULL)
                arr.put(obj)

                val out = if (arr.length() > MAX_BUFFER) {
                    val trimmed = JSONArray()
                    for (i in (arr.length() - MAX_BUFFER) until arr.length()) trimmed.put(arr.get(i))
                    trimmed
                } else {
                    arr
                }
                p.edit().putString(KEY_BUFFER, out.toString()).apply()
            }
        }
    }

    /** Records a Sí/No decision from the confirm notification. */
    fun recordDecision(ctx: Context, id: String, decision: String) {
        synchronized(lock) {
            val p = prefs(ctx)
            val obj = try {
                JSONObject(p.getString(KEY_DECISIONS, "{}") ?: "{}")
            } catch (e: Exception) {
                JSONObject()
            }
            obj.put(id, decision)
            p.edit().putString(KEY_DECISIONS, obj.toString()).apply()
        }
    }

    /** True if a confirm notification was already posted for [id] (dedupe posts). */
    fun wasNotified(ctx: Context, id: String): Boolean {
        val raw = prefs(ctx).getString(KEY_NOTIFIED, "[]") ?: "[]"
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).any { arr.getString(it) == id }
        } catch (e: Exception) {
            false
        }
    }

    fun markNotified(ctx: Context, id: String) {
        synchronized(lock) {
            val p = prefs(ctx)
            val arr = try {
                JSONArray(p.getString(KEY_NOTIFIED, "[]") ?: "[]")
            } catch (e: Exception) {
                JSONArray()
            }
            arr.put(id)
            val out = if (arr.length() > MAX_NOTIFIED) {
                val trimmed = JSONArray()
                for (i in (arr.length() - MAX_NOTIFIED) until arr.length()) trimmed.put(arr.get(i))
                trimmed
            } else {
                arr
            }
            p.edit().putString(KEY_NOTIFIED, out.toString()).apply()
        }
    }

    /**
     * Returns `{"entries": [...], "decisions": {id: "confirm"|"dismiss"}}` and
     * clears both. Decisions are returned separately (not merged into entries)
     * because a Sí/No tap can arrive AFTER its capture was already drained into
     * the inbox — the app applies those by id to existing rows.
     */
    fun drain(ctx: Context): Map<String, Any?> {
        synchronized(lock) {
            val p = prefs(ctx)
            val raw = p.getString(KEY_BUFFER, "[]") ?: "[]"
            val decisionsRaw = p.getString(KEY_DECISIONS, "{}") ?: "{}"
            p.edit().putString(KEY_BUFFER, "[]").putString(KEY_DECISIONS, "{}").apply()

            val entries = ArrayList<Map<String, Any?>>()
            try {
                val arr = JSONArray(raw)
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    entries.add(
                        mapOf(
                            "id" to o.optString("id", ""),
                            "package" to o.optString("package", ""),
                            "appName" to if (o.isNull("appName")) null else o.optString("appName"),
                            "title" to if (o.isNull("title")) null else o.optString("title"),
                            "text" to if (o.isNull("text")) null else o.optString("text"),
                            "postedAt" to o.optLong("postedAt", 0L),
                            "key" to if (o.isNull("key")) null else o.optString("key"),
                            "amount" to if (o.isNull("amount")) null else o.optDouble("amount"),
                            "last4" to if (o.isNull("last4")) null else o.optString("last4"),
                            "direction" to if (o.isNull("direction")) null else o.optString("direction")
                        )
                    )
                }
            } catch (e: Exception) {
                // corrupt buffer → drop
            }

            val decisions = HashMap<String, Any?>()
            try {
                val obj = JSONObject(decisionsRaw)
                val keys = obj.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    decisions[k] = obj.optString(k)
                }
            } catch (e: Exception) {
                // corrupt decisions → drop
            }

            return mapOf("entries" to entries, "decisions" to decisions)
        }
    }
}
