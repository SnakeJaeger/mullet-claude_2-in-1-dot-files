# infinity-omarchy (SDDM login screen)

Login screen design from [Infinity-Plasma-Themes](https://github.com/L4ki/Infinity-Plasma-Themes)
by L4ki, rebuilt in plain QtQuick without Plasma, with a user switcher
(← → ↑ ↓ / Tab, or the ‹ › beside the name).

The original Infinity SDDM theme imports Plasma's own login components, so it
needs `plasma-workspace`, `libplasma` and `plasma5support`. This rebuild keeps
its look (galaxy background, clock, round avatar, password pill, power icons)
and needs only SDDM.

## License

GPL-3.0-or-later, like the original theme: this folder reuses its icons
(`assets/`) and its design. See [LICENSE](LICENSE). The rest of this repo is
MIT.

## Background image

Not included here. Take `background.jpg` (the 4K galaxy wallpaper) from L4ki's
[Infinity-SDDM theme](https://github.com/L4ki/Infinity-Plasma-Themes/tree/main/Infinity-SDDM)
and put it next to `Main.qml`. Without it the screen falls back to a plain
dark background.

## Install

From `system/usr/share/sddm/themes/` in this repo:

```sh
sudo cp -r infinity-omarchy /usr/share/sddm/themes/
sudo cp ../../../../etc/sddm.conf.d/99-zz-theme.conf /etc/sddm.conf.d/
```

SDDM lets the config file that sorts last win, and Omarchy's
`99-omarchy-login.conf` also sets the theme, hence the `99-zz-` name. SDDM
reads its config at boot, so reboot to see it. Preview without rebooting:
`sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/infinity-omarchy`.
