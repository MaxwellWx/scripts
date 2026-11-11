#!/usr/bin/env nu

def main [program: string --mpi: string = ""] {
  let base = if $mpi == "" { $program } else { $"($program)_($mpi)" }
  let image = $"($base)_env"
  cd ($env.HOME | path join Code_Program $program)

  let pending = $"($image).building-(random uuid).sif"
  ^apptainer build --fakeroot $pending $"($image).def"
  ^apptainer inspect $pending
  mv -f $pending $image
}
