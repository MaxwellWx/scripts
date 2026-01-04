#!/usr/bin/env nu

# Syncs specific files from remote subdirectories while preserving structure.
# Logic: remote:parent/child*/grandchild* -> local/child*/grandchild*
def main [
  remote: string # SSH host (e.g., "user@server")
  parent: string # Remote parent path
  dest: path # Local destination (WSL path)
  child_prefix: string # Directory prefix pattern
  ...file_prefixes: string # List of file prefix patterns
  --dry-run (-n) # Preview changes without downloading
] {
  # Ensure local directory exists
  if not ($dest | path exists) {
    mkdir $dest
  }

  # Ensure remote path ends with '/' to sync contents, not the directory itself
  let src_path = if ($parent | str ends-with "/") { $parent } else { $"($parent)/" }
  let remote_src = $"($remote):($src_path)"

  # Build rsync filter rules dynamically
  # 1. Include the specific directories (child_prefix)
  # 2. Include the specific files within those directories (child_prefix/file_prefix)
  # 3. Exclude everything else
  let rules = [
    $"--include=($child_prefix)*/"
    ...($file_prefixes | each {|fp| $"--include=($child_prefix)*/($fp)*" })
    "--exclude=*"
  ]

  # Base flags: archive, prune empty dirs, compress, skip owner/group (for WSL/NTFS)
  mut args = ["-amz" "--prune-empty-dirs" "--no-o" "--no-g"]

  if $dry_run {
    $args = ($args | append ["--dry-run" "-v"])
    print $"(ansi yellow)[DRY RUN] Command to be executed:(ansi reset)"
  }

  # Construct final command arguments
  let final_args = ($args | append $rules | append $remote_src | append $dest)

  # Execute rsync
  try {
    ^rsync ...$final_args
    print $"(ansi green)Sync completed successfully.(ansi reset)"
  } catch {
    print $"(ansi red)Sync failed.(ansi reset)"
    exit 1
  }
}
