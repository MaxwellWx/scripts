# sync_files.nu

# terminal path
let terminal_path = [
  "/mnt/d"
  "/home/xuanwu"
]

# nas home path
let NAS_home_path = "/mnt/y"

# nas group path
let NAS_group_path = "/mnt/z/吴玄"

# webdav path
let webdav_remote = "ustcpan"

#log file
let log_file = "/var/log/sync.log"

# Function to log messages with timestamp
def log [message: string] {
  let timestamp = (date now | format date '%Y-%m-%d %H:%M:%S')
  print $"($timestamp): ($message)"
  $"($timestamp): ($message)\n" | save --append $log_file
}

# Main script execution
log "=== Starting file synchronization process ==="

# sync from windows to nas home
log $"Starting sync from ($terminal_path.0) to ($NAS_home_path)"
^rsync -arv --exclude-from="/home/xuanwu/Code_Program/sync_file/exclude_rules_windows_nas_home" $"($terminal_path.0)/" $"($NAS_home_path)/"
if $env.LAST_EXIT_CODE == 0 {
  log "sync from windows to nas home:successful"
} else {
  log $"Error:sync from windows to nas home failed with exit code ($env.LAST_EXIT_CODE)"
  exit 1
}

# sync from linux to nas home
log $"Starting sync from ($terminal_path.1) to ($NAS_home_path)"
^rsync -arv --exclude-from="/home/xuanwu/Code_Program/sync_file/exclude_rules_linux_nas_home" $"($terminal_path.1)/" $"($NAS_home_path)/"
if $env.LAST_EXIT_CODE == 0 {
  log "sync from linux to nas home:successful"
} else {
  log $"Error:sync from linux to nas home failed with exit code ($env.LAST_EXIT_CODE)"
  exit 1
}

# sync from nas home to nas group
log $"Starting sync from ($NAS_home_path) to ($NAS_group_path)"
try {
  ^rsync -avr --delete --exclude-from="/home/xuanwu/Code_Program/sync_file/exclude_rules_nas_home_nas_group" $"($NAS_home_path)/" $"($NAS_group_path)/"
} catch {
}

if $env.LAST_EXIT_CODE == 0 {
  log "sync from nas home to nas group:successful"
} else {
  log $"Error:sync from nas home to nas group failed with exit code ($env.LAST_EXIT_CODE)"
}

# sync from nas home to webdav
log $"Starting sync from ($NAS_home_path) to ustcpan"
^rclone copy -v --progress --exclude="#recycle/**" $"($NAS_home_path)/" $"($webdav_remote):NAS_HOME"
if $env.LAST_EXIT_CODE == 0 {
  log "sync from nas home to webdav:successful"
} else {
  log $"Error:sync from nas home to webdav failed with exit code ($env.LAST_EXIT_CODE)"
  exit 1
}

log "=== All sync operations completed successfully ==="
