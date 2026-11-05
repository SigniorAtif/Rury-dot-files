hl.on("hyprland.start", function ()
    -- Auto-mount USB drives under /run/media/$USER/<label>
    hl.exec_cmd("udiskie")
end)
