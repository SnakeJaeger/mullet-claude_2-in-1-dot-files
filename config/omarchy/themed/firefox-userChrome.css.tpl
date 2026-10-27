/* Generated from the current Omarchy theme. Edit ~/.config/omarchy/themed/firefox-userChrome.css.tpl */
:root {
  --omarchy-bg: {{ background }};
  --omarchy-bg-dark: {{ dark_background }};
  --omarchy-bg-darker: {{ darker_background }};
  --omarchy-bg-light: {{ lighter_background }};
  --omarchy-selection: {{ selection }};
  --omarchy-muted: {{ muted }};
  --omarchy-fg: {{ foreground }};
  --omarchy-fg-dim: {{ dark_foreground }};
  --omarchy-fg-bright: {{ bright_foreground }};
  --omarchy-accent: {{ accent }};
  --omarchy-red: {{ red }};
  --omarchy-blood: #c1121f; /* Firefox-only error red */

  /* Window frame + tab strip */
  --lwt-accent-color: var(--omarchy-bg-darker) !important;
  --lwt-accent-color-inactive: var(--omarchy-bg-darker) !important;
  --lwt-text-color: var(--omarchy-fg) !important;
  --tab-selected-bgcolor: var(--omarchy-bg-light) !important;
  --tab-selected-textcolor: var(--omarchy-fg-bright) !important;
  --tab-hover-background-color: var(--omarchy-selection) !important;
  --tab-loading-fill: var(--omarchy-accent) !important;
  --tab-attention-icon-color: var(--omarchy-accent) !important;
  --lwt-tab-line-color: var(--omarchy-red) !important;
  --tab-border-color-accent: var(--omarchy-red) !important;

  /* Toolbars */
  --toolbar-bgcolor: var(--omarchy-bg-light) !important;
  --toolbar-color: var(--omarchy-fg) !important;
  --toolbar-field-background-color: var(--omarchy-bg-dark) !important;
  --toolbar-field-color: var(--omarchy-fg-bright) !important;
  --toolbar-field-border-color: transparent !important;
  --toolbar-field-focus-background-color: var(--omarchy-bg-dark) !important;
  --toolbar-field-focus-color: var(--omarchy-fg-bright) !important;
  --toolbar-field-focus-border-color: var(--omarchy-accent) !important;
  --toolbarbutton-icon-fill: var(--omarchy-fg) !important;
  --toolbarbutton-hover-background: var(--omarchy-selection) !important;
  --toolbarbutton-active-background: var(--omarchy-muted) !important;
  --chrome-content-separator-color: var(--omarchy-bg-darker) !important;
  --focus-outline-color: var(--omarchy-accent) !important;

  /* URL bar dropdown */
  --urlbarView-highlight-background: var(--omarchy-selection) !important;
  --urlbarView-highlight-color: var(--omarchy-fg-bright) !important;
  --urlbarView-separator-color: var(--omarchy-bg-light) !important;
  --urlbar-box-bgcolor: var(--omarchy-bg-dark) !important;
  --urlbar-box-text-color: var(--omarchy-fg) !important;

  /* Sidebar */
  --sidebar-background-color: var(--omarchy-bg-dark) !important;
  --sidebar-text-color: var(--omarchy-fg) !important;
  --sidebar-border-color: var(--omarchy-bg-darker) !important;

  /* Menus and panels */
  --arrowpanel-background: var(--omarchy-bg-dark) !important;
  --arrowpanel-color: var(--omarchy-fg) !important;
  --arrowpanel-border-color: var(--omarchy-muted) !important;
  --panel-separator-color: var(--omarchy-bg-light) !important;
  --button-bgcolor: var(--omarchy-bg-light) !important;
  --button-hover-bgcolor: var(--omarchy-selection) !important;
  --button-primary-bgcolor: var(--omarchy-accent) !important;
  --button-primary-color: var(--omarchy-bg-darker) !important;
  --color-accent-primary: var(--omarchy-accent) !important;

  /* Errors */
  --text-color-error: var(--omarchy-blood) !important;
  --border-color-error: var(--omarchy-blood) !important;
  --icon-color-critical: var(--omarchy-blood) !important;
  --background-color-critical: color-mix(in srgb, var(--omarchy-blood) 20%, var(--omarchy-bg)) !important;

  /* Blank page flash while loading */
  --tabpanel-background-color: var(--omarchy-bg) !important;
}

menupopup, panel {
  --panel-background: var(--omarchy-bg-dark) !important;
  --panel-color: var(--omarchy-fg) !important;
  --panel-border-color: var(--omarchy-muted) !important;
  --menuitem-hover-background-color: var(--omarchy-selection) !important;
}

#navigator-toolbox { border-bottom-color: var(--omarchy-bg-darker) !important; }
/* Text selection highlight: theme coral (pages get the same rule in userContent). */
::selection { background-color: var(--omarchy-red) !important; color: var(--omarchy-bg-darker) !important; }
.tab-background:is([selected], [multiselected]) { box-shadow: none !important; }
/* Selected tab: coral -> cyan diagonal, the reverse of the Hyprland window border (cyan -> coral, 45deg). */
.tab-background[selected]:not([multiselected]) {
  outline: none !important;
  position: relative !important;
}
/* 1px gradient ring: the mask cuts the content box out, leaving only the padding edge. */
.tab-background[selected]:not([multiselected])::before {
  content: "";
  position: absolute;
  inset: 0;
  padding: 1px;
  border-radius: inherit;
  background: linear-gradient(168deg, var(--omarchy-red), var(--omarchy-accent));
  mask: linear-gradient(#000 0 0) content-box exclude, linear-gradient(#000 0 0);
  pointer-events: none;
}
#tabbrowser-tabpanels, browser[type="content"] { background-color: var(--omarchy-bg) !important; }
