/* GTK3 (Adwaita-dark) colors generated from the current Omarchy theme.
   Linked from ~/.config/gtk-3.0/gtk.css. Open apps need a restart to pick it up. */

@define-color theme_bg_color {{ background }};
@define-color theme_fg_color {{ foreground }};
@define-color theme_base_color {{ background }};
@define-color theme_text_color {{ foreground }};
@define-color theme_selected_bg_color {{ accent }};
@define-color theme_selected_fg_color {{ background }};
@define-color insensitive_bg_color {{ dark_background }};
@define-color insensitive_fg_color {{ dark_foreground }};
@define-color insensitive_base_color {{ dark_background }};
@define-color theme_unfocused_bg_color {{ background }};
@define-color theme_unfocused_fg_color {{ foreground }};
@define-color theme_unfocused_base_color {{ background }};
@define-color theme_unfocused_text_color {{ foreground }};
@define-color theme_unfocused_selected_bg_color {{ accent }};
@define-color theme_unfocused_selected_fg_color {{ background }};
@define-color borders {{ darker_background }};
@define-color unfocused_borders {{ darker_background }};
@define-color warning_color {{ yellow }};
@define-color error_color {{ red }};
@define-color success_color {{ green }};


/* Menu bars (Sublime Text's File / Edit / ... row) are black, matching
   Sublime's black tab strip (Adaptive.sublime-theme.tpl). GTK CSS can't
   target one app, so this covers every GTK3 menu bar. */
menubar {
  background-color: #000000;
  background-image: none;
  box-shadow: none;
  border: none;
}

/* Right-click and drop-down menus: almost black and slightly see-through
   (Hyprland blurs popups behind them). */
window.popup, window.popup.csd, .csd.popup decoration {
  background-color: transparent;
  box-shadow: none;
}
menu, .menu, .context-menu {
  background-color: rgba(8, 8, 12, 0.84);
  border: 1px solid rgba(169, 177, 214, 0.12);
  border-radius: 8px;
  padding: 4px 0;
}
menu menuitem:hover, .menu menuitem:hover {
  background-color: rgba(125, 207, 255, 0.18);
}

/* Message dialogs ("Save changes before closing?" and the like): almost
   black and slightly see-through like the menus, flat buttons with a cyan
   hover. */
messagedialog.background, messagedialog.csd {
  background-color: rgba(8, 8, 12, 0.94);
  background-image: none;
  border-radius: 10px;
}
/* GTK paints the window backing only below the title bar, so the (empty)
   title bar gets the same backing, rounded at the top. */
messagedialog .titlebar, messagedialog headerbar {
  background-color: rgba(8, 8, 12, 0.94);
  background-image: none;
  border-radius: 10px 10px 0 0;
  box-shadow: none;
  border: none;
}
messagedialog .dialog-vbox, messagedialog box {
  background-color: transparent;
  background-image: none;
  box-shadow: none;
  border: none;
}
messagedialog.csd decoration, messagedialog decoration {
  background-color: transparent;
  border: 1px solid rgba(169, 177, 214, 0.12);
  border-radius: 10px;
  box-shadow: none;
}
messagedialog label {
  color: #c0caf5;
}
messagedialog .dialog-action-box button, messagedialog .dialog-action-area button {
  background-color: transparent;
  background-image: none;
  color: #a9b1d6;
  border: none;
  border-top: 1px solid rgba(169, 177, 214, 0.12);
  box-shadow: none;
}
messagedialog .dialog-action-box button:not(:first-child) {
  border-left: 1px solid rgba(169, 177, 214, 0.12);
}
messagedialog .dialog-action-box button:hover {
  background-color: rgba(125, 207, 255, 0.18);
  color: #c0caf5;
}
