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
    readonly Dictionary<string,ScreenRegion[]> screens=new Dictionary<string,ScreenRegion[]>();
    readonly Dictionary<string,ScreenRegion[]> faceRegions=new Dictionary<string,ScreenRegion[]>();
    readonly Dictionary<string,byte[][]> faceArt=new Dictionary<string,byte[][]>();
    readonly Dictionary<string,byte[]> composed=new Dictionary<string,byte[]>();
    int expression;
    public void SetExpression(int mood,bool closed){expression=Math.Max(0,Math.Min(3,mood))+(closed?4:0);}
    public int GetFrameCount(string key){return sheets[key].Length;}
    readonly WriteableBitmap output=new WriteableBitmap(W,H,96,96,PixelFormats.Pbgra32,null);
    byte[] shown=new byte[W*H*4], previous;
    string currentKey="";
    bool currentMirror;
    double changedAt, transition, breath;
    public int FrameCount { get { int total=0;foreach(var a in sheets.Values)total+=a.Length;return total; } }
    public void Load(string folder)
    {
        foreach(string name in new[]{"walk","sit","sleep","stretch","wave","compact","moods"})
            sheets.Add(name,LoadSheet(Path.Combine(folder,name+".png"),name=="wave"||name=="stretch"?4:2));
        var open=LoadSheet(Path.Combine(folder,"action-moods.png"),6);
        var closed=LoadSheet(Path.Combine(folder,"action-blinks.png"),6);
        var tucked=LoadSheet(Path.Combine(folder,"compact-moods.png"),2);
        string[] actions={"walk","sit","sleep","stretch","compact","wave"};
        int[] order={1,0,2,3};
        for(int row=0;row<actions.Length;row++){
            string key=actions[row];var faces=new byte[8][];
            for(int i=0;i<8;i++)faces[i]=key=="compact"?tucked[(i/4)*4+order[i%4]]:(i<4?open:closed)[row*4+order[i%4]];
            faceArt.Add(key,faces);
        }
        faceArt.Add("moods",sheets["moods"]);
        // Original full-body cels remain intact. Only the raster screen pixels
        // receive the corresponding newly drawn action expression.
        foreach(string key in sheets.Keys){
            var regions=new ScreenRegion[sheets[key].Length];
            for(int i=0;i<regions.Length;i++)regions[i]=new ScreenRegion(sheets[key][i]);
            screens.Add(key,regions);
            var faces=new ScreenRegion[8];for(int i=0;i<8;i++)faces[i]=new ScreenRegion(faceArt[key][i]);faceRegions.Add(key,faces);
        }
    }
    sealed class ScreenRegion
    {
        public bool[] mask=new bool[W*H];
        public double cx,cy,c,s,left=1e6,right=-1e6,top=1e6,bottom=-1e6;
        public ScreenRegion(byte[] p)
        {
            var tags=new int[W*H];var queue=new int[W*H];int tag=0,best=0,size=0;
            for(int start=0;start<tags.Length;start++){
                if(tags[start]!=0||!Dark(p,start))continue;
                int begin=0,end=1;queue[0]=start;tags[start]=++tag;
                while(begin<end){int n=queue[begin++],x=n%W,y=n/W;for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){int xx=x+dx,yy=y+dy;if(xx<0||xx>=W||yy<0||yy>=H)continue;int k=yy*W+xx;if(tags[k]==0&&Dark(p,k)){tags[k]=tag;queue[end++]=k;}}}
                if(end>size){size=end;best=tag;}
            }
            if(size<300)throw new InvalidDataException("Cannot locate raster face screen");
            // Flood the exterior, filling eyes/mouth holes inside the screen.
            var exterior=new bool[W*H];int head=0,tail=1;queue[0]=0;exterior[0]=true;
            while(head<tail){int n=queue[head++],x=n%W,y=n/W;foreach(int d in new[]{-1,1,-W,W}){int k=n+d;if(k<0||k>=W*H||(d==-1&&x==0)||(d==1&&x==W-1)||exterior[k]||tags[k]==best)continue;exterior[k]=true;queue[tail++]=k;}}
            int count=0;for(int i=0;i<mask.Length;i++)if(!exterior[i]){mask[i]=true;cx+=i%W;cy+=i/W;count++;}
            cx/=count;cy/=count;double xxSum=0,yySum=0,xySum=0;
            for(int i=0;i<mask.Length;i++)if(mask[i]){double x=i%W-cx,y=i/W-cy;xxSum+=x*x;yySum+=y*y;xySum+=x*y;}
            double angle=.5*Math.Atan2(2*xySum,xxSum-yySum);c=Math.Cos(angle);s=Math.Sin(angle);
            for(int i=0;i<mask.Length;i++)if(mask[i]){double x=i%W-cx,y=i/W-cy,u=x*c+y*s,v=-x*s+y*c;left=Math.Min(left,u);right=Math.Max(right,u);top=Math.Min(top,v);bottom=Math.Max(bottom,v);}
        }
        static bool Dark(byte[] p,int i){i*=4;return p[i+3]>240&&p[i]<90&&p[i+1]<105&&p[i+2]<65;}
    }
    byte[] Compose(string key,int frame)
    {
        string id=key+":"+frame+":"+expression;byte[] result;
        if(composed.TryGetValue(id,out result))return result;
        result=(byte[])sheets[key][frame].Clone();var dst=screens[key][frame];var src=faceRegions[key][expression];var art=faceArt[key][expression];
        for(int i=0;i<W*H;i++)if(dst.mask[i]){
            double x=i%W-dst.cx,y=i/W-dst.cy;
            double u=(x*dst.c+y*dst.s-dst.left)/(dst.right-dst.left),v=(-x*dst.s+y*dst.c-dst.top)/(dst.bottom-dst.top);
            double a=src.left+u*(src.right-src.left),b=src.top+v*(src.bottom-src.top);
            double px=Math.Max(0,Math.Min(W-1,src.cx+a*src.c-b*src.s)),py=Math.Max(0,Math.Min(H-1,src.cy+a*src.s+b*src.c));
            if(!src.mask[(int)Math.Round(py)*W+(int)Math.Round(px)]){px=src.cx;py=Math.Max(0,Math.Min(H-1,src.cy+(src.top+.12*(src.bottom-src.top))*src.c));}
            int x0=(int)px,y0=(int)py,x1=Math.Min(W-1,x0+1),y1=Math.Min(H-1,y0+1);double fx=px-x0,fy=py-y0;
            for(int k=0;k<3;k++){
                double color=art[(y0*W+x0)*4+k]*(1-fx)*(1-fy)+art[(y0*W+x1)*4+k]*fx*(1-fy)+art[(y1*W+x0)*4+k]*(1-fx)*fy+art[(y1*W+x1)*4+k]*fx*fy;
                result[i*4+k]=(byte)Math.Min(result[i*4+3],color);
            }
        }
        composed.Add(id,result);return result;
    }
    static byte[][] LoadSheet(string path,int rows=2)
    {
        var source=new BitmapImage();source.BeginInit();source.CacheOption=BitmapCacheOption.OnLoad;source.UriSource=new Uri(Path.GetFullPath(path));source.EndInit();source.Freeze();
        var bitmap=new FormatConvertedBitmap(source,PixelFormats.Bgra32,null,0);
        int sw=bitmap.PixelWidth,sh=bitmap.PixelHeight;
        var data=new byte[sw*sh*4];bitmap.CopyPixels(data,sw*4,0);
        var frames=new byte[rows*4][];
        double scale=0;
        for(int i=0;i<frames.Length;i++)
        {
            int ox=i%4*sw/4,oy=i/4*sh/rows,cw=(i%4+1)*sw/4-ox,ch=(i/4+1)*sh/rows-oy;
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
            // White-paper removal applies to the exterior and silhouette edge.
            // Mint eyes/cheeks inside the enclosed character stay opaque; treating
            // those highlights as paper leaves holes when the expression changes.
            var exterior=new bool[cw*ch];int head=0,tail=0;
            for(int n=0;n<tags.Length;n++)if((n<cw||n>=cw*(ch-1)||n%cw==0||n%cw==cw-1)&&tags[n]!=bestTag){exterior[n]=true;queue[tail++]=n;}
            while(head<tail){int n=queue[head++],x=n%cw;foreach(int d in new[]{-1,1,-cw,cw}){int k=n+d;if(k<0||k>=tags.Length||(d==-1&&x==0)||(d==1&&x==cw-1)||exterior[k]||tags[k]==bestTag)continue;exterior[k]=true;queue[tail++]=k;}}
            for(int y=1;y<ch-1;y++)for(int x=1;x<cw-1;x++){
                int n=y*cw+x;if(exterior[n]||exterior[n-1]||exterior[n+1]||exterior[n-cw]||exterior[n+cw])continue;
                int srcOffset=((oy+y)*sw+ox+x)*4;
                for(int k=0;k<3;k++)pixels[n*4+k]=data[srcOffset+k];pixels[n*4+3]=255;
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
        string state=key+":"+(expression%4);
        if(state!=currentKey||mirror!=currentMirror){previous=(byte[])shown.Clone();changedAt=now;transition=transitionSeconds;currentKey=state;currentMirror=mirror;}
        var frames=sheets[key];frame=Math.Max(0,Math.Min(frames.Length-1,frame));int lo=(int)Math.Round(frame),hi=lo;double f=0;
        if(alternate>=0){hi=Math.Max(0,Math.Min(frames.Length-1,alternate));f=Math.Max(0,Math.Min(1,mix));}
        var low=Compose(key,lo);var high=Compose(key,hi);
        double t=transition<=0?1:Math.Max(0,Math.Min(1,(now-changedAt)/transition));t=t*t*t*(t*(t*6-15)+10);
        for(int y=0;y<H;y++)for(int x=0;x<W;x++)
        {
            int d=(y*W+x)*4,s=(y*W+(mirror?W-1-x:x))*4;
            for(int k=0;k<4;k++){double target=low[s+k]*(1-f)+high[s+k]*f;shown[d+k]=(byte)(previous==null?target:previous[d+k]*(1-t)+target*t);}
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
