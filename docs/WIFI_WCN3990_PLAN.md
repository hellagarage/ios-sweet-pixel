# WCN3990 Wi-Fi bring-up plan (sunfish / Pixel 4a)

Staged like [`GPU_A618_PLAN.md`](GPU_A618_PLAN.md) and the sweet USB series (`0072`–`0081`). Goal: a real 802.11 link on Pixel 4a under XNU, exposed first as a BSD `ifnet` (not Apple80211 / Settings).

## Hardware facts

From mainline `sm7150.dtsi` + `sm7150-google-sunfish.dts`:

| Item | Value |
| --- | --- |
| Chip | Qualcomm WCN3990 (SNoC ath10k) |
| Compatible | `qcom,wcn3990-wifi` |
| MMIO | `0x18800000` size `0x800000` (`membase`) |
| MSA carve-out | `wlan_msa_mem` @ `0x98d00000` (2 MiB) |
| Calibration variant | `google_sunfish` |
| Regulators (sunfish) | WCSS CX (`vdd_wcss_cx`), 1.8 V XO (`vreg_l1c_1p8`), 1.3 V RFA (`vdd_wcss_adc_dac`), 3.3 V ch0/ch1 (`vreg_l10c_3p3` / `vreg_l11c_3p3`) |
| BT (out of scope) | Same combo, UART3 `qcom,wcn3990-bt` |

Linux uses ath10k SNoC. We reimplement against these facts in XNU; we do not paste the Linux driver.

## Boot-arg stages (`sweetwifi=N`)

| N | Meaning | Phone gate |
| --- | --- | --- |
| 0 | Off (default until explicitly enabled) | — |
| 1 | Read-only probe: map membase, print safe ID/status regs if powered | `SWEET WIFI:` lines on console |
| 2 | RPMh regulator votes for the Wi-Fi rails + clock notes | Rails on without hang |
| 3 | Load `firmware-5.bin` + `board-2.bin` (google_sunfish) into MSA / target | Firmware accept |
| 4 | WMI / HTC / copy-engine bring-up | Host↔target messages |
| 5 | `ifnet` `wlan0`, scan, associate, ping | Link up |

v1 success = N=5 ping. Settings.app / `wifid` / IOKit `IONetworkInterface` come later (same gap as USB `ue0`).

## Firmware (not in git)

See [`tools/sunfish/fetch-wifi-fw.sh`](../tools/sunfish/fetch-wifi-fw.sh):

- `ath10k/WCN3990/hw1.0/firmware-5.bin` from linux-firmware
- sunfish `board-2.bin` with `google_sunfish` variant from sm7150-mainline firmware repos

Place under e.g. `/private/var/sweet/wifi/` on the HFS root or pass as payload blobs (like `GPUFW=1`).

## Patch series

| Patch | Status |
| --- | --- |
| `0112-sunfish-wifi-probe.patch` | **Landed** — `bsd/dev/sweet_wifi.c`, `sweetwifi` boot-arg, UFS-path hook after USB probe |
| later `0113+` | Power (N=2), firmware (N=3), WMI (N=4), ifnet (N=5) |

Hook point matches USB: after `sweet_usb_probe()` in the UFS root bring-up path (`bsd/dev/sweet_ufs.c`).

## Testing

```sh
# Console boot so probe prints are visible
CPUS=6 SWEETLOG=1 ADT=shim/out/sunfish-hi-scale2.adt \
  bash tools/sunfish/mkboot.sh xnu/out wifi1 \
  'ufsrw=1 rootrw=1 sweetfb_hz=30 sweetwifi=1'
fastboot boot shim/out/shim-boot-wifi1.img
```

Look for `SWEET WIFI:` lines. Do not enable N≥2 on-device until N=1 is clean (unclocked MMIO can hang the SoC).

## References

- Linux DT: `arch/arm64/boot/dts/qcom/sm7150*.dts*`
- Binding: `Documentation/devicetree/bindings/net/wireless/qcom,ath10k.yaml`
- Upstream USB pattern: `xnu/patches/0072-sweet-usb-probe.patch` …
- Site note: Wi-Fi needs firmware + remoteproc; USB net was the first network step
