

-- Bar popout animates itself; compositor popin/fade on unmap made it "drop"
hl.layer_rule({ match = { namespace = "quickshell:popout" }, no_anim = true})
