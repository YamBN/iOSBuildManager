# dmgbuild settings for the iOS Build Manager installer.
#
# dmgbuild writes the .DS_Store bytes directly instead of driving Finder's
# GUI — deterministic and works headless (CI), unlike osascript-driven
# Finder automation which was found to intermittently drop the background/
# icon-position metadata depending on Finder's live window-cache state.
#
# Usage: dmgbuild -s scripts/dmg_settings.py -D app=path/to/App.app \
#          -D background=path/to/background.png "Volume Name" out.dmg
import os.path

application = defines.get("app")
background_image = defines.get("background")
app_name = os.path.basename(application)

files = [application]
symlinks = {"Applications": "/Applications"}

# Must match the background image's own layout (scripts/render_dmg_background.swift).
window_rect = ((100, 100), (660, 420))
icon_size = 128
background = background_image
icon_locations = {
    app_name: (160, 185),
    "Applications": (490, 185),
}

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"

format = "UDZO"
compression_level = 9
