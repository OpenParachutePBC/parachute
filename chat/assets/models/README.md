# SmolLM2 Model for Title Generation

This directory contains the SmolLM2-360M-Instruct model used for generating semantic titles from voice note transcripts.

## Model Information

- **Model**: SmolLM2-360M-Instruct
- **Size**: ~200MB (Q4_K_M quantization)
- **Purpose**: Generate concise 5-8 word titles from transcripts
- **Source**: https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF

## Download Instructions

### Option 1: Direct Download (Recommended)

Visit: https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/tree/main

Download: `smollm2-360m-instruct-q4_k_m.gguf` (~200MB)

Place it in: `assets/models/smollm2-360m-instruct-q4_k_m.gguf`

### Option 2: Using Hugging Face CLI

```bash
# Install huggingface-cli
pip install huggingface_hub

# Download the model
cd assets/models
huggingface-cli download HuggingFaceTB/SmolLM2-360M-Instruct-GGUF smollm2-360m-instruct-q4_k_m.gguf --local-dir .
```

### Option 3: Using wget

```bash
cd assets/models
wget https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q4_k_m.gguf
```

## Usage

The TitleGenerationService will automatically load this model on first use and cache it for future requests.

**Prompt Template:**
```
Generate a concise 5-8 word title for this voice note transcript:

[transcript text]

Title:
```

## Alternative Models

If you need a smaller or larger model:

- **135M** (smaller, faster): `smollm2-135m-instruct-q4_k_m.gguf` (~80MB)
- **1.7B** (larger, better quality): `smollm2-1.7b-instruct-q4_k_m.gguf` (~1GB)

Update the model filename in `lib/core/services/title_generation_service.dart` if using a different model.

## Performance

Expected inference time on typical hardware:
- **macOS (M1/M2)**: ~1-2 seconds per title
- **macOS (Intel)**: ~3-5 seconds per title
- **Windows/Linux**: ~2-4 seconds per title

The model runs entirely on-device, no internet required.
