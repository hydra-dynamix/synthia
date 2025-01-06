from dotenv import load_dotenv
from typing import Optional, Dict, Any
import os
from openai import OpenAI
from src.synthia.miner._config import OpenAISettings
from src.synthia.miner.BaseLLM import BaseLLM

load_dotenv()

class OpenAIModule(BaseLLM):
    """OpenAI implementation of the BaseLLM interface."""

    def __init__(self, settings: Optional[OpenAISettings] = None) -> None:
        super().__init__()
        self.settings = settings or OpenAISettings()
        self.client = OpenAI(
            api_key=self.settings.api_key,
            base_url=self.settings.base_url
        )
        self.system_prompt = (
            "You are a supreme polymath renowned for your ability to explain "
            "complex concepts effectively to any audience from laypeople "
            "to fellow top experts. "
            "By principle, you always ensure factual accuracy. "
            "You are master at adapting your explanation strategy as needed "
            "based on the field and target audience, using a wide array of "
            "tools such as examples, analogies and metaphors whenever and "
            "only when appropriate. Your goal is their comprehension of the "
            "explanation, according to their background expertise. "
            "You always structure your explanations coherently and express "
            "yourself clear and concisely, crystallizing thoughts and "
            "key concepts. You only respond with the explanations themselves, "
            "eliminating redundant conversational additions. "
            f"Keep your answer below {int(self.settings.max_tokens * 0.75)} tokens"
        )

    def prompt(
        self, user_prompt: str, system_prompt: str | None = None
    ) -> tuple[str | None, str]:
        """Generate a response using the OpenAI API.

        Args:
            user_prompt: The user's prompt
            system_prompt: Optional system prompt to guide the model

        Returns:
            Tuple of (error message or None, model response)
        """
        if not system_prompt:
            system_prompt = self.system_prompt
            
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": user_prompt})

        try:
            response = self.client.chat.completions.create(
                model=self.settings.model,
                messages=messages,
                max_tokens=self.settings.max_tokens,
                temperature=self.settings.temperature,
            )
            return response.choices[0].message.content, ""
        except Exception as e:
            return str(e), ""

    @property
    def max_tokens(self) -> int:
        """Get the maximum number of tokens for the model."""
        return self.settings.max_tokens

    @property
    def model(self) -> str:
        """Get the model name."""
        return self.settings.model
