# Symphony Elixir — Dockerized Agent Sandbox
# Multi-stage build: compile Symphony, then run in a slim image.

FROM hexpm/elixir:1.19.5-erlang-28.0-ubuntu-noble-20250415.1 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates make && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY elixir/ ./

ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force
RUN mix setup
RUN mix build

# ---------------------------------------------------------------------------
# Runtime image
# ---------------------------------------------------------------------------
FROM hexpm/elixir:1.19.5-erlang-28.0-ubuntu-noble-20250415.1

# Core tooling an agent needs inside the sandbox
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget jq openssh-client ca-certificates \
    build-essential python3 python3-pip python3-venv \
    nodejs npm sudo && \
    rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Codex CLI (OpenAI)
RUN npm install -g @openai/codex

# Non-root user with passwordless sudo (agent gets full root when needed)
RUN useradd -m -s /bin/bash agent && \
    echo "agent ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Copy the compiled Symphony escript from builder
COPY --from=builder /build/bin/symphony /usr/local/bin/symphony
# Copy mix project files needed at runtime
COPY --from=builder /build/_build /opt/symphony/_build
COPY --from=builder /build/deps /opt/symphony/deps
COPY --from=builder /build/mix.exs /opt/symphony/mix.exs
COPY --from=builder /build/mix.lock /opt/symphony/mix.lock
COPY --from=builder /build/lib /opt/symphony/lib
COPY --from=builder /build/config /opt/symphony/config

# Default directories
RUN mkdir -p /workspaces /workflow && chown -R agent:agent /workspaces /workflow

USER agent
WORKDIR /home/agent

# Volumes:
#   /workflow   — mount your project's WORKFLOW.md here
#   /workspaces — Symphony clones per-issue workspaces here
#   /repo       — optionally mount your target repo for local dev
VOLUME ["/workflow", "/workspaces", "/repo"]

# Dashboard port
EXPOSE 4000

# Default: start Symphony pointing at the mounted WORKFLOW.md
ENTRYPOINT ["symphony"]
CMD ["/workflow/WORKFLOW.md", "--port", "4000", "--i-understand-that-this-will-be-running-without-the-usual-guardrails"]
