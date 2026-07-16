#!/usr/bin/env bash

guard_release_output_path() {
  local repository_root="$1"
  local output_path="$2"
  local physical_root
  local dist_root
  local relative_path
  local current_path
  local component

  physical_root="$(cd "$repository_root" && pwd -P)"
  dist_root="$physical_root/dist"
  case "$output_path" in
    "$dist_root"/*) ;;
    *)
      echo "Release output must remain under the repository dist directory: $output_path" >&2
      return 3
      ;;
  esac

  relative_path="${output_path#"$dist_root"/}"
  current_path="$dist_root"
  if [[ -L "$current_path" ]]; then
    echo "Release output path contains a symbolic link: $current_path" >&2
    return 3
  fi

  IFS='/' read -r -a components <<< "$relative_path"
  for component in "${components[@]}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. ]] || {
      echo "Release output path contains an unsafe component: $output_path" >&2
      return 3
    }
    current_path="$current_path/$component"
    if [[ -L "$current_path" ]]; then
      echo "Release output path contains a symbolic link: $current_path" >&2
      return 3
    fi
  done
}
