# API Key Setup Guide

Cortex uses LLM-based extraction by default to intelligently filter and extract meaningful memories.

## Quick Setup

1. **Copy the example file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` and add your API key:**
   ```bash
   OPENAI_API_KEY=sk-your-actual-key-here
   ```

3. **Restart the app** - it will automatically load the `.env` file

## Supported Providers

### OpenAI (Recommended)
```env
CORTEX_LLM_PROVIDER=openai
OPENAI_API_KEY=sk-...
```

Get your key: https://platform.openai.com/api-keys

### Anthropic (Claude)
```env
CORTEX_LLM_PROVIDER=anthropic
ANTHROPIC_API_KEY=sk-ant-...
```

Get your key: https://console.anthropic.com/

### Ollama (Local, Free)
```env
CORTEX_LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://localhost:11434
```

No API key needed! Install Ollama: https://ollama.ai

## Optional Settings

```env
# Use a specific model
CORTEX_LLM_MODEL=gpt-4

# Custom API endpoint
CORTEX_LLM_BASE_URL=https://api.openai.com/v1

# Embedding model
CORTEX_EMBED_MODEL=text-embedding-3-small
```

## File Location

The `.env` file should be in the **project root** (same folder as `Cortex.xcodeproj`).

For production builds, you can also place it:
- Next to the `.app` bundle
- In `~/.cortex.env` (home directory)

## Verification

After setting up, check the console logs when the app starts:
```
[EnvironmentLoader] Loaded 2 variables from .env
[MemoryProcessor] Configured with OpenAI (enabled: true)
```

If you see `enabled: false`, check that:
1. Your API key is correct
2. The `.env` file is in the right location
3. The variable name matches exactly (e.g., `OPENAI_API_KEY`)

## Fast Extraction (No API Key)

If you don't want to use LLM extraction, you can enable fast (regex-based) extraction:

In `MemoryProcessor.swift`, change:
```swift
@Published var useFastExtraction: Bool = false  // Change to true
```

**Note:** Fast extraction is less selective and may save more noise.

