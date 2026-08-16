FROM node:24-bookworm

# git ships with the base image; gh powers T3's GitHub integration (PRs,
# statuses, clone lookups).
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

# t3 plus the provider CLIs it can spawn; auth state for both lands under
# $HOME (/data/home) so logins survive redeploys.
RUN npm i -g t3@latest @openai/codex@latest @anthropic-ai/claude-code@latest

# All credentials (gh, git, provider) and t3 state live under the /data
# volume so they survive redeploys; the image itself stays disposable.
ENV HOME=/data/home

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
