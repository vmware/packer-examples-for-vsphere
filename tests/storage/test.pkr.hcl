source "file" "storage" {
  target = var.output_file
  content = templatefile(var.template, {
    device     = var.vm_disk_device
    swap       = var.vm_disk_use_swap
    partitions = var.vm_disk_partitions
    lvm        = var.vm_disk_lvm
  })
}

build {
  sources = ["source.file.storage"]
}
