-- youtube-quality.lua
--
-- Change youtube video quality on the fly.
--
-- Diplays a menu that lets you switch to different ytdl-format settings while
-- you're in the middle of a video (just like you were using the web player).
--
-- Bound to ctrl-f by default.

local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'

local opts = {
    menu_binding = "ctrl+f",
    menu_timeout = 10,
    quality_strings=[[
    [
    {"1080p" : "bestvideo[height<=?1080]+bestaudio/best"},
    {"720p" : "bestvideo[height<=?720]+bestaudio/best"},
    {"360p" : "bestvideo[height<=?360]+bestaudio/best"},
    {"240p" : "bestvideo[height<=?240]+bestaudio/best"},
    {"144p" : "bestvideo[height<=?144]+bestaudio/best"}
    ]
    ]],
}
(require 'mp.options').read_options(opts)
opts.quality_strings = utils.parse_json(opts.quality_strings)

function show_menu()
    local selected = 1
    local num_options = 0
    local options = {}

    for i,v in ipairs(opts.quality_strings) do
        num_options = num_options + 1
        for k,v2 in pairs(v) do
            options[i] = {label = k, format=v2}
        end
    end

    function selected_move(amt)
        selected = selected + amt
        if selected < 1 then selected = num_options
        elseif selected > num_options then selected = 1 end
        timeout:kill()
        timeout:resume()
        draw_menu()
    end

    function draw_menu()
        local ass = assdraw.ass_new()
        for i,v in ipairs(options) do
            prepend = i == selected and "▶ - " or "○ - "
            ass:append(prepend..v.label.."\\N")
        end
        mp.set_osd_ass(0, 0, ass.text)
    end

    function destroy()
        timeout:kill()
        mp.set_osd_ass(0,0,"")
        mp.remove_key_binding("move_up")
        mp.remove_key_binding("move_down")
        mp.remove_key_binding("select")
        mp.remove_key_binding("escape")
    end
    timeout = mp.add_periodic_timer(opts.menu_timeout, destroy)

    mp.add_forced_key_binding("UP", "move_up", function() selected_move(-1) end)
    mp.add_forced_key_binding("DOWN", "move_down", function() selected_move(1) end)
    mp.add_forced_key_binding("ENTER", "select", function()
        destroy()
        mp.set_property("ytdl-format", options[selected].format)
        reload_resume()
    end)
    mp.add_forced_key_binding(opts.menu_binding, "escape", destroy)

    draw_menu()
    return 
end

-- keybind to launch menu
mp.add_forced_key_binding(opts.menu_binding, "quality-menu", show_menu)


-- credit belongs to reload.lua (https://github.com/4e6/mpv-reload/)
function reload_resume()
    function reload(path, time_pos)
        msg.debug("reload", path, time_pos)
        if time_pos == nil then
            mp.commandv("loadfile", path, "replace")
        else
            mp.commandv("loadfile", path, "replace", "start=+" .. time_pos)
        end
    end

    local path = mp.get_property("path")
    local time_pos = mp.get_property("time-pos")
    local reload_duration = mp.get_property_native("duration")

    local playlist_count = mp.get_property_number("playlist/count")
    local playlist_pos = mp.get_property_number("playlist-pos")
    local playlist = {}
    for i = 0, playlist_count-1 do
        playlist[i] = mp.get_property("playlist/" .. i .. "/filename")
    end
    -- Tries to determine live stream vs. pre-recordered VOD. VOD has non-zero
    -- duration property. When reloading VOD, to keep the current time position
    -- we should provide offset from the start. Stream doesn't have fixed start.
    -- Decent choice would be to reload stream from it's current 'live' positon.
    -- That's the reason we don't pass the offset when reloading streams.
    if reload_duration and reload_duration > 0 then
        msg.info("reloading video from", time_pos, "second")
        reload(path, time_pos)
    else
        msg.info("reloading stream")
        reload(path, nil)
    end
    msg.info("file ", playlist_pos+1, " of ", playlist_count, "in playlist")
    for i = 0, playlist_pos-1 do
        mp.commandv("loadfile", playlist[i], "append")
    end
    mp.commandv("playlist-move", 0, playlist_pos+1)
    for i = playlist_pos+1, playlist_count-1 do
        mp.commandv("loadfile", playlist[i], "append")
    end
end
