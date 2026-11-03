{
  "product": {
    "id": "SLES",
    "registrationCode": "${scc_code}",
    "registrationEmail": "${scc_email}"
  },
  "root": {
    "hashedPassword": true,
    "password": "${build_password_encrypted}"
  },
  "user": {
    "fullName": "Build User",
    "userName": "${build_username}",
    "hashedPassword": true,
    "password": "${build_password_encrypted}"
  },
  "l10n": {
    "locale": "${vm_guest_os_language}",
    "keymap": "${vm_guest_os_keyboard}",
    "timezone": "${vm_guest_os_timezone}"
  },
  "software": {
    "packages": [
      "openssh",
      "open-vm-tools"
%{ if vm_guest_os_cloudinit ~}
      , "cloud-init"
%{ endif ~}
%{ for package in additional_packages ~}
      , "${package}"
%{ endfor ~}
    ]
  },
  "storage": {
    "drives": [
      {
        "partitions": [
          { "generate": "default" }
        ]
      }
    ]
  },
  "scripts": {
    "post": [
      {
        "name": "sudoers",
        "chroot": true,
        "content": "#!/bin/sh\nusermod -aG wheel ${build_username}\necho '${build_username} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/${build_username}\nchmod 440 /etc/sudoers.d/${build_username}\n"
      }
    ]
  }
}
