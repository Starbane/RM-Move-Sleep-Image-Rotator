# reMarkable Sleep Image Rotator (Paper Pro Move)

Rotate custom **sleep screen images** on the reMarkable Paper Pro Move using an **event-driven approach** (no polling, no extra battery drain).

When the device goes to sleep (power button pressed), a PNG from `/home/root/images/` is mounted over the system’s `suspended.png`. Each sleep cycle rotates to the next image in the folder.

---

## ⚙️ Prerequisites

1. **Enable Developer Mode on your reMarkable**  
   - On the tablet, go to **Settings → Software**.  
   - Tap the firmware version number, then toggle **Advanced**.  
   - Enable **Developer Mode**.  
   - ⚠️ This will perform a **factory reset** of the device. Make sure your files are synced/backed up first.  
   - After reboot, go to **Settings → Help → About → Copyrights and Licenses**. Here you’ll see the SSH credentials (username `root`, generated password, and IP).  

2. **SSH access from your computer**  
   Make sure you can SSH into the device (usually `ssh root@10.11.99.1` over USB).

3. **Prepare images**  
   - PNG format  
   - Resolution: **954×1696**  
   - Color supported  
   - You’ll upload these after installation.

---

## 📦 Installation

1. **Copy installer script to the device**
   ```sh
   scp install-remarkable-sleep-rotate.sh root@10.11.99.1:/home/root/
   ```

2. **SSH into the device and run it**
   ```sh
   ssh root@10.11.99.1
   sh /home/root/install-remarkable-sleep-rotate.sh
   ```

3. **Copy your PNG images** (formatted 954×1696) to:
   ```sh
   scp *.png root@10.11.99.1:/home/root/images/
   ```

4. **Test**
   - Put the device to sleep with the power button → wake it again.  
   - Check the log:
     ```sh
     tail -n 50 /home/root/rotate.log
     ```
   - You should see entries like:
     ```
     [YYYY-MM-DD HH:MM:SS] Edge 0->1 (bl_power=4) -> rotate
     [YYYY-MM-DD HH:MM:SS] OK: mounted '/home/root/images/Image001.png' -> '/usr/share/remarkable/suspended.png' (IDX=0/2)
     ```

---

## 🛠 How it works

- Two scripts are installed into `/home/root/bin/`:
  - **rotate_suspend.sh**  
    Selects the next PNG (stable order), unmounts any previous bind, then bind-mounts the chosen PNG onto `/usr/share/remarkable/suspended.png`.  
    It refuses to run while the frontlight is ON (wake).

  - **rotate_wrapper.sh**  
    Reads `rm_frontlight/bl_power` and triggers rotation **only** on the transition from `0` (ON) → `≠0` (OFF).  
    Debounces multiple udev events to avoid double-rotations.

- A **systemd oneshot service** (`rotate-suspend-udev.service`) runs the wrapper.

- A **udev rule** requests that service on each `backlight/rm_frontlight` `ACTION=change` event.

- Logs → `/home/root/rotate.log`. One successful sleep cycle yields one `Edge 0->1` line and one `OK: mounted ...` line.

---

## 🔄 Image Preparation

Images must be **PNG**, **954×1696** pixels for best results.  
Color is supported.

Convert JPGs using ImageMagick on your computer:
```sh
magick input.jpg -resize 954x1696^ -gravity center -extent 954x1696 output.png
```

Batch convert all JPGs:
```sh
for f in *.jpg; do
  magick "$f" -resize 954x1696^ -gravity center -extent 954x1696 "${f%.*}.png"; done
```

---

## 🧹 Uninstall

```sh
/home/root/bin/uninstall-remarkable-sleep-rotate.sh
```
This removes the udev rule and systemd service, unmounts `suspended.png`, and deletes the scripts. The log file (`/home/root/rotate.log`) is left in place.

---

## 📂 File Layout (after install)
```
/home/root/images/                       # Your PNG sleep images
/home/root/bin/rotate_suspend.sh         # Rotation logic
/home/root/bin/rotate_wrapper.sh         # Edge detection + debounce
/home/root/bin/uninstall-remarkable-sleep-rotate.sh
/home/root/rotate.log                    # Rotation log
/etc/systemd/system/rotate-suspend-udev.service
/etc/udev/rules.d/99-remarkable-backlight-rotate.rules
```

---

## ⚠️ Notes

- Tested on **reMarkable Paper Pro Move, firmware ≥3.22**.  
- Firmware updates or factory reset can wipe changes — just rerun the installer.  
- We use bind-mount over `/usr/share/remarkable/suspended.png` (no permanent system file changes).  
- **No polling** → negligible battery impact.

---

## 🛡️ License & Liability

- License: **MIT** (see `LICENSE`) — do whatever you want, with attribution.  
- **No Liability**: This project is provided *as-is*. You accept the risk that DIY changes could misconfigure or even brick your device. See `DISCLAIMER` for details.
