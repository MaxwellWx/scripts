#!/usr/bin/env nu

# Download selected files and directories from matching remote subdirectories.
# Preserve paths relative to the remote parent directory.
# Matching data directories are downloaded recursively.
def main [
  remote: string # SSH host or alias
  parent: string # Remote parent directory
  dest: path # Local destination directory, using a WSL path
  child_prefix: string # Prefix of immediate subdirectories to select
  ...file_prefixes: string # Prefixes of files or directories to download
  --dry-run (-n) # Preview changes without downloading files
  --compress (-z) # Enable compression during transfer
] {
  if ($child_prefix | is-empty) or ($file_prefixes | is-empty) {
    error make {
      msg: "Specify a directory prefix and at least one data prefix."
    }
  }

  if ($file_prefixes | any {|fp| $fp | is-empty }) {
    error make {
      msg: "Data prefixes must not be empty."
    }
  }

  if ($dest | path exists) {
    if ($dest | path type) != "dir" {
      error make {
        msg: "The destination path must be a directory."
      }
    }
  } else if not $dry_run {
    mkdir $dest
  }

  # Append a trailing slash to transfer the parent directory's contents.
  let src_path = if ($parent | str ends-with "/") {
    $parent
  } else {
    $"($parent)/"
  }

  let remote_src = $"($remote):($src_path)"

  # Select matching immediate subdirectories of the remote parent.
  mut rules = [$"--include=/($child_prefix)*/"]

  for fp in $file_prefixes {
    $rules = (
      $rules | append [
        # Include matching files and directories.
        $"--include=/($child_prefix)*/($fp)*"

        # Include all contents of matching data directories.
        $"--include=/($child_prefix)*/($fp)*/***"
      ]
    )
  }

  # Exclude all remaining paths.
  $rules = ($rules | append "--exclude=*")

  # Preserve file modification times without copying Unix ownership,
  # permissions, or symbolic links. Retain partial transfers for reuse.
  mut args = [
    "-rtm"
    "--omit-dir-times"
    "--partial-dir=.rsync-partial"
    "--info=progress2"
    "--human-readable"
    "--stats"
    "--no-inc-recursive"
    "--timeout=300"
    "-e"
    "ssh -o ConnectTimeout=30 -o ServerAliveInterval=30 -o ServerAliveCountMax=3"
  ]

  if $compress {
    $args = ($args | append "--compress")
  }

  if $dry_run {
    $args = ($args | append ["--dry-run" "--itemize-changes"])
    print "Dry run: previewing changes without downloading files."
  } else {
    print "Scanning remote files. Overall progress will appear when the transfer starts."
  }

  let final_args = (
    $args
    | append $rules
    | append ["--" $remote_src $"($dest)/"]
  )

  try {
    ^rsync ...$final_args
  } catch {|err|
    print --stderr $"Synchronization failed: ($err.msg)"
    exit 1
  }

  if $dry_run {
    print "Preview completed successfully."
  } else {
    print "Synchronization completed successfully."
  }
}
