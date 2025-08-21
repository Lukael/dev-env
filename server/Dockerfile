# Build arguments
ARG CUDA_VER=12.4.1
ARG UBUNTU_VER=22.04

# Download the base image
FROM nvidia/cuda:${CUDA_VER}-cudnn-runtime-ubuntu${UBUNTU_VER}
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
    unzip \
    vim \
    wget \
	pipx \
    zsh \
    zip && \
    apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

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

# Change Workdir
WORKDIR /home/${USERNAME}

RUN pipx ensurepath

# Install poetry
RUN pipx install poetry

# Install oh-my-zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true && \
    cp -f ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc

# Install zsh plugins
RUN ZSH_CUSTOM="${ZSH_CUSTOM:-~/.oh-my-zsh/custom}" \
    && git clone --depth=1 https://github.com/MichaelAquilina/zsh-autoswitch-virtualenv.git "$ZSH_CUSTOM/plugins/zsh-autoswitch-virtualenv" \
    && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

RUN if grep -qE '^plugins=' ~/.zshrc; then \
    sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-autoswitch-virtualenv zsh-syntax-highlighting)/' ~/.zshrc; \
  else \
    sed -i '/^source \$ZSH\/oh-my-zsh.sh/i plugins=(git zsh-autosuggestions zsh-autoswitch-virtualenv zsh-syntax-highlighting)' ~/.zshrc; \
  fi

# Install powerlevel10k
RUN curl -fsSL https://raw.githubusercontent.com/romkatv/powerlevel10k/master/config/p10k-classic.zsh -o ~/.p10k.zsh \
    && echo '\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' >> ~/.zshrc

# Change git config
RUN git config --global push.autoSetupRemote true
