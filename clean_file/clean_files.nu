#!/usr/bin/env nu

def main [] {
  let current_script = $env.CURRENT_FILE | default "clean.nu"

  print "Scanning directory for files to delete..."

  # 1. Identify files to delete
  # ---------------------------------------------------------
  let files_to_delete = (
    ls -a **/*
    | where type == file
    # Fixed: Use closure {|x| ...} to correctly evaluate the logic
    | where {|row| ".git" not-in ($row.name | path split) }
    # Protect .py files
    | where {|row| not ($row.name | str ends-with ".py") }
    # Protect .sh files
    | where {|row| not ($row.name | str ends-with ".sh") }
    # Protect this script itself
    | where {|row| ($row.name | path basename) != ($current_script | path basename) }
  )

  if ($files_to_delete | is-empty) {
    print "No files found to delete."
    return
  }

  # 2. User Confirmation
  # ---------------------------------------------------------
  print $"Found ($files_to_delete | length) files to delete:"
  print ($files_to_delete | get name)
  print ""

  let answer = (input "Delete these files and remove empty directories? [y/N] ")

  if ($answer | str downcase) != "y" {
    print "Operation cancelled by user."
    return
  }

  # 3. Delete Files
  # ---------------------------------------------------------
  print "Deleting files..."
  for file in $files_to_delete {
    try {
      rm $file.name
    } catch {
      print $"Failed to delete: ($file.name)"
    }
  }

  # 4. Remove Empty Directories (Recursive)
  # ---------------------------------------------------------
  let dirs = (
    ls -a **/*
    | where type == dir
    # Fixed: Use closure here too
    | where {|row| ".git" not-in ($row.name | path split) }
    | sort-by -r {|row| $row.name | str length }
  )

  print "Cleaning empty directories..."
  for dir in $dirs {
    let is_empty = (ls -a $dir.name | is-empty)
    if $is_empty {
      print $"Removing empty directory: ($dir.name)"
      try {
        rm $dir.name
      } catch {
        print $"Failed to remove directory: ($dir.name)"
      }
    }
  }

  print "Cleanup complete."
}
