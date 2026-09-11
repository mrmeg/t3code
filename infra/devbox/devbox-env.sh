# Devbox environment, sourced by every shell flavour so a tool or credential is
# there however a process was started: /etc/zsh/zshenv covers all zsh (T3
# terminals, Tailscale SSH, Zed), /etc/profile.d covers login sh/bash, and
# $BASH_ENV covers non-interactive bash — the shape an agent's Bash tool uses.
# Processes t3 spawns already inherit the image ENV; this closes the other doors.
# Sourced, never executed: no output, no side effects, cheap enough to run per
# shell.

# Listed lowest priority first, since each is prepended: the staged CLI release
# ends up ahead of everything, which is the point. Stale copies of the same CLIs
# exist under ~/.npm-global from an earlier devbox; nothing here puts that
# directory on PATH, and nothing should.
for _devbox_dir in /data/home/.opencode/bin /data/home/.local/bin /data/cli/current/bin; do
  case ":$PATH:" in
    *":$_devbox_dir:"*) ;;
    *) PATH="$_devbox_dir:$PATH" ;;
  esac
done
unset _devbox_dir
export PATH

# Propagate to non-interactive bash started from a shell that has no image ENV —
# a Tailscale SSH session, say. Sourcing this file again is harmless: the PATH
# guard above makes it idempotent.
export BASH_ENV=/etc/devbox-env.sh

# Credentials mirrored out of the Railway service variables by entrypoint.sh,
# because those variables reach PID 1 but not a Tailscale SSH session.
[ -r /data/home/.config/devbox/env ] && . /data/home/.config/devbox/env
