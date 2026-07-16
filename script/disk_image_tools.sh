#!/usr/bin/env bash

use_modern_disk_image_tools() {
  [[ "${CODEBASE_COMBINER_USE_HDIUTIL:-0}" != 1 ]] &&
    command -v diskutil >/dev/null 2>&1 &&
    diskutil help image create from >/dev/null 2>&1
}

require_disk_image_tool() {
  if use_modern_disk_image_tools; then
    return 0
  fi
  command -v hdiutil >/dev/null 2>&1 || {
    echo "Missing required disk image tool: diskutil image or hdiutil" >&2
    return 1
  }
}

disk_image_create() {
  local volume_name="$1"
  local source_directory="$2"
  local destination="$3"
  if use_modern_disk_image_tools; then
    diskutil image create from \
      --format UDZO \
      --volumeName "$volume_name" \
      "$source_directory" \
      "$destination" >/dev/null
  else
    hdiutil create -volname "$volume_name" -srcfolder "$source_directory" -ov -format UDZO "$destination" >/dev/null
  fi
}

disk_image_attach() {
  local disk_image="$1"
  if use_modern_disk_image_tools; then
    diskutil image attach --readOnly --mountOptions nobrowse "$disk_image"
  else
    hdiutil attach -readonly -nobrowse "$disk_image"
  fi
}

disk_image_eject() {
  local mount_or_device="$1"
  if use_modern_disk_image_tools; then
    diskutil eject "$mount_or_device" >/dev/null
  else
    hdiutil detach "$mount_or_device" >/dev/null
  fi
}
