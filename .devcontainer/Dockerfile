# Image for a project's dev container.
# Based on Anthropic's reference Dockerfile (github.com/anthropics/claude-code/tree/main/.devcontainer).
# Every deviation from it is marked "CHANGE:".

# CHANGE: Node 24 LTS instead of Node 20 (end of life). The Salesforce CLI needs Node 22 or later.
FROM node:24-bookworm

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest
ARG SF_CLI_VERSION=latest

# Basic development tools and iptables/ipset for the firewall
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Global npm packages live outside the home folder (the home folder is the project's volume)
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

ENV DEVCONTAINER=true

RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.20.1
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

USER node

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
# CHANGE: ~/.local/bin, where the native installer puts the claude command
ENV PATH=$PATH:/usr/local/share/npm-global/bin:/home/node/.local/bin

ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

ARG ZSH_IN_DOCKER_VERSION=1.2.1
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# CHANGE: Claude Code with the native installer (npm is deprecated). It lives in the home volume and updates itself.
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_CODE_VERSION}"

# CHANGE: the Salesforce CLI
RUN npm install -g "@salesforce/cli@${SF_CLI_VERSION}" && npm cache clean --force

COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
# CHANGE: shell history lives in the home volume instead of its own volume
RUN ln -s /home/node/.commandhistory /commandhistory && \
  mkdir -p /home/node/.commandhistory && touch /home/node/.commandhistory/.bash_history && \
  chown -R node:node /home/node/.commandhistory
USER node
