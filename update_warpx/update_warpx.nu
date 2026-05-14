#!/usr/bin/env nu

# Main entry point for the automation script
# Accepts optional targets to specify which dimension to update.
# e.g., `./updatewarpx.nu` (updates all)
# e.g., `./updatewarpx.nu 1` (updates 1d only)
# e.g., `./updatewarpx.nu 2 3 rz` (updates 2d, 3d, and rz)
def main [...targets: string] {
  alias bd_sglt_images = nu ~/scripts/build_singularity_image/bd_sglt_images.nu
  alias tsf_sglt_images = nu ~/scripts/build_singularity_image/tsf_sglt_images.nu

  # Define all available configurations for target repositories and clusters
  let all_configs = [
    {name: "warpx" path: "~/Code_Program/warpx/WarpX" clusters: ["hf_home" "hf_share" "ty_home" "ty_share" "wz_home" "wz_share"]}
  ]

  # Map user inputs to canonical configuration names
  let mapped_targets = if ($targets | is-empty) {
    # If no parameters are given, default to all configurations
    $all_configs | get name
  } else {
    $targets | each {|t|
      match $t {
        "1" => "warpx_1d"
        "2" => "warpx_2d"
        "3" => "warpx_3d"
        "rz" => "warpx_rz"
        _ => $t # Fallback to support exact name matching if provided
      }
    }
  }

  # Filter the configurations based on the mapped target names
  let warpx_configs = $all_configs | where {|c| $c.name in $mapped_targets }

  # Exit early if arguments are invalid
  if ($warpx_configs | is-empty) {
    print $"(ansi red)Error: No valid targets specified. Valid options are: 1, 2, 3, rz.(ansi reset)"
    return
  }

  # Record starting directory to reset path on each iteration
  let root_dir = $env.PWD
  let max_retries = 3

  for config in $warpx_configs {
    cd $root_dir

    print $"\n(ansi blue)=== Processing ($config.name) ===(ansi reset)"

    let expanded_path = ($config.path | path expand)

    # Skip if the target directory does not exist
    if not ($expanded_path | path exists) {
      print $"(ansi red)Path ($expanded_path) does not exist. Skipping...(ansi reset)"
      continue
    }

    cd $expanded_path

    print "Pulling latest repository changes..."

    # Execute directly without '^' so Topiary parses it as a standard external call
    git pull

    if $env.LAST_EXIT_CODE != 0 {
      print $"(ansi yellow)Warning: Git pull failed (Exit code: ($env.LAST_EXIT_CODE)). Proceeding with local version.(ansi reset)"
    }

    print $"Building singularity images for ($config.name)..."

    bd_sglt_images $config.name

    if $env.LAST_EXIT_CODE != 0 {
      print $"(ansi red)Build failed for ($config.name). Skipping transfers.(ansi reset)"
      continue
    }

    print $"(ansi green)Build completed successfully.(ansi reset)"

    # Iterate through target clusters and transfer with inline retry logic
    for cluster in $config.clusters {
      mut success = false

      let retry_range = 1..$max_retries

      for attempt in $retry_range {
        print $"Transferring ($config.name) to ($cluster)... [Attempt ($attempt)/($max_retries)]"

        # Capture exit code securely without breaking AST parsing
        let result = do { tsf_sglt_images $config.name $cluster } | complete

        if $result.exit_code == 0 {
          print $"(ansi green)Successfully transferred ($config.name) to ($cluster).(ansi reset)"
          $success = true
          break
        }

        print $"(ansi yellow)Attempt ($attempt) failed with exit code ($result.exit_code).(ansi reset)"

        if $attempt < $max_retries {
          sleep 3sec
        }
      }

      # Strict boolean comparison for Topiary compatibility
      if ($success == false) {
        print $"(ansi red)Error: Failed to transfer ($config.name) to ($cluster) after ($max_retries) attempts.(ansi reset)"
      }
    }
  }

  # Return to the original directory after all operations
  cd $root_dir
  print $"\n(ansi green)All operations completed.(ansi reset)"
}
