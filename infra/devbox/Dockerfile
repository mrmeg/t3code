FROM node:24-bookworm

# git ships with the base image; gh powers T3's GitHub integration (PRs,
# statuses, clone lookups). zsh is for interactive terminals — T3 spawns
# $SHELL, so set SHELL=/usr/bin/zsh on the service to use it; shell config
# lives in $HOME on the volume. tailscale is the data plane for dev servers:
# phones reach Metro/Vite on the box over the tailnet (userspace networking,
# since Railway containers have no TUN device).
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl zsh \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
  && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
    -o /usr/share/keyrings/tailscale-archive-keyring.gpg \
  && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list \
    -o /etc/apt/sources.list.d/tailscale.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh tailscale \
  && rm -rf /var/lib/apt/lists/*

# t3 plus the provider CLIs it can spawn; auth state for both lands under
# $HOME (/data/home) so logins survive redeploys. bun runs the app projects,
# eas-cli builds/submits them on EAS, and @expo/ngrok backs
# `expo start --tunnel` without an interactive install prompt. Docker caches
# this layer, so these versions are only a floor: entrypoint.sh reinstalls
# all of them on every start.
RUN npm i -g t3@latest @openai/codex@latest @anthropic-ai/claude-code@latest \
  bun@latest eas-cli@latest @expo/ngrok@latest

# All credentials (gh, git, provider) and t3 state live under the /data
# volume so they survive redeploys; the image itself stays disposable. bun's
# install cache joins them so the daily restart doesn't re-download every
# project's dependency tree.
ENV HOME=/data/home
ENV BUN_INSTALL_CACHE_DIR=/data/cache/bun

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
