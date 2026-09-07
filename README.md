# kakip-bsp — Ubuntu 26.04 + GNOME (mutter) on Kakip (RZ/V2H)

An Ubuntu 26.04 (resolute) BSP for the Kakip board (AMATAMA, Renesas RZ/V2H
`r9a09g057h48`), built on the **Renesas AI SDK v6.00 kernel 6.1.141-cip43**
(the customer-approved kernel). Userland is Ubuntu 26.04, the desktop is
GNOME on Wayland (mutter), and GPU/VPU use the AI SDK's Mali-G31 and codec
v4.3.3.0 blobs.

## Build environment

The standard build environment is the `26.04-build` Docker container:
ubuntu:26.04, privileged, with your home bind-mounted (root inside, so
mmdebstrap runs in root mode).

### Creating the container

```bash
docker run -d --name 26.04-build --privileged \
    -v /home/wig:/home/mnt \
    ubuntu:26.04 sleep infinity
docker exec -it 26.04-build bash
```

Adjust the `-v` mount so the repo is reachable inside — here `/home/wig` maps
to `/home/mnt`, i.e. the repo lives at
`/home/mnt/dev-nvme/kakip/kaki/ubuntu-26.04/kakip-bsp`. Privileged is needed
for mmdebstrap's chroot/bind-mounts and arm64 binfmt emulation. Then install
the build packages inside the container:

```bash
apt update && apt install -y \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu build-essential \
    git make bc bison flex libssl-dev libelf-dev cpio kmod bzip2 xz-utils \
    python3 python3-pyelftools swig device-tree-compiler \
    mmdebstrap qemu-user-binfmt binfmt-support arch-test fakeroot ubuntu-keyring \
    mtools dosfstools e2fsprogs util-linux ca-certificates wget rsync
```

- Cross-compile (kernel/u-boot/TF-A): `gcc-aarch64-linux-gnu`; host tools
  (fiptool/bptool/mke2fs) via `build-essential`.
- rootfs: `mmdebstrap` + `qemu-user-binfmt` (an x86 host runs the arm64 chroot
  hooks). `qemu-user-binfmt` registers the aarch64 handler; if `make rootfs`
  cannot exec arm64 binaries, run `update-binfmts --enable qemu-aarch64`
  (or `systemctl restart systemd-binfmt`).
- image: `mtools`/`dosfstools` (FAT16 boot) + `e2fsprogs` (ext4 rootfs).
- `dwarves`/pahole is **not** needed (this kernel has BTF off).

`make fetch` clones the private roseapple-dev forks over SSH, so give the
container a key that can read them (mount `~/.ssh` read-only, or add a deploy
key) — or run `make fetch` on the host (the repo is bind-mounted, so `src/`
is visible inside) and only build in the container.

Running on a bare (non-root) host also works — mmdebstrap falls back to
`unshare` + `fakeroot` — but grant subuid traverse to your home once:
`setfacl -m u:100000:--x /home/$USER`. Disk: src + build ≈ 20 GB.

### Day-to-day

```bash
docker exec -it 26.04-build bash
cd /home/mnt/dev-nvme/kakip/kaki/ubuntu-26.04/kakip-bsp
```

## Components

Per-component pins live in `configs/components/*.mk`; to bump a component,
edit its `.mk`. `make fetch` pulls every source from GitHub:

- **roseapple-dev forks** (SSH key required) carry the AI SDK patches baked in
  as commits — there is no build-time patching:
  kernel (`kakip_linux`), u-boot (`kakip_u-boot`),
  TF-A (`kakip_trusted-firmware`), `mmngr_drv`, `vspm_drv`, `vspmif_drv`,
  `vspmif_lib`, `vspmfilter`.
- **upstream renesas** for the unpatched pieces: `mmngr_lib`, `gst-omx`.
- The kernel config is an in-tree `arch/arm64/configs/kakip_defconfig` on the
  kernel fork.

The only in-repo patch dir is `patch/mali-km/`: the Mali kernel module ships
as a closed blob tarball (not a git repo), so it is patched at build time.
The closed Renesas blobs are cached in `dl/` (SHA256-verified); rebuild the
cache by setting `BLOB_BASE_URL=<server>`, or by providing the local AI SDK
package as a fallback source.

Provenance is documented in `docs/MANIFEST.md` and `patch/PROVENANCE.md`.

## Build order

Run in the container, in order (there are dependencies — do not reorder):

```bash
make clean        # wipe build/ (keeps src/ and dl/); distclean is not needed for a normal rebuild
                  # clean/distclean must run in the container too: build outputs are root-owned
                  # (distclean also wipes src/ and dl/* except SHA256SUMS; FORCE=1 if src/ has uncommitted work)
make fetch        # sources into src/ (skipped if present) + blobs into dl/
make kernel       # -> build/kernel/{Image, r9a09g057h48-kakip.dtb} + build/modules-stage
make modules      # out-of-tree: mali_kbase / mmngr / mmngrbuf / vspm / vspm_if / uvcs
make bootloader   # from source: u-boot 2024.07 + TF-A 2.10 -> dl/bootloader/kakip/{bp,bl2,fip}
make rootfs       # mmdebstrap -> build/rootfs.tar
make image        # -> build/kakip-ubuntu-26.04-gnome-arm64.img
```

