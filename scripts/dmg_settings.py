# dmgbuild settings for the iOS Build Manager installer.
#
# dmgbuild writes the .DS_Store bytes directly instead of driving Finder's
# GUI — deterministic and works headless (CI), unlike osascript-driven
# Finder automation which was found to intermittently drop the background/
# icon-position metadata depending on Finder's live window-cache state.
#
# Usage: dmgbuild -s scripts/dmg_settings.py \
#          -D app=path/to/App.app \
#          -D background=path/to/background.png \
#          -D volicon=path/to/AppIcon.icns \
#          "Volume Name" out.dmg
import os.path

application = defines.get("app")
background_image = defines.get("background")
volume_icon = defines.get("volicon")
app_name = os.path.basename(application)

files = [application]
symlinks = {"Applications": "/Applications"}

# Volume icon → shown in the DMG's title bar and as the mounted-disk icon.
if volume_icon:
    icon = volume_icon

# Geometry — the background image is 720×564 (content area). The window's
# total height includes the ~28pt title bar, so the window is 28pt taller than
# the background or the bottom (footer) row gets clipped.
window_rect = ((120, 120), (720, 592))
icon_size = 128
background = background_image
icon_locations = {
    app_name: (205, 250),
    "Applications": (515, 250),
}

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
text_size = 13

format = "UDZO"
compression_level = 9
