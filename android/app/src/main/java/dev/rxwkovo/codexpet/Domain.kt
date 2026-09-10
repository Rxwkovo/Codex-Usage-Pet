package dev.rxwkovo.codexpet

import kotlin.math.*

data class WindowQuota(val remaining: Double, val resetsAt: Long)
data class Usage(val five: WindowQuota?, val week: WindowQuota?, val updatedAt: Long, val status: String) {
    fun fresh(now: Long): Boolean = status == "ok" && updatedAt <= now + 5 && now - updatedAt < 120 &&
        listOf(five, week).all { it != null && it.remaining.isFinite() && it.remaining in 0.0..100.0 && it.resetsAt > now }
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
    fun start(name: String, now: Long) {
        action = name; started = now; distance = 0.0
        duration = when(name) { "walk" -> 8.0; "sit" -> 12.0; "sleep" -> 20.0; "compact" -> 3600.0; else -> 3.5 }
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
            "wave", "stretch" -> (7 * (age/duration).coerceIn(0.0,1.0)).roundToInt()
            else -> mood + if(blink) 4 else 0
        }
        return Pair(if(action=="idle") "moods" else action,frame.coerceIn(0,7))
    }
}
