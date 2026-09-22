

-- Bar popout animates itself; compositor popin/fade on unmap made it "drop"
hl.layer_rule({ match = { namespace = "quickshell:popout" }, no_anim = true})
-- Popout is opaque; compositor blur under it is wasted work every frame
hl.layer_rule({ match = { namespace = "quickshell:popout" }, blur = false})
