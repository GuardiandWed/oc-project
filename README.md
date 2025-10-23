# oc-project

oc-project
A Lua-based GUI menu for games in OpenComputers (Minecraft mod). This script creates an interactive dashboard to browse, sort, and launch games loaded from a JSON file. Features custom drawing with rounded rectangles, shadows, gradients, and event handling for a polished user interface.
Features

Game Loading: Parses games from games.json in /home/games (with fallback to default examples if missing).
Card-Based UI: Displays up to 6 games in a 3x2 grid with details like title, creation date, and playtime.
Interactive Elements: Clickable "Play" buttons, selection highlighting, and bottom action buttons (Refresh, Sort, Theme, Play Selected, Delete, Exit).
Sorting: Toggle between alphabetical (A→Z) and by creation date.
Theme Switching: Switch between dark and light themes with background images.
Custom Drawing: Rounded rectangles with shadows, gradient bars, and centered text for a modern look.
Logging and Metrics: Right panel for game details, metrics, and logs.
Fallback Parser: Simple JSON parsing with regex fallback if json lib is unavailable.

Requirements

OpenComputers mod in Minecraft.
Lua environment with libraries: filesystem, unicode, doubleBuffering, serialization, rcui (custom UI lib, assume it's installed or included).
Background images: /home/images/reactorGUI.pic and /home/images/reactorGUI_white.pic.
Optional: json lib for better parsing.