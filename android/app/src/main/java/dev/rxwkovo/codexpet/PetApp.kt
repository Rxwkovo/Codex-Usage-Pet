package dev.rxwkovo.codexpet

import android.app.Application
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.net.URL
import java.net.Proxy
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.X509Certificate
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.net.ssl.*

class PetApp : Application() {
    lateinit var store: PetStore
    override fun onCreate() { super.onCreate(); store=PetStore(this) }
}

/** One repository per process; both UI hosts subscribe to it. Pairing secrets use Android Keystore. */
class PetStore(private val context: Context) {
    val prefs=context.getSharedPreferences("pet",Context.MODE_PRIVATE)
    private val main=Handler(Looper.getMainLooper())
    private val executor=Executors.newSingleThreadExecutor()
    private var clients=0
    private var inFlight=false
    private var generation=0
    var message="还没有连接电脑"; private set
    var usage: Usage?=decode(prefs.getString("snapshot",null),prefs.getLong("snapshotReceivedAt",System.currentTimeMillis()/1000)); private set
    var demo=false; private set
    var demoMood=1
    val listeners=mutableSetOf<()->Unit>()
    var paired=prefs.contains("pairing"); private set
    // Cached because MainActivity.render() reads this once a second, and every uncached read
    // did a KeyStore round trip plus an AES-GCM decrypt on the main thread. Invalidated
    // wherever the stored pairing changes (below); all of those run on the main thread.
    @Volatile private var addressCache:String?=null
    private fun invalidateAddress(){addressCache=null}
    val connectionAddress:String get()=addressCache ?: decodeAddress().also{addressCache=it}
    // Distinguish "never paired" from "the stored pairing can no longer be decrypted".
    // The Keystore key is invalidated when the user changes the lock screen, and the old
    // code reported that as 尚未配对 while paired stayed true, leaving no way to tell why.
    private fun decodeAddress():String{
        val raw=prefs.getString("pairing",null) ?: return "尚未配对"
        return try{URL(JSONObject(unseal(raw)).getString("url")).let{
            if(it.host=="127.0.0.1" || it.host=="localhost")"USB 测试连接 · 拔线会断开，请切换无线地址"
            else "电脑地址：${it.host}:${if(it.port<0)443 else it.port}"
        }}catch(e:Exception){"配对信息无法解密，请解除配对后重新导入配对码"}
    }
    private class SyncHttpException(val status:Int):Exception()
    private fun connectionError(e:Exception)=when(e){
        is SyncHttpException -> if(e.status==401 || e.status==403)"配对已失效或过期，请导入电脑的新配对码" else "电脑同步端返回错误 ${e.status}"
        is SSLException -> "电脑身份校验失败，请确认同步端并重新配对"
        is java.security.GeneralSecurityException -> "配对信息无法解密，请解除配对后重新导入配对码"
        is IllegalArgumentException, is org.json.JSONException -> "配对信息已损坏，请解除配对后重新导入配对码"
        else -> "无法连接电脑：请确认同步端已启动、无线地址正确，并允许其通过防火墙"
    }
    fun switchAddress(address:String,done:(String?)->Unit){
        if(inFlight){done("正在同步，请稍后重试");return}
        val endpoint=try{WirelessEndpoint.parse(address)}catch(e:Exception){done("请输入电脑的局域网 IPv4，例如 192.168.3.44:47831");return}
        if(!paired){done("请先导入电脑配对码");return}
        inFlight=true;val ticket=++generation
        executor.execute{
            try{
                val spec=JSONObject(unseal(prefs.getString("pairing",null)!!)).put("url",endpoint)
                val raw=request(spec,"/usage",spec.getString("token"),false)
                val receivedAt=System.currentTimeMillis()/1000
                val parsed=decode(raw,receivedAt)?:error("Invalid quota")
                val encrypted=seal(spec.toString())
                main.post{inFlight=false;if(ticket==generation){prefs.edit().putString("pairing",encrypted).putString("snapshot",raw).putLong("snapshotReceivedAt",receivedAt).apply();invalidateAddress();usage=parsed;message="已切换无线连接";done(null);changed();refresh()}}
            }catch(e:Exception){main.post{inFlight=false;if(ticket==generation){message=connectionError(e)+"；原连接已保留";done(message);changed()}}}
        }
    }
    private val ticker=object:Runnable { override fun run() { if(clients>0){ refresh(); main.postDelayed(this,60000) } } }
    fun acquire(){ if(clients++==0) main.post(ticker) }
    fun release(){clients=(clients-1).coerceAtLeast(0);if(clients==0)main.removeCallbacks(ticker)}
    fun changed(){listeners.toList().forEach{it()}}
    fun mood()=if(demo)demoMood else usage?.mood(System.currentTimeMillis()/1000)?:0
    fun setDemo(enabled:Boolean){demo=enabled;changed()}
    fun forget(){generation++;prefs.edit().remove("pairing").remove("snapshot").remove("snapshotReceivedAt").apply();invalidateAddress();paired=false;usage=null;message="已解除配对";changed()}
    private fun key():SecretKey {
        val ks=KeyStore.getInstance("AndroidKeyStore").apply{load(null)}
        (ks.getKey("pet-pairing",null) as? SecretKey)?.let{return it}
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply{
            init(KeyGenParameterSpec.Builder("pet-pairing",KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun seal(s:String):String {val c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,key());return Base64.encodeToString(c.iv+c.doFinal(s.toByteArray()),Base64.NO_WRAP)}
    private fun unseal(s:String):String {val b=Base64.decode(s,Base64.NO_WRAP);val c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,key(),GCMParameterSpec(128,b.copyOfRange(0,12)));return String(c.doFinal(b.copyOfRange(12,b.size)))}
    fun pair(code:String, done:(String?)->Unit) {
        if(inFlight){done("正在同步，请稍后重试");return}
        val spec=try {
            require(code.trim().startsWith("mdt1:"))
            JSONObject(String(Base64.decode(code.trim().removePrefix("mdt1:"),Base64.URL_SAFE or Base64.NO_WRAP))).also{
                val u=URL(it.getString("url"));require(u.protocol=="https" && u.userInfo==null && u.query==null && u.ref==null)
                require(it.getString("pin").matches(Regex("[a-f0-9]{64}")))
                require(it.getString("code").length>=24)
            }
        }catch(e:Exception){done("配对码无效，请从电脑同步端重新复制");return}
        inFlight=true;val ticket=++generation
        executor.execute {
            try {
                val reply=request(spec,"/pair",spec.getString("code"),true)
                spec.put("token",JSONObject(reply).getString("token")).remove("code")
                val encrypted=seal(spec.toString())
                main.post{inFlight=false;if(ticket==generation){prefs.edit().putString("pairing",encrypted).apply();invalidateAddress();paired=true;demo=false;message="配对成功";done(null);refresh()}}
            }catch(e:Exception){main.post{inFlight=false;if(ticket==generation)done(connectionError(e))}}
        }
    }
    fun refresh() {
        if(inFlight || !paired)return
        inFlight=true;val ticket=generation
        executor.execute{
            try {
                val spec=JSONObject(unseal(prefs.getString("pairing",null)!!))
                val raw=request(spec,"/usage",spec.getString("token"),false)
                val receivedAt=System.currentTimeMillis()/1000
                val parsed=decode(raw,receivedAt)?:error("Invalid quota")
                main.post{inFlight=false;if(ticket==generation){usage=parsed;prefs.edit().putString("snapshot",raw).putLong("snapshotReceivedAt",receivedAt).apply();message=if(parsed.fresh(System.currentTimeMillis()/1000))"已同步 · 加密连接" else "电脑额度尚未更新";changed()}}
            }catch(e:Exception){main.post{inFlight=false;if(ticket==generation){usage=usage?.copy(status="stale");message=connectionError(e)+" · 显示上次数据";changed()}}}
        }
    }
    private fun request(spec:JSONObject,path:String,secret:String,post:Boolean):String {
        val pin=spec.getString("pin")
        val tm=object:X509TrustManager {
            override fun getAcceptedIssuers()=emptyArray<X509Certificate>()
            override fun checkClientTrusted(c:Array<X509Certificate>,a:String){throw java.security.cert.CertificateException()}
            override fun checkServerTrusted(c:Array<X509Certificate>,a:String){
                if(c.isEmpty())throw java.security.cert.CertificateException("Missing certificate")
                c[0].checkValidity()
                val actual=MessageDigest.getInstance("SHA-256").digest(c[0].encoded).joinToString(""){"%02x".format(it)}
                if(!MessageDigest.isEqual(actual.toByteArray(),pin.toByteArray()))throw java.security.cert.CertificateException("Pin mismatch")
            }
        }
        val ssl=SSLContext.getInstance("TLS").apply{init(null,arrayOf(tm),null)}
        // Bypass HTTP proxy settings for LAN traffic; OS-level VPN routing still applies.
        val conn=URL(spec.getString("url").trimEnd('/')+path).openConnection(Proxy.NO_PROXY) as HttpsURLConnection
        conn.sslSocketFactory=ssl.socketFactory
        // Certificate identity is explicitly bound by the pairing fingerprint, including LAN IP changes.
        conn.hostnameVerifier=HostnameVerifier{_,session->try{val cert=session.peerCertificates[0];MessageDigest.getInstance("SHA-256").digest(cert.encoded).joinToString(""){"%02x".format(it)}==pin}catch(e:Exception){false}}
        conn.connectTimeout=7000;conn.readTimeout=10000;conn.instanceFollowRedirects=false
        conn.setRequestProperty("Authorization","Bearer $secret")
        try {
            if(post){conn.requestMethod="POST";conn.doOutput=true;conn.outputStream.use{it.write(byteArrayOf())}}
            if(conn.responseCode!=200)throw SyncHttpException(conn.responseCode)
            return conn.inputStream.use{input->
            val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(2048)
            while(true){val count=input.read(buffer);if(count<0)break;require(out.size()+count<=16384);out.write(buffer,0,count)}
            String(out.toByteArray())
        }} finally{conn.disconnect()}
    }
    companion object {
        fun decode(raw:String?,receivedAt:Long=System.currentTimeMillis()/1000):Usage?=try {val j=JSONObject(raw?:"");fun window(k:String):WindowQuota?{val w=j.optJSONObject(k)?:return null;return WindowQuota(w.getDouble("remaining"),w.optLong("resetsAt",0))};val updatedAt=j.getLong("updatedAt");Usage(window("fiveHour"),window("weekly"),updatedAt,j.getString("status"),j.optLong("serverTime",updatedAt),receivedAt)}catch(e:Exception){null}
    }
}
