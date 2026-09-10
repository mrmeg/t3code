FROM node:24-bookworm

# git ships with the base image; gh powers T3's GitHub integration (PRs,
# statuses, clone lookups). zsh is for interactive terminals — T3 spawns
# $SHELL, so set SHELL=/usr/bin/zsh on the service to use it; shell config
# lives in $HOME on the volume. tailscale is the data plane for dev servers:
# phones reach Metro/Vite on the box over the tailnet (userspace networking,
# since Railway containers have no TUN device). ripgrep/fd/jq/less/tmux are
# what agents and their skills reach for without asking; a missing `rg` or `jq`
# turns a working skill into a confusing failure. apt installs do not persist,
# so anything here has to be here rather than added to the volume by hand.
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
  && apt-get install -y --no-install-recommends gh tailscale tini \
    ripgrep fd-find jq less tmux \
  && ln -s "$(command -v fdfind)" /usr/local/bin/fd \
  && rm -rf /var/lib/apt/lists/*

# uv: the Python side of the toolchain, one static binary, installed into the
# image rather than the volume so it cannot half-exist after a volume reset.
RUN curl -fsSL https://astral.sh/uv/install.sh \
  | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh

# t3, the provider CLIs it can spawn, and the service CLIs the agents' skills
# drive (railway, supabase, stripe, clerk, sentry, cloudflare, vercel); auth
# state for all of them lands under $HOME (/data/home) so logins survive
# redeploys. bun and pnpm run the app projects, eas-cli builds/submits them on
# EAS, and @expo/ngrok backs `expo start --tunnel` without an interactive
# install prompt. Docker caches this layer, so these versions are only the
# fallback for a fresh volume: devbox-refresh stages current releases into
# /data/cli/next while the box runs, and entrypoint.sh promotes them to
# /data/cli/current on the next boot. PATH prefers that release over the baked
# one (harmless when it is absent). Keep this list and the one in
# devbox-refresh.sh identical, or a fresh volume ships a different tool set than
# a refreshed one.
RUN npm i -g t3@latest @openai/codex@latest @anthropic-ai/claude-code@latest \
  bun@latest pnpm@latest eas-cli@latest @expo/ngrok@latest \
  @railway/cli@latest supabase@latest @stripe/cli@latest clerk@latest \
  @sentry/cli@latest wrangler@latest vercel@latest
ENV PATH=/data/cli/current/bin:/data/home/.local/bin:$PATH

# All credentials (gh, git, provider) and t3 state live under the /data
# volume so they survive redeploys; the image itself stays disposable. bun's
# install cache joins them so the daily restart doesn't re-download every
# project's dependency tree.
ENV HOME=/data/home
ENV BUN_INSTALL_CACHE_DIR=/data/cache/bun

# Tailscale SSH sessions (Zed remote, plain ssh) start from /etc/passwd, not
# from the image ENV. Give root the home and shell t3 itself runs with, so an
# ssh terminal sees the same logins, zshrc and .zed_server.
RUN sed -i 's#^\(root:x:0:0:[^:]*:\)[^:]*:[^:]*$#\1/data/home:/usr/bin/zsh#' /etc/passwd

# One environment definition, wired into every entry point: zshenv for all zsh
# (T3 terminals, Tailscale SSH, Zed), profile.d for login sh/bash, BASH_ENV for
# non-interactive bash. Without this a PATH entry or token set in ~/.zshrc is
# invisible to exactly the shells agents run in.
COPY devbox-env.sh /etc/devbox-env.sh
RUN printf '\n. /etc/devbox-env.sh\n' >> /etc/zsh/zshenv \
  && printf '. /etc/devbox-env.sh\n' > /etc/profile.d/devbox.sh
ENV BASH_ENV=/etc/devbox-env.sh

COPY entrypoint.sh /entrypoint.sh
COPY devbox-refresh.sh /usr/local/bin/devbox-refresh
RUN chmod +x /entrypoint.sh /usr/local/bin/devbox-refresh
# tini reaps the background refresh loop and forwards SIGTERM to t3 on redeploy.
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
