package dev.rxwkovo.codexpet

import kotlin.math.*

object WirelessEndpoint {
    fun parse(value:String):String {
        val parts=value.trim().removePrefix("https://").trimEnd('/').split(':')
        require(parts.size in 1..2)
        val ip=parts[0].split('.').map{require(it.matches(Regex("[0-9]{1,3}")));it.toInt().also{v->require(v in 0..255)}}
        require(ip.size==4)
        require(ip[0]==10 || (ip[0]==172 && ip[1] in 16..31) || (ip[0]==192 && ip[1]==168))
        val port=if(parts.size==2)parts[1].toInt() else 47831
        require(port in 1..65535)
        return "https://${ip.joinToString(".")}:$port"
    }
}

data class WindowQuota(val remaining: Double, val resetsAt: Long)
data class Usage(
    val five: WindowQuota?, val week: WindowQuota?, val updatedAt: Long, val status: String,
    val serverTime: Long = updatedAt, val receivedAt: Long = serverTime
) {
    // The quota timestamps come from the computer, while now comes from the phone.
    // Compare values within their own clock domains so ordinary clock skew cannot make a
    // freshly received snapshot look expired (or keep an old one fresh).
    fun fresh(now: Long): Boolean = status == "ok" && receivedAt <= now + 5 && now - receivedAt < 120 &&
        updatedAt <= serverTime + 5 && serverTime - updatedAt < 120 &&
        listOf(five, week).all { it != null && it.remaining.isFinite() && it.remaining in 0.0..100.0 && it.resetsAt > serverTime }
    fun localTime(serverValue: Long): Long =
        if(serverTime > 0 && receivedAt > 0) receivedAt + (serverValue - serverTime) else serverValue
    fun mood(now: Long): Int {
        if (!fresh(now)) return 0
        val low = min(five!!.remaining, week!!.remaining)
        return when { low <= 0 -> 3; low <= 20 -> 2; low >= 50 -> 1; else -> 0 }
    }
}

/** Pure time-based animation: movement is measured in pixels, independent of display refresh. */
class PetMotion {
    var action = "idle"; private set
    var started = 0L; private set
    var duration = 1.0; private set
    var facingLeft = false
    var distance = 0.0; private set
    var stretchHoldPercent = 18
    fun start(name: String, now: Long) {
        action = name; started = now; distance = 0.0
        // Kept in step with the desktop defaults in preferences-core.ps1. This used to run
        // 16-frame wave/stretch at 3.5s and sleep at 20s, so the very same 伸展顶点停留
        // percentage produced a noticeably shorter peak hold on the phone than on the desktop.
        duration = when(name) { "walk" -> 8.0; "sit" -> 12.0; "sleep" -> 18.0; "stretch" -> 5.0; "wave" -> 3.8; "compact" -> 3600.0; else -> 3.5 }
    }
    fun finished(now: Long) = action != "idle" && (now - started) / 1000.0 >= duration
    fun step(dt: Double, pixelsPerSecond: Double): Double {
        if(action != "walk") return 0.0
        val movement = dt.coerceIn(0.0, 0.1) * pixelsPerSecond
        distance += movement
        return if(facingLeft) -movement else movement
    }
    fun sample(now: Long, mood: Int, blink: Boolean): Pair<String, Int> {
        val age = max(0.0, (now - started) / 1000.0)
        val frame = when(action) {
            "walk" -> ((distance / 48.0 * 8).toInt() % 8)
            "sit", "sleep" -> { val t=(min(age,duration-age)/1.3).coerceIn(0.0,1.0); (7*t*t*(3-2*t)).roundToInt() }
            "compact" -> (7 * (age / 0.7).coerceIn(0.0,1.0)).roundToInt()
            "wave" -> (15 * (age/duration).coerceIn(0.0,1.0)).roundToInt()
            "stretch" -> {
                val t=(age/duration).coerceIn(0.0,1.0)
                val hold=stretchHoldPercent.coerceIn(0,40)/100.0
                val before=(1-hold)*0.6; val after=before+hold
                when { t<before -> (9*t/before).roundToInt(); t<=after -> 9; else -> (9+6*(t-after)/(1-after)).roundToInt() }
            }
            else -> mood + if(blink) 4 else 0
        }
        return Pair(if(action=="idle") "moods" else action,frame.coerceIn(0,if(action in listOf("wave","stretch"))15 else 7))
    }
}
