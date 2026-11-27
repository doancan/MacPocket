"""Finder layout, written without Finder automation so release builds work without a GUI session."""
from pathlib import Path

app = str(Path(defines["app"]).resolve())
files = [app]
symlinks = {"Applications": "/Applications"}
format = "UDZO"
filesystem = "HFS+"
icon = str(Path(app) / "Contents/Resources/AppIcon.icns")
background = defines["background"]
# Reserve the native Finder title bar above the 720 × 480 artwork.
window_rect = ((200, 200), (720, 508))
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
icon_locations = {Path(app).name: (200, 232), "Applications": (520, 232)}
# Do not set FinderInfo on the signed app: codesign --strict rejects those attributes.
