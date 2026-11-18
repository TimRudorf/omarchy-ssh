# SSH for Omarchy

Open and close shared SSH connections from the Omarchy bar. The widget shows
named hosts from your OpenSSH configuration, open masters, and the number of
active shell, command, and file-transfer sessions.

Closing a master stops it from accepting new sessions. Existing sessions can
continue and are no longer counted. Without the optional master-only policy,
clients can still make new direct connections after a master is closed.

## Install

Requires Omarchy with shell plugin support (tested on 4.5.0), Python 3,
OpenSSH 10.3 or newer (`Match tagged` and `ssh -O channels`), and a graphical
SSH askpass such as `ksshaskpass`. The widget uses your existing SSH keys and
host-key checks; it is designed for use with a security key such as a YubiKey.

```sh
omarchy plugin add https://github.com/TimRudorf/omarchy-ssh.git --enable
```

If you don't already have equivalent multiplexing settings, add this block
**after** your host-specific entries in `~/.ssh/config`:

```sshconfig
Host *
    ControlMaster no
    ControlPath ~/.ssh/cm/%C
```

This lets ordinary `ssh`, `scp`, `rsync`, and `sshfs` reuse a master without
starting one automatically. Earlier settings take precedence. The widget
bundles its own helper; it needs no `PATH` changes and never edits `~/.ssh/config`.

### Optional: block direct connections

If you want ordinary clients to require an open master, copy the included
policy into your SSH directory and add the include under the `Host *` block
above:

```sh
cp -n ~/.config/omarchy/plugins/io.github.timrudorf.ssh/ssh/master-only.conf \
      ~/.ssh/master-only.conf
```

```sshconfig
    Include ~/.ssh/master-only.conf
```

For a host that should still allow direct access, set `ProxyCommand none` in
its host block **before** the include. Existing `ProxyCommand` or `ProxyJump`
settings also take precedence; this sample policy does not gate those routes.
Check the effective settings with `ssh -G <host>` and the local master with
`ssh -O check <host>`. This controls normal OpenSSH use, not clients that
deliberately use a different configuration.

## Usage

- Use the SSH icon to open or close a master, or to close all discovered masters.
- The widget lists explicit `Host` aliases, follows `Include` files, and groups
  aliases that share a control socket. Wildcards are rules, not listed hosts.
- Status refreshes locally every 10 seconds, or every 3 seconds while the panel
  is open. Turn off polling in the widget settings to stop periodic refreshes.
- The session count excludes pure port forwarding. If OpenSSH cannot provide
  the count, the widget shows it as unknown.

The bundled command is also available from a terminal:

```sh
~/.config/omarchy/plugins/io.github.timrudorf.ssh/bin/ssh-master status
```

## Uninstall

If you enabled the master-only policy, remove its `Include` from `~/.ssh/config`
to restore direct connections. Keep the multiplexing settings only if you use
them separately. Uninstalling the widget does not close masters; close them
first in the widget if desired.

```sh
omarchy plugin remove io.github.timrudorf.ssh
```

## Development

```sh
omarchy plugin validate .
node --test tests/ssh-widget.test.mjs
python3 -m unittest discover -s tests -p 'test_ssh_master.py' -v
python3 tests/smoke-ssh-widget.py
```

The integration test starts a local `sshd` on loopback with temporary keys. The
widget smoke test needs a Wayland session and uses fixture data instead of SSH.

## License

MIT
