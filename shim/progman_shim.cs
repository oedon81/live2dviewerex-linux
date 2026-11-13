// progman_shim v5 - Steam launch target for Live2DViewerEX under Proton (Linux).
//
// 1. The viewer's tray program (lwtray.exe) refuses to start its wallpaper until it finds Explorer's desktop
//    window (class "Progman"), which Wine does not have. This creates a hidden window of that class, runs
//    launcher.exe with the same arguments, and exits 15 s after lwtray.exe is gone (60 s if it never appeared)
//    so Steam sees the app close.
//    v5: the Progman window also holds the children Explorer has on Windows 11 24H2 - "SHELLDLL_DefView" and
//    "WorkerW" - so the viewer's Wallpaper launch mode finds its desktop window (else: DESKWND_NOT_FOUND). In
//    that mode the player is put inside WorkerW; Progman is then shown over all screens (click-through, the KWin
//    script keeps it at the bottom and the effect hides it) and hidden again when the player is gone.
// 2. It is the Linux side's hand inside Wine. l2dex-bridge sends one-line UDP datagrams to 127.0.0.1:48398:
//      "c X Y"     move Wine's cursor. Under Wayland Wine only learns the pointer position while it is over one
//                  of its own windows; the viewer's on-wallpaper buttons and drag handles go by Wine's cursor.
//      "run NAME"  start one of the viewer's own tools the way its tray menu does:
//                  lwui (Control Panel), exstudio, motiontracker, instancemanager. Nothing else can be started.
// 3. Wine's own tray icon for the viewer is switched off (Windows policy NoTrayItemsDisplay in this prefix, which
//    only this program uses): the bridge provides a native Plasma tray icon and menu instead.
//    Put L2D_WINE_TRAY=1 in the Steam launch options to get the Wine icon back.
// Set L2D_SHIM_LOG=1 in the Steam launch options to log to progman_shim.log next to this exe.
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32;

class P {
    const int PORT = 48398;

    delegate IntPtr WndProc(IntPtr h, uint m, IntPtr w, IntPtr l);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WNDCLASS { public uint style; public WndProc proc; public int cls, wnd; public IntPtr inst, icon, cursor, bg; public string menu, name; }
    [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr h; public uint m; public IntPtr w, l; public uint t; public int x, y; }

    [DllImport("user32", CharSet = CharSet.Unicode)] static extern ushort RegisterClassW(ref WNDCLASS c);
    [DllImport("user32", CharSet = CharSet.Unicode)] static extern IntPtr CreateWindowExW(uint ex, string c, string n, uint s, int x, int y, int w, int h, IntPtr p, IntPtr m, IntPtr i, IntPtr a);
    [DllImport("user32")] static extern IntPtr DefWindowProcW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32")] static extern int PeekMessageW(out MSG m, IntPtr h, uint a, uint b, uint r);
    [DllImport("user32")] static extern int TranslateMessage(ref MSG m);
    [DllImport("user32")] static extern IntPtr DispatchMessageW(ref MSG m);
    [DllImport("user32")] static extern uint MsgWaitForMultipleObjects(uint n, IntPtr h, bool all, uint ms, uint mask);
    [DllImport("user32")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hh, uint f);
    [DllImport("user32")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32")] static extern int GetSystemMetrics(int i);
    [DllImport("user32")] static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);

    static WndProc keep = (h, m, w, l) => DefWindowProcW(h, m, w, l);   // held so the delegate is not collected
    static string dir, logPath;

    static void Log(string s) {
        if (logPath == null) return;
        try { File.AppendAllText(logPath, DateTime.Now.ToString("HH:mm:ss ") + s + "\r\n"); } catch { }
    }

    static void WineTray(bool show) {
        try {
            using (var k = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
                if (show) k.DeleteValue("NoTrayItemsDisplay", false);
                else k.SetValue("NoTrayItemsDisplay", 1, RegistryValueKind.DWord);
            }
        } catch (Exception e) { Log("tray policy: " + e.Message); }
    }

    static int Setting(string name) {       // bin\system.dat is the tray program's settings, plain JSON
        try {
            var m = Regex.Match(File.ReadAllText(Path.Combine(dir, @"bin\system.dat")), "\"" + name + "\"\\s*:\\s*(-?\\d+)");
            return m.Success ? int.Parse(m.Groups[1].Value) : 0;
        } catch { return 0; }
    }

