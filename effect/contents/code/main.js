// Live2DViewerEX wallpaper window: not drawn on screen.
//
// The viewer's window has to stay where the picture is - exactly over its screen - because the viewer works out
// what is under the mouse from its own window position. The KWin script "live2dviewerex-wallpaper" puts it there,
// below every other window, and marks it (keep below + not in the window switcher + no title bar). This effect
// draws marked windows with opacity 0. An effect's opacity is applied only when the screen is painted, so the
// window's live stream, which the wallpaper plugin shows under the icons, still has the full picture.
// The window ignores the mouse by itself (click-through), so everything on the desktop stays reachable.
"use strict";

var APP_CLASS = "steam_app_616720";

function marked(w) {
    return !w.deleted && String(w.windowClass).indexOf(APP_CLASS) != -1 && !w.hasDecoration &&
           ((w.keepBelow && w.skipSwitcher) || w.caption == "UnityContainer" || w.caption == "Program Manager");
}

function update(w) {
    if (marked(w)) {
        if (!w.l2dexHidden)
            w.l2dexHidden = set({ window: w, duration: 1, keepAlive: false,
                                  animations: [{ type: Effect.Opacity, from: 0.0, to: 0.0 }] });
    } else if (w.l2dexHidden) {
        cancel(w.l2dexHidden);
        delete w.l2dexHidden;
    }
}

function updateAll() { effects.stackingOrder.forEach(update); }

effects.windowAdded.connect(update);
effect.configChanged.connect(updateAll);     // the KWin script asks for a re-check (reconfigureEffect) after marking
updateAll();
