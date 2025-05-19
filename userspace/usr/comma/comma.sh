#/usr/bin/env bash

source /etc/profile

SETUP="/usr/comma/setup"
RESET="/usr/comma/reset"
CONTINUE="/data/continue.sh"
INSTALLER="/tmp/installer"
RESET_TRIGGER="/data/__system_reset__"

echo "waiting for weston"
for i in {1..200}; do
  if systemctl is-active --quiet weston-ready; then
    break
  fi
  sleep 0.1
done

if systemctl is-active --quiet weston-ready; then
  echo "weston ready after ${SECONDS}s"
else
  echo "timed out waiting for weston, ${SECONDS}s"
fi

sudo chown comma: /data
sudo chown comma: /data/media

handle_setup_keys () {
  # install default SSH key while still in setup
  if [[ ! -e /data/params/d/GithubSshKeys && ! -e /data/continue.sh ]]; then
    if [ ! -e /data/params/d ]; then
      mkdir -p /data/params/d_tmp
      ln -s /data/params/d_tmp /data/params/d
    fi

    echo -n 1 > /data/params/d/AdbEnabled
    echo -n 1 > /data/params/d/SshEnabled
    cp /usr/comma/setup_keys /data/params/d/GithubSshKeys
  elif [[ -e /data/params/d/GithubSshKeys && -e /data/continue.sh ]]; then
    if cmp -s /data/params/d/GithubSshKeys /usr/comma/setup_keys; then
      rm /data/params/d/AdbEnabled
      rm /data/params/d/SshEnabled
      rm /data/params/d/GithubSshKeys
    fi
  fi
}

handle_unregistered_device() {
  local dongle_id_file="/data/params/d/DongleId"
  if [ -f "$dongle_id_file" ]; then
    # Read the content of the file, being careful about no newline at EOF
    local content
    content=$(cat "$dongle_id_file")
    if [ "$content" = "UnregisteredDevice" ]; then
      echo "comma.sh: DongleId is UnregisteredDevice. Deleting $dongle_id_file."
      if rm "$dongle_id_file"; then
        echo "comma.sh: Successfully deleted $dongle_id_file."
      else
        echo "comma.sh: Failed to delete $dongle_id_file." >&2
      fi
    fi
  fi
}

handle_comma_konik() {
  if sed -i 's/connect.comma.ai/stable.konik.ai\//g' /data/openpilot/selfdrive/ui/qt/widgets/prime.cc && \
     sed -i 's/comma account/konik account/g' /data/openpilot/selfdrive/ui/qt/widgets/prime.cc; then
    echo "Successfully updated prime.cc"
  else
    echo "Failed to update prime.cc" >&2
  fi

  if sed -i 's/connect.comma.ai/stable.konik.ai\//g' /data/openpilot/selfdrive/ui/ui && \
     sed -i 's/comma account/konik account/g' /data/openpilot/selfdrive/ui/ui; then
    echo "Successfully updated ui"
  else
    echo "Failed to update ui" >&2
  fi
}

patch_custom_api() {
  local api_host_export="export API_HOST=https://api.konik.ai"
  local athena_host_export="export ATHENA_HOST=wss://athena.konik.ai"

  local api_exists=false
  grep -qxF "$api_host_export" "$CONTINUE" && api_exists=true

  local athena_exists=false
  grep -qxF "$athena_host_export" "$CONTINUE" && athena_exists=true

  if $api_exists && $athena_exists; then
    return 0
  fi

  echo "comma.sh: Patching $CONTINUE with custom API hosts."
  local temp_file
  temp_file=$(mktemp)
  if [ -z "$temp_file" ]; then
    echo "comma.sh: Failed to create temp file for $CONTINUE modification." >&2
    return 1
  fi

  local shebang=""
  # Try to read the first line to capture shebang
  if IFS= read -r first_line < "$CONTINUE"; then
    if [[ "$first_line" == "#!"* ]]; then
      shebang="$first_line"
    fi
  fi

  # Write shebang to temp file if it exists
  if [ -n "$shebang" ]; then
    echo "$shebang" > "$temp_file"
  fi

  # Add the custom export lines, with blank lines for readability (similar to C++ logic)
  echo "" >> "$temp_file"
  echo "$api_host_export" >> "$temp_file"
  echo "$athena_host_export" >> "$temp_file"

  # Append the rest of the original script's content to the temp file,
  # skipping the shebang (if already written) and any exact duplicates of the export lines.
  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    # Skip the first line if it was the shebang and we've already written it
    if [ "$line_num" -eq 1 ] && [ -n "$shebang" ]; then
      continue
    fi
    # Skip lines that are exact matches of what we just added
    if [[ "$line" == "$api_host_export" ]] || [[ "$line" == "$athena_host_export" ]]; then
      continue
    fi
    echo "$line" >> "$temp_file"
  done < "$CONTINUE"

  # Replace the original script with the modified version and ensure it's executable
  if mv "$temp_file" "$CONTINUE"; then
    chmod +x "$CONTINUE"
    echo "comma.sh: Successfully patched $CONTINUE."
    handle_unregistered_device
    handle_comma_konik
  else
    echo "comma.sh: Failed to overwrite $CONTINUE with patched version." >&2
    rm -f "$temp_file" # Clean up temp file on failure
    return 1
  fi

  return 0
}

# factory reset handling
if [ ! -f /tmp/booted ]; then
  touch /tmp/booted
  if [ -f "$RESET_TRIGGER" ]; then
    echo "launching system reset, reset trigger present"
    rm -f $RESET_TRIGGER
    $RESET
  elif (( "$(cat /sys/devices/platform/soc/894000.i2c/i2c-2/2-0017/touch_count)" > 4 )); then
    echo "launching system reset, got taps"
    $RESET
  elif ! mountpoint -q /data; then
    echo "userdata not mounted. loading system reset"
    if [ "$(head -c 15 /dev/disk/by-partlabel/userdata)" == "COMMA_RESET" ]; then
      $RESET --format
    else
      $RESET --recover
    fi
  fi
fi

# setup /data/tmp
rm -rf /data/tmp
mkdir -p /data/tmp

# symlink vscode to userdata
mkdir -p /data/tmp/vscode-server
ln -s /data/tmp/vscode-server ~/.vscode-server
ln -s /data/tmp/vscode-server ~/.cursor-server
ln -s /data/tmp/vscode-server ~/.windsurf-server

while true; do
  pkill -f "$SETUP"
  handle_setup_keys

  if [ -f "$CONTINUE" ]; then
    patch_custom_api
  fi

  if [ -f $CONTINUE ]; then
    exec "$CONTINUE"
  fi

  sudo abctl --set_success

  # cleanup installers from previous runs
  rm -f $INSTALLER
  pkill -f $INSTALLER

  # run setup and wait for installer
  $SETUP &
  echo "waiting for installer"
  while [ ! -f $INSTALLER ]; do
    sleep 1
  done

  # run installer and wait for continue.sh
  chmod +x $INSTALLER
  $INSTALLER &
  echo "running installer"
  while [ ! -f $CONTINUE ] && ps -p $! > /dev/null; do
    sleep 1
  done
done
