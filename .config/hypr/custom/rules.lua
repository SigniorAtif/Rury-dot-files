

-- Bar popout animates itself; compositor popin/fade on unmap made it "drop"
hl.layer_rule({ match = { namespace = "quickshell:popout" }, no_anim = true})
-- Popout is opaque; compositor blur under it is wasted work every frame
hl.layer_rule({ match = { namespace = "quickshell:popout" }, blur = false})

-- SigniorAtif agent desk viewer (Super+Shift+/): its own special workspace, desk pixels 1:1, room on the right for the HUD.
-- Matched by class (only the agent opens TigerVNC); the effects sit in one rule, split rules did not all apply.
hl.window_rule({
    match = { class = "^(Vncviewer)$" },
    workspace = "special:agent silent",
    float = true,
    size = {1280, 800},
    move = {"((monitor_w-1656)*0.5)", "((monitor_h-800)*0.5+30)"},
})
