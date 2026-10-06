[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$source=Join-Path $projectRoot 'tools/rustdesk/rustdesk.exe'
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -cne '8555777215510d83d2d61c9dc984e4fcc838bd7e79f9d18a42585431f5e8bb47') { throw 'Pinned upstream archive differs.' }
$destination=Join-Path $projectRoot 'tools/desktop-build/native'
if (Test-Path -LiteralPath $destination) {
    if (-not (Test-Path -LiteralPath (Join-Path $destination '.xixi-engine.json'))) { throw 'Engine cache has no ownership record.' }
}
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
public static class XiXiEngineExtractor {
    public sealed class Entry { public string path; public byte[] data; public string sha256; }
    static int Int32At(byte[] b, int p) { if (p<0 || p>b.Length-4) throw new InvalidDataException(); long n=((long)b[p]<<24)|((long)b[p+1]<<16)|((long)b[p+2]<<8)|b[p+3]; if(n>int.MaxValue)throw new InvalidDataException();return (int)n; }
    static bool Header(byte[] b,int p) { var h=Encoding.ASCII.GetBytes("rustdesk"); if(p>b.Length-8)return false;for(int j=0;j<8;j++)if(b[p+j]!=h[j])return false;return true; }
    static List<Entry> Parse(byte[] b,int start) {
        int p=start+8;var entries=new List<Entry>();var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        while(!Header(b,p)) {
            if(entries.Count>2000)throw new InvalidDataException();int n=Int32At(b,p);p+=4;if(n<1||n>1024||p>b.Length-n)throw new InvalidDataException();
            string name=new UTF8Encoding(false,true).GetString(b,p,n).Replace('\\','/');p+=n;while(name.StartsWith("./"))name=name.Substring(2);
            if(name.StartsWith("/")||name.Contains(":")||name.Contains("../")||name.Contains("\0")||!names.Add(name))throw new InvalidDataException();
            int len=Int32At(b,p);p+=4;if(len<1||p>b.Length-len-32)throw new InvalidDataException();
            byte[] data;using(var input=new MemoryStream(b,p,len,false))using(var decoder=new BrotliStream(input,CompressionMode.Decompress))using(var output=new MemoryStream()) { var buf=new byte[65536];int count;while((count=decoder.Read(buf,0,buf.Length))>0){output.Write(buf,0,count);if(output.Length>536870912)throw new InvalidDataException();}data=output.ToArray(); }
            p+=len;string md5=Encoding.ASCII.GetString(b,p,32);p+=32;
            using(var h=MD5.Create())if(BitConverter.ToString(h.ComputeHash(data)).Replace("-","").ToLowerInvariant()!=md5)throw new InvalidDataException("Payload checksum differs.");
            string sha;using(var h=SHA256.Create())sha=BitConverter.ToString(h.ComputeHash(data)).Replace("-","").ToLowerInvariant();
            entries.Add(new Entry{path=name,data=data,sha256=sha});
        }
        if(entries.Count<18||!entries.Exists(e=>e.path=="librustdesk.dll"&&e.sha256=="da4889603c26c6c29fdaa4bb3aec857f9e714e9e795a2c031184bff78fe7c597"))throw new InvalidDataException("Pinned native library missing.");
        return entries;
    }
    public static List<Entry> Read(string file) { var b=File.ReadAllBytes(file);for(int p=0;p<b.Length-8;p++)if(Header(b,p)){try{return Parse(b,p);}catch(InvalidDataException){}catch(ArgumentException){}}throw new InvalidDataException("No valid pinned portable payload."); }
}
'@
$entries=[XiXiEngineExtractor]::Read($source)
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$records=@()
foreach ($entry in $entries) {
    $path=[IO.Path]::GetFullPath((Join-Path $destination $entry.path))
    if (-not $path.StartsWith($destination+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Payload escaped cache.' }
    New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
    [IO.File]::WriteAllBytes($path,$entry.data)
    $records += [ordered]@{path=$entry.path;bytes=$entry.data.Length;sha256=$entry.sha256}
}
[ordered]@{schemaVersion=1;sourceSha256='8555777215510d83d2d61c9dc984e4fcc838bd7e79f9d18a42585431f5e8bb47';nativeSha256='da4889603c26c6c29fdaa4bb3aec857f9e714e9e795a2c031184bff78fe7c597';files=$records} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destination '.xixi-engine.json') -Encoding utf8
Write-Output ('Extracted and checksum-verified '+$records.Count+' payload files. No installer or engine was launched.')
