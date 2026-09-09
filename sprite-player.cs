using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

// Artwork stays in the original PNG sheets. This player only loads, keys the
// paper background, aligns cells and blends image frames; it draws no character geometry.
public sealed class PetSpriteView : FrameworkElement
{
    const int W=220,H=210,Stride=W*4;
    readonly Dictionary<string,byte[][]> sheets=new Dictionary<string,byte[][]>();
    readonly WriteableBitmap output=new WriteableBitmap(W,H,96,96,PixelFormats.Pbgra32,null);
    byte[] shown=new byte[W*H*4], previous;
    string currentKey="";
    bool currentMirror;
    double changedAt, transition, breath;
    public int FrameCount { get { return sheets.Count*8; } }
    public void Load(string folder)
    {
        foreach(string name in new[]{"walk","sit","sleep","stretch","wave","compact","moods"})
            sheets.Add(name,LoadSheet(Path.Combine(folder,name+".png")));
    }
    static byte[][] LoadSheet(string path)
    {
        var source=new BitmapImage();source.BeginInit();source.CacheOption=BitmapCacheOption.OnLoad;source.UriSource=new Uri(Path.GetFullPath(path));source.EndInit();source.Freeze();
        var bitmap=new FormatConvertedBitmap(source,PixelFormats.Bgra32,null,0);
        int sw=bitmap.PixelWidth,sh=bitmap.PixelHeight;
        var data=new byte[sw*sh*4];bitmap.CopyPixels(data,sw*4,0);
        var frames=new byte[8][];
        double scale=0;
        for(int i=0;i<8;i++)
        {
            int ox=i%4*sw/4,oy=i/4*sh/2,cw=(i%4+1)*sw/4-ox,ch=(i/4+1)*sh/2-oy;
            var pixels=new byte[cw*ch*4];int minX=cw,minY=ch,maxX=0,maxY=0;
            for(int y=0;y<ch;y++)for(int x=0;x<cw;x++)
            {
                int s=((oy+y)*sw+ox+x)*4,d=(y*cw+x)*4;
                int low=Math.Min(data[s],Math.Min(data[s+1],data[s+2])),high=Math.Max(data[s],Math.Max(data[s+1],data[s+2]));
                double a=Math.Max(0,Math.Min(1,Math.Max((245-low)/220.0,(high-low-3)/35.0)))*data[s+3]/255.0;
                // Remove the white matte without keeping white edge halos. Pbgra output.
                for(int k=0;k<3;k++)pixels[d+k]=(byte)Math.Max(0,Math.Min(255*a,data[s+k]-255*(1-a)));
                pixels[d+3]=(byte)(255*a);
            }
            // Discard detached ink motion marks, preserving the main connected character.
            int[] tags=new int[cw*ch];var queue=new int[cw*ch];int tag=0,bestTag=0,bestSize=0;
            for(int seed=0;seed<tags.Length;seed++)
            {
                if(tags[seed]!=0||pixels[seed*4+3]<24)continue;
                tag++;int begin=0,end=1;queue[0]=seed;tags[seed]=tag;
                while(begin<end){int q=queue[begin++],qx=q%cw,qy=q/cw;for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){int nx=qx+dx,ny=qy+dy;if(nx<0||nx>=cw||ny<0||ny>=ch)continue;int n=ny*cw+nx;if(tags[n]==0&&pixels[n*4+3]>=24){tags[n]=tag;queue[end++]=n;}}}
                if(end>bestSize){bestSize=end;bestTag=tag;}
            }
            if(bestSize<100)throw new InvalidDataException("No sprite found: "+path+" cell "+i);
            for(int n=0;n<tags.Length;n++)
            {
                if(tags[n]!=bestTag){for(int k=0;k<4;k++)pixels[n*4+k]=0;continue;}
                int x=n%cw,y=n/cw;minX=Math.Min(minX,x);maxX=Math.Max(maxX,x);minY=Math.Min(minY,y);maxY=Math.Max(maxY,y);
            }
            if(i==0)scale=Math.Min(180.0/(maxY-minY+1),188.0/(maxX-minX+1));
            var cell=BitmapSource.Create(cw,ch,96,96,PixelFormats.Pbgra32,null,pixels,cw*4);cell.Freeze();
            var visual=new DrawingVisual();
            using(var dc=visual.RenderOpen())
            {
                // First cell fixes scale for the entire action; all cells share a foot anchor.
                bool flip=Path.GetFileNameWithoutExtension(path)=="walk" && i>=4;
                if(flip)dc.PushTransform(new ScaleTransform(-1,1,W/2.0,0));
                dc.DrawImage(cell,new Rect(W/2.0-(minX+maxX+1)/2.0*scale,198-(maxY+1)*scale,cw*scale,ch*scale));
                if(flip)dc.Pop();
            }
            var rendered=new RenderTargetBitmap(W,H,96,96,PixelFormats.Pbgra32);rendered.Render(visual);
            frames[i]=new byte[W*H*4];rendered.CopyPixels(frames[i],Stride,0);
        }
        return frames;
    }
    public void SetFrame(string key,double frame,bool mirror,double now,double transitionSeconds,double breathing,int alternate,double mix)
    {
        string state=key+(key=="moods"?((int)frame).ToString():"");
        if(state!=currentKey||mirror!=currentMirror){previous=(byte[])shown.Clone();changedAt=now;transition=transitionSeconds;currentKey=state;currentMirror=mirror;}
        var frames=sheets[key];frame=Math.Max(0,Math.Min(7,frame));int lo=(int)Math.Round(frame),hi=lo;double f=0;
        if(alternate>=0){hi=Math.Max(0,Math.Min(7,alternate));f=Math.Max(0,Math.Min(1,mix));}
        double t=transition<=0?1:Math.Max(0,Math.Min(1,(now-changedAt)/transition));t=t*t*t*(t*(t*6-15)+10);
        for(int y=0;y<H;y++)for(int x=0;x<W;x++)
        {
            int d=(y*W+x)*4,s=(y*W+(mirror?W-1-x:x))*4;
            for(int k=0;k<4;k++){double target=frames[lo][s+k]*(1-f)+frames[hi][s+k]*f;shown[d+k]=(byte)(previous==null?target:previous[d+k]*(1-t)+target*t);}
        }
        breath=breathing;output.WritePixels(new Int32Rect(0,0,W,H),shown,Stride,0);InvalidateVisual();
    }
    public byte[] GetPixels(){return (byte[])shown.Clone();}
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        dc.PushTransform(new TranslateTransform(0,-breath));
        dc.DrawImage(output,new Rect(0,0,W,H));dc.Pop();
    }
}
