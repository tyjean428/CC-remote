$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Add-Type -AssemblyName System.Drawing
$bitmap=[Drawing.Bitmap]::new(256,256)
$graphics=[Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([Drawing.Color]::Transparent)
$path=[Drawing.Drawing2D.GraphicsPath]::new()
foreach($arc in @(@(12,12,68,68,180,90),@(176,12,68,68,270,90),@(176,176,68,68,0,90),@(12,176,68,68,90,90))){$path.AddArc($arc[0],$arc[1],$arc[2],$arc[3],$arc[4],$arc[5])}
$path.CloseFigure()
$brush=[Drawing.Drawing2D.LinearGradientBrush]::new([Drawing.Rectangle]::new(12,12,232,232),[Drawing.Color]::FromArgb(56,116,255),[Drawing.Color]::FromArgb(23,75,210),90)
$graphics.FillPath($brush,$path)
$pen=[Drawing.Pen]::new([Drawing.Color]::White,17)
$pen.StartCap=$pen.EndCap=[Drawing.Drawing2D.LineCap]::Round
$pen.LineJoin=[Drawing.Drawing2D.LineJoin]::Round
$graphics.DrawLine($pen,80,176,175,81)
$graphics.DrawLine($pen,108,80,176,80)
$graphics.DrawLine($pen,176,80,176,148)
$png=[IO.MemoryStream]::new();$bitmap.Save($png,[Drawing.Imaging.ImageFormat]::Png)
$assets=Join-Path $root 'desktop/assets';New-Item -ItemType Directory -Path $assets -Force | Out-Null
$file=[IO.File]::Create((Join-Path $assets 'app_icon.ico'));$writer=[IO.BinaryWriter]::new($file)
try{
 $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]1)
 $writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([byte]0)
 $writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$png.Length);$writer.Write([uint32]22);$writer.Write($png.ToArray())
}finally{$writer.Dispose();$file.Dispose();$pen.Dispose();$brush.Dispose();$path.Dispose();$graphics.Dispose();$bitmap.Dispose();$png.Dispose()}
Write-Output 'Generated own silver/cobalt product icon.'
