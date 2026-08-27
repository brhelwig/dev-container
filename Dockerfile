FROM debian:bookworm

ARG USERNAME=dev
ARG USER_UID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

ARG BASE_PACKAGES="build-essential ca-certificates curl file git git-lfs gnupg locales man-db openssh-server procps python3 sudo tini unzip zsh"
RUN apt-get update && apt-get install -y --no-install-recommends $BASE_PACKAGES \
    && git lfs install --system \
    && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen \
    && rm -f /etc/ssh/ssh_host_* \
    && rm -rf /var/lib/apt/lists/*

RUN HOME=/etc/skel RUNZSH=no CHSH=no \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && printf 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"\n' | tee -a /etc/skel/.zshrc /etc/skel/.bashrc \
    && printf 'PROMPT="%%F{cyan}%%m%%f $PROMPT"\n' >> /etc/skel/.zshrc

ARG APT_PACKAGES="mosh podman"
RUN apt-get update && apt-get install -y --no-install-recommends $APT_PACKAGES \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/containers/registries.conf.d \
    && printf 'unqualified-search-registries = ["docker.io"]\n' \
        > /etc/containers/registries.conf.d/00-unqualified-docker.conf \
    && printf '#!/bin/sh\nexec sudo /usr/bin/podman "$@"\n' > /usr/local/bin/podman \
    && chmod +x /usr/local/bin/podman \
    && mkdir -p /etc/containers && printf '%s\n' \
        '[storage]' \
        'driver = "overlay"' \
        "graphroot = \"/home/$USERNAME/.local/share/containers/storage\"" \
        "runroot = \"/home/$USERNAME/.local/share/containers/run\"" \
        > /etc/containers/storage.conf

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
           conntrack e2fsprogs ethtool iproute2 socat util-linux \
    && rm -rf /var/lib/apt/lists/* \
    && case "$(dpkg --print-architecture)" in \
         arm64) asset=k3s-arm64 ;; \
         amd64) asset=k3s ;; \
         *) echo "unsupported arch for k3s: $(dpkg --print-architecture)" >&2; exit 1 ;; \
       esac \
    && tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
              https://update.k3s.io/v1-release/channels/stable | sed 's|.*/||')" \
    && echo "installing k3s $tag ($asset)" \
    && curl -fsSL -o /usr/local/bin/k3s \
         "https://github.com/k3s-io/k3s/releases/download/$(printf '%s' "$tag" | sed 's/+/%2B/')/$asset" \
    && chmod +x /usr/local/bin/k3s \
    && /usr/local/bin/k3s --version

RUN case "$(dpkg --print-architecture)" in \
      arm64) asset=cli-alpine-arm64 ;; \
      amd64) asset=cli-alpine-x64 ;; \
      *) echo "unsupported arch for the VS Code CLI: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac \
    && curl -fsSL --retry 5 --retry-delay 5 -o /tmp/vscode-cli.tar.gz \
         "https://code.visualstudio.com/sha/download?build=stable&os=$asset" \
    && tar -xzf /tmp/vscode-cli.tar.gz -C /usr/local/bin code \
    && rm -f /tmp/vscode-cli.tar.gz \
    && /usr/local/bin/code --version

RUN useradd --uid $USER_UID --create-home --shell /usr/bin/zsh $USERNAME \
    && printf '%s\n' \
         "$USERNAME ALL=(ALL) NOPASSWD:ALL" \
         'Defaults:'"$USERNAME"' secure_path="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' \
         > /etc/sudoers.d/$USERNAME \
    && visudo -c -f /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && chown -R $USERNAME:$USERNAME "/home/$USERNAME"

USER $USERNAME
ENV HOME=/home/$USERNAME SHELL=/usr/bin/zsh
WORKDIR $HOME

RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"

ARG BREW_TAPS="terraform-linters/tap hashicorp/tap"
RUN for t in $BREW_TAPS; do brew tap "$t" && { brew trust "$t" || true; }; done

ARG BREW_FORMULAE="ansible awscli azure-cli cloudflare-wrangler cloudflared docker docker-compose fzf gh go golangci-lint gum hadolint hashicorp/tap/terraform helm helmfile htop jq k9s kubectl kubectx kustomize lazygit lazysql nano node pre-commit rust shellcheck sops sqlite tailscale uv watch yq zellij zstd"
RUN brew install $BREW_FORMULAE

ARG BREW_CASKS="claude-code@latest gcloud-cli tflint"
RUN for c in $BREW_CASKS; do \
      out="$(brew install --cask "$c" 2>&1)" && rc=0 || rc=$?; \
      printf '%s\n' "$out"; \
      [ "$rc" -eq 0 ] && continue; \
      if brew list --cask "$c" >/dev/null 2>&1 || printf '%s' "$out" | grep -q 'Linking Binary'; then \
        echo "note: cask $c installed (tolerating exit $rc)"; \
      else \
        echo "ERROR: cask $c failed to install" >&2; exit 1; \
      fi; \
    done

RUN gcloud components install gke-gcloud-auth-plugin --quiet
ENV PATH="/home/linuxbrew/.linuxbrew/share/google-cloud-sdk/bin:${PATH}"

ENV DOCKER_HOST="unix:///run/podman/podman.sock"

USER root
COPY sshd_config /etc/ssh/dev-container-sshd.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY dev/dev /usr/local/bin/dev
COPY dev/lib/ /usr/local/lib/dev/
COPY dev/nice.sh /etc/dev-nice.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/dev \
    && printf '\n[ -r /etc/dev-nice.sh ] && . /etc/dev-nice.sh\n' >> /etc/zsh/zshenv \
    && printf '\n[ -x /usr/local/bin/dev ] && /usr/local/bin/dev welcome\n' >> /etc/zsh/zshrc \
    && install -d -o $USERNAME -g $USERNAME /var/lib/dev /var/lib/dev/kube \
    && for t in dev bash zsh ionice losetup findmnt mkfs.ext4 truncate; do \
         command -v "$t" > /dev/null || { echo "missing: $t" >&2; exit 1; }; \
       done \
    && shellcheck -x -S warning /usr/local/bin/dev /usr/local/bin/entrypoint.sh \
         /usr/local/lib/dev/*.sh /etc/dev-nice.sh

ENV KUBECONFIG=/var/lib/dev/kube/config:/var/lib/dev/kube/k3s.yaml

USER $USERNAME
WORKDIR $HOME
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/zsh"]
