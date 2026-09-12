package dev.rxwkovo.codexpet
import org.junit.Assert.*
import org.junit.Test
class DomainTest {
    @Test fun wirelessEndpointRejectsRemoteAndLoopback(){
        assertEquals("https://192.168.3.44:47831",WirelessEndpoint.parse("192.168.3.44"))
        listOf("127.0.0.1","8.8.8.8","192.168.3.999","192.168.3.4:0","192.168.3.4@evil.com","192.168.3.4/path").forEach{
            try{WirelessEndpoint.parse(it);fail("Accepted invalid wireless endpoint: $it")}catch(expected:IllegalArgumentException){}
        }
    }
    @Test fun gesturesUseAllFramesAndStretchHoldsPeak(){
        val p=PetMotion();p.start("wave",0)
        // wave now runs for 3.8s (desktop default), so sample the whole span to reach frame 15
        assertEquals((0..15).toSet(),(0..3800 step 10).map{p.sample(it.toLong(),1,false).second}.toSet())
        p.start("stretch",0)
        // stretch is 5.0s with an 18% peak hold, so the hold covers t in [0.492, 0.672]
        assertTrue(p.sample(1000,1,false).second<9)
        assertEquals(9,p.sample(2500,1,false).second);assertEquals(9,p.sample(3300,1,false).second)
        assertEquals(15,p.sample(5000,1,false).second)
    }
    @Test fun compactRampsThroughItsOwnFrames(){
        val p=PetMotion();p.start("compact",0)
        assertEquals(0,p.sample(0,1,false).second)
        assertEquals(7,p.sample(700,1,false).second)
        assertEquals(7,p.sample(60000,1,false).second)
    }
    @Test fun resetWindowsAndOutOfRangeQuotaAreNotFresh(){
        val reset=Usage(WindowQuota(80.0,900),WindowQuota(80.0,900),1000,"ok")
        assertFalse(reset.fresh(1000))
        assertFalse(quota(101.0,80.0).fresh(1050))
        assertFalse(quota(-1.0,80.0).fresh(1050))
    }
    @Test fun pairingEndpointAcceptsOnlyExplicitPrivateOrUsbAddresses(){
        assertEquals("https://192.168.3.44:47831",PairingEndpoint.parse("https://192.168.3.44:47831"))
        assertEquals("https://127.0.0.1:47831",PairingEndpoint.parse("https://127.0.0.1:47831/"))
        listOf("https://8.8.8.8:47831","https://example.com:47831","https://192.168.3.44",
            "http://192.168.3.44:47831","https://192.168.3.44:47831/path",
            "https://192.168.3.44:47831?x=1","https://192.168.3.44:47831@evil.com").forEach{
            try{PairingEndpoint.parse(it);fail("Accepted invalid pairing endpoint: $it")}catch(expected:IllegalArgumentException){}
        }
    }
    @Test fun computerAndPhoneClockSkewDoesNotExpireFreshData(){
        val u=Usage(WindowQuota(80.0,2000),WindowQuota(70.0,3000),950,"ok",1000,5000)
        assertTrue(u.fresh(5050))
        assertEquals(4950,u.localTime(u.updatedAt))
        assertEquals(6000,u.localTime(u.five!!.resetsAt))
        assertFalse(u.fresh(5120))
    }
    private fun quota(f:Double,w:Double)=Usage(WindowQuota(f,5000),WindowQuota(w,6000),1000,"ok")
    @Test fun lowerWindowControlsMood(){assertEquals(2,quota(80.0,20.0).mood(1050));assertEquals(3,quota(0.0,90.0).mood(1050));assertEquals(1,quota(50.0,90.0).mood(1050))}
    @Test fun staleMissingAndFutureNeverLookHappy(){assertEquals(0,quota(90.0,90.0).mood(1120));assertFalse(quota(80.0,80.0).copy(week=null).fresh(1050));assertFalse(quota(80.0,80.0).fresh(990));assertFalse(quota(Double.NaN,80.0).fresh(1050));assertFalse(quota(80.0,80.0).copy(status="stale").fresh(1050))}
    @Test fun walkMovesAcrossRefreshRates(){val a=PetMotion();val b=PetMotion();a.start("walk",0);b.start("walk",0);var x=0.0;var y=0.0;repeat(60){x+=a.step(1.0/60,23.0)};repeat(30){y+=b.step(1.0/30,23.0)};assertEquals(23.0,x,0.001);assertEquals(x,y,0.001)}
    @Test fun restEntersHoldsAndGetsUp(){val p=PetMotion();p.start("sit",1000);assertEquals(0,p.sample(1000,1,false).second);assertEquals(7,p.sample(7000,1,false).second);assertEquals(0,p.sample(13000,1,false).second)}
    @Test fun screenOffDoesNotTeleport(){val p=PetMotion();p.start("walk",0);assertEquals(2.3,p.step(100.0,23.0),0.001)}
}
