terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  username = data.coder_workspace_owner.me.name
}

### You need to add server ssh connection in here
data "coder_parameter" "docker_host" {
  name         = "docker_host"
  display_name = "Docker Host"
  description  = "Select which GPU server (Docker host) to use"
  type         = "string"
  icon         = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/docker.png"
  mutable      = false

  option {
    name  = "PC 0"
    value = ""
  }
  option {
    name  = "Workstation 1"
    value = "ssh://ubuntu@work.iilab.io:16870"
  }
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

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Prepare user home with default files on first start.
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # Create user data directory
    mkdir -p ~/data
    # make user share directory
    mkdir -p ~/share

  EOT

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
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

module "code-server" {
  count     = data.coder_workspace.me.start_count
  source    = "registry.coder.com/modules/code-server/coder"
  agent_id  = coder_agent.main.id
  folder    = "/home/${local.username}/"
  subdomain = false
  order     = 2
}

module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  agent_id = coder_agent.main.id
  folder    = "/home/${local.username}/"
  order     = 3
}

module "jupyterlab" {
  count     = data.coder_workspace.me.start_count
  source    = "registry.coder.com/modules/jupyterlab/coder"
  subdomain = false
  agent_id  = coder_agent.main.id
  order     = 4
}

module "filebrowser" {
  count     = data.coder_workspace.me.start_count
  source    = "registry.coder.com/modules/filebrowser/coder"
  subdomain = false
  agent_id  = coder_agent.main.id
  order     = 5
}

resource "docker_image" "main" {
  name = "coder-${data.coder_workspace.me.id}"
  build {
    context = "./build"
    build_args = {
      USERNAME = local.username
    }
  }
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(path.module, "build/*") : filesha1(f)]))
  }
}

#Volumes Resources
#home_volume
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-home"
}

#usr_volume
resource "docker_volume" "usr_volume" {
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-usr"
}

#etc_volume
resource "docker_volume" "etc_volume" {
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-etc"
}

#opt_volume
resource "docker_volume" "opt_volume" {
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-opt"
}


resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.name
  gpus     = "all"
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  restart  = "unless-stopped"

  
  # NEED TO BE CHANGED ALONG GPU NUMBER OF HOST
  # devices {
  #   host_path = "/dev/nvidia0"
  # }
  
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
    container_path = "/home/${local.username}/mnt/"
    host_path      = "/mnt/"
    read_only      = false
  }

  # users data directory
  volumes {
    container_path = "/home/${local.username}/data/"
    host_path      = "/data/${data.coder_workspace_owner.me.name}/"
    read_only      = false
  }

  # shared data directory
  volumes {
    container_path = "/home/${local.username}/share"
    host_path      = "/data/share/"
    read_only      = false
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
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