Dependencies:

- `kernel` + `modules` **must run before `rootfs`** — the rootfs post-config
  copies `build/modules-stage/lib/modules` into the image and errors if it is
  absent.
- `bootloader` before `image`; its output lives in `dl/bootloader/kakip/`
  (which survives `make clean`), so skip it when u-boot/TF-A are unchanged.
- `image` needs `rootfs.tar` + the kernel Image/dtb + `dl/bootloader/kakip/`.

The resulting `.img` is self-consistent (the kernel version string matches the
baked-in modules); `dd` the whole image to an SD card to boot. After a
kernel/modules-only change you can skip the bootstrap and refresh the image's
modules with `tools/update_rootfs_modules.sh`, then `make image`.

`make rootfs` does three things inside the mmdebstrap namespace:

1. Bootstrap resolute + `ubuntu-desktop-minimal`/GDM (login `ubuntu`/`ubuntu`).
2. **`ubuntu_post_config.sh`**: install the kernel modules and the Mali UM
   blob (Mesa's libEGL/libGLESv2/libgbm are diverted and replaced by the Mali
   builds), the VPU codec blob + `/etc/omxr` + OMX headers, udev rules, and
   the GNOME integration (`gpuconfig` patchelfs libmutter's libGL dependency
   to libGLESv2 at boot, GDM is locked to Wayland, `gen-monitors.py`); it also
   applies the clock workaround (see Known issues).
3. **`build_gst_plugins.sh`**: in an arm64 chroot (qemu), build the
   mmngr/mmngrbuf/libvspm userspace libs, gst-omx (target=rz) and vspmfilter
   against GStreamer 1.28, ending with a `gst-inspect` sanity check. A failure
   leaves `/etc/bsp-gst-failed` but does not abort the bootstrap.

### Iterating on the gst hook (without a full bootstrap)

```bash
tools/rerun_gst_hook.sh            # reads build/rootfs.tar -> build/rootfs-gst.tar
mv build/rootfs-gst.tar build/rootfs.tar && make image
```

`--variant=custom` + `tar-in` replays only the hook onto the existing rootfs
(~10 min).

## Flashing (Kakip, eSD boot)

`dd` the whole image — `create_image.sh` embeds the bootloader
(sector 1 = boot-param / sector 8 = BL2 / sector 768 = FIP):

```bash
sudo dd if=build/kakip-ubuntu-26.04-gnome-arm64.img of=/dev/sdX bs=4M conv=fsync status=progress
```

No Flash Writer / xSPI is involved. Kakip is eSD boot:
BootROM → TF-A → u-boot → kernel → GDM (Wayland).

## Known issues

- **RTC**: the `rtc-rtca3` probe fails (`-ETIMEDOUT`), so the boot clock is
  wrong until NTP syncs. Worked around in the rootfs (apt date-check disabled
  + systemd-timesyncd enabled); the real fix is the RTC itself (DT/driver).
- **Display**: the device tree has no on-SoC HDMI output (the ADV7535 bridge
  was removed); the desktop is driven over USB DisplayLink (`DRM_UDL`). Add a
  bridge node if on-SoC HDMI is required.
- **PCIe**: `rzg3s-pcie` probe returns `-ETIMEDOUT`.
- **SPI flash**: the DT `compatible` is `mt25qu512a`, but the board fits
  `w25q256jwm` (it still probes via `jedec`; correct the compatible when
  convenient).
- **DRP / DRP-AI** are not ported to 6.1 yet (removed for now; re-add from the
  AI SDK when the feature is needed).
- **Blob licensing**: Mali/codec/TVM are closed Renesas blobs — review
  `codec_pkg_product_v4.3.3.0/License.txt` and the AI SDK terms before
  shipping.

## Layout

```
configs/sdk.yml           identity (kernel pin, Ubuntu codename)
configs/components/*.mk   per-component URL / REV / fetch target
include/download.mk       fetch_git / fetch_blob macros
configs/ubuntu/           rootfs bootstrap (mmdebstrap + hooks) + post-config
patch/mali-km/            build-time patches for the Mali KM blob tarball
vendor/gstomx.conf        Renesas gst-omx config (templated at build time)
dl/                       closed blob cache (SHA256SUMS; gitignored, only the checksum is tracked)
system/                   gpuconfig, gen-monitors, udev rules (BSP-owned)
src/                      sources fetched by `make fetch` (gitignored)
tools/                    per-step build scripts (incl. rerun_gst_hook.sh, update_rootfs_modules.sh)
build/                    outputs (kernel, modules-stage, rootfs.tar, .img)
docs/MANIFEST.md          provenance and open items
```
