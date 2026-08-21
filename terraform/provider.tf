terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.66.0"
    }
  }
}

provider "proxmox" {
  alias    = "pve01"
  endpoint = "https://10.8.30.10:8006/"
  username = "root@pam"
  password = var.pve01_password
  insecure = true
}

provider "proxmox" {
  alias    = "pve02"
  endpoint = "https://10.8.30.11:8006/"
  username = "root@pam"
  password = var.pve02_password
  insecure = true
}
