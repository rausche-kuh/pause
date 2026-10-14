# Pause

Full-screen, blurred-backdrop break prompts for KDE Plasma (Wayland):

- **Eye break**: after every 45 minutes of unlocked screen time, 30 s of looking out the window.
- **Walking pad**: at 9:30 and 14:30 on weekdays. The main button unlocks after the 20 s it takes to set up the pad.

Prompts appear only Mon–Fri, 7:00–16:30. A locked screen counts as being away and resets the eye-break timer.

## Try it

    python3 pause.py show eye        # eye break
    python3 pause.py show walk 1     # morning walk (2 = afternoon)
    python3 pause.py test            # self-check of the schedule logic

Prompts started by hand are not logged and do not change the schedule.

    systemctl --user status pause    # is the background loop running?
    cat log                          # every scheduled prompt and how it was answered

## Install

Requires KDE Plasma 6 on Wayland. On Arch/CachyOS:

    sudo pacman -S --needed python pyside6 qt6-declarative qt6-tools spectacle libpulse ocean-sound-theme adwaita-fonts
    git clone https://github.com/rausche-kuh/pause ~/.local/share/pause   # pause.service expects this path
    systemctl --user enable --now ~/.local/share/pause/pause.service

If your speakers are in a DisplayPort/HDMI monitor and the start of sounds gets cut off:

    cp wireplumber-hdmi-no-suspend.conf ~/.config/wireplumber/wireplumber.conf.d/51-hdmi-no-suspend.conf
    systemctl --user restart wireplumber

## Adjust

Times, intervals, durations and sounds are constants at the top of `pause.py`. After editing them, run `systemctl --user restart pause`. Changes to `pause.qml` apply to the next prompt without a restart.

## Uninstall

    systemctl --user disable --now pause
    rm -r ~/.local/share/pause
