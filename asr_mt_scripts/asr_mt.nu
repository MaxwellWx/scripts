#!/usr/bin/env nu

# =============================================================================
# Sub-Pipeline: A 3-Stage Automated Video Subtitling Workflow
# Pipeline: Transcribe (Whisper) -> Translate (NLLB) -> Burn (FFmpeg)
# ==============================================================================
def main [
  filename: path # [Required] Input video file path

  # --- Stage 1: ASR (Whisper) Parameters ---
  --model (-m): string = "large-v3" # Whisper model size (tiny, base, small, medium, large-v3)
  --precision (-p): string = "float16" # Compute precision (float16, int8)
  --lang (-l): string # Spoken language code (e.g., zh, en, ja). Auto-detect if omitted.
  --beam-size: int = 5 # Beam search size. Higher is more accurate but slower (default: 5)
  --vad # Enable VAD filter to remove long silences and prevent hallucination

  # --- Stage 2: MT (NLLB Translation) Parameters ---
  --translate (-t) # Switch: Enable Stage 2 (Translation)
  --src-lang: string = "eng_Latn" # NLLB Source language code (e.g., eng_Latn, zho_Hans, jpn_Jpan)
  --tgt-lang: string = "zho_Hans" # NLLB Target language code (e.g., eng_Latn, zho_Hans, jpn_Jpan)

  # --- Stage 3: Render (FFmpeg) Parameters ---
  --burn (-b) # Switch: Enable Stage 3 (Burn subtitles into video)
  --encoder (-e): string = "libx264" # Video encoder to use for burning (default: libx264)
] {
  # --- Environment Configuration ---
  let script_dir = "~/scripts/asr_mt_scripts" | path expand
  let image_dir = "~/Code_Program/asr_mt_containers" | path expand
  let asr_image_path = ($image_dir | path join "faster_whisper")
  let mt_image_path = ($image_dir | path join "meta_NLLB")

  # --- File Validation & Path Parsing ---
  if not ($filename | path exists) { error make {msg: $"Error: File '($filename)' not found."} }
  let abs_file = ($filename | path expand)
  let data_dir = ($abs_file | path dirname)
  let file_name = ($abs_file | path basename)
  let file_base = ($abs_file | path parse | get stem)
  let file_ext = ($abs_file | path parse | get extension)

  # ==========================================
  # Stage 1: Generate Subtitles (Whisper)
  # ==========================================
  print $"\n[Stage 1/3] Transcribing: ($file_name)"
  let orig_srt_filename = $"($file_base).srt"

  mut asr_args = ["/app/transcribe.py" $"/data/($file_name)" "--model" $model "--precision" $precision]
  if ($lang != null) { $asr_args = ($asr_args | append ["--language" $lang]) }
  if $vad { $asr_args = ($asr_args | append ["--vad"]) }

  # Execute Whisper
  let asr_out = (
    singularity exec --nv --bind /usr/lib/wsl --bind $"($script_dir):/app" --bind $"($data_dir):/data" --env LD_LIBRARY_PATH=/usr/lib/wsl/lib
    $asr_image_path python3 ...$asr_args
  )

  # ==========================================
  # Stage 2: Translate Subtitles (NLLB)
  # ==========================================
  mut final_srt_filename = $orig_srt_filename

  if $translate {
    print $"\n[Stage 2/3] Translating from ($src_lang) to ($tgt_lang)..."
    let trans_srt_filename = $"($file_base)_($tgt_lang).srt"
    $final_srt_filename = $trans_srt_filename # Update pointer to the translated file

    let mt_args = ["/app/translate.py" $"/data/($orig_srt_filename)" $"/data/($trans_srt_filename)" "--src" $src_lang "--tgt" $tgt_lang]

    # Execute NLLB
    let mt_out = (
      singularity exec --nv --bind /usr/lib/wsl --bind $"($script_dir):/app" --bind $"($data_dir):/data" --env LD_LIBRARY_PATH=/usr/lib/wsl/lib
      --env HF_HOME=/opt/huggingface --env TRANSFORMERS_OFFLINE=1
      $mt_image_path python3 ...$mt_args
    )
    print "Translation complete."
  } else {
    print "\n[Stage 2/3] Translation skipped."
  }

  # ==========================================
  # Stage 3: Burn Subtitles (FFmpeg)
  # ==========================================
  if $burn {
    print $"\n[Stage 3/3] Burning [($final_srt_filename)] into video..."
    let output_video = $"($file_base)_subbed.($file_ext)"

    try {
      cd $data_dir
      ffmpeg -y -v warning -stats -i $file_name -vf $"subtitles='($final_srt_filename)'" -c:v $encoder -c:a copy $output_video
      print $"\nSUCCESS: Video saved to ($data_dir)/($output_video)"
    } catch {
      print "Error: FFmpeg execution failed."
    }
  } else {
    print "\n[Stage 3/3] Video burning skipped. Pipeline finished."
  }
}
