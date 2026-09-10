# Devbox environment, sourced by every shell flavour so a tool or credential is
# there however a process was started: /etc/zsh/zshenv covers all zsh (T3
# terminals, Tailscale SSH, Zed), /etc/profile.d covers login sh/bash, and
# $BASH_ENV covers non-interactive bash — the shape an agent's Bash tool uses.
# Processes t3 spawns already inherit the image ENV; this closes the other doors.
# Sourced, never executed: no output, no side effects, cheap enough to run per
# shell.

# The staged CLI release outranks the image-baked copies (see devbox-refresh);
# ~/.local/bin holds tools installed by hand onto the volume (aws) and wrappers
# (claude-bedrock).
for _devbox_dir in /data/cli/current/bin /data/home/.local/bin; do
  case ":$PATH:" in
    *":$_devbox_dir:"*) ;;
    *) PATH="$_devbox_dir:$PATH" ;;
  esac
done
unset _devbox_dir
export PATH

# Credentials mirrored out of the Railway service variables by entrypoint.sh,
# because those variables reach PID 1 but not a Tailscale SSH session.
[ -r /data/home/.config/devbox/env ] && . /data/home/.config/devbox/env
