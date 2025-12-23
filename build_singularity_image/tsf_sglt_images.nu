#!/usr/bin/env nu

# Define the main function with type annotations for better error checking
def main [
  program: string # The name of the program/project to build
  eshell: string # The target environment ('hf', 'ty', 'wz' or 'local')
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
  let image_name = $"($program)"

  # Expand the path to handle the tilde (~) correctly
  let work_dir = ($"~/Code_Program/($program)" | path expand)

  # -------------------------------------------------------------------------
  # 2. Execution Phase
  # -------------------------------------------------------------------------

  print $"Navigate to working directory: ($work_dir)"
  cd $work_dir

  # -------------------------------------------------------------------------
  # 3. Transfer Phase
  # -------------------------------------------------------------------------

  match $eshell {
    "hf" => {
      print $"Transferring image to HF cluster..."
      scp $image_name $"hfcluster:~/.local/bin/($image_name)"
      scp $image_name $"hfcluster:/public/share/ac58qn21ek/singularity_images/($image_name)"
    }
    "ty" => {
      print $"Transferring image to TY cluster..."
      scp $image_name $"tycluster:~/.local/bin/($image_name)"
      scp $image_name $"tycluster:/work/share/ac58qn21ek/singularity_images/($image_name)"
    }
    "wz" => {
      print $"Transferring image to WZ cluster..."
      scp $image_name $"wzcluster:~/.local/bin/($image_name)"
      scp $image_name $"wzcluster:/work/share/ac58qn21ek/singularity_images/($image_name)"
    }
    "local" => {
      print "Keep image locally. No transfer performed."
    }
    _ => {
      print $"Warning: Unknown eshell target '($eshell)'. Image built but not transferred."
    }
  }

  print "Process completed successfully."
}
