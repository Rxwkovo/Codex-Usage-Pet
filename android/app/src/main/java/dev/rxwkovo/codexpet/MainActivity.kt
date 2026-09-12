package dev.rxwkovo.codexpet

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.content.res.ColorStateList
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.view.*
import android.widget.*
import com.google.zxing.*
import com.google.zxing.common.HybridBinarizer
import java.text.SimpleDateFormat
import java.util.*

class MainActivity:Activity() {
    private val store get()=(application as PetApp).store
    private lateinit var column:LinearLayout
    private lateinit var pet:PetView
    private lateinit var status:TextView
    private lateinit var five:TextView
    private lateinit var week:TextView
    private lateinit var updated:TextView
    private lateinit var overlay:Button
    private lateinit var address:TextView
    private val handler=Handler(Looper.getMainLooper())
    private val refreshUi=object:Runnable{override fun run(){render();handler.postDelayed(this,1000)}}
    private val onChange:()->Unit={render()}
    private val ink=Color.rgb(26,64,54)
    private fun dp(n:Int)=(n*resources.displayMetrics.density).toInt()
    private fun text(value:String,size:Float=15f,bold:Boolean=false)=TextView(this).apply{text=value;textSize=size;setTextColor(ink);if(bold)typeface=Typeface.create("sans-serif-medium",Typeface.NORMAL);setPadding(0,dp(5),0,dp(5))}
    private fun button(label:String,primary:Boolean=false,fn:()->Unit)=object:Button(this){
        override fun onTouchEvent(event:MotionEvent):Boolean{
            when(event.actionMasked){
                MotionEvent.ACTION_DOWN->animate().scaleX(0.97f).scaleY(0.97f).setDuration(100).start()
                MotionEvent.ACTION_UP,MotionEvent.ACTION_CANCEL->animate().scaleX(1f).scaleY(1f).setDuration(180).start()
            }
            return super.onTouchEvent(event)
        }
    }.apply{
        text=label;isAllCaps=false;textSize=14f;typeface=Typeface.create("sans-serif-medium",Typeface.NORMAL)
        setTextColor(if(primary)Color.WHITE else ink)
        backgroundTintList=null;stateListAnimator=null;elevation=0f
        minimumWidth=0;minWidth=0;minimumHeight=dp(46);minHeight=dp(46)
        setPadding(dp(10),dp(10),dp(10),dp(10))
        val shape=GradientDrawable().apply{setColor(if(primary)Color.rgb(30,125,101) else Color.rgb(229,243,235));cornerRadius=dp(18).toFloat()}
        background=RippleDrawable(ColorStateList.valueOf(Color.argb(38,32,110,86)),shape,null)
        layoutParams=LinearLayout.LayoutParams(-1,dp(48)).apply{topMargin=dp(6);bottomMargin=dp(6)}
        setOnClickListener{fn()}
    }
    private fun chipParams()=LinearLayout.LayoutParams(0,dp(46),1f).apply{setMargins(dp(3),dp(5),dp(3),dp(5))}
    private fun card():LinearLayout=LinearLayout(this).apply{
        orientation=LinearLayout.VERTICAL;setPadding(dp(18),dp(14),dp(18),dp(14))
        background=GradientDrawable().apply{setColor(Color.WHITE);cornerRadius=dp(22).toFloat();setStroke(dp(1),Color.rgb(220,232,224))}
        column.addView(this,LinearLayout.LayoutParams(-1,-2).apply{bottomMargin=dp(14)})
    }
    override fun onCreate(s:Bundle?){
        super.onCreate(s)
        val scroll=ScrollView(this).apply{setBackgroundColor(Color.rgb(244,248,245));isFillViewport=true}
        column=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;setPadding(dp(22),dp(24),dp(22),dp(24))}
        scroll.addView(column);setContentView(scroll)
        scroll.setOnApplyWindowInsetsListener{v,insets->if(Build.VERSION.SDK_INT>=30){val bars=insets.getInsets(WindowInsets.Type.systemBars());v.setPadding(bars.left,bars.top,bars.right,bars.bottom)};insets}
        column.addView(text("码团",32f,true));column.addView(text("让额度有表情，让日常多一点陪伴。",14f))
        val stage=card();pet=PetView(this);stage.addView(pet,LinearLayout.LayoutParams(-1,dp(230)))
        status=text("",14f,true);stage.addView(status)
        val quota=card();quota.addView(text("我的额度",20f,true))
        five=text("",19f,true);week=text("",19f,true);updated=text("",12f)
        quota.addView(five);quota.addView(week);quota.addView(updated)
        quota.addView(button("立即同步"){store.refresh()})
        val live=card();live.addView(text("陪伴模式",20f,true))
        overlay=button("开启悬浮码团",true){toggleOverlay()};live.addView(overlay)
        live.addView(text("点击摸摸 · 拖动移动 · 长按打开 App\n通知栏可以随时收起。熄屏时暂停动画。",13f))
        val row=LinearLayout(this);live.addView(row)
        listOf("walk" to "走走","sit" to "坐下","sleep" to "休息").forEach{(key,label)->row.addView(button(label){playAction(key)},chipParams())}
        val row2=LinearLayout(this);live.addView(row2)
        listOf("stretch" to "伸展","wave" to "招手","compact" to "缩团").forEach{(key,label)->row2.addView(button(label){playAction(key)},chipParams())}
        val connection=card();connection.addView(text("连接电脑",20f,true))
        connection.addView(text("在电脑启动同步端，手机与电脑连接同一 Wi-Fi。首次配对支持粘贴配对码或导入二维码图片。",14f))
        address=text("",13f);connection.addView(address)
        connection.addView(button("切换无线地址"){wirelessDialog()})
        connection.addView(button("输入配对码",true){pairDialog()})
        connection.addView(button("导入配对二维码"){startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE),41)})
        connection.addView(button("解除配对"){AlertDialog.Builder(this).setMessage("解除与电脑的连接并清除缓存？").setNegativeButton("取消",null).setPositiveButton("解除"){_,_->store.forget()}.show()})
        val options=card();options.addView(text("按你的节奏",20f,true))
        fun toggle(key:String,label:String,default:Boolean){options.addView(Switch(this).apply{text=label;setTextColor(ink);isChecked=store.prefs.getBoolean(key,default);setPadding(0,dp(8),0,dp(8));setOnCheckedChangeListener{_,v->store.prefs.edit().putBoolean(key,v).apply()}})}
        toggle("random","待机时随机活动",true);toggle("compact","悬浮待机 20 秒后缩团",true)
        val hold=text("伸展顶点停留：${store.prefs.getInt("stretchHold",18)}%",13f);options.addView(hold)
        options.addView(SeekBar(this).apply{max=40;progress=store.prefs.getInt("stretchHold",18);setOnSeekBarChangeListener(object:SeekBar.OnSeekBarChangeListener{override fun onProgressChanged(s:SeekBar?,p:Int,user:Boolean){if(user){store.prefs.edit().putInt("stretchHold",p).apply();hold.text="伸展顶点停留：$p%"}};override fun onStartTrackingTouch(s:SeekBar?){};override fun onStopTrackingTouch(s:SeekBar?){}})})
        options.addView(text("悬浮大小（重新开启悬浮后生效）",13f))
        options.addView(SeekBar(this).apply{max=80;progress=store.prefs.getInt("size",150)-110;setOnSeekBarChangeListener(object:SeekBar.OnSeekBarChangeListener{override fun onProgressChanged(s:SeekBar?,p:Int,user:Boolean){if(user)store.prefs.edit().putInt("size",110+p).apply()};override fun onStartTrackingTouch(s:SeekBar?){};override fun onStopTrackingTouch(s:SeekBar?){}})})
        options.addView(Switch(this).apply{text="演示表情（不代表真实额度）";setTextColor(ink);isChecked=store.demo;setOnCheckedChangeListener{_,v->store.setDemo(v)}})
        val moods=LinearLayout(this);options.addView(moods)
        listOf("平静","开心","担忧","难过").forEachIndexed{i,label->moods.addView(button(label){store.demoMood=i;store.setDemo(true);pet.action("idle")},chipParams())}
        column.addView(text("码团 Android 0.2.2 · 动作同步桌面 v2.2.2\n电脑离线时额度不会更新；登录凭据留在电脑。",12f))
        render()
    }
    private fun render(){
        val u=store.usage;val now=System.currentTimeMillis()/1000
        status.text=if(store.demo)"演示模式 · 表情预览" else store.message
        fun label(title:String,w:WindowQuota?)="$title   ${w?.remaining?.let{if(it.isFinite()&&it in 0.0..100.0)"${it.toInt()}%" else "—"}?:"—"}"+
            if(w!=null && w.resetsAt>0)"\n"+"恢复于 "+SimpleDateFormat("MM-dd HH:mm",Locale.getDefault()).format(Date((u?.localTime(w.resetsAt)?:w.resetsAt)*1000)) else ""
        five.text=label("五小时剩余",u?.five);week.text=label("一周剩余",u?.week)
        updated.text=if(u==null)"尚无额度数据 · 配对后显示" else (if(u.fresh(now))"实时快照" else "已过期 / 未同步")+" · 上次更新 "+if(u.updatedAt>0)SimpleDateFormat("MM-dd HH:mm:ss",Locale.getDefault()).format(Date(u.localTime(u.updatedAt)*1000)) else "未知"
        overlay.text=if(PetService.running)"收起悬浮码团" else "开启悬浮码团"
        address.text=store.connectionAddress
    }
    private fun playAction(name:String){pet.action(name);if(PetService.running)startService(Intent(this,PetService::class.java).putExtra("petAction",name))}
    private fun toggleOverlay(){
        if(PetService.running){stopService(Intent(this,PetService::class.java));return}
        if(!Settings.canDrawOverlays(this)){AlertDialog.Builder(this).setMessage("让码团显示在其他应用上方，需要开启悬浮窗权限。开启后返回这里，再点击开启。").setNegativeButton("稍后",null).setPositiveButton("去开启"){_,_->startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,Uri.parse("package:$packageName")))}.show();return}
        if(Build.VERSION.SDK_INT>=33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED){requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),42);return}
        try{startForegroundService(Intent(this,PetService::class.java))}catch(e:RuntimeException){toast("系统暂时无法开启悬浮，请检查权限后重试")}
    }
    override fun onRequestPermissionsResult(r:Int,p:Array<out String>,g:IntArray){super.onRequestPermissionsResult(r,p,g);if(r==42){if(g.firstOrNull()==PackageManager.PERMISSION_GRANTED)toggleOverlay() else toast("请允许通知，方便随时收起码团")}}
    private fun pairDialog(){val input=EditText(this).apply{hint="mdt1:…";inputType=android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE};AlertDialog.Builder(this).setTitle("粘贴电脑配对码").setView(input).setNegativeButton("取消",null).setPositiveButton("连接"){_,_->pair(input.text.toString())}.show()}
    private fun wirelessDialog(){val input=EditText(this).apply{hint="电脑 Wi-Fi 地址，例如 192.168.3.44";inputType=android.text.InputType.TYPE_CLASS_TEXT};AlertDialog.Builder(this).setTitle("切换到无线同步").setMessage("填写电脑同步端显示的局域网地址。会验证电脑身份和连接成功后再保存；无需解除已有配对。").setView(input).setNegativeButton("取消",null).setPositiveButton("连接"){_,_->store.switchAddress(input.text.toString()){error->toast(error?:"无线同步已连接，可拔掉数据线")}}.show()}
    private fun pair(code:String){toast("正在安全配对…");store.pair(code){error->toast(error?:"已连接电脑")}}
    @Deprecated("Legacy result bridge") override fun onActivityResult(r:Int,result:Int,data:Intent?){
        super.onActivityResult(r,result,data)
        if(r!=41||result!=RESULT_OK)return
        var bitmap:Bitmap?=null
        var code:String?=null
        try{
            val uri=data?.data?:return
            val bounds=BitmapFactory.Options().apply{inJustDecodeBounds=true}
            contentResolver.openInputStream(uri).use{BitmapFactory.decodeStream(it,null,bounds)}
            // A picture the framework cannot measure reports -1, which used to leave
            // inSampleSize at 1 and decode the full image: the usual route to an OOM here.
            if(bounds.outWidth<=0||bounds.outHeight<=0){toast("没有找到配对二维码，请使用原图或粘贴配对码");return}
            val options=BitmapFactory.Options().apply{inSampleSize=(maxOf(bounds.outWidth,bounds.outHeight)/1600).coerceAtLeast(1)}
            bitmap=contentResolver.openInputStream(uri).use{BitmapFactory.decodeStream(it,null,options)}
            val source=bitmap
            if(source==null){toast("没有找到配对二维码，请使用原图或粘贴配对码");return}
            val pixels=IntArray(source.width*source.height);source.getPixels(pixels,0,source.width,0,0,source.width,source.height)
            code=MultiFormatReader().decode(BinaryBitmap(HybridBinarizer(RGBLuminanceSource(source.width,source.height,pixels)))).text
        }catch(e:Exception){
            toast("没有找到配对二维码，请使用原图或粘贴配对码")
        }catch(e:OutOfMemoryError){
            // A very large photo must not take the whole app down.
            toast("图片太大，请改用粘贴配对码")
        }finally{
            // Was only recycled on the success path, so a failed decode kept the
            // full-size bitmap alive until the next GC.
            bitmap?.recycle()
        }
        code?.let{pair(it)}
    }
    private fun toast(s:String){Toast.makeText(this,s,Toast.LENGTH_LONG).show()}
    override fun onResume(){super.onResume();pet.start();store.listeners.add(onChange);store.acquire();handler.post(refreshUi)}
    override fun onPause(){handler.removeCallbacks(refreshUi);store.listeners.remove(onChange);store.release();pet.pause();super.onPause()}
}
