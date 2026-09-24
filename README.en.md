# macOS Hangul Switch

[한국어](README.md)

Use a Windows keyboard's Han/Yeong key as a global macOS input-source switch. Physical keyboards and Windows Moonlight clients are supported without Karabiner-Elements, another key-remapping app, or `sudo`.

## Support matrix

| Feature | Status | Notes |
|---|---:|---|
| Physical `LANG1` Han/Yeong key | ✅ | Enabled by default |
| Physical Right Alt | ✅ | Enabled by default; replaces its Option behavior |
| Physical Right Command | ✅ | Optional with `--right-command` |
| Windows Moonlight Han/Yeong and Right Alt | ✅ | Optional with `--sunshine` |
| Recovery after login, reboot, and keyboard reconnect | ✅ | User LaunchAgent reapplies every 10 seconds |
| Backup and restoration of previous settings | ✅ | Conflicting mappings are not overwritten |
| Caps Lock input-source switching | ⚠️ | Left untouched and not guaranteed |
| In-progress composition in Chromium-based apps | ⚠️ | Unresolved marked-text behavior |

Verified on macOS 26.3.1 Apple Silicon with Sunshine `2026.516.143833` and a Windows Moonlight client. Reports from other macOS and Sunshine versions are welcome.

## Quick start

First, add English (ABC) and Korean (2-Set) input sources in macOS. This project does not install input sources.

Clone the repository and install it from Terminal. By default, Right Alt switches input sources instead of acting as Option.

```bash
git clone https://github.com/hae-long/macos-hangul-switch.git
cd macos-hangul-switch
./install.sh
./status.sh
```

Use `./status.sh` to check that the LaunchAgent, F18 shortcut, and key mappings are active. The default profile maps the global HID `LANG1` and Right Alt inputs to F18. To keep Right Alt as Option and map only a dedicated language key:

```bash
./install.sh --lang1-only
```

To reproduce the full configuration used to validate this project:

```bash
./install.sh --right-command --sunshine
```

Right Alt and optional Right Command lose their original modifier behavior when mapped.

### Options

| Option | Behavior |
|---|---|
| `--lang1-only` | Map only the physical `LANG1` key |
| `--right-command` | Also use Right Command as Han/Yeong |
| `--sunshine` | Add the remote mapping to `~/.config/sunshine/sunshine.conf` |

The installer merges existing `hidutil` mappings. It exits without changing persistent configuration when a source key already maps to a different destination.

## Moonlight and Sunshine

On the verified Windows Moonlight path, Han/Yeong and Right Alt arrive as macOS Right Option. Sunshine therefore needs:

```text
0xA5 (VK_RMENU) → 0x81 (VK_F18)
```

Configure it with:

```bash
./install.sh --sunshine
```

The helper creates a backup, preserves unrelated keybindings, and rejects a conflicting `0xA5` mapping. It never restarts Sunshine automatically because doing so disconnects the current Moonlight session.

After saving your work, restart Sunshine using the method appropriate to your installation. For Homebrew:

```bash
brew services restart sunshine
```

For the verified Homebrew LaunchAgent:

```bash
launchctl kickstart -k "gui/$(id -u)/homebrew.mxcl.sunshine"
```

For a custom configuration path:

```bash
MHS_SUNSHINE_CONFIG=/path/to/sunshine.conf ./install.sh --sunshine
```

## Uninstall and restore

```bash
./uninstall.sh
```

This restores the recorded pre-install HID mapping, symbolic hotkey 60, and previous LaunchAgent. It removes the Sunshine pair only when this project added it. To keep Sunshine unchanged:

```bash
./uninstall.sh --keep-sunshine
```

Recovery state is retained under:

```text
~/Library/Application Support/macos-hangul-switch.uninstalled-TIMESTAMP-PID
```

## Known limitations

- Caps Lock is not remapped. The native macOS Caps Lock input-source option may work in some environments, but it was not reliable in the verified physical and remote sessions.
- Some Chromium-based apps can mishandle in-progress Korean marked text across an input-source switch. Commit the composition with Space, Enter, or an arrow key before switching.
- Moonlight clients and keyboard layouts may send a code other than `VK_RMENU(0xA5)`.
- The LaunchAgent runs after user login; it does not apply at FileVault or other pre-login screens.

## Documentation

- [How it works](docs/how-it-works.md)
- [Troubleshooting and rollback](docs/troubleshooting.md)
- [Contributing](CONTRIBUTING.md)

## License

[MIT](LICENSE)
