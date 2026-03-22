#!/usr/bin/env python3
"""
Variant-aware download script for KittenTTS model files.
Downloads all three variants (nano, micro, mini) from HuggingFace.
Run during `make kitten-model` to bundle model files locally.
"""

import json
import os
import shutil
import sys
from pathlib import Path

try:
    from huggingface_hub import hf_hub_download
    from huggingface_hub.utils import (
        EntryNotFoundError,
        RepositoryNotFoundError,
    )
except ImportError as e:
    print(f"[Kitten] Error: huggingface_hub not installed: {e}")
    sys.exit(1)

VARIANTS = {
    "nano": "KittenML/kitten-tts-nano-0.8",
    "micro": "KittenML/kitten-tts-micro-0.8",
    "mini": "KittenML/kitten-tts-mini-0.8",
}
DEST = Path(__file__).parent.parent / "backend"


def download_variant(variant: str, repo: str) -> bool:
    """
    Download one variant. Returns True on success.
    Returns False if repo not found (graceful skip for optional variants).
    """
    # Check if all 3 files already exist (skip if they do)
    onnx_path = DEST / f"kitten-{variant}.onnx"
    voices_path = DEST / f"kitten-{variant}-voices.npz"
    config_path = DEST / f"kitten-{variant}-config.json"

    if onnx_path.exists() and voices_path.exists() and config_path.exists():
        print(f"[Kitten] ✅ {variant} already downloaded, skipping")
        return True

    print(f"[Kitten] Downloading {variant} from {repo}...")

    try:
        # Download config to get model and voices filenames
        config_file = hf_hub_download(repo_id=repo, filename="config.json")
        with open(config_file) as f:
            cfg = json.load(f)

        # Download model and voices files
        model_file = cfg.get("model_file", "model.onnx")
        voices_file = cfg.get("voices", "voices.npz")

        print(f"[Kitten] Downloading {model_file}...")
        model_path = hf_hub_download(repo_id=repo, filename=model_file)

        print(f"[Kitten] Downloading {voices_file}...")
        voices_path_src = hf_hub_download(repo_id=repo, filename=voices_file)

        # Copy to backend directory with variant name
        print(f"[Kitten] Copying {variant} model...")
        shutil.copy(model_path, onnx_path)
        shutil.copy(voices_path_src, voices_path)

        # Store speed_priors and voice_aliases for offline use
        config_subset = {
            "speed_priors": cfg.get("speed_priors", {}),
            "voice_aliases": cfg.get("voice_aliases", {}),
        }
        with open(config_path, "w") as f:
            json.dump(config_subset, f)

        print(f"[Kitten] ✅ Successfully downloaded {variant}")
        return True

    except (RepositoryNotFoundError, EntryNotFoundError) as e:
        print(
            f"[Kitten] ⚠️ Repo not found for '{variant}': {repo} — skipping "
            f"({type(e).__name__})"
        )
        return False
    except Exception as e:
        print(f"[Kitten] ❌ Download failed for {variant}: {e}")
        return False


def main():
    """Download all variants. Nano is required; others are optional."""
    results = {}
    for variant, repo in VARIANTS.items():
        success = download_variant(variant, repo)
        results[variant] = success

    # Nano is required; fail if it didn't download
    if not results["nano"]:
        print("[Kitten] ❌ Nano model (required) failed to download")
        return False

    # Micro and mini are optional
    if not results["micro"]:
        print("[Kitten] ⚠️ Micro model download skipped (optional)")
    if not results["mini"]:
        print("[Kitten] ⚠️ Mini model download skipped (optional)")

    print("[Kitten] ✅ Download complete")
    return True


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
