// Live2DViewerEX (Steam/Proton) as a Plasma wallpaper - KWin side.
//
// The viewer draws its wallpaper into an ordinary full-screen window ("UnityContainer"). Shown as it is, that
// window covers Plasma's desktop: no icons, no desktop menu. This script
//   1. keeps that window exactly over its screen and below every other window, and marks it so that the effect
//      "live2dviewerex-hide" stops drawing it. It has to stay in place rather than be moved away: the viewer works
//      out what is under the mouse (its menu button, drag handles) from its own window position.
//      The window ignores the mouse by itself, so clicks land on Plasma's desktop underneath.
//   2. tells the Plasma wallpaper plugin "local.live2dviewerex.stream" which window to show - the plugin displays
//      its live picture in the wallpaper layer, under the icons,
//   3. tells the viewer where the cursor is, anywhere on screen, through l2dex-bridge (D-Bus). On Windows the
//      viewer gets this from a global mouse hook, which sees nothing under Wayland.
// Meta+Alt+L shows the real window as a normal window and hides it again.
var APP_CLASS = "steam_app_616720";
var PLUGIN = "local.live2dviewerex.stream";
var EFFECT = "live2dviewerex-hide";
var BRIDGE = "local.l2dex.Bridge";

var managed = {};       // internalId -> { w: window, home: output the viewer opened on }
var count = 0;
var hiddenMode = true;

function sameRect(a, b) { return a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height; }

// The wallpaper window opens as "UnityContainer" and is renamed "Live2DViewerEX" once the player is inside it.
// In the viewer's "Window" launch mode the player's own window carries that second name too, but it has a title
// bar and must stay an ordinary window - so under that name only a borderless window that fills a screen is taken
// (how the wallpaper window looks, also after this script was reloaded).
function isApp(w) {
    if (!w.normalWindow || w.resourceClass != APP_CLASS) return false;
    if (w.caption == "UnityContainer") return true;
    // Wallpaper launch mode: the player sits inside progman_shim's "Program Manager" window, shown over all screens
    if (w.caption == "Program Manager") return true;
    if (w.caption != "Live2DViewerEX" || !w.noBorder) return false;
    return w.fullScreen || sameRect(w.frameGeometry, (w.output || workspace.activeScreen).geometry);
}

function publish(uuid) {
    var js = "desktops().forEach(function (d) { if (d.wallpaperPlugin == '" + PLUGIN + "') {" +
             " d.currentConfigGroup = ['Wallpaper', '" + PLUGIN + "', 'General'];" +
             " d.writeConfig('WindowUuid', '" + uuid + "'); d.reloadConfig(); } });";
    callDBus("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript", js);
}

// the effect looks at the marks set below; ask it to look again
function recheckEffect() {
    callDBus("org.kde.KWin", "/Effects", "org.kde.kwin.Effects", "loadEffect", EFFECT);
    callDBus("org.kde.KWin", "/Effects", "org.kde.kwin.Effects", "reconfigureEffect", EFFECT);
}

function homeRect(m) {
    var g = (m.home || workspace.activeScreen).geometry;
    return { x: g.x, y: g.y, width: g.width, height: g.height };
}

// in place, under everything, marked for the effect. KWin's fullscreen state stays off: Wine asks for it for
// any window that fills a monitor, and a fullscreen window keeps auto-hide panels from showing.
function hide(m) {
    var w = m.w;
    w.noBorder = true; w.skipTaskbar = true; w.skipPager = true; w.skipSwitcher = true;
    w.fullScreen = false; w.keepAbove = false; w.keepBelow = true; w.onAllDesktops = true;
    w.frameGeometry = homeRect(m);
}

function show(m) {
    var w = m.w, g = workspace.activeScreen.geometry;
    w.keepBelow = false; w.noBorder = false; w.skipTaskbar = false; w.skipPager = false; w.skipSwitcher = false;
    w.onAllDesktops = false;
    w.frameGeometry = { x: g.x + g.width / 8, y: g.y + g.height / 8, width: g.width * 3 / 4, height: g.height * 3 / 4 };
    workspace.activeWindow = w;
}

