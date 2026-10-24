// Additions to Sublime's Adaptive UI theme (Sublime merges a same-named file
// in Packages/User over the built-in one), linked into
// ~/.config/sublime-text/Packages/User/: an almost-black strip around the tabs,
// dark grey tabs, and almost-black, see-through panels (Ctrl+P palette, Goto
// Anything) with a cyan-tinted selected row. Keep tab rules colour-only: a version that also set
// opacities and tint_modifier on tabs stopped them taking clicks.
{
  "rules": [
    { "class": "tabset_control", "layer0.tint": "{{ dark_background }}" },
    { "class": "tab_control", "layer0.tint": "#2b2c32" },
    { "class": "tab_control", "attributes": ["selected"], "layer0.tint": "#3a3c44" },
    { "class": "overlay_control", "layer0.tint": "{{ dark_background }}", "layer0.opacity": 0.78 },
    { "class": "quick_panel", "row_padding": [8, 6], "layer0.tint": "{{ dark_background }}", "layer0.opacity": 0.78 },
    { "class": "quick_panel_row", "layer0.tint": "{{ dark_background }}", "layer0.opacity": 0.0 },
    { "class": "quick_panel_row", "attributes": ["selected"], "layer0.tint": "{{ accent }}", "layer0.opacity": 0.18 },
    { "class": "mini_quick_panel_row", "attributes": ["selected"], "layer0.tint": "{{ accent }}", "layer0.opacity": 0.18 }
  ]
}
