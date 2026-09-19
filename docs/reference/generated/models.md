<!--
GENERATED — DO NOT EDIT.
Source: configs/models.toml
Generator: scripts/docs/generate_reference.py
-->

# Models registry (generated)

## Policy

| key | value |
| --- | --- |
| include_cleanup_by_default | False |
| preferred_coding_provider | llamacpp |
| preferred_general_provider | ollama |
| reserve_disk_gb | 20 |
| reserve_memory_gb | 4 |
| tier_balanced_max_ram_gb | 31 |
| tier_large_max_ram_gb | 63 |
| tier_minimal_max_ram_gb | 15 |

## Models

| id | provider | role | tier | default | platforms | min_ram_gb | upstream id | automation | description |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ollama-general-minimal | ollama | general | minimal | yes | darwin, linux | 8 | llama3.2:3b | auto | Small general chat model for constrained hosts |
| ollama-general-balanced | ollama | general | balanced | yes | darwin, linux | 16 | qwen2.5:7b | auto | Balanced general chat (Qwen2.5 7B) |
| ollama-general-large | ollama | general | large | yes | darwin, linux | 32 | qwen2.5:14b | auto | Larger general chat for 32GB+ hosts |
| ollama-general-max | ollama | general | max | yes | darwin, linux | 64 | qwen2.5:32b | auto | High-capacity general chat for 64GB+ hosts |
| llamacpp-coding-minimal | llamacpp | coding | minimal | yes | darwin, linux | 8 | Qwen/Qwen2.5-Coder-3B-Instruct-GGUF:Q4_K_M | auto | Small coding GGUF for constrained hosts |
| llamacpp-coding-balanced | llamacpp | coding | balanced | yes | darwin, linux | 16 | Qwen/Qwen2.5-Coder-7B-Instruct-GGUF:Q4_K_M | auto | Balanced coding GGUF (Q4_K_M) |
| llamacpp-coding-large | llamacpp | coding | large | yes | darwin, linux | 32 | Qwen/Qwen2.5-Coder-14B-Instruct-GGUF:Q4_K_M | auto | Larger coding GGUF for 32GB+ hosts |
| llamacpp-coding-max | llamacpp | coding | max | yes | darwin, linux | 64 | Qwen/Qwen2.5-Coder-32B-Instruct-GGUF:Q4_K_M | auto | High-capacity coding GGUF for 64GB+ hosts |
| drawthings-image-balanced | drawthings | image | balanced | yes | darwin | 16 | flux_2_klein_4b_q6p.ckpt | auto | FLUX.2 Klein 4B (6-bit) — responsive on 24GB Apple Silicon |
| drawthings-image-large | drawthings | image | large | yes | darwin | 32 | flux_2_klein_4b_q8p.ckpt | auto | FLUX.2 Klein 4B higher-quality quant for larger hosts |
| drawthings-image-max | drawthings | image | max | yes | darwin | 64 | flux_2_klein_9b_q6p.ckpt | auto | FLUX.2 Klein 9B for max-tier Apple Silicon |
| drawthings-image-minimal | drawthings | image | minimal | yes | darwin | 8 | flux_2_klein_4b_q6p.ckpt | auto | FLUX.2 Klein 4B (same as balanced; smallest recommended) |
| fluidvoice-speech-balanced | fluidvoice | speech | balanced | yes | darwin | 8 | Parakeet TDT v3 | manual | Recommended multilingual speech model (app download) |
| fluidvoice-speech-minimal | fluidvoice | speech | minimal | yes | darwin | 8 | Parakeet TDT v3 | manual | Recommended speech model for smaller hosts |
| fluidvoice-speech-large | fluidvoice | speech | large | yes | darwin | 8 | Parakeet TDT v3 | manual | Recommended speech model (same upstream default) |
| fluidvoice-speech-max | fluidvoice | speech | max | yes | darwin | 8 | Parakeet TDT v3 | manual | Recommended speech model (same upstream default) |
| fluidvoice-cleanup-balanced | fluidvoice | cleanup | balanced | no | darwin | 16 | Fluid-1 | manual | Optional local dictation cleanup model (~3.5 GB) |
| fluidvoice-cleanup-large | fluidvoice | cleanup | large | no | darwin | 16 | Fluid-1 | manual | Optional Fluid-1 cleanup model |
| fluidvoice-cleanup-max | fluidvoice | cleanup | max | no | darwin | 16 | Fluid-1 | manual | Optional Fluid-1 cleanup model |
