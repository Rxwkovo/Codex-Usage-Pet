package dev.rxwkovo.codexpet

import java.net.URL
import kotlin.math.*

private fun privateIpv4(host:String, allowLoopback:Boolean=false):Boolean {
    val parts=host.split('.')
    if(parts.size!=4 || parts.any{!it.matches(Regex("[0-9]{1,3}"))})return false
    val ip=parts.map{it.toIntOrNull()?:return false}
    if(ip.any{it !in 0..255})return false
    return (allowLoopback && ip[0]==127) || ip[0]==10 ||
        (ip[0]==172 && ip[1] in 16..31) || (ip[0]==192 && ip[1]==168)
}

object WirelessEndpoint {
    fun parse(value:String):String {
        require(value.length<=64)
        val parts=value.trim().removePrefix("https://").trimEnd('/').split(':')
        require(parts.size in 1..2)
        require(privateIpv4(parts[0]))
        val port=if(parts.size==2)parts[1].toInt() else 47831
        require(port in 1..65535)
        return "https://${parts[0].split('.').joinToString("."){it.toInt().toString()}}:$port"
    }
}

object PairingEndpoint {
    fun parse(value:String):String {
        require(value.length<=128)
        val url=URL(value)
        require(url.protocol=="https" && url.userInfo==null && url.query==null && url.ref==null)
        require(url.path.isEmpty() || url.path=="/")
        require(url.port in 1..65535)
        require(privateIpv4(url.host,allowLoopback=true))
        return "https://${url.host}:${url.port}"
    }
}

data class WindowQuota(val remaining: Double, val resetsAt: Long)

/** Public policy carried by /usage v2.  Missing or malformed policy keeps legacy peers safe. */
data class UsagePolicy(
    val refreshSeconds: Double = DEFAULT_REFRESH_SECONDS,
    val staleSeconds: Double = DEFAULT_STALE_SECONDS,
    val clockSkewToleranceSeconds: Double = DEFAULT_CLOCK_SKEW_SECONDS,
    val happyMinRemaining: Double = DEFAULT_HAPPY_MIN,
    val worriedMaxRemaining: Double = DEFAULT_WORRIED_MAX,
    val exhaustedMaxRemaining: Double = DEFAULT_EXHAUSTED_MAX
) {
    fun valid() = refreshSeconds.isFinite() && staleSeconds.isFinite() && clockSkewToleranceSeconds.isFinite() &&
        refreshSeconds in 30.0..600.0 && staleSeconds in 60.0..3600.0 && staleSeconds >= refreshSeconds+30.0 &&
        clockSkewToleranceSeconds == DEFAULT_CLOCK_SKEW_SECONDS &&
        exhaustedMaxRemaining.isFinite() && worriedMaxRemaining.isFinite() && happyMinRemaining.isFinite() &&
        exhaustedMaxRemaining == DEFAULT_EXHAUSTED_MAX && worriedMaxRemaining in 0.0..99.0 && happyMinRemaining in 1.0..100.0 &&
        worriedMaxRemaining < happyMinRemaining

    companion object {
        const val DEFAULT_REFRESH_SECONDS = 60.0
        const val DEFAULT_STALE_SECONDS = 120.0
        const val DEFAULT_CLOCK_SKEW_SECONDS = 5.0
        const val DEFAULT_HAPPY_MIN = 50.0
        const val DEFAULT_WORRIED_MAX = 20.0
        const val DEFAULT_EXHAUSTED_MAX = 0.0
        val DEFAULT = UsagePolicy()
        fun fromDeclared(protocolVersion: Long, declared: UsagePolicy?): UsagePolicy =
            if(protocolVersion == 2L && declared?.valid()==true) declared else DEFAULT
    }
}

data class Usage(
    val five: WindowQuota?, val week: WindowQuota?, val updatedAt: Long, val status: String,
    val serverTime: Long = updatedAt, val receivedAt: Long = serverTime,
    val policy: UsagePolicy = UsagePolicy.DEFAULT
) {
    // serverTime was observed when the phone received this response.  Advance that clock by
    // local elapsed time so an old cached response cannot remain fresh for another full window.
    fun serverNow(now: Long): Long = serverTime + (now - receivedAt)
    fun fresh(now: Long): Boolean {
        if(status != "ok" || !policy.valid() || receivedAt.toDouble() > now.toDouble() + policy.clockSkewToleranceSeconds) return false
        val currentServerTime=serverNow(now)
        return updatedAt <= currentServerTime + policy.clockSkewToleranceSeconds &&
            currentServerTime - updatedAt < policy.staleSeconds &&
            listOf(five, week).all { it != null && it.remaining.isFinite() && it.remaining in 0.0..100.0 && it.resetsAt > currentServerTime }
    }
    fun localTime(serverValue: Long): Long =
        if(serverTime > 0 && receivedAt > 0) receivedAt + (serverValue - serverTime) else serverValue
    fun mood(now: Long): Int {
        if (!fresh(now)) return 0
        val low = min(five!!.remaining, week!!.remaining)
        return when { low <= policy.exhaustedMaxRemaining -> 3; low <= policy.worriedMaxRemaining -> 2; low >= policy.happyMinRemaining -> 1; else -> 0 }
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
