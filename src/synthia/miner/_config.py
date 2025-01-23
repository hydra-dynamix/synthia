from pydantic_settings import BaseSettings


class AnthropicSettings(BaseSettings):
    api_key: str
    model: str = "claude-3-5-sonnet-20240620"
    max_tokens: int = 3000
    temperature: float = 0.5

    class Config:
        env_prefix = "ANTHROPIC_"
        env_file = "env/config.env"
        extra = "ignore"


class OpenrouterSettings(BaseSettings):
    api_key: str
    model: str = "anthropic/claude-3.5-sonnet"
    max_tokens: int = 3000
    temperature: float = 0.5

    class Config:
        env_prefix = "OPENROUTER_"
        env_file = "env/config.env"
        extra = "ignore"


class OpenAISettings(BaseSettings):
    api_key: str
    base_url: str = "https://api.openai.com/v1"
    model: str = "gpt-4-1106-preview"
    max_tokens: int = 3000
    temperature: float = 0.5

    class Config:
        env_prefix = "OPENAI_"
        env_file = "env/config.env"
        extra = "ignore"
