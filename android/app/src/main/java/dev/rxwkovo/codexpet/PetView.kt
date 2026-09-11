package dev.rxwkovo.codexpet

import android.content.Context
import android.graphics.*
import android.os.SystemClock
import android.view.*
import kotlin.math.*
import kotlin.random.Random

class PetView @JvmOverloads constructor(context:Context, val floating:Boolean=false):View(context) {
    private val store=(context.applicationContext as PetApp).store
    val motion=PetMotion()
    var moveWindow:((Float)->Unit)?=null
    var dragWindow:((Float,Float)->Unit)?=null
    var openApp:(()->Unit)?=null
    private val paint=Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val rect=RectF()
    private var previous:Bitmap?=null
    private var shown:Bitmap?=null
    private var lastKey=""
    private var transitionAt=0L
    private var active=false
    private var last=0L
    private var nextAction=SystemClock.uptimeMillis()+15000
    private var lastTouch=SystemClock.uptimeMillis()
    private var blinkAt=SystemClock.uptimeMillis()+3000
    private var localX=0f
    private var downX=0f;private var downY=0f;private var prevX=0f;private var prevY=0f;private var downAt=0L;private var dragged=false
    // Bound decoded HD images instead of retaining every action/expression (~370 MB).
    private val frames=object:android.util.LruCache<String,Bitmap>(12*1024*1024){
        override fun sizeOf(key:String,value:Bitmap)=value.allocationByteCount
    }
    private fun frame(name:String):Bitmap=frames.get(name)?:context.assets.open("pet/$name.png").use{
        BitmapFactory.decodeStream(it)!!.also{bitmap->frames.put(name,bitmap)}
    }
    private val tick=object:Runnable{override fun run(){if(!active)return;update();invalidate();postDelayed(this,if(motion.action=="compact")100 else 33)}}
    init {isClickable=true;contentDescription="码团，点击互动，拖动移动，长按打开主界面"}
    fun start(){if(active)return;active=true;last=SystemClock.uptimeMillis();post(tick)}
    fun pause(){active=false;removeCallbacks(tick)}
    fun action(name:String){lastTouch=SystemClock.uptimeMillis();motion.start(name,lastTouch);nextAction=lastTouch+Random.nextLong(60000,120001);invalidate()}
    private fun update(){
        val now=SystemClock.uptimeMillis();val dt=(now-last)/1000.0;last=now
        if(motion.finished(now)){val previous=motion.action;motion.start(if(previous=="sleep")"stretch" else "idle",now);nextAction=now+Random.nextLong(60000,120001);lastTouch=now}
        if(motion.action=="walk") {
            val dx=motion.step(dt,23.0).toFloat()
            if(floating)moveWindow?.invoke(dx*resources.displayMetrics.density) else {
                localX+=dx
                val bound=((width-min(width,height))/2f).coerceAtLeast(0f)
                if(abs(localX)>bound){localX=localX.coerceIn(-bound,bound);motion.facingLeft=!motion.facingLeft}
            }
        }
        if(store.prefs.getBoolean("random",true) && now>=nextAction && motion.action in listOf("idle","compact"))action(listOf("walk","sit","sleep","wave","stretch").random())
        if(floating && store.prefs.getBoolean("compact",true) && now-lastTouch>20000 && motion.action=="idle")motion.start("compact",now)
        if(now>blinkAt+160)blinkAt=now+Random.nextLong(2500,6000)
    }
    override fun onDraw(canvas:Canvas){
        super.onDraw(canvas)
        val now=SystemClock.uptimeMillis()
        motion.stretchHoldPercent=store.prefs.getInt("stretchHold",18)
        val mood=store.mood()
        val blink=now in blinkAt..blinkAt+160
        val sample=motion.sample(now,mood,blink)
        val expression=mood+if(blink || (sample.first=="sleep" && sample.second>=6))4 else 0
        val name="${sample.first}_${sample.second}"+if(sample.first=="moods")"" else "_$expression"
        val frame=frame(name)
        val key=sample.first+mood
        if(key!=lastKey){previous=shown;transitionAt=now;lastKey=key}
        shown=frame
        val compact=motion.action=="compact"
        val factor=if(compact)0.62f else 1f
        // Keep the quota badge above the full stretch/leaf silhouette.
        val availableHeight=height-if(floating && !compact)26*resources.displayMetrics.density else 0f
        val size=min(width.toFloat(),availableHeight)*factor
        val left=(width-size)/2+(if(floating)0f else localX)
        val top=height-size-abs(sin(now/850.0)).toFloat()*2f
        canvas.save()
        if(motion.facingLeft && motion.action=="walk")canvas.scale(-1f,1f,left+size/2,0f)
        rect.set(left,top,left+size,top+size*210/220)
        val blend=((now-transitionAt)/120f).coerceIn(0f,1f)
        previous?.let{if(blend<1f){paint.alpha=((1-blend)*255).toInt();canvas.drawBitmap(it,null,rect,paint)}}
        paint.alpha=if(previous==null)255 else (blend*255).toInt();canvas.drawBitmap(frame,null,rect,paint);paint.alpha=255
        canvas.restore()
        if(floating && !compact){
            val fresh=store.usage?.fresh(System.currentTimeMillis()/1000)==true
            val label=if(store.demo)"演示模式" else if(fresh)"5h ${store.usage!!.five!!.remaining.toInt()}% · 周 ${store.usage!!.week!!.remaining.toInt()}%" else "额度未更新"
            paint.typeface=Typeface.create("sans-serif-medium",Typeface.NORMAL);paint.textSize=11*resources.displayMetrics.density
            val w=paint.measureText(label)+18*resources.displayMetrics.density
            rect.set((width-w)/2,0f,(width+w)/2,22*resources.displayMetrics.density)
            paint.color=Color.rgb(237,249,243);canvas.drawRoundRect(rect,12f,12f,paint)
            paint.color=Color.rgb(32,87,72);paint.textAlign=Paint.Align.CENTER;canvas.drawText(label,width/2f,15*resources.displayMetrics.density,paint)
        }
    }
    override fun onTouchEvent(e:MotionEvent):Boolean {
        when(e.actionMasked){
            MotionEvent.ACTION_DOWN->{downX=e.rawX;downY=e.rawY;prevX=downX;prevY=downY;downAt=SystemClock.uptimeMillis();dragged=false;motion.start("idle",downAt);lastTouch=downAt;return true}
            MotionEvent.ACTION_MOVE->{if(hypot(e.rawX-downX,e.rawY-downY)>8*resources.displayMetrics.density)dragged=true;if(dragged)dragWindow?.invoke(e.rawX-prevX,e.rawY-prevY);prevX=e.rawX;prevY=e.rawY;return true}
            MotionEvent.ACTION_UP->{if(!dragged){if(SystemClock.uptimeMillis()-downAt>600)openApp?.invoke() else performClick()};return true}
            MotionEvent.ACTION_CANCEL->return true
        };return true
    }
    override fun performClick():Boolean{super.performClick();action("wave");return true}
    override fun onDetachedFromWindow(){pause();super.onDetachedFromWindow()}
}
