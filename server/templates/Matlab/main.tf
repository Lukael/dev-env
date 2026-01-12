terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~>0.12.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~>3.0.2"
    }
  }
}

locals {
  username = data.coder_workspace.me.owner
}

data "coder_parameter" "matlab_version" {
  name         = "matlab_version"
  display_name = "MATLAB Version"
  description  = "Enter the Matlab version (e.g. r2025b, r2024a)"
  type         = "string"
  mutable      = false
  default      = "r2025b"
  order        = 2
}

data "coder_parameter" "docker_host" {
  name         = "docker_host"
  display_name = "Docker Host"
  description  = "Select which GPU server (Docker host) to use"
  type         = "string"
  icon         = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/docker.png"
  order        = 1
  mutable      = false

  option {
    name  = "PC 0"
    value = ""
  }
  option {
    name  = "Workstation 1"
    value = ""
  }
}

locals {
  gpu_devices = {
    ""                                    = 1
  }
}

locals {
  gpu_string = join(",", [for i in range(local.gpu_devices[data.coder_parameter.docker_host.value]) : i])
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

provider "docker" {
  # Defaulting to null if the variable is an empty string lets us have an optional variable without having to set our own default
  host = data.coder_parameter.docker_host.value != "" ? data.coder_parameter.docker_host.value : null
  ssh_opts = ["-i", "/var/lib/coder/.ssh/docker"]
}

provider "coder" {
}

data "coder_workspace" "me" {
}

locals {
  matlab_base_path = "/@${data.coder_workspace.me.owner}/${data.coder_workspace.me.name}.main/apps/matlab"
}

# Matlab
resource "coder_app" "matlab_browser" {
  agent_id     = coder_agent.main.id
  display_name = "Matlab Browser"
  slug         = "matlab"
  icon         = "/icon/matlab.svg"
  url          = "http://localhost:20000${local.matlab_base_path}"
  subdomain    = false
  share        = "owner"
}

resource "coder_app" "filebrowser" {
  agent_id     = coder_agent.main.id
  display_name = "File Browser"
  slug         = "filebrowser"
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/database.svg"
  url          = "http://localhost:8080"
  subdomain    = false
  share        = "owner"
}

resource "coder_agent" "main" {
  arch                   = "amd64"
  os                     = "linux"
  startup_script         = <<EOT
    #!/bin/bash
    set -euo pipefail
    # make user share directory
    mkdir -p ~/share
    # make user data directory
    mkdir -p ~/data
    export MWI_BASE_URL="${local.matlab_base_path}"
    echo $MWI_BASE_URL
    export MWI_APP_PORT=20000
    echo $MWI_APP_PORT
    # start Matlab browser
    /bin/run.sh -browser > /tmp/matlab-browser.log 2>&1 &
    echo "Starting Matlab Browser"
    # Intall and start filebrowser
    echo "Installing and starting File Browser"
    curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
    filebrowser --noauth -r ~/data >/dev/null 2>&1 &
  EOT

  display_apps {
    vscode                 = false
    ssh_helper             = false
    port_forwarding_helper = false
  }
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "GPU Usage"
    interval     = 10
    key          = "gpu_usage"
    script       = <<EOT
      nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | awk '{printf "%s%% ", $1}'
    EOT
  }

  metadata {
    display_name = "GPU Memory Usage"
    interval     = 10
    key          = "gpu_memory_usage"
    script       = <<EOT
      nvidia-smi --query-gpu=utilization.memory --format=csv,noheader,nounits | awk '{printf "%s%% ", $1}'
    EOT
  }
}

resource "docker_image" "main" {
  name = "coder-${data.coder_workspace.me.id}"
  build {
    context = "./build"
    build_args = {
      MATLAB_RELEASE = data.coder_parameter.matlab_version.value
    }
  }
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(path.module, "build/*") : filesha1(f)]))
    release  = data.coder_parameter.matlab_version.value
  }
}

#home_volume
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}-home"
}

#usr_volume
resource "docker_volume" "usr_volume" {
  name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}-usr"
}

#etc_volume
resource "docker_volume" "etc_volume" {
  name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}-etc"
}

#opt_volume
resource "docker_volume" "opt_volume" {
  name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}-opt"
}

resource "docker_container" "workspace" {
  count  = data.coder_workspace.me.start_count
  image  = docker_image.main.name
  gpus   = "all"
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname   = lower(data.coder_workspace.me.name)
  entrypoint = ["sh", "-c", coder_agent.main.init_script]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  restart    = "unless-stopped"

  dynamic "devices" {
    for_each = range(local.gpu_devices[data.coder_parameter.docker_host.value])
    content {
      host_path = "/dev/nvidia${devices.value}"
    }
  }

  devices {
    host_path = "/dev/nvidiactl"
  }
  devices {
    host_path = "/dev/nvidia-uvm-tools"
  }
  devices {
    host_path = "/dev/nvidia-uvm"
  }
  devices {
    host_path = "/dev/nvidia-modeset"
  }

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  ipc_mode = "host"

  # users home directory
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  volumes {
    container_path = "/usr/"
    volume_name    = docker_volume.usr_volume.name
    read_only      = false
  }
  volumes {
    container_path = "/etc/"
    volume_name    = docker_volume.etc_volume.name
    read_only      = false
  }
  volumes {
    container_path = "/opt/"
    volume_name    = docker_volume.opt_volume.name
    read_only      = false
  }

  # /mnt
  volumes {
    container_path = "/home/matlab/mnt/"
    host_path      = "/mnt/"
    read_only      = false
  }

  # users data directory
  volumes {
    container_path = "/home/matlab/data/"
    host_path      = "/data/${data.coder_workspace.me.owner}/"
    read_only      = false
  }

  # shared data directory
  volumes {
    container_path = "/home/matlab/share/"
    host_path      = "/data/share/"
    read_only      = false
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace.me.owner
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace.me.owner_id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}