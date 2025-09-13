# Contributing

Thanks for considering a contribution!

## How to contribute
1. Fork the repo and create a feature branch.
2. Keep shell scripts POSIX-compliant (`/bin/sh`), avoid bashisms.
3. Avoid external dependencies on the device (no curl/wget during runtime).
4. Test on a Paper Pro Move running firmware ≥ 3.22.
5. Open a PR with a clear description and steps to verify.

## Coding style
- Two-space indentation for shell.
- Prefer readability over clever one-liners.
- Log to `/home/root/rotate.log` when it helps debugging.

## Reporting issues
Please include:
- Firmware version
- Exact device model (Paper Pro Move)
- Relevant lines from `/home/root/rotate.log`
- Output of `udevadm monitor --kernel --udev` around sleep/wake
