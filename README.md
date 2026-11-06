# ios-sweet-pixel

**Apple's iOS 16 running on a Google Pixel 4a.**

This fork ports Apple's open-source XNU kernel (xnu-8796, the iOS 16 generation) to the **Google Pixel 4a** (`sunfish`, Qualcomm SM7150 / Snapdragon 730G). On top of it runs the **unmodified iOS 16.7.16 (20H392) userland of the iPhone X**: launchd, the system daemons, backboardd, SpringBoard and the stock apps.

The work builds on [frokfrdk/ios-sweet-build](https://github.com/frokfrdk/ios-sweet-build), which brought the same stack up on the Xiaomi Redmi Note 10 Pro (`sweet`, also SM7150). This repository defaults to **sunfish**.

> Experimental bring-up, not a usable phone OS. Many things are missing or stubbed (see below), and Apple's security model is mostly switched off. It installs into the `userdata` partition and so **erases Android's user data**.

## What works (Pixel 4a / sunfish)

| Area | State |
| --- | --- |
| Boot | Stock Google ABL → `fastboot boot` of our shim → XNU. Nothing is flashed to the boot partitions |
| CPU | 6 of the 8 cores (the six Cortex-A55s) via PSCI; `cpus=6` recommended |
| Memory | Upper DDR bank via `--highmem` ADT |
| Storage | Own UFS host driver; journaled HFS+ iOS root in `userdata`, read/write |
| iOS userland | Real iPhone X 16.7.16 root + shared cache; launchd and system daemons |
| Display | Kernel IOSurface + IOMobileFramebuffer; CPU-composited frames into ABL splash FB at `0x9c000000` (1080×2340 panel). Prefer `--scale2` ADT (828×1792 @2x) for bring-up |
| GUI | backboardd + SpringBoard (lock / home). First boot is slow; use `sweetfb_noconsole=1` so the kernel console does not cover the GUI |
| Touch | Focaltech FTM5 (`sweetfts=1`), HID digitizer events |
| Buttons | Power / volume as HID keys (shared SWEET SPMI path) |
| Battery | Stub IOPMPowerSource (static 100 %); no real charger driver |
| Device identity | iPhone X (`iPhone10,3` / `D22AP`) via ADT + extracted `d22ap.adt` |
| USB | Experimental CDC-ECM (`sweetusb=2`) for host ethernet + live UDP console — not ADB |
| Wi-Fi | **Bring-up in progress** — WCN3990 probe stub (`sweetwifi=1`); see [`docs/WIFI_WCN3990_PLAN.md`](docs/WIFI_WCN3990_PLAN.md) |

## What does not work (yet)

- **No Wi-Fi association, Bluetooth, cellular, audio, camera, sensors, GPS or SEP / Face ID** (Wi-Fi is staged; see the plan doc).
- **No GPU.** CPU compositing only. Adreno 618 work continues in `docs/GPU_A618_PLAN.md`.
- **No normal iOS USB** (no usbmuxd / Finder / ADB while XNU is running).
- **Security is off:** permissive AMFI/sandbox, stub AppleKeyStore. Do not put personal data on it.

## How it boots

```
ABL (stock Pixel 4a bootloader, unlocked)
  -> fastboot boot shim-boot.img              (temporary; nothing flashed to boot)
     -> shim (BOARD=sunfish): MMU, live FDT, payload from ramdisk
        -> XNU Mach-O + sunfish ADT + boot-args
           -> UFS -> HFS+ root on userdata
              -> dyld + shared cache -> launchd -> backboardd + SpringBoard
```

There is no useful debug UART on this board. The kernel draws into the ABL framebuffer and can keep a 4 MiB console ring at the end of userdata (`sweetlog=1`).

## How to do it yourself

You need a **Pixel 4a (`sunfish`)** with an **unlocked bootloader**, Linux (or WSL2 with an HFS+-capable kernel), and GitHub Actions for the XNU build. **Everything on `userdata` is wiped.**

### 0. Back up

From Android or recovery, back up calibration-critical partitions (`persist`, modem NV, etc.) and unpack a stock `boot.img` so the shim has a sunfish DTB:

```sh
python3 tools/unpack_bootv2.py backup/boot.img dtb/sunfish_unpacked
cp dtb/sunfish_unpacked/dtb dtb/sunfish/dtb
```

### 1. Build the kernel

```sh
gh workflow run xnu.yml -R YOU/ios-sweet-pixel
gh run download RUN_ID -R YOU/ios-sweet-pixel -n xnu-kernel -D xnu/out
```

### 2. Build the iOS root image

Download the iPhone X (iPhone10,3) iOS **16.7.16 (20H392)** IPSW. On Linux with `apfs-fuse`, `hfsprogs`, and sudo:

```sh
tools/mkiosroot.sh OS.dmg SystemOS.dmg AppOS.dmg ios16-root.img 16G
sudo fsck.hfsplus -fy ios16-root.img
sudo mount -t hfsplus -o loop,force ios16-root.img /mnt/iosroot
sudo python3 tools/sweet-root-tweaks.py /mnt/iosroot
# Pixel-specific: software CoreUI, Autobahn off, wallpaper, optional app migrator
sudo python3 -I tools/sunfish/mkwallpaper.py /tmp/wall.png 828 1792
sudo python3 -I tools/sunfish/png2cpbitmap.py /tmp/wall.png /tmp/wall.cpbitmap
sudo mkdir -p /mnt/iosroot/private/var/mobile/Library/SpringBoard
sudo python3 -I tools/sunfish/sunfish-root-tweaks.py /mnt/iosroot \
    --wallpaper /tmp/wall.cpbitmap
# First image that should install staged system apps (Calculator, Files, ...):
#   ... sunfish-root-tweaks.py /mnt/iosroot --wallpaper /tmp/wall.cpbitmap --migrate-once
sudo umount /mnt/iosroot
img2simg ios16-root.img ios16-root.simg
# Pixel ABL is slow on FILL chunks:
python3 -I tools/sunfish/nofill.py ios16-root.simg ios16-root-nofill.simg
```

Extract `DeviceTree.d22ap` for `mkadt.py` (or use `python3 -I tools/adt.py unwrap …`):

```sh
python3 tools/remotezip.py IPSW_URL DeviceTree.d22ap.im4p research/ipsw-x/dt
python3 -I tools/adt.py unwrap research/ipsw-x/dt/Firmware/all_flash/DeviceTree.d22ap.im4p \
    research/ipsw-x/d22ap.adt
```

### 3. Build the boot image

Needs `aarch64-linux-gnu-gcc`, `lz4`, `mkbootimg`, and AOSP `avbtool` (path via `AVBTOOL` or `~/ios-pixel/src/avb/avbtool.py`).

```sh
python3 -I tools/mkadt.py shim/out/sunfish-hi-scale2.adt --highmem --sunfish --scale2
CPUS=6 SWEETLOG=1 ADT=shim/out/sunfish-hi-scale2.adt \
  bash tools/sunfish/mkboot.sh xnu/out bringup \
  'ufsrw=1 rootrw=1 sweetfb_noconsole=1 sweetfb_hz=30'
# -> shim/out/shim-boot-bringup.img
```

Useful boot-args:

| Boot-arg | Effect |
| --- | --- |
| `rd=ufsroot0 ufsrw=1 rootrw=1` | Writable HFS+ root on userdata |
| `cpus=6` | Six A55 cores (prefer over `cpus=1`) |
| `sweetfb_noconsole=1` | Hide kernel text over the GUI |
| `sweetfts=1` | Focaltech touch (sunfish default in `mkboot.sh`) |
| `sweetwifi=1` | WCN3990 read-only probe (see Wi-Fi plan) |
| `sweetusb=2` | USB CDC-ECM + live UDP console |

### 4. Flash and boot

```sh
fastboot -S 128M flash userdata ios16-root-nofill.simg   # do not unplug; ~15–20 min
fastboot boot shim/out/shim-boot-bringup.img
```

First boot often needs several minutes on the Apple logo (longer if `--migrate-once` is installing staged apps). Swipe up on the lock screen. Power + Volume Down returns to fastboot.

### 5. Logs

- On-screen: omit `sweetfb_noconsole=1` for a console boot.
- Persistent ring: `sweetlog=1`, then pull from recovery with `tools/sweet-log-pull.sh` when you have a recovery image.
- USB live log: `sweetusb=2` + `tools/sweet-usbnet.sh` on a Linux host.

## Repository layout

| Path | What |
| --- | --- |
| `shim/` | Boot shim; `BOARD=sunfish` packs LZ4 + AVB footer |
| `xnu/patches/` | XNU patch series (CI applies in order) |
| `tools/sunfish/` | Pixel helpers: `mkboot.sh`, root tweaks, wallpaper, nofill, Wi-Fi FW fetch |
| `tools/mkadt.py` | ADT; `--sunfish` and `--scale2` for Pixel |
| `docs/WIFI_WCN3990_PLAN.md` | Staged WCN3990 Wi-Fi bring-up |
| `docs/GPU_A618_PLAN.md` | Adreno 618 GPU plan |
| `NOTES.md` | Upstream sweet engineering log (still useful) |

## Upstream sweet

The Redmi Note 10 Pro (`sweet`) path remains documented upstream: [frokfrdk/ios-sweet-build](https://github.com/frokfrdk/ios-sweet-build). Same SoC family, different panel, touch, and boot packaging.

## Credits

Built on Apple's open-source releases (xnu, IOHIDFamily, libpthread, hfs), [BearSSL](https://bearssl.org), [blacktop/darwin-xnu-build](https://github.com/blacktop/darwin-xnu-build), [ipsw](https://github.com/blacktop/ipsw), Qualcomm / Google published Linux sources for hardware facts (including sm7150-mainline), and the ios-sweet project. iOS itself is Apple's and is not distributed here. Vendor Wi-Fi firmware is not committed; see `tools/sunfish/fetch-wifi-fw.sh`.
