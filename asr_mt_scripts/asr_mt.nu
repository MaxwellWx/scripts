#!/usr/bin/env nu

# Main entry point containing all logic
def main [] {
  let warpx_configs = [
    {name: "warpx_1d" path: "~/warpx_1d" clusters: ["hf" "ty" "wz"]}
    # { name: "warpx_2d", path: "~/warpx_2d", clusters: ["hf", "ty"] }
  ]

  let root_dir = $env.PWD
  let max_retries = 3

  for config in $warpx_configs {
    cd $root_dir

    print $"\n(ansi blue)=== Processing ($config.name) ===(ansi reset)"

    let expanded_path = ($config.path | path expand)

    if not ($expanded_path | path exists) {
      print $"(ansi red)Path ($expanded_path) does not exist. Skipping...(ansi reset)"
      continue
    }

    cd $expanded_path

    print "Pulling latest repository changes..."

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

    # Inline transfer and retry logic
    let retry_range = 1..$max_retries

    for attempt in $retry_range {
      # 3. 降低字符串插值中的括号嵌套复杂度，使用 [] 替代文本 ()
      print $"transferring ($config.name) to ($cluster)... [attempt ($attempt)/($max_retries)]"

      # 2. 移除 do 闭包和管道外层的冗余 ()
      let result = do { tsf_sglt_images $config.name $cluster } | complete

      if $result.exit_code == 0 {
        print $"(ansi green)successfully transferred ($config.name) to ($cluster).(ansi reset)"
        $success = true
        break
      }

      print $"(ansi yellow)attempt ($attempt) failed with exit code ($result.exit_code).(ansi reset)"

      if $attempt < $max_retries {
        sleep 3sec
      }
    }
  }

  cd $root_dir
  print $"\n(ansi green)All operations completed.(ansi reset)"
}
