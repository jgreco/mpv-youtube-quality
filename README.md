# youtube-quality
A userscript for MPV that allows you to change youtube video quality (ytdl-format) on the fly, as though you were using the web player.

![screenshot](quality-menu.png)

Toggle the menu with ctrl+f (configurable).   Select from the list (configurable) with the arrow keys, and press enter to select.  Menu times out after 10 seconds (configurable).

## Plans For Future Enhancement
- [x] Visual indication of what the current quality level is.
- [ ] Option to populate the quality list automatically with the exact formats available for a given video.

## Credit
- [reload.lua](https://github.com/4e6/mpv-reload/) for the function to reload a video while preserving the playlist.
- [mpv-playlistmanager](https://github.com/jonniek/mpv-playlistmanager), from which I ripped off much of the menu formatting config.
- somebody on /mpv/ for the idea
