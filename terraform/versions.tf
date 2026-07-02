terraform {
  required_version = ">= 1.8"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.66"
    }
  }
}

# Token comes from the HCLOUD_TOKEN environment variable; the justfile
# tf-* recipes populate it from gitignored ../secrets/hcloud-token.
provider "hcloud" {}
