#!/usr/bin/env nu

def main [program: string eshell: string --mpi: string = ""] {
  let image = if $mpi == "" { $program } else { $"($program)_($mpi)" }
  let destination = match $eshell {
    hf_home => "hfcluster:~/.local/bin"
    hf_share => "hfcluster:/public/share/ac58qn21ek/apptainer_images"
    ty_home => "tycluster:~/.local/bin"
    ty_share => "tycluster:/work/share/ac58qn21ek/apptainer_images"
    wz_home => "wzcluster:~/.local/bin"
    wz_share => "wzcluster:/work/share/ac58qn21ek/apptainer_images"
    local => { return }
    _ => { error make {msg: $"Unknown target: ($eshell)"} }
  }

  let image_path = ($env.HOME | path join Code_Program $program $image)
  ^scp $image_path $"($destination)/($image)"
}
