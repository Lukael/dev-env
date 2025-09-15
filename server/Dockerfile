# Build arguments
ARG CUDA_VER=12.4.1
ARG UBUNTU_VER=22.04

# Download the base image
FROM nvidia/cuda:${CUDA_VER}-cudnn-devel-ubuntu${UBUNTU_VER}
# you can check for all available images at https://hub.docker.com/r/nvidia/cuda/tags

# Install as root
USER root

# Shell
SHELL ["/bin/bash", "--login", "-o", "pipefail", "-c"]

# Install dependencies
ARG DEBIAN_FRONTEND="noninteractive"
ARG USERNAME=coder
ARG USERID=1000
ARG GROUPID=1000
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    bash-completion \
    ca-certificates \
    curl \
    git \
    htop \
    nano \
    nvidia-modprobe \
    nvtop \
    openssh-client \
    python3 python3-dev python3-pip python-is-python3 \
    sudo \
    tmux \
    byobu \
    unzip \
    vim \
    wget \
	pipx \
    zsh \
    zip && \
    apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install lazygit
RUN set -eux; \
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" \
        | grep -Po '"tag_name": *"v\K[^"]*') && \
    curl -Lo /tmp/lazygit.tar.gz \
        "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" && \
    tar -C /tmp -xf /tmp/lazygit.tar.gz lazygit && \
    install -m 0755 /tmp/lazygit /usr/local/bin/lazygit && \
    rm -f /tmp/lazygit.tar.gz /tmp/lazygit

# Change shell to zsh
RUN chsh -s /bin/zsh

# Add a user `${USERNAME}` so that you're not developing as the `root` user
RUN groupadd -g ${GROUPID} ${USERNAME} && \
    useradd ${USERNAME} \
    --create-home \
    --uid ${USERID} \
    --gid ${GROUPID} \
    --shell=/bin/bash && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >>/etc/sudoers.d/nopasswd

# Change to your user
USER ${USERNAME}

# Change shell to zsh
RUN sudo chsh -s $(which zsh) $(whoami)

# Change Workdir
WORKDIR /home/${USERNAME}

RUN pipx ensurepath

# Install poetry
RUN pipx install poetry

# Install oh-my-zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true && \
    cp -f $HOME/.oh-my-zsh/templates/zshrc.zsh-template $HOME/.zshrc

# Install zsh plugins
RUN ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}" \
    && git clone --depth=1 https://github.com/MichaelAquilina/zsh-autoswitch-virtualenv.git "$ZSH_CUSTOM/plugins/autoswitch_virtualenv" \
    && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

RUN if grep -qE '^plugins=' $HOME/.zshrc; then \
    sed -i 's/^plugins=.*/plugins=(git autoswitch_virtualenv zsh-syntax-highlighting)/' $HOME/.zshrc; \
  else \
    sed -i '/^source \$ZSH\/oh-my-zsh.sh/i plugins=(git autoswitch_virtualenv zsh-syntax-highlighting)' $HOME/.zshrc; \
  fi

# Install powerlevel10k
RUN ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}" \
    && git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k" \
    && sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' $HOME/.zshrc \
    && curl -fsSL https://raw.githubusercontent.com/romkatv/powerlevel10k/master/config/p10k-classic.zsh -o $HOME/.p10k.zsh \
    && printf '\n[[ -f $HOME/.p10k.zsh ]] && source $HOME/.p10k.zsh\n' >> $HOME/.zshrc

# Set default as byobu
RUN byobu-enable

# Change git config
RUN git config --global push.autoSetupRemote true

# Install poetry shell
RUN poetry self add poetry-plugin-shell
