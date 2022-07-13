-- quality-menu.lua
--
-- Change the stream video and audio quality on the fly.
--
-- Usage:
-- add bindings to input.conf:
-- Ctrl+f   script-message-to quality_menu video_formats_toggle
-- Alt+f    script-message-to quality_menu audio_formats_toggle
--
-- Displays a menu that lets you switch to different ytdl-format settings while
-- you're in the middle of a video (just like you were using the web player).

local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'

local opts = {
    --key bindings
    up_binding = "UP WHEEL_UP",
    down_binding = "DOWN WHEEL_DOWN",
    select_binding = "ENTER MBTN_LEFT",
    close_menu_binding = "ESC MBTN_RIGHT Ctrl+f Alt+f",

    --youtube-dl version(could be youtube-dl or yt-dlp, or something else)
    ytdl_ver = "yt-dlp",

    --formatting / cursors
    selected_and_active     = "▶  - ",
    selected_and_inactive   = "●  - ",
    unselected_and_active   = "▷ - ",
    unselected_and_inactive = "○ - ",

    --font size scales by window, if false requires larger font and padding sizes
    scale_playlist_by_window=true,

    --playlist ass style overrides inside curly brackets, \keyvalue is one field, extra \ for escape in lua
    --example {\\fnUbuntu\\fs10\\b0\\bord1} equals: font=Ubuntu, size=10, bold=no, border=1
    --read http://docs.aegisub.org/3.2/ASS_Tags/ for reference of tags
    --undeclared tags will use default osd settings
    --these styles will be used for the whole playlist. More specific styling will need to be hacked in
    --
    --(a monospaced font is recommended but not required)
    style_ass_tags = "{\\fnmonospace\\fs10\\bord1}",

    --paddings for top left corner
    text_padding_x = 5,
    text_padding_y = 5,

    --how many seconds until the quality menu times out
    --setting this to 0 deactivates the timeout
    menu_timeout = 6,

    --use youtube-dl to fetch a list of available formats (overrides quality_strings)
    fetch_formats = true,

    --default menu entries
    quality_strings=[[
    [
    {"4320p" : "bestvideo[height<=?4320p]+bestaudio/best"},
    {"2160p" : "bestvideo[height<=?2160]+bestaudio/best"},
    {"1440p" : "bestvideo[height<=?1440]+bestaudio/best"},
    {"1080p" : "bestvideo[height<=?1080]+bestaudio/best"},
    {"720p" : "bestvideo[height<=?720]+bestaudio/best"},
    {"480p" : "bestvideo[height<=?480]+bestaudio/best"},
    {"360p" : "bestvideo[height<=?360]+bestaudio/best"},
    {"240p" : "bestvideo[height<=?240]+bestaudio/best"},
    {"144p" : "bestvideo[height<=?144]+bestaudio/best"}
    ]
    ]],

    --reset ytdl-format to the original format string when changing files (e.g. going to the next playlist entry)
    --if file was opened previously, reset to previously selected format
    reset_format = true,

    --automatically fetch available formats when opening a file
    fetch_on_start = true,

    --show the video format menu after opening a file
    start_with_menu = true,

    --sort formats instead of keeping the order from yt-dlp/youtube-dl
    sort_formats = false,

    --hide columns that are identical for all formats
    hide_identical_columns = true,
}
(require 'mp.options').read_options(opts, "quality-menu")
opts.quality_strings = utils.parse_json(opts.quality_strings)

