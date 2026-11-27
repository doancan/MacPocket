"""Finder layout, written without Finder automation so release builds work without a GUI session."""
from pathlib import Path

app = str(Path(defines["app"]).resolve())
files = [app]
symlinks = {"Applications": "/Applications"}
format = "UDZO"
filesystem = "HFS+"
icon = str(Path(app) / "Contents/Resources/AppIcon.icns")
background = defines["background"]
# The macOS 27 title bar and toolbar take 68 pt above the 720 × 480 artwork. A Finder with the path bar and status
# bar turned on takes another 56 pt below, so the artwork keeps everything that matters in its top 424 pt.
window_rect = ((200, 200), (720, 548))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
icon_size = 112
text_size = 13
label_pos = "bottom"
arrange_by = None
icon_locations = {Path(app).name: (200, 212), "Applications": (520, 212)}
# Do not set FinderInfo on the signed app: codesign --strict rejects those attributes.
