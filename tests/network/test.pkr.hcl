source "file" "network" {
  target = var.output_file
  content = templatefile(var.template, {
    device  = var.vm_network_device
    ip      = var.vm_ip_address
    netmask = var.vm_ip_netmask
    gateway = var.vm_ip_gateway
    dns     = var.vm_dns_list
  })
}

build {
  sources = ["source.file.network"]
}