-- special thanks to reload.lua (https://github.com/4e6/mpv-reload/)
local function reload_resume()
    local playlist_pos = mp.get_property_number("playlist-pos")
    local reload_duration = mp.get_property_native("duration")
    local time_pos = mp.get_property("time-pos")

    mp.set_property_number("playlist-pos", playlist_pos)

    -- Tries to determine live stream vs. pre-recorded VOD. VOD has non-zero
    -- duration property. When reloading VOD, to keep the current time position
    -- we should provide offset from the start. Stream doesn't have fixed start.
    -- Decent choice would be to reload stream from it's current 'live' position.
    -- That's the reason we don't pass the offset when reloading streams.
    if reload_duration and reload_duration > 0 then
        local function seeker()
            mp.commandv("seek", time_pos, "absolute")
            mp.unregister_event(seeker)
        end
        mp.register_event("file-loaded", seeker)
    end
end

local ytdl = {
    path = opts.ytdl_ver,
    searched = false,
    blacklisted = {}
}

local url_data={}
local function download_formats()

    local function get_url()
        local path = mp.get_property("path")
        path = string.gsub(path, "ytdl://", "") -- Strip possible ytdl:// prefix.

        local function is_url(s)
            -- adapted the regex from https://stackoverflow.com/questions/3809401/what-is-a-good-regular-expression-to-match-a-url
            return nil ~= string.match(path, "^[%w]-://[-a-zA-Z0-9@:%._\\+~#=]+%.[a-zA-Z0-9()][a-zA-Z0-9()]?[a-zA-Z0-9()]?[a-zA-Z0-9()]?[a-zA-Z0-9()]?[a-zA-Z0-9()]?[-a-zA-Z0-9()@:%_\\+.~#?&/=]*")
        end

        return is_url(path) and path or nil
    end

    local url = get_url()
    if url == nil then
        return
    end

    if url_data[url] ~= nil then
        local data = url_data[url]
        return data.voptions, data.aoptions, data.vfmt, data.afmt, url
    end

    if opts.fetch_formats == false then
        local vres = {}
        for i,v in ipairs(opts.quality_strings) do
            for k,v2 in pairs(v) do
                vres[i] = {label = k, format=v2}
            end
        end
        url_data[url] = {voptions=vres, aoptions={}, vfmt=nil, afmt=nil}
        return vres, {}, nil, nil, url
    end

    mp.osd_message("fetching available formats with youtube-dl...", 60)

    if not (ytdl.searched) then
        local ytdl_mcd = mp.find_config_file(opts.ytdl_ver)
        if not (ytdl_mcd == nil) then
            msg.verbose("found youtube-dl at: " .. ytdl_mcd)
            ytdl.path = ytdl_mcd
        end
        ytdl.searched = true
    end

    local function exec(args)
        local res, err = mp.command_native({name = "subprocess", args = args, capture_stdout = true, capture_stderr = true})
        return res.status, res.stdout, res.stderr
    end

    local ytdl_format = mp.get_property("ytdl-format")
    local command = nil
    if (ytdl_format == nil or ytdl_format == "") then
        command = {ytdl.path, "--no-warnings", "--no-playlist", "-j", url}
    else
        command = {ytdl.path, "--no-warnings", "--no-playlist", "-j", "-f", ytdl_format, url}
    end

    msg.verbose("calling youtube-dl with command: " .. table.concat(command, " "))

    local es, stdout, stderr = exec(command)

    if (es < 0) or (stdout == nil) or (stdout == "") then
        mp.osd_message("fetching formats failed...", 1)
        msg.error("failed to get format list: " .. es)
        msg.error("stderr: " .. stderr)
        return
    end

    local json, err = utils.parse_json(stdout)

    if (json == nil) then
        mp.osd_message("fetching formats failed...", 1)
        msg.error("failed to parse JSON data: " .. err)
        return
    end

    msg.verbose("youtube-dl succeeded!")

    if json.formats == nil then
        return
    end

    local function string_split (inputstr, sep)
        if sep == nil then
            sep = "%s"
        end
        local t={}
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
            table.insert(t, str)
        end
        return t
    end

    local original_format=json.format_id
    local formats_split = string_split(original_format, "+")
    local vfmt = formats_split[1]
    local afmt = formats_split[2]

    local video_formats = {}
    local audio_formats = {}
    for i = #json.formats, 1, -1 do
        local format = json.formats[i]
        local is_video = (format.vcodec and format.vcodec ~= "none") or (format.video_ext and format.video_ext ~= "none")
        local is_audio = (format.acodec and format.acodec ~= "none") or (format.audio_ext and format.audio_ext ~= "none")
        if is_video then
            video_formats[#video_formats+1] = {format=format}
        elseif is_audio and not is_video then
            audio_formats[#audio_formats+1] = {format=format}
        end
    end

    if opts.sort_formats then
        table.sort(video_formats,
        function(a, b)
            a = a.format
            b = b.format
            local size_a = a.filesize or a.filesize_approx
            local size_b = b.filesize or b.filesize_approx
            if a.height ~= nil and b.height ~= nil and a.height ~= b.height then
                return a.height > b.height
            elseif a.fps ~= nil and b.fps ~= nil and a.fps ~= b.fps then
                return a.fps > b.fps
            elseif a.tbr ~= nil and b.tbr ~= nil and a.tbr ~= b.tbr then
                return a.tbr > b.tbr
            elseif size_a ~= nil and size_b ~= nil and size_a ~= size_b then
                return size_a > size_b
            elseif a.format_id ~= nil and b.format_id ~= nil and a.format_id ~= b.format_id then
                return a.format_id > b.format_id
            end
        end)

        table.sort(audio_formats,
        function(a, b)
            a = a.format
            b = b.format
            local size_a = a.filesize or a.filesize_approx
            local size_b = b.filesize or b.filesize_approx
            if a.asr ~= nil and b.asr ~= nil and a.asr ~= b.asr then
                return a.asr > b.asr
            elseif a.tbr ~= nil and b.tbr ~= nil and a.tbr ~= b.tbr then
                return a.tbr > b.tbr
            elseif size_a ~= nil and size_b ~= nil and size_a ~= size_b then
                return size_a > size_b
            elseif a.format_id ~= nil and b.format_id ~= nil and a.format_id ~= b.format_id then
                return a.format_id > b.format_id
            end
        end)
    end

    local function scale_filesize(size)
        size = tonumber(size)
        if size == nil then
            return "unknown"
        end

        local counter = 0
        while size > 1024 do
            size = size / 1024
            counter = counter+1
        end

        if counter >= 3 then return string.format("%.1fGiB", size)
        elseif counter >= 2 then return string.format("%.1fMiB", size)
        elseif counter >= 1 then return string.format("%.1fKiB", size)
        else return string.format("%.1fB  ", size)
        end
    end

    local function scale_bitrate(br)
        br = tonumber(br)
        if br == nil then
            return "unknown"
        end

        local counter = 0
        while br > 1000 do
            br = br / 1000
            counter = counter+1
        end

        if counter >= 2 then return string.format("%.1fGbps", br)
        elseif counter >= 1 then return string.format("%.1fMbps", br)
        else return string.format("%.1fKbps", br)
        end
    end

    local function video_label_format(format)
        local dynamic_range = format.dynamic_range
        local fps = format.fps and format.fps.."fps" or ""
        local resolution = format.resolution or string.format("%sx%s", format.width, format.height)
        local size = nil
        if format.filesize == nil and format.filesize_approx then
            size = "~"..scale_filesize(format.filesize_approx)
        else
            size = scale_filesize(format.filesize)
        end
        local tbr = scale_bitrate(format.tbr)
        local vcodec = format.vcodec == nil and "unknown" or format.vcodec
        local acodec = format.acodec == nil and "unknown" or format.acodec ~= "none" and format.acodec or ""
        return {resolution, fps, dynamic_range, tbr, size, format.ext, vcodec, acodec}
    end

    for i,f in ipairs(video_formats) do
        video_formats[i].labels = video_label_format(f.format)
    end

    local function audio_label_format(format)
        local size = scale_filesize(format.filesize)
        local tbr = scale_bitrate(format.tbr)
        return {tostring(format.asr) .. 'Hz', tbr, size, format.ext, format.acodec}
    end

    for i,f in ipairs(audio_formats) do
        audio_formats[i].labels = audio_label_format(f.format)
    end

    local function format_table(formats)
        local display_col = {}
        local col_widths = {}
        local col_val = {}
        for row=1, #formats do
            for col=1, #formats[row].labels do
                col_val[col] = col_val[col] or formats[row].labels[col]
                local label = formats[row].labels[col]
                if not col_widths[col] or col_widths[col] < label:len() then
                    col_widths[col] = label:len()
                end
                display_col[col] = display_col[col] or (col_val[col] ~= label)
            end
        end

        local spacing = 2
        for i=2, #col_widths do
            col_widths[i] = col_widths[i] + spacing
        end

        local res = {}
        for _,f in ipairs(formats) do
            local row = ''
            for col,label in ipairs(f.labels) do
                if not opts.hide_identical_columns or display_col[col] then
                    row = row .. string.format('%' .. col_widths[col] .. 's', label)
                end
            end
            res[#res+1] = {label=row, format=f.format.format_id}
        end
        return res
    end

    local vres = format_table(video_formats)
    local ares = format_table(audio_formats)

    mp.osd_message("", 0)
    url_data[url] = {voptions=vres, aoptions=ares, vfmt=vfmt, afmt=afmt}
    return vres, ares , vfmt, afmt, url
end

local function format_string(vfmt, afmt)
    if vfmt ~= nil and afmt ~= nil then
        return vfmt.."+"..afmt
    elseif vfmt ~= nil then
        return vfmt
    elseif afmt ~= nil then
        return afmt
    else
        return ""
    end
end

local destroyer = nil
local function show_menu(isvideo)

    if destroyer ~= nil then
        destroyer()
    end

    local voptions, aoptions, vfmt, afmt, url = download_formats()
    if voptions == nil then
        return
    end

    local options = isvideo and voptions or aoptions

    msg.verbose("current ytdl-format: "..format_string(vfmt, afmt))

    local active = 0
    local selected = 1
    --set the cursor to the current format
    for i,v in ipairs(options) do
        if v.format == (isvideo and vfmt or afmt) then
            active = i
            selected = active
            break
        end
    end

    local function table_size(t)
        local s = 0
        for i,v in ipairs(t) do
            s = s+1
        end
        return s
    end

    local function choose_prefix(i)
        if     i == selected and i == active then return opts.selected_and_active
        elseif i == selected then return opts.selected_and_inactive end

        if     i ~= selected and i == active then return opts.unselected_and_active
        elseif i ~= selected then return opts.unselected_and_inactive end
        return "> " --shouldn't get here.
    end

    local function draw_menu()
        local ass = assdraw.ass_new()

        ass:pos(opts.text_padding_x, opts.text_padding_y)
        ass:append(opts.style_ass_tags)

        if options[1] ~= nil then
            for i,v in ipairs(options) do
                ass:append(choose_prefix(i)..v.label.."\\N")
            end
        else
            ass:append("no formats found")
        end

        local w, h = mp.get_osd_size()
        if opts.scale_playlist_by_window then w,h = 0, 0 end
        mp.set_osd_ass(w, h, ass.text)
    end

    local num_options = table_size(options)
    local timeout = nil

    local function selected_move(amt)
        selected = selected + amt
        if selected < 1 then selected = num_options
        elseif selected > num_options then selected = 1 end
        if timeout ~= nil then
            timeout:kill()
            timeout:resume()
        end
        draw_menu()
    end

    local function bind_keys(keys, name, func, opts)
        if not keys then
          mp.add_forced_key_binding(keys, name, func, opts)
          return
        end
        local i = 1
        for key in keys:gmatch("[^%s]+") do
          local prefix = i == 1 and '' or i
          mp.add_forced_key_binding(key, name..prefix, func, opts)
          i = i + 1
        end
    end

    local function unbind_keys(keys, name)
        if not keys then
          mp.remove_key_binding(name)
          return
        end
        local i = 1
        for key in keys:gmatch("[^%s]+") do
          local prefix = i == 1 and '' or i
          mp.remove_key_binding(name..prefix)
          i = i + 1
        end
    end

    local function destroy()
        if timeout ~= nil then
            timeout:kill()
        end
        mp.set_osd_ass(0,0,"")
        unbind_keys(opts.up_binding, "move_up")
        unbind_keys(opts.down_binding, "move_down")
        unbind_keys(opts.select_binding, "select")
        unbind_keys(opts.close_menu_binding, "close")
        destroyer = nil
    end

    if opts.menu_timeout > 0 then
        timeout = mp.add_periodic_timer(opts.menu_timeout, destroy)
    end
    destroyer = destroy

    bind_keys(opts.up_binding,     "move_up",   function() selected_move(-1) end, {repeatable=true})
    bind_keys(opts.down_binding,   "move_down", function() selected_move(1)  end, {repeatable=true})
    if options[1] ~= nil then
        bind_keys(opts.select_binding, "select", function()
            destroy()
            if selected == active then return end

            if isvideo == true then
                vfmt = options[selected].format
                url_data[url].vfmt = vfmt
            else
                afmt = options[selected].format
                url_data[url].afmt = afmt
            end
            mp.set_property("ytdl-raw-options", "")    --reset youtube-dl raw options before changing format
            mp.set_property("ytdl-format", format_string(vfmt, afmt))
            reload_resume()
        end)
    end
    bind_keys(opts.close_menu_binding, "close", destroy)    --close menu using ESC
    draw_menu()
end

local function video_formats_toggle()
    show_menu(true)
end

local function audio_formats_toggle()
    show_menu(false)
end

-- keybind to launch menu
mp.add_key_binding(nil, "video_formats_toggle", video_formats_toggle)
mp.add_key_binding(nil, "audio_formats_toggle", audio_formats_toggle)
mp.add_key_binding(nil, "reload", reload_resume)

local original_format = mp.get_property("ytdl-format")
local path = nil
local function file_start()
    local new_path = mp.get_property("path")
    if opts.reset_format and path ~= nil and new_path ~= path then
        local data = url_data[new_path]
        if data ~= nil then
            msg.verbose("setting previously set format")
            mp.set_property("ytdl-format", format_string(data.vfmt, data.afmt))
        else
            msg.verbose("setting original format")
            mp.set_property("ytdl-format", original_format)
        end
    end
    if opts.start_with_menu and new_path ~= path then
        video_formats_toggle()
    elseif opts.fetch_on_start then
        download_formats()
    end
    path = new_path
end
mp.register_event("start-file", file_start)
