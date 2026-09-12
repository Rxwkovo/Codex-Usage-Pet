package dev.rxwkovo.codexpet

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.*
import android.provider.Settings
import android.view.*

class PetService:Service() {
    private lateinit var wm:WindowManager
    private var pet:PetView?=null
    private lateinit var params:WindowManager.LayoutParams
    private val store get()=(application as PetApp).store
    private var observing=false
    private var fx=0f;private var fy=0f
    private val screen=object:BroadcastReceiver(){override fun onReceive(c:Context,i:Intent){if(i.action==Intent.ACTION_SCREEN_OFF)pet?.pause() else if(i.action==Intent.ACTION_SCREEN_ON)pet?.start()}}
    override fun onBind(i:Intent?)=null
    override fun onStartCommand(i:Intent?,flags:Int,startId:Int):Int {
        // A plain startService("stop") carries no startForeground obligation.
        if(i?.action=="stop"){stopSelf();return START_NOT_STICKY}
        // Everything below can return early, and the entry point is startForegroundService(),
        // which obliges us to call startForeground() within a few seconds on EVERY path -
        // including the ones that give up (the overlay permission can be revoked between
        // MainActivity's check and this one, and addView can fail). Miss it and the platform
        // kills the process with ForegroundServiceDidNotStartInTimeException. So post the
        // notification first and only then decide whether we can actually draw.
        val manager=getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("pet","码团悬浮陪伴",NotificationManager.IMPORTANCE_LOW))
        val open=PendingIntent.getActivity(this,0,Intent(this,MainActivity::class.java),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop=PendingIntent.getService(this,1,Intent(this,PetService::class.java).setAction("stop"),PendingIntent.FLAG_IMMUTABLE)
        val n=Notification.Builder(this,"pet").setSmallIcon(R.drawable.ic_pet_notify).setContentTitle("码团正在陪你")
            .setContentText("拖动移动 · 点击互动 · 长按打开 App").setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null,"收起码团",stop).build()).build()
        if(Build.VERSION.SDK_INT>=34)startForeground(7,n,ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE) else startForeground(7,n)
        if(!Settings.canDrawOverlays(this)){stopForeground(STOP_FOREGROUND_REMOVE);stopSelf();return START_NOT_STICKY}
        if(pet!=null){i?.getStringExtra("petAction")?.let{if(it in listOf("walk","sit","sleep","wave","stretch","compact","idle"))pet?.action(it)};return START_NOT_STICKY}
        wm=getSystemService(WindowManager::class.java)
        val d=resources.displayMetrics.density
        val size=(store.prefs.getInt("size",150)*d).toInt()
        params=WindowManager.LayoutParams(size,size,WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,PixelFormat.TRANSLUCENT)
        params.gravity=Gravity.TOP or Gravity.LEFT
        fx=store.prefs.getFloat("x",30*d);fy=store.prefs.getFloat("y",200*d)
        val view=PetView(this,true);pet=view
        view.openApp={startActivity(Intent(this,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))}
        view.moveWindow={dx->fx+=dx;clamp(true);updateWindow()}
        // Persist on release only: ACTION_MOVE is delivered 60-120 times a second, and a
        // SharedPreferences commit per event queued up disk writes that onPause waits for.
        view.dragWindow={dx,dy->fx+=dx;fy+=dy;clamp(false);updateWindow()}
        view.dragEnd={store.prefs.edit().putFloat("x",fx).putFloat("y",fy).apply()}
        clamp(false)
        try{wm.addView(view,params)}catch(e:RuntimeException){pet=null;stopSelf();return START_NOT_STICKY}
        val filter=IntentFilter().apply{addAction(Intent.ACTION_SCREEN_ON);addAction(Intent.ACTION_SCREEN_OFF)}
        if(Build.VERSION.SDK_INT>=33)registerReceiver(screen,filter,RECEIVER_NOT_EXPORTED) else registerReceiver(screen,filter)
        observing=true;store.acquire();running=true
        if(getSystemService(PowerManager::class.java).isInteractive)view.start()
        return START_NOT_STICKY
    }
    private fun clamp(bounce:Boolean){
        val bounds=if(Build.VERSION.SDK_INT>=30)wm.currentWindowMetrics.bounds else android.graphics.Rect(0,0,resources.displayMetrics.widthPixels,resources.displayMetrics.heightPixels)
        val maxX=(bounds.width()-params.width).coerceAtLeast(0).toFloat()
        val maxY=(bounds.height()-params.height-32*resources.displayMetrics.density).coerceAtLeast(0f)
        if(bounce && (fx<0||fx>maxX))pet?.motion?.let{it.facingLeft=!it.facingLeft}
        fx=fx.coerceIn(0f,maxX);fy=fy.coerceIn(0f,maxY);params.x=fx.toInt();params.y=fy.toInt()
    }
    private fun updateWindow(){try{pet?.let{wm.updateViewLayout(it,params)}}catch(e:RuntimeException){stopSelf()}}
    override fun onConfigurationChanged(c:android.content.res.Configuration){super.onConfigurationChanged(c);if(pet!=null){clamp(false);updateWindow()}}
    override fun onDestroy(){
        if(observing){unregisterReceiver(screen);store.release()}
        pet?.let{it.pause();try{wm.removeView(it)}catch(_:RuntimeException){}}
        pet=null;running=false;super.onDestroy()
    }
    companion object{@Volatile var running=false}
}
