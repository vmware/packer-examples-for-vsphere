##################################################################################
# VERSIONS
##################################################################################

terraform {
  required_providers {
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.115.0"
    }
    vsphere = {
      source  = "vmware/vsphere"
      version = ">= 2.17.1"
    }
  }
  required_version = ">= 1.16.0"
}
