using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Codex Usage Pet")]
[assembly: AssemblyDescription("Animated desktop companion with Codex quota expressions")]
[assembly: AssemblyVersion("2.2.1.0")]
[assembly: AssemblyFileVersion("2.2.1.0")]
internal static class Launcher
{
    [STAThread]
    private static int Main(string[] args)
    {
        bool smoke = args.Length == 1 && args[0] == "--smoke";
        bool first;
        using (var mutex = new Mutex(true, "Local\\CodexUsagePet" + (smoke ? "Smoke" : ""), out first))
        {
            if (!first) return 0;
            try
            {
                string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodexUsagePet", "2.2.1");
                Directory.CreateDirectory(root);
                if (!smoke)
                {
                    foreach (string name in new[] { "settings.json", "preferences.json" })
                    {
                        string oldFile = "";
                        foreach (string version in new[] { "2.2.0", "2.1.2", "2.1.1", "2.1.0", "2.0.0", "1.3.1" })
                        {
                            string candidate = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodexUsagePet", version, name);
                            if (File.Exists(candidate)) { oldFile = candidate; break; }
                        }
                        string newFile = Path.Combine(root, name);
                        if (!File.Exists(newFile) && File.Exists(oldFile)) File.Copy(oldFile, newFile);
                    }
                }
                using (Stream source = Assembly.GetExecutingAssembly().GetManifestResourceStream("pet.zip"))
                using (var archive = new ZipArchive(source, ZipArchiveMode.Read))
                {
                    foreach (var entry in archive.Entries)
                    {
                        string target = Path.GetFullPath(Path.Combine(root, entry.FullName));
                        if (!target.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Invalid package path.");
                        if (String.IsNullOrEmpty(entry.Name)) { Directory.CreateDirectory(target); continue; }
                        Directory.CreateDirectory(Path.GetDirectoryName(target));
                        using (var input = entry.Open())
                        using (var output = File.Create(target)) input.CopyTo(output);
                    }
                }
                string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
                var info = new ProcessStartInfo(powershell,
                    "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + Path.Combine(root, "pet.ps1") + "\"" + (smoke ? " -Smoke" : ""));
                info.WorkingDirectory = root;
                info.UseShellExecute = false;
                info.CreateNoWindow = true;
                info.WindowStyle = ProcessWindowStyle.Hidden;
                info.RedirectStandardOutput = smoke;
                info.RedirectStandardError = smoke;
                using (var child = Process.Start(info))
                {
                    var output = smoke ? child.StandardOutput.ReadToEndAsync() : null;
                    var error = smoke ? child.StandardError.ReadToEndAsync() : null;
                    child.WaitForExit();
                    if (smoke) File.WriteAllText(Path.Combine(root, "smoke.log"), output.Result + error.Result);
                    if (child.ExitCode != 0 && !smoke) MessageBox.Show("The pet could not start. Check that Windows PowerShell and .NET Framework are available.", "Codex Pet");
                    return child.ExitCode;
                }
            }
            catch (Exception ex)
            {
                if (!smoke) MessageBox.Show(ex.Message, "Codex Pet", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
    }
}
