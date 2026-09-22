hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

-- Ported from Fedora setup --

-- Edit shell config
hl.bind("CTRL+SUPER+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/illogical-impulse/config.json"), { description = "Edit shell config" })

-- Send window to workspace silently with Super+Ctrl+number (Fedora used this instead of Super+Alt)
for i = 1, 10 do
    local numberkey = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
    local numpadkey = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
    local send = function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = false }))
    end
    hl.bind("CTRL + SUPER + code:" .. numberkey[i], send, { description = "Window: Send to workspace " .. i })
    hl.bind("CTRL + SUPER + code:" .. numpadkey[i], send)
end

-- Alt-Tab window cycler (non-visual)
hl.bind("ALT + Tab", hl.dsp.window.cycle_next(), { description = "Window: Cycle next" })
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }), { description = "Window: Cycle previous" })
