package dev.rxwkovo.codexpet
import org.junit.Assert.*
import org.junit.Test
class DomainTest {
    private fun quota(f:Double,w:Double)=Usage(WindowQuota(f,5000),WindowQuota(w,6000),1000,"ok")
    @Test fun lowerWindowControlsMood(){assertEquals(2,quota(80.0,20.0).mood(1050));assertEquals(3,quota(0.0,90.0).mood(1050));assertEquals(1,quota(50.0,90.0).mood(1050))}
    @Test fun staleMissingAndFutureNeverLookHappy(){assertEquals(0,quota(90.0,90.0).mood(1120));assertFalse(quota(80.0,80.0).copy(week=null).fresh(1050));assertFalse(quota(80.0,80.0).fresh(990));assertFalse(quota(Double.NaN,80.0).fresh(1050));assertFalse(quota(80.0,80.0).copy(status="stale").fresh(1050))}
    @Test fun walkMovesAcrossRefreshRates(){val a=PetMotion();val b=PetMotion();a.start("walk",0);b.start("walk",0);var x=0.0;var y=0.0;repeat(60){x+=a.step(1.0/60,23.0)};repeat(30){y+=b.step(1.0/30,23.0)};assertEquals(23.0,x,0.001);assertEquals(x,y,0.001)}
    @Test fun restEntersHoldsAndGetsUp(){val p=PetMotion();p.start("sit",1000);assertEquals(0,p.sample(1000,1,false).second);assertEquals(7,p.sample(7000,1,false).second);assertEquals(0,p.sample(13000,1,false).second)}
    @Test fun screenOffDoesNotTeleport(){val p=PetMotion();p.start("walk",0);assertEquals(2.3,p.step(100.0,23.0),0.001)}
}
