# Android control via Mobile Next MCP (Petasos)

Optional: let your Hermes agent see and operate your Android phone (launch apps, read the
screen, tap, swipe, take screenshots) through the [Mobile Next MCP server](https://github.com/mobile-next/mobile-mcp)
over paired wireless ADB. Petasos itself does not need this; push notifications work without it.

## Install

1. Install Android Platform Tools (`adb`) and Node.js 20+ on your Hermes host.
2. Install a pinned, audited version (1.0.16 is newer than the fixes for
   GHSA-3p2m-h2v6-g9mx and GHSA-5qhv-x9j4-c3vm):

   ```bash
   npm install --prefix ~/.hermes/tools/mobile-mcp --save-exact --ignore-scripts @mobilenext/mobile-mcp@1.0.16
   ```

3. Add an MCP entry to `~/.hermes/config.yaml` under `mcp_servers:` (back the file up first).
   Use absolute paths for your machine:

   ```yaml
     android_mobile_mcp:
       command: /opt/homebrew/bin/node
       args:
         - /Users/<you>/.hermes/tools/mobile-mcp/node_modules/@mobilenext/mobile-mcp/lib/index.js
       env:
         MOBILEMCP_DISABLE_TELEMETRY: '1'
         PATH: /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
       enabled: true
       trust: untrusted
       supports_parallel_tool_calls: false
       tools:
         include:
           - mobile_list_available_devices
           - mobile_get_foreground_app
           - mobile_launch_app
           - mobile_list_elements_on_screen
           - mobile_take_screenshot
           - mobile_click_on_screen_at_coordinates
           - mobile_swipe_on_screen
           - mobile_press_button
         resources: false
         prompts: false
   ```

4. Pair the phone (below), then reload MCP in Hermes (`/reload-mcp`) and ask it to list devices.

## Security choices

- `trust: untrusted`: Hermes asks for approval before write-capable tools run.
- An allowlist of eight tools. No uninstall, clipboard, URL intents, arbitrary install,
  file-save or screen-recording tools are exposed.
- Telemetry disabled. No HTTP listener or public device-control port is opened; the server
  runs over stdio on the Hermes host.

## Cable-free Android 11+ pairing: preferred secure approach

On the **unlocked phone**, with Mac and Android on the **same trusted Wi-Fi**:

1. **Settings → Developer options → Wireless debugging**. Enable it
   and approve the trusted network prompt.
2. Enter **Pair device with pairing code**. Keep the pairing screen open
   while pairing.
3. Use `adb pair <IP>:<pairing-port>` **on the Mac** and enter the
   six-digit code **locally**; never put the pairing code or endpoint in
   GitHub workflow inputs, committed files, PR comments or CI logs.
4. Once paired, Android displays a separate **IP address & Port**
   for debugging. Run `adb connect <IP>:<debug-port>` if mDNS
   automatic discovery has not already connected it.
5. Run `adb devices -l` to verify a device with a
   `<IP>:<debug-port>  device` transport. Only then unplug USB and
   check `adb devices` again. No APK reinstall is required.
6. A second later connection may use mDNS on trusted networks; ports can
   change with Wi-Fi or Wireless debugging restarts. If unavailable,
   reconnect with the *current* debug port. Check
   `adb mdns services` for discovery.

Do **not** use `adb tcpip 5555`, forward the ADB daemon or Mobile MCP port
on the public internet, or enable an HTTP listener without separate secure
authentication and network controls. Legacy ADB-over-TCP is a broader exposure
than Android's paired wireless-debugging mode.

Android and Mac must be able to reach each other. Pairing on one LAN does
not guarantee control over arbitrary cellular or remote Tailscale paths.
Tailscale is a separate remote transport decision requiring verified address
binding, reachability and access restrictions. The Petasos push-notification
transport is independent of ADB and remains designed to work when wireless
debugging is off.

**If the screen is locked or cannot be read:** unlock the device yourself
and confirm Wireless debugging on-device. UI automation must never bypass
the device lock or ask for the PIN in chat, issues or CI. Once paired, a
Hermes session can reload its MCP tools via `/reload-mcp` and use them
without keeping a USB cable attached.

## Moving to a new machine

Repeat the install steps, update the absolute paths, and authorize the new machine on the
phone with Android's own USB or Wireless debugging prompt. Never commit ADB keys.

## References

- [Mobile Next/mobile-mcp](https://github.com/mobile-next/mobile-mcp)
- [Android official wireless ADB guide](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi)
- [Hermes MCP configuration](https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp/)
