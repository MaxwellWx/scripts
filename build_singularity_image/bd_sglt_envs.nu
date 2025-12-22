#!/usr/bin/env nu

# Define the main function with type annotations for better error checking
def main [
  program: string # The name of the program/project to build
] {
  # -------------------------------------------------------------------------
  # 1. Configuration & Path Resolution
  # -------------------------------------------------------------------------

  # Use 'match' to map the program name to its specific subdirectory.
  let program_subdir = match $program {
    "smilei" => "Smilei"
    "smilei_fatido" => "Smilei_FaTiDo"
    "smilei_fatido_no_rad_push" => "Smilei_FaTiDo_no_rad_push"
    "smilei_spin" => "Smilei_Spin"
    "fatido" => "FaTiDo"
    "warpx_1d" => "WarpX"
    "warpx_2d" => "WarpX"
    "warpx_3d" => "WarpX"
    _ => {
      # Exit gracefully if an unknown program is passed
      error make {msg: $"Unknown program: ($program)"}
    }
  }

  # Define file names using Nushell's string interpolation ($"...")
  let image_name = $"($program)_env"
  let def_file_name = $"($program)_env.def"

  # Expand the path to handle the tilde (~) correctly
  let work_dir = ($"~/Code_Program/($program)" | path expand)

  # -------------------------------------------------------------------------
  # 2. Execution Phase
  # -------------------------------------------------------------------------

  print $"Navigate to working directory: ($work_dir)"
  cd $work_dir

  # Build the Singularity container
  # 'sudo -E' preserves environment variables needed for the build
  print $"Building Singularity image: ($image_name)..."
  sudo -E singularity build --force $image_name $def_file_name

  print "Process completed successfully."
}