    // same command lines as lwtray's AppUtil.StartIfNotRunning / ProcessUtil.StartInstanceManager
    static void Run(string name) {
        string exe, proc = name, gpuKey = null, args;
        switch (name) {
            case "lwui": exe = @"bin\lwui\lwui.exe"; gpuKey = "gpuControlPanel"; break;
            case "exstudio": exe = @"bin\exstudio\exstudio.exe"; gpuKey = "gpuExStudio"; break;
            case "motiontracker": exe = @"bin\motiontracker64\motiontracker.exe"; gpuKey = "gpuMotionTracker"; break;
            case "instancemanager": exe = "InstanceManager.exe"; proc = "InstanceManager"; break;
            default: Log("run: unknown tool " + name); return;
        }
        if (Process.GetProcessesByName(proc).Length > 0) { Log("run: " + name + " is already running"); return; }
        if (gpuKey == null) args = CultureInfo.CurrentUICulture.Name;
        else {
            int api = Setting("graphicApi"), gpu = Setting(gpuKey);
            string g = api == 1 ? "-force-d3d11" : api == 2 ? "-force-d3d11-no-singlethreaded" : "";
            if (gpu > 0) g += " -force-device-index " + (gpu - 1);
            string log = Path.Combine(dir, @"bin\log\" + name + "-" + DateTime.Now.ToString("yyyyMMdd") + ".log");
            args = "-logFile \"" + log + "\" " + g.Trim();
        }
        string path = Path.Combine(dir, exe);
        Process.Start(new ProcessStartInfo(path, args) { WorkingDirectory = Path.Combine(dir, "bin"), UseShellExecute = false });
        Log("run: " + path + " " + args);
    }

    static void Listen() {
        UdpClient udp;
        try { udp = new UdpClient(new IPEndPoint(IPAddress.Loopback, PORT)); }
        catch (Exception e) { Log("udp " + PORT + ": " + e.Message); return; }
        var from = new IPEndPoint(IPAddress.Any, 0);
        while (true) {
            try {
                string[] t = Encoding.ASCII.GetString(udp.Receive(ref from)).Trim().Split(' ');
                if (t[0] == "c" && t.Length >= 3) SetCursorPos(int.Parse(t[1]), int.Parse(t[2]));
                else if (t[0] == "run" && t.Length >= 2) Run(t[1]);
            } catch (Exception e) { Log("udp: " + e.Message); }
        }
    }

    [STAThread]
    static int Main(string[] a) {
        dir = AppDomain.CurrentDomain.BaseDirectory;
        string exe = Path.Combine(dir, "launcher.exe");
        if (Environment.GetEnvironmentVariable("L2D_SHIM_LOG") != null) logPath = Path.Combine(dir, "progman_shim.log");
        string args = "";
        foreach (var s in a) args += "\"" + s + "\" ";

        // before the first window: Wine's explorer reads the policy when it starts, which the first window triggers
        WineTray(Environment.GetEnvironmentVariable("L2D_WINE_TRAY") != null);

        foreach (var cls in new[] { "Progman", "SHELLDLL_DefView", "WorkerW" }) {
            var wc = new WNDCLASS { proc = keep, name = cls };
            if (RegisterClassW(ref wc) == 0) return 2;
        }
        // WS_POPUP|WS_CLIPCHILDREN, WS_EX_LAYERED|WS_EX_TRANSPARENT|WS_EX_NOACTIVATE: never takes the pointer
        IntPtr progman = CreateWindowExW(0x08080020, "Progman", "Program Manager", 0x82000000, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        if (progman == IntPtr.Zero) return 3;
        SetLayeredWindowAttributes(progman, 0, 255, 2);
        // order as on 24H2: DefView first (the viewer looks for it), then WorkerW (the player's parent); WS_CHILD|WS_CLIPCHILDREN
        CreateWindowExW(0, "SHELLDLL_DefView", "", 0x42000000, 0, 0, 0, 0, progman, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        IntPtr workerW = CreateWindowExW(0, "WorkerW", "", 0x42000000, 0, 0, 0, 0, progman, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        SetWindowPos(workerW, IntPtr.Zero, 0, 0, GetSystemMetrics(78), GetSystemMetrics(79), 0x0014 /*SWP_NOZORDER|SWP_NOACTIVATE*/);
        bool shown = false; int sx = 0, sy = 0, sw = 0, sh = 0;

        Process.Start(new ProcessStartInfo(exe, args) { WorkingDirectory = dir, UseShellExecute = false });
        Log("v5: started launcher");
        new Thread(Listen) { IsBackground = true }.Start();

        DateTime lastSeen = DateTime.UtcNow, next = DateTime.MinValue; bool seen = false;
        while (true) {
            MSG m;
            while (PeekMessageW(out m, IntPtr.Zero, 0, 0, 1) != 0) { TranslateMessage(ref m); DispatchMessageW(ref m); }
            // Wallpaper mode: show Progman over all screens while the player sits in WorkerW
            bool want = workerW != IntPtr.Zero && GetWindow(workerW, 5 /*GW_CHILD*/) != IntPtr.Zero;
            int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77), vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);
            if (want && (!shown || vx != sx || vy != sy || vw != sw || vh != sh)) {
                SetWindowPos(progman, (IntPtr)1 /*HWND_BOTTOM*/, vx, vy, vw, vh, 0x0050 /*SWP_NOACTIVATE|SWP_SHOWWINDOW*/);
                // Explorer keeps WorkerW the size of the desktop; at 0x0 it clips the player away
                SetWindowPos(workerW, IntPtr.Zero, 0, 0, vw, vh, 0x0054 /*SWP_NOZORDER|SWP_NOACTIVATE|SWP_SHOWWINDOW*/);
                shown = true; sx = vx; sy = vy; sw = vw; sh = vh;
                Log("wallpaper mode: Progman shown " + vw + "x" + vh);
            } else if (!want && shown) {
                ShowWindow(progman, 0);
                shown = false;
                Log("wallpaper mode: Progman hidden");
            }
            if (DateTime.UtcNow >= next) {
                next = DateTime.UtcNow.AddSeconds(2);
                if (Process.GetProcessesByName("lwtray").Length > 0) { seen = true; lastSeen = DateTime.UtcNow; }
                else if ((DateTime.UtcNow - lastSeen).TotalSeconds > (seen ? 15 : 60)) { Log("lwtray gone, exiting"); return 0; }
            }
            MsgWaitForMultipleObjects(0, IntPtr.Zero, false, 500, 0x4FF);
        }
    }
}