function apply(m) {
    if (hiddenMode) hide(m); else show(m);
    recheckEffect();
}

function desktopOf(m) {
    var all = workspace.windowList();
    for (var i = 0; i < all.length; i++) if (all[i].desktopWindow && all[i].output == m.home) return all[i];
    return null;
}

// An unseen window must not hold the keyboard. KWin activates it when it opens, and may pick it when another
// window closes: give the keyboard back to the window that had it, or to the desktop.
var recent = [];        // the last two windows that had the keyboard, newest first
workspace.windowActivated.connect(function (w) { if (w && w !== recent[0]) recent = [w, recent[0]]; });

function unfocus(m) {
    if (!hiddenMode || !m.w.active) return;
    var t = desktopOf(m);
    for (var i = recent.length - 1; i >= 0; i--) {      // the viewer's window may itself be in the list
        var r = recent[i];
        if (r && !r.deleted && !r.minimized && !managed[r.internalId.toString()]) t = r;
    }
    if (t) workspace.activeWindow = t;
}

function take(w) {
    var id = w.internalId.toString();
    if (managed[id] || !isApp(w)) return;
    var m = managed[id] = { w: w, home: w.output || workspace.activeScreen };
    count++;
    apply(m);
    // Wine re-sends its own idea of position and state now and then: put ours back
    w.frameGeometryChanged.connect(function () {
        if (hiddenMode && managed[id] && (w.fullScreen || !sameRect(w.frameGeometry, homeRect(m)))) hide(m);
    });
    w.fullScreenChanged.connect(function () { if (hiddenMode && managed[id] && w.fullScreen) hide(m); });
    w.keepBelowChanged.connect(function () { if (hiddenMode && managed[id] && !w.keepBelow) { w.keepBelow = true; recheckEffect(); } });
    w.keepAboveChanged.connect(function () { if (hiddenMode && managed[id] && w.keepAbove) hide(m); });
    w.activeChanged.connect(function () { if (managed[id]) unfocus(m); });
    w.closed.connect(function () {
        if (!managed[id]) return;
        delete managed[id];
        count--;
        if (!count) publish("");
    });
    publish(id);
    callDBus(BRIDGE, "/Bridge", BRIDGE, "Event", "");    // starts the bridge now, and with it the tray icon
    unfocus(m);
}

function watch(w) {
    take(w);
    w.captionChanged.connect(function () { take(w); });
}

// Cursor -> bridge, at most once per frame and only while the viewer's wallpaper exists: "p X Y H" with X,Y from
// the top-left of the whole screen area and H its height (the viewer counts from the bottom). A capital "P"
// means the cursor is over the bare desktop; only then is Wine's own cursor moved along, which the viewer's
// buttons and drag handles go by. Over other windows Wine's cursor is left alone, so that X11 programs lying
// under a Wayland window do not react to a pointer that is not really on them.
function overDesktop(p) {
    var top = workspace.windowAt(p, 1);
    if (!top || !top.length) return true;
    return top[0].desktopWindow || !!managed[top[0].internalId.toString()];
}

var lastSent = "";
var feed = new QTimer();
feed.interval = 16;
feed.singleShot = true;
feed.timeout.connect(function () {
    if (!count) return;
    var p = workspace.cursorPos, v = workspace.virtualScreenGeometry;
    var s = (hiddenMode && overDesktop(p) ? "P " : "p ") + Math.round(p.x - v.x) + " " + Math.round(p.y - v.y) + " " + v.height;
    if (s == lastSent) return;
    lastSent = s;
    callDBus(BRIDGE, "/Bridge", BRIDGE, "Event", s);
});
workspace.cursorPosChanged.connect(function () { if (count && !feed.active) feed.start(); });

registerShortcut("Live2DViewerEX wallpaper toggle", "Live2DViewerEX: show the real window / hide it again", "Meta+Alt+L", function () {
    hiddenMode = !hiddenMode;
    for (var id in managed) apply(managed[id]);
});

workspace.windowList().forEach(watch);
workspace.windowAdded.connect(watch);
if (!count) publish("");        // nothing running: make sure the wallpaper is not waiting for an old window
