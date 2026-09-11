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
    const int Density=2,W=220*Density,H=210*Density,Stride=W*4;
    public int PixelWidth {get{return W;}}
    public int PixelHeight {get{return H;}}
    public PetSpriteView(){RenderOptions.SetBitmapScalingMode(this,BitmapScalingMode.HighQuality);}
    readonly Dictionary<string,byte[][]> sheets=new Dictionary<string,byte[][]>();
    readonly Dictionary<string,ScreenRegion[]> screens=new Dictionary<string,ScreenRegion[]>();
    readonly Dictionary<string,ScreenRegion[]> faceRegions=new Dictionary<string,ScreenRegion[]>();
    readonly Dictionary<string,byte[][]> faceArt=new Dictionary<string,byte[][]>();
    readonly Dictionary<string,byte[]> composed=new Dictionary<string,byte[]>();
    readonly Queue<string> compositionOrder=new Queue<string>();
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
        public FacePaint paint;
        public double cx,cy,c,s,left=1e6,right=-1e6,top=1e6,bottom=-1e6;
        public ScreenRegion(byte[] p)
        {
            // A resting face may touch the body's ink outline. Find the thick
            // panel core first so connected thin outlines cannot become a face.
            var core=new bool[W*H];
            int radius=2*Density;
            for(int y=radius;y<H-radius;y++)for(int x=radius;x<W-radius;x++){
                bool solid=true;for(int dy=-radius;dy<=radius&&solid;dy++)for(int dx=-radius;dx<=radius;dx++)if(!Dark(p,(y+dy)*W+x+dx)){solid=false;break;}
                core[y*W+x]=solid;
            }
            var tags=new int[W*H];var queue=new int[W*H];int tag=0,best=0,size=0;
            for(int start=0;start<tags.Length;start++){
                if(tags[start]!=0||!core[start])continue;
                int begin=0,end=1;queue[0]=start;tags[start]=++tag;
                while(begin<end){int n=queue[begin++],x=n%W,y=n/W;for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){int xx=x+dx,yy=y+dy;if(xx<0||xx>=W||yy<0||yy>=H)continue;int k=yy*W+xx;if(tags[k]==0&&core[k]){tags[k]=tag;queue[end++]=k;}}}
                if(end>size){size=end;best=tag;}
            }
            if(size<300)throw new InvalidDataException("Cannot locate raster face screen");
            var panel=new bool[W*H];
            for(int n=0;n<tags.Length;n++)if(tags[n]==best){int x=n%W,y=n/W;for(int dy=-radius;dy<=radius;dy++)for(int dx=-radius;dx<=radius;dx++){int xx=x+dx,yy=y+dy;if(xx>=0&&xx<W&&yy>=0&&yy<H&&Dark(p,yy*W+xx))panel[yy*W+xx]=true;}}
            FillPanelHull(panel);
            // Flood the exterior, filling eyes/mouth holes inside the screen.
            var exterior=new bool[W*H];int head=0,tail=1;queue[0]=0;exterior[0]=true;
            while(head<tail){int n=queue[head++],x=n%W,y=n/W;foreach(int d in new[]{-1,1,-W,W}){int k=n+d;if(k<0||k>=W*H||(d==-1&&x==0)||(d==1&&x==W-1)||exterior[k]||panel[k])continue;exterior[k]=true;queue[tail++]=k;}}
            int count=0;for(int i=0;i<mask.Length;i++)if(!exterior[i]){mask[i]=true;cx+=i%W;cy+=i/W;count++;}
            cx/=count;cy/=count;double xxSum=0,yySum=0,xySum=0;
            for(int i=0;i<mask.Length;i++)if(mask[i]){double x=i%W-cx,y=i/W-cy;xxSum+=x*x;yySum+=y*y;xySum+=x*y;}
            double angle=.5*Math.Atan2(2*xySum,xxSum-yySum);c=Math.Cos(angle);s=Math.Sin(angle);
            for(int i=0;i<mask.Length;i++)if(mask[i]){double x=i%W-cx,y=i/W-cy,u=x*c+y*s,v=-x*s+y*c;left=Math.Min(left,u);right=Math.Max(right,u);top=Math.Min(top,v);bottom=Math.Max(bottom,v);}
            paint=new FacePaint(p,mask);
        }
        static bool Dark(byte[] p,int i){i*=4;return p[i+3]>240&&p[i]<90&&p[i+1]<105&&p[i+2]<65;}
        static double Cross(Point a,Point b,Point c){return (b.X-a.X)*(c.Y-a.Y)-(b.Y-a.Y)*(c.X-a.X);}
        static void FillPanelHull(bool[] panel){
            var points=new List<Point>();for(int x=0;x<W;x++)for(int y=0;y<H;y++)if(panel[y*W+x])points.Add(new Point(x,y));
            var hull=new List<Point>();foreach(var pt in points){while(hull.Count>=2&&Cross(hull[hull.Count-2],hull[hull.Count-1],pt)<=0)hull.RemoveAt(hull.Count-1);hull.Add(pt);}
            int lower=hull.Count;for(int i=points.Count-2;i>=0;i--){var pt=points[i];while(hull.Count>lower&&Cross(hull[hull.Count-2],hull[hull.Count-1],pt)<=0)hull.RemoveAt(hull.Count-1);hull.Add(pt);}
            for(int y=0;y<H;y++){double left=W,right=-1,scan=y+.001;
                for(int i=0;i<hull.Count-1;i++){var a=hull[i];var b=hull[i+1];if((a.Y>scan)==(b.Y>scan))continue;double x=a.X+(scan-a.Y)*(b.X-a.X)/(b.Y-a.Y);left=Math.Min(left,x);right=Math.Max(right,x);}
                for(int x=Math.Max(0,(int)Math.Ceiling(left));x<=Math.Min(W-1,(int)Math.Floor(right));x++)panel[y*W+x]=true;
            }
        }
    }
    // Transfer only the drawn eyes, mouth, cheeks and tear. Reconstruct the
    // original panel beneath its old marks from nearby unmarked panel pixels.
    // The panel boundary, colour gradient and ink texture stay with the body cel.
    sealed class FacePaint
    {
        int l,t,w,h;
        public byte[] clean;
        public bool[] ink;
        short[] delta;
        public FacePaint(byte[] pixels,bool[] mask){
            int right=0,bottom=0;l=W;t=H;
            for(int i=0;i<mask.Length;i++)if(mask[i]){l=Math.Min(l,i%W);t=Math.Min(t,i/W);right=Math.Max(right,i%W);bottom=Math.Max(bottom,i/W);}
            w=right-l+1;h=bottom-t+1;ink=new bool[w*h];clean=new byte[w*h*3];delta=new short[w*h*3];
            var seed=new bool[w*h];var valid=new bool[w*h];double[] average=new double[3];int count=0;
            for(int y=0;y<h;y++)for(int x=0;x<w;x++){
                int j=y*w+x,p=(t+y)*W+l+x;valid[j]=mask[p];
                for(int k=0;k<3;k++)clean[j*3+k]=pixels[p*4+k];
                if(!valid[j])continue;
                int b=pixels[p*4],g=pixels[p*4+1],r=pixels[p*4+2];
                seed[j]=Math.Max(b,Math.Max(g,r))>112||(r>70&&r>g*1.08);
            }
            int radius=Density;
            for(int y=0;y<h;y++)for(int x=0;x<w;x++)if(seed[y*w+x])for(int dy=-radius;dy<=radius;dy++)for(int dx=-radius;dx<=radius;dx++){
                int xx=x+dx,yy=y+dy;if(xx>=0&&xx<w&&yy>=0&&yy<h&&valid[yy*w+xx])ink[yy*w+xx]=true;
            }
            for(int j=0;j<valid.Length;j++)if(valid[j]&&!ink[j]){count++;for(int k=0;k<3;k++)average[k]+=clean[j*3+k];}
            if(count==0)throw new InvalidDataException("No unmarked face panel available");
            for(int k=0;k<3;k++)average[k]/=count;
            int[] stepX={-1,1,0,0},stepY={0,0,-1,1};
            for(int y=0;y<h;y++)for(int x=0;x<w;x++){
                int j=y*w+x;if(!ink[j])continue;double weight=0;double[] tone=new double[3];
                for(int direction=0;direction<4;direction++)for(int distance=1;;distance++){
                    int xx=x+stepX[direction]*distance,yy=y+stepY[direction]*distance;
                    if(xx<0||xx>=w||yy<0||yy>=h)break;int q=yy*w+xx;
                    if(!valid[q]||ink[q])continue;
                    double a=1.0/distance;weight+=a;for(int k=0;k<3;k++)tone[k]+=clean[q*3+k]*a;break;
                }
                int p=((t+y)*W+l+x)*4;int magnitude=0;
                for(int k=0;k<3;k++){clean[j*3+k]=(byte)(weight>0?tone[k]/weight:average[k]);delta[j*3+k]=(short)(pixels[p+k]-clean[j*3+k]);magnitude=Math.Max(magnitude,Math.Abs(delta[j*3+k]));}
                if(magnitude<8)for(int k=0;k<3;k++)delta[j*3+k]=0;
            }
        }
        public void ClearMarks(byte[] result){
            for(int y=0;y<h;y++)for(int x=0;x<w;x++){int j=y*w+x;if(!ink[j])continue;int p=((t+y)*W+l+x)*4;for(int k=0;k<3;k++)result[p+k]=(byte)Math.Min(result[p+3],clean[j*3+k]);}
        }
        double At(int x,int y,int channel){return x<0||y<0||x>=w||y>=h?0:delta[(y*w+x)*3+channel];}
        public double Sample(double px,double py,int channel){
            double x=px-l,y=py-t;int x0=(int)Math.Floor(x),y0=(int)Math.Floor(y);double fx=x-x0,fy=y-y0;
            return At(x0,y0,channel)*(1-fx)*(1-fy)+At(x0+1,y0,channel)*fx*(1-fy)+At(x0,y0+1,channel)*(1-fx)*fy+At(x0+1,y0+1,channel)*fx*fy;
        }
    }
    byte[] Compose(string key,int frame)
    {
        string id=key+":"+frame+":"+expression;byte[] result;
        if(composed.TryGetValue(id,out result))return result;
        result=(byte[])sheets[key][frame].Clone();var dst=screens[key][frame];var src=faceRegions[key][expression];
        dst.paint.ClearMarks(result);
        // One uniform fit preserves the proportions of hand-drawn features.
        double scale=.94*Math.Min((dst.right-dst.left)/(src.right-src.left),(dst.bottom-dst.top)/(src.bottom-src.top));
        for(int i=0;i<W*H;i++)if(dst.mask[i]){
            double x=i%W-dst.cx,y=i/W-dst.cy;
            double a=(src.left+src.right)/2+(x*dst.c+y*dst.s-(dst.left+dst.right)/2)/scale;
            double b=(src.top+src.bottom)/2+(-x*dst.s+y*dst.c-(dst.top+dst.bottom)/2)/scale;
            double px=src.cx+a*src.c-b*src.s,py=src.cy+a*src.s+b*src.c;
            for(int k=0;k<3;k++)result[i*4+k]=(byte)Math.Max(0,Math.Min(result[i*4+3],result[i*4+k]+src.paint.Sample(px,py,k)));
        }
        while(compositionOrder.Count>=48)composed.Remove(compositionOrder.Dequeue());
        composed.Add(id,result);compositionOrder.Enqueue(id);return result;
    }
    // Generated sheets can have uneven gutters. Cut only through clear paper
    // near the nominal grid boundary, never through a leaf or raised hand.
    static int[] FindCuts(int[] ink,int divisions){
        var cuts=new int[divisions+1];cuts[divisions]=ink.Length;
        double step=(double)ink.Length/divisions;
        for(int n=1;n<divisions;n++){
            int nominal=(int)Math.Round(n*step),start=(int)Math.Max(cuts[n-1]+1,nominal-step*.22),end=(int)Math.Min(ink.Length-1,nominal+step*.22);
            int best=nominal;double score=-1e9;
            for(int k=start;k<=end;){if(ink[k]!=0){k++;continue;}int first=k;while(k<=end&&ink[k]==0)k++;int center=(first+k-1)/2;double value=(k-first)-Math.Abs(center-nominal)*.1;if(value>score){score=value;best=center;}}
            if(score<-1e8)throw new InvalidDataException("No clear gutter between sprite cells");
            cuts[n]=best;
        }
        return cuts;
    }
    static byte[][] LoadSheet(string path,int rows=2)
    {
        var source=new BitmapImage();source.BeginInit();source.CacheOption=BitmapCacheOption.OnLoad;source.UriSource=new Uri(Path.GetFullPath(path));source.EndInit();source.Freeze();
        var bitmap=new FormatConvertedBitmap(source,PixelFormats.Bgra32,null,0);
        int sw=bitmap.PixelWidth,sh=bitmap.PixelHeight;
        var data=new byte[sw*sh*4];bitmap.CopyPixels(data,sw*4,0);
        var frames=new byte[rows*4][];
        var rowInk=new int[sh];var colInk=new int[sw];
        for(int y=0;y<sh;y++)for(int x=0;x<sw;x++){int j=(y*sw+x)*4;int low=Math.Min(data[j],Math.Min(data[j+1],data[j+2])),high=Math.Max(data[j],Math.Max(data[j+1],data[j+2]));if(data[j+3]>24&&((low<220&&high-low>18)||low<100)){rowInk[y]++;colInk[x]++;}}
        int[] xCuts=FindCuts(colInk,4),yCuts=FindCuts(rowInk,rows);
        var cells=new BitmapSource[frames.Length];var bounds=new Rect[frames.Length];
        for(int i=0;i<frames.Length;i++)
        {
            int ox=xCuts[i%4],oy=yCuts[i/4],cw=xCuts[i%4+1]-ox,ch=yCuts[i/4+1]-oy;
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
            cells[i]=BitmapSource.Create(cw,ch,96,96,PixelFormats.Pbgra32,null,pixels,cw*4);cells[i].Freeze();
            bounds[i]=new Rect(minX,minY,maxX-minX+1,maxY-minY+1);
        }
        // Keep a single scale through the action, sized for its largest pose.
        double scale=Density*Math.Min(180.0/bounds[0].Height,188.0/bounds[0].Width);
        foreach(var box in bounds)scale=Math.Min(scale,Density*Math.Min(190.0/box.Height,204.0/box.Width));
        for(int i=0;i<frames.Length;i++){
            var box=bounds[i];var cell=cells[i];var visual=new DrawingVisual();
            RenderOptions.SetBitmapScalingMode(visual,BitmapScalingMode.HighQuality);
            using(var dc=visual.RenderOpen()){
                bool flip=Path.GetFileNameWithoutExtension(path)=="walk"&&i>=4;
                if(flip)dc.PushTransform(new ScaleTransform(-1,1,W/2.0,0));
                dc.DrawImage(cell,new Rect(W/2.0-(box.Left+box.Width/2)*scale,198*Density-box.Bottom*scale,cell.PixelWidth*scale,cell.PixelHeight*scale));
                if(flip)dc.Pop();
            }
            var rendered=new RenderTargetBitmap(W,H,96,96,PixelFormats.Pbgra32);rendered.Render(visual);
            frames[i]=new byte[W*H*4];rendered.CopyPixels(frames[i],Stride,0);
        }
        // One generated side-bend reverses the sprout orientation. Hold the
        // preceding drawn peak for that cel instead, then lower the arms.
        if(Path.GetFileNameWithoutExtension(path)=="stretch"&&frames.Length==16)frames[10]=frames[9];
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
        dc.DrawImage(output,new Rect(0,0,220,210));dc.Pop();
    }
}
