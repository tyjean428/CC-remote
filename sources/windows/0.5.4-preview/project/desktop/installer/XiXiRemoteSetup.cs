using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

namespace XiXiRemote.Setup {
 public sealed class ProductManifest {public int schemaVersion; public string product,version,entryPoint;public ProductFile[] files;}
 public sealed class ProductFile {public string path,sha256;public long bytes;}
 public static class Installer {
  const string Version="0.5.4-preview";
  const string RegistryPath=@"Software\Microsoft\Windows\CurrentVersion\Uninstall\XiXiRemote";
  public static string Root {get{return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Programs","XiXiRemote");}}
  public static string App {get{return Path.Combine(Root,"app-"+Version);}}
  public static string Exe {get{return Path.Combine(App,"XiXiRemote.exe");}}
  static string Hash(byte[] b){using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(b)).Replace("-","").ToLowerInvariant();}
  static void NoReparse(string path) {var d=new DirectoryInfo(path);while(d!=null){if(d.Exists&&(d.Attributes&FileAttributes.ReparsePoint)!=0)throw new InvalidDataException("安装路径不能是重定向目录。");d=d.Parent;}}
  public static string SafeRelative(string root,string name){
   if(String.IsNullOrEmpty(name)||name.Contains("\\")||name.StartsWith("/")||name.Contains(":")||name.Contains("\0"))throw new InvalidDataException("安装文件路径不正确。");
   foreach(var p in name.Split('/'))if(p==".."||p=="."||p.Length==0)throw new InvalidDataException("安装路径包含上级目录。");
   string result=Path.GetFullPath(Path.Combine(root,name));
   if(!result.StartsWith(Path.GetFullPath(root)+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("安装文件超出产品目录。");
   return result;
  }
  static ProductManifest Validate(byte[] archive) {
   using(var stream=new MemoryStream(archive))using(var zip=new ZipArchive(stream,ZipArchiveMode.Read)){
    var item=zip.GetEntry("product-manifest.json");if(item==null||item.Length>131072)throw new InvalidDataException("安装清单不存在或过大。");
    ProductManifest m;using(var reader=new StreamReader(item.Open(),new UTF8Encoding(false,true)))m=new JavaScriptSerializer().Deserialize<ProductManifest>(reader.ReadToEnd());
    if(m==null||m.schemaVersion!=1||m.product!="XiXiRemote"||m.version!=Version||m.entryPoint!="XiXiRemote.exe"||m.files==null||m.files.Length<8)throw new InvalidDataException("安装包产品身份不一致。");
    var paths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);long total=0;
    foreach(var f in m.files){SafeRelative(App,f.path);if(!paths.Add(f.path)||f.bytes<1||f.bytes>536870912)throw new InvalidDataException("安装清单重复或大小无效。");total+=f.bytes;if(total>1073741824)throw new InvalidDataException("安装包过大。");
     var entry=zip.GetEntry(f.path);if(entry==null||entry.Length!=f.bytes)throw new InvalidDataException("安装文件不完整："+f.path);
     using(var input=entry.Open())using(var data=new MemoryStream()){input.CopyTo(data);if(Hash(data.ToArray())!=f.sha256)throw new InvalidDataException("安装文件校验失败："+f.path);}
    }
    if(zip.Entries.Count!=m.files.Length+1||!paths.Contains("librustdesk.dll")||!paths.Contains("data/app.so")||!paths.Contains("LICENSE-AGPL-3.0.txt")||!paths.Contains("XiXiRemote-source.zip"))throw new InvalidDataException("安装包缺少引擎、源码或许可。");
    return m;
   }
  }
  static byte[] Payload(){using(var s=Assembly.GetExecutingAssembly().GetManifestResourceStream("XiXiRemote.Payload")){if(s==null)throw new InvalidDataException("内置产品文件不存在。");using(var b=new MemoryStream()){s.CopyTo(b);return b.ToArray();}}}
  static void EnsureStopped(){foreach(var p in Process.GetProcessesByName("XiXiRemote")){using(p){string path;try{path=p.MainModule.FileName;}catch{throw new InvalidOperationException("请先关闭正在运行的西西远程再安装。");}if(path.StartsWith(Root+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("请先从西西远程退出，再更新或卸载。");}}}
  static bool Owned(){var path=Path.Combine(Root,".xixi-product.json");if(!File.Exists(path))return false;try{var m=new JavaScriptSerializer().Deserialize<ProductManifest>(File.ReadAllText(path,Encoding.UTF8));return m!=null&&m.schemaVersion==1&&m.product=="XiXiRemote";}catch{return false;}}
  static void SetCom(object obj,string key,object value){obj.GetType().InvokeMember(key,BindingFlags.SetProperty,null,obj,new[]{value});}
  static void Shortcut(string path){var t=Type.GetTypeFromProgID("WScript.Shell");var shell=Activator.CreateInstance(t);var link=t.InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,null,shell,new object[]{path});SetCom(link,"TargetPath",Exe);SetCom(link,"WorkingDirectory",App);SetCom(link,"IconLocation",Exe+",0");SetCom(link,"Description","西西远程");link.GetType().InvokeMember("Save",BindingFlags.InvokeMethod,null,link,null);}
  public static void Install(){
   NoReparse(Root);if(Directory.Exists(Root)&&!Owned())throw new InvalidOperationException("目标目录已有非本产品文件，已保留，请先检查。");EnsureStopped();
   var payload=Payload();var manifest=Validate(payload);
   Directory.CreateDirectory(Root);Directory.CreateDirectory(App);
   // Mark ownership before copying so an interrupted first install can be retried.
   File.WriteAllText(Path.Combine(Root,".xixi-product.json"),new JavaScriptSerializer().Serialize(manifest),new UTF8Encoding(false));
   using(var stream=new MemoryStream(payload))using(var zip=new ZipArchive(stream,ZipArchiveMode.Read))foreach(var f in manifest.files){
    var path=SafeRelative(App,f.path);NoReparse(Path.GetDirectoryName(path));Directory.CreateDirectory(Path.GetDirectoryName(path));
    using(var input=zip.GetEntry(f.path).Open())using(var output=new FileStream(path,FileMode.Create,FileAccess.Write,FileShare.None)){input.CopyTo(output);output.Flush(true);}
   }
   File.WriteAllText(Path.Combine(Root,".xixi-product.json"),new JavaScriptSerializer().Serialize(manifest),new UTF8Encoding(false));
   string self=Assembly.GetExecutingAssembly().Location;string support=Path.Combine(Root,"XiXiRemoteSetup.exe");if(!String.Equals(Path.GetFullPath(self),support,StringComparison.OrdinalIgnoreCase))File.Copy(self,support,true);
   using(var key=Registry.CurrentUser.CreateSubKey(RegistryPath)){key.SetValue("DisplayName","西西远程");key.SetValue("DisplayVersion",Version);key.SetValue("Publisher","XiXi Remote");key.SetValue("InstallLocation",Root);key.SetValue("DisplayIcon",Exe);key.SetValue("UninstallString","\""+support+"\" --uninstall");key.SetValue("NoModify",1,RegistryValueKind.DWord);key.SetValue("NoRepair",1,RegistryValueKind.DWord);}
   Shortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"西西远程.lnk"));
   var menu=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),"Programs","西西远程");Directory.CreateDirectory(menu);Shortcut(Path.Combine(menu,"西西远程.lnk"));
   File.WriteAllText(Path.Combine(Root,"installation-status.json"),new JavaScriptSerializer().Serialize(new{product="XiXiRemote",version=Version,installedAtUtc=DateTime.UtcNow.ToString("o"),entryPoint=Exe,bundledEngine=true,externalRustDeskRequired=false}),new UTF8Encoding(false));
  }
  public static void Uninstall(){
   NoReparse(Root);if(!Owned())throw new InvalidOperationException("没有发现本产品的有效安装记录。");EnsureStopped();
   // Work from a private temporary copy so the running uninstaller does not lock
   // the product tree. The deletion target is always the exact owned product root.
   if(Assembly.GetExecutingAssembly().Location.StartsWith(Root+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)){
    string temp=Path.Combine(Path.GetTempPath(),"XiXiRemote-Uninstall-"+Guid.NewGuid().ToString("N")+".exe");File.Copy(Assembly.GetExecutingAssembly().Location,temp);
    Process.Start(new ProcessStartInfo(temp,"--uninstall-owned"){UseShellExecute=false});return;
   }
   foreach(var p in Directory.GetFileSystemEntries(Root,"*",SearchOption.AllDirectories))if((File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)throw new InvalidDataException("产品目录包含重定向文件，已保留。");
   Directory.Delete(Root,true);Registry.CurrentUser.DeleteSubKeyTree(RegistryPath,false);
   string shortcut=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"西西远程.lnk");if(File.Exists(shortcut))File.Delete(shortcut);
   var menu=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),"Programs","西西远程");var menuShortcut=Path.Combine(menu,"西西远程.lnk");if(File.Exists(menuShortcut))File.Delete(menuShortcut);if(Directory.Exists(menu)&&Directory.GetFileSystemEntries(menu).Length==0)Directory.Delete(menu);
  }
  public static int CheckPayload(){var p=Payload();Validate(p);Console.WriteLine("PASS: independent product payload, hashes, paths, native engine, source and license");return 0;}
  public static int SelfTest(){string[] bad={"../outside.exe","/outside","C:/outside","a/../outside","a\\b","a//b"};foreach(var p in bad){try{SafeRelative(App,p);return 1;}catch(InvalidDataException){}}SafeRelative(App,"data/app.so");return CheckPayload();}
 }
 public sealed class SilverInstallButton:Button {
  bool pressed;
  public SilverInstallButton(){FlatStyle=FlatStyle.Flat;FlatAppearance.BorderSize=0;Cursor=Cursors.Hand;SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);}
  protected override void OnMouseDown(MouseEventArgs e){pressed=true;Invalidate();base.OnMouseDown(e);}
  protected override void OnMouseUp(MouseEventArgs e){pressed=false;Invalidate();base.OnMouseUp(e);}
  protected override void OnMouseLeave(EventArgs e){pressed=false;Invalidate();base.OnMouseLeave(e);}
  protected override void OnPaint(PaintEventArgs e){e.Graphics.Clear(Parent.BackColor);e.Graphics.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
   int shift=pressed?2:0;var r=new Rectangle(1,1+shift,Width-3,Height-5);using(var path=new System.Drawing.Drawing2D.GraphicsPath()){
    int d=20;path.AddArc(r.Left,r.Top,d,d,180,90);path.AddArc(r.Right-d,r.Top,d,d,270,90);path.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);path.AddArc(r.Left,r.Bottom-d,d,d,90,90);path.CloseFigure();
    using(var brush=new System.Drawing.Drawing2D.LinearGradientBrush(r,Enabled?Color.FromArgb(56,116,255):Color.FromArgb(150,169,204),Enabled?Color.FromArgb(23,75,210):Color.FromArgb(130,150,186),90))e.Graphics.FillPath(brush,path);
    using(var pen=new Pen(Color.FromArgb(23,74,202)))e.Graphics.DrawPath(pen,path);
    using(var pen=new Pen(Color.FromArgb(100,255,255,255)))e.Graphics.DrawLine(pen,r.Left+12,r.Top+1,r.Right-12,r.Top+1);
   }TextRenderer.DrawText(e.Graphics,Text,Font,r,Color.White,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine);
  }
 }
 public sealed class SetupForm:Form {
  readonly Button install=new SilverInstallButton();readonly Label state=new Label();
  public SetupForm(){Text="安装西西远程";Size=new Size(550,380);MinimumSize=Size;StartPosition=FormStartPosition.CenterScreen;BackColor=Color.FromArgb(246,247,250);Font=new Font("Microsoft YaHei UI",10);MaximizeBox=false;
   var title=new Label{Text="西西远程",Font=new Font("Microsoft YaHei UI",23,FontStyle.Bold),ForeColor=Color.FromArgb(34,44,64),Location=new Point(32,28),AutoSize=true};Controls.Add(title);
   var desc=new Label{Text="一个软件，连接你的电脑和手机。\r\n远控引擎和服务器配置已经内置，无需另装其它客户端。",Location=new Point(34,90),Size=new Size(465,63),ForeColor=Color.FromArgb(100,112,133)};Controls.Add(desc);
   state.Text="安装到当前用户目录，无需管理员权限。";state.Location=new Point(34,175);state.Size=new Size(465,66);Controls.Add(state);
   install.Text="安装西西远程";install.Location=new Point(34,258);install.Size=new Size(465,48);install.FlatStyle=FlatStyle.Flat;install.FlatAppearance.BorderColor=Color.FromArgb(23,74,202);install.BackColor=Color.FromArgb(36,91,234);install.ForeColor=Color.White;install.Click+=InstallClicked;Controls.Add(install);
  }
  async void InstallClicked(object sender,EventArgs args){install.Enabled=false;state.Text="正在核验并安装内置组件…";try{await System.Threading.Tasks.Task.Run(()=>Installer.Install());state.Text="安装完成。输入对方 ID，即可发起连接。";install.Text="打开西西远程";install.Click-=InstallClicked;install.Click+=delegate{Process.Start(new ProcessStartInfo(Installer.Exe){WorkingDirectory=Installer.App,UseShellExecute=true});Close();};}catch(Exception ex){state.Text="安装未完成："+ex.Message;}finally{install.Enabled=true;}}
 }
 public static class Program {
  [STAThread]public static int Main(string[] args){try{
   if(args.Length==1&&args[0]=="--self-test")return Installer.SelfTest();
   if(args.Length==1&&args[0]=="--verify-payload")return Installer.CheckPayload();
   if(args.Length==1&&args[0]=="--install"){Installer.Install();return 0;}
   if(args.Length==1&&(args[0]=="--uninstall"||args[0]=="--uninstall-owned")){if(args[0]=="--uninstall"&&MessageBox.Show("卸载西西远程？本机设备及连接数据会保留。","西西远程",MessageBoxButtons.OKCancel)!=DialogResult.OK)return 0;Installer.Uninstall();return 0;}
   Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new SetupForm());return 0;
  }catch(Exception ex){if(args.Length>0){Console.Error.WriteLine(ex.Message);return 1;}MessageBox.Show(ex.Message,"西西远程");return 1;}}
 }
}
