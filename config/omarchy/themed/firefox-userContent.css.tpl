/* Generated from the current Omarchy theme. Edit ~/.config/omarchy/themed/firefox-userContent.css.tpl */
@-moz-document url-prefix("about:"), url-prefix("chrome:") {
  :root {
    --newtab-background-color: {{ background }} !important;
    --newtab-background-color-secondary: {{ lighter_background }} !important;
    --newtab-text-primary-color: {{ foreground }} !important;
    --newtab-primary-action-background: {{ accent }} !important;
    --newtab-element-hover-color: {{ selection }} !important;
    --in-content-page-background: {{ background }} !important;
    --in-content-page-color: {{ foreground }} !important;
    --in-content-box-background: {{ lighter_background }} !important;
    --in-content-box-border-color: {{ muted }} !important;
    --in-content-item-hover: {{ selection }} !important;
    --in-content-item-selected: {{ accent }} !important;
    --in-content-primary-button-background: {{ accent }} !important;
    --in-content-primary-button-text-color: {{ darker_background }} !important;
    --background-color-canvas: {{ background }} !important;
    --background-color-box: {{ lighter_background }} !important;
    --text-color: {{ foreground }} !important;
    --color-accent-primary: {{ accent }} !important;
    --link-color: {{ accent }} !important;
    --text-color-error: #c1121f !important;
    --border-color-error: #c1121f !important;
    --icon-color-critical: #c1121f !important;
    --background-color-critical: color-mix(in srgb, #c1121f 20%, {{ background }}) !important;
  }
  body { background-color: {{ background }} !important; }
}

/* Text selection highlight on every page: theme coral. */
::selection { background-color: {{ red }} !important; color: {{ darker_background }} !important; }
