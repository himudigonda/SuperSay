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
    def VOICES_PATH(self) -> str:
        return os.path.join(self.RESOURCE_PATH, "voices-v1.0.bin")


settings = Settings()
