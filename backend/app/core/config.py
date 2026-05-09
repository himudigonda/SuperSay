import os
import sys

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    PROJECT_NAME: str = "SuperSay Backend"
    VERSION: str = "1.0.0"
    HOST: str = "0.0.0.0"
    PORT: int = 10101

    # Paths
    BASE_DIR: str = os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    )

    @property
    def RESOURCE_PATH(self) -> str:
        """Returns the path to resources, handling PyInstaller's temp folder."""
        if getattr(sys, "frozen", False):
            # Running inside PyInstaller bundle
            return sys._MEIPASS
        else:
            # Running locally
            return self.BASE_DIR

    @property
    def MODEL_PATH(self) -> str:
        return os.path.join(self.RESOURCE_PATH, "kokoro-v1.0.onnx")

    @property
    def ACTIVE_MODEL_PATH(self) -> str:
        """Returns INT8 quantized model if present, else falls back to FP32."""
        int8_path = self.MODEL_PATH.replace(".onnx", "-int8.onnx")
        if os.path.exists(int8_path):
            print(f"[Config] Using INT8 quantized model: {int8_path}")
            return int8_path
        return self.MODEL_PATH

    @property
    def VOICES_PATH(self) -> str:
        return os.path.join(self.RESOURCE_PATH, "voices-v1.0.bin")

    def kitten_model_path(self, variant: str) -> str:
        """Return the path to a KittenTTS model ONNX file for the given variant."""
        return os.path.join(self.RESOURCE_PATH, f"kitten-{variant}.onnx")

    def kitten_voices_path(self, variant: str) -> str:
        """Return the path to a KittenTTS voices file for the given variant."""
        return os.path.join(self.RESOURCE_PATH, f"kitten-{variant}-voices.npz")

    def kitten_config_path(self, variant: str) -> str:
        """Return the path to a KittenTTS config JSON for the given variant."""
        return os.path.join(self.RESOURCE_PATH, f"kitten-{variant}-config.json")

    @property
    def USER_DATA_DIR(self) -> str:
        """Writable user-data dir for audiobooks. Cleaned by `make nuke`."""
        return os.path.expanduser(
            "~/Library/Application Support/com.himudigonda.SuperSay"
        )

    @property
    def AUDIOBOOKS_DIR(self) -> str:
        path = os.path.join(self.USER_DATA_DIR, "audiobooks")
        os.makedirs(path, exist_ok=True)
        return path


settings = Settings()
