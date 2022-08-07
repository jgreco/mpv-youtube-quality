# quality-menu
A userscript for MPV that allows you to change the streamed video and audio quality (ytdl-format) on the fly.

Simply open the video or audio menu, select your prefered format and confirm your choice. The keybindings for opening the menus are configured in input.conf, and everthing else is configured in quality-menu.conf.

![screenshot](quality-menu-preview-video.jpg)

![screenshot](quality-menu-preview-audio.jpg)

## Features

- Columns and their order are configurable
- All format related information from yt-dlp/youtube-dl can be shown
- Columns that are identical for all formats are automatically hidden
- Formats can be sorted based on resolution, fps, bitrate, etc.
- Currently playing format is marked and selected when opening the menu
- Indentation makes it easy to see which line you're currently on
- Remembers selected format for every url in the current session (e.g. going back to previous playlist item automatically selects the prefered format)
- Controllable entirely by mouse and keyboard (opening and closing the menu by mouse requires the OSC extension)
- Simple reload functionality (for something more sophisticated, go to [reload.lua](https://github.com/4e6/mpv-reload/))

## OSC extension
**(optional)** An extended version of the OSC is available that includes a button to display the quality menu.

![screenshot](quality-menu-preview-osc.jpg)

**PLEASE NOTE:** This conflicts with other scripts that modify the OSC, such as marzzzello's fork of the excellent [mpv_thumbnail_script](https://github.com/marzzzello/mpv_thumbnail_script).  Merging this OSC modification with that script or others is certainly possible, *but is left as an exercise for the user...* (hint: There are two sections markt with `START quality-menu` and `END quality-menu`)


## Installation
1. Save the `quality-menu.lua` into your [scripts directory](https://mpv.io/manual/stable/#script-location)
2. Set key bindings in [`input.conf`](https://mpv.io/manual/stable/#input-conf):

    `Ctrl+f script-binding quality_menu/video_formats_toggle`

    `Alt+f script-binding quality_menu/audio_formats_toggle`

    **(optional)** `Ctrl+r script-binding quality_menu/reload`

3. **(optional)** Save the `quality-menu.conf` into your `script-opts` directory (next to the [scripts directory](https://mpv.io/manual/stable/#script-location), create if it doesn't exist)
4. **(optional)** Save the `quality-menu-osc.lua` into your [scripts directory](https://mpv.io/manual/stable/#script-location)  and put `osc=no` in your [mpv.conf](https://mpv.io/manual/stable/#location-and-syntax)

## Plans For Future Enhancement
- [x] Visual indication of what the current quality level is.
- [x] Option to populate the quality list automatically with the exact formats available for a given video.
- [x] Optional OSC extension.
- [x] Get formats from when mpv calls yt-dlp/youtube-dl to get the video, instead of calling yt-dlp/youtube-dl  again. (implemented on get_json_from_ytdl_hook branch, requires PR for mpv to be merged)
- [ ] Integration into [uosc](https://github.com/darsain/uosc/) (PoC exists on the [script_interface](https://github.com/christoph-heinrich/mpv-quality-menu/tree/script_interface) branch and a [WIP PR for uosc](https://github.com/darsain/uosc/pull/102))
- [ ] Detect when there is no video output and then deactivate video menu and formats.
- [ ] Scrolling for long menus
- [ ] Keep data buffer of unchanged format (e.g. after selecting a new audio format, having to reload the already buffered video data is wasteful).
- [ ] *\[your suggestion here\]*

## Ask for help
I have no idea how to go about switching out the format for one stream, while retaining the other.
Any help would be highly appreciated.


## Credit
- [reload.lua](https://github.com/4e6/mpv-reload/), for the function to reload a video while preserving the playlist.
- [mpv-playlistmanager](https://github.com/jonniek/mpv-playlistmanager), for the menu formatting config.
- ytdl_hook.lua, much of the  code to fetch the format list with youtube-dl came from there.
- somebody on /mpv/ for the idea
