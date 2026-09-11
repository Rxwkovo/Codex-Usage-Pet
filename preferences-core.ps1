# One schema drives defaults, validation and the settings window.
function Get-PreferenceSchema {
 @(
 @('randomActions','动作','启用随机动作','bool',1,0,1),
 @('sleepStretch','动作','睡醒后自动连播伸懒腰','bool',1,0,1),
 @('actionMin','动作','随机动作最短间隔（秒）','number',60,10,3600),
 @('actionMax','动作','随机动作最长间隔（秒）','number',120,10,3600),
 @('walkWeight','动作','散步权重（0 为禁用）','number',1,0,100),
 @('sitWeight','动作','坐下权重','number',2,0,100),
 @('sleepWeight','动作','躺下权重','number',1,0,100),
 @('stretchWeight','动作','伸懒腰权重','number',1,0,100),
 @('waveWeight','动作','挥手权重','number',1,0,100),
 @('walkDuration','动作','散步时长（秒）','number',8,3,120),
 @('sitDuration','动作','坐下时长（秒）','number',12,3,600),
 @('sleepDuration','动作','躺下时长（秒）','number',18,3,600),
 @('stretchDuration','动作','伸懒腰时长（秒）','number',5,3,60),
 @('stretchHoldPercent','动作','伸展顶点停留（时长占比 %）','number',18,0,40),
 @('waveDuration','动作','挥手时长（秒）','number',3.8,3,60),
 @('walkMin','动作','散步最短距离（像素）','number',90,10,1000),
 @('walkMax','动作','散步最长距离（像素）','number',170,10,1000),
 @('autoCompact','缩团','空闲自动缩团','bool',1,0,1),
 @('compactDelay','缩团','空闲多久后缩团（秒）','number',15,2,600),
 @('compactScale','缩团','缩团大小（相对正常大小）','number',0.42,0.25,0.8),
 @('expandHold','缩团','展开后至少保持（秒）','number',8,1,120),
 @('compactTransition','缩团','缩团 / 展开过渡（秒）','number',1.2,0.2,5),
 @('wakeOnUsage','缩团','额度变化时展开','bool',1,0,1),
 @('spriteTransition','动效','手绘动作切换淡入（秒）','number',0.12,0,0.5),
 @('poseEase','动效','动作起身 / 收尾缓动（秒）','number',1.5,0.3,3),
 @('strideLength','动效','每步距离（像素）','number',26,10,80),
 @('breathAmount','动效','待机呼吸幅度倍率','number',1,0,2),
 @('breathPeriod','动效','呼吸周期（秒）','number',3.8,1,12),
 @('fps','动效','动画帧率','number',30,15,60),
 @('blinkMin','眼神','眨眼最短间隔（秒）','number',2.8,1,30),
 @('blinkMax','眼神','眨眼最长间隔（秒）','number',6.5,1,30),
 @('blinkDurationMin','眼神','闭眼最短时长（毫秒）','number',80,40,400),
 @('blinkDurationMax','眼神','闭眼最长时长（毫秒）','number',110,40,400),
 @('doubleBlinkChance','眼神','连续眨眼概率（%）','number',16.7,0,100),
 @('doubleBlinkGap','眼神','连续眨眼间隔（秒）','number',0.3,0.1,2),
 @('walkRightChance','动作','散步优先向右概率（%）','number',50,0,100),
 @('scale','外观','正常大小倍率','number',1,0.7,1.5),
 @('fontSize','外观','额度文字大小','number',15,12,22),
 @('opacity','外观','窗口不透明度','number',1,0.4,1),
 @('topmost','外观','窗口置顶','bool',1,0,1),
 @('quiet','外观','安静模式（暂停肢体动画）','bool',0,0,1),
 @('speechSeconds','互动','说话气泡停留（秒）','number',6,1,60),
 @('happySeconds','互动','摸摸后笑容保持（秒）','number',1.8,0.2,15),
 @('focusMinutes','互动','专注时长（分钟）','number',25,1,180),
 @('bounceDuration','互动','点击弹性过渡（秒）','number',0.43,0.1,2),
 @('bounceOscillations','互动','点击弹跳次数','number',2,0,6),
 @('bounceSpring','互动','点击弹性强度','number',5,1,12),
 @('edgeSnap','互动','拖动吸边距离（像素）','number',45,0,150),
 @('refreshSeconds','额度','在线刷新间隔（秒）','number',60,30,600),
 @('staleSeconds','额度','额度过期判定（秒）','number',120,60,3600),
 @('happyThreshold','额度','开心阈值（剩余 %）','number',50,1,100),
 @('worriedThreshold','额度','担忧阈值（剩余 %）','number',20,0,99),
 @('barTransition','额度','额度条过渡（秒）','number',0.7,0.1,3)
 ) | ForEach-Object { @{key=$_[0];group=$_[1];label=$_[2];type=$_[3];default=$_[4];min=$_[5];max=$_[6]} }
}
function Get-DefaultPreferences {
 $p=@{fontFamily='Microsoft YaHei UI'}
 foreach($s in (Get-PreferenceSchema)) { if($s.type -eq 'bool') {$p[$s.key]=[bool]$s.default} else {$p[$s.key]=[double]$s.default} }
 return $p
}
function Test-Preferences($p) {
 $p=$p.Clone()
 foreach($s in (Get-PreferenceSchema)) {
  if(-not $p.ContainsKey($s.key)) {return '缺少设置：'+$s.label}
  if($s.type -eq 'number') {
   $n=0.0
   if(-not [double]::TryParse([string]$p[$s.key],[ref]$n) -or [double]::IsNaN($n) -or [double]::IsInfinity($n) -or $n -lt $s.min -or $n -gt $s.max) {return ($s.label+'：请输入 '+$s.min+' 至 '+$s.max+' 之间的数字。')}
   $p[$s.key]=$n
  }
 }
 foreach($pair in @(@('actionMin','actionMax'),@('walkMin','walkMax'),@('blinkMin','blinkMax'),@('blinkDurationMin','blinkDurationMax'))) {
  if([double]$p[$pair[0]] -gt [double]$p[$pair[1]]) {return '最短间隔 / 距离不能大于对应的最长值。'}
 }
 if($p.happyThreshold -le $p.worriedThreshold) {return '开心阈值必须大于担忧阈值。'}
 if($p.staleSeconds -lt $p.refreshSeconds+30) {return '过期判定至少应比刷新间隔多 30 秒。'}
 if(($p.walkWeight+$p.sitWeight+$p.sleepWeight+$p.stretchWeight+$p.waveWeight) -le 0) {return '请至少保留一种动作的非零权重。'}
 return $null
}
function Get-RandomRange([double]$Min,[double]$Max) { return $Min+($Max-$Min)*(Get-Random -Minimum 0 -Maximum 1000000)/1000000.0 }
function Get-WeightedAction($p,[string]$Last) {
 $choices=@('walk','sit','sleep','stretch','wave') | Where-Object {$p[$_+'Weight'] -gt 0}
 $other=@($choices | Where-Object {$_ -ne $Last}); if($other.Count -gt 0) {$choices=$other}
 $total=0.0; foreach($a in $choices) {$total+=$p[$a+'Weight']}
 $roll=Get-RandomRange 0 $total
 foreach($a in $choices) {$roll-=$p[$a+'Weight']; if($roll -le 0) {return $a}}
 return $choices[-1]
}
function Merge-PetPose($From,$To,[double]$Progress) {
 $p=[Math]::Max(0.0,[Math]::Min(1.0,$Progress)); $f=$p*$p*$p*($p*($p*6-15)+10)
 $result=$To.Clone()
 if($null -ne $From) {foreach($k in @($result.Keys)) {if($k -ne 'progress') {$result[$k]=$From[$k]+($To[$k]-$From[$k])*$f}}}
 return $result
}
