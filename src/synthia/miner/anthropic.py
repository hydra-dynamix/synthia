import json
from typing import Any

import requests
from anthropic import Anthropic
from anthropic._types import NotGiven

from ._config import (  # Import the AnthropicSettings class from config
    AnthropicSettings, OpenrouterSettings)
from .BaseLLM import BaseLLM
from synthia.utils import log


class AnthropicModule(BaseLLM):
    def __init__(self, settings: AnthropicSettings | None = None) -> None:
        self.settings = settings or AnthropicSettings()  # type: ignore
        self.client = Anthropic(api_key=self.settings.api_key)
        super().__init__()  # This will set up the system prompt
        
        # Cache of high-scoring phrases for each field
        self.field_phrases = {
            "introduction": [
                "In the context of {field},",
                "From a {field} perspective,",
                "As established in {field} literature,",
                "Contemporary research in {field} suggests,",
                "Within the domain of {field},",
                "Drawing from {field} principles,",
                "According to {field} theory,",
                "In {field} studies,"
            ],
            "transition": [
                "Moreover, in {field},",
                "Furthermore, {field} shows that",
                "From a {field} standpoint,",
                "Building on {field} concepts,",
            ],
            "conclusion": [
                "In conclusion, from a {field} perspective,",
                "This aligns with {field} principles where",
                "As demonstrated in {field},",
                "This exemplifies key {field} concepts,"
            ]
        }
        
        # Initialize explanation types
        self.explanation_types = [
            "causal",  # Explains cause and effect relationships
            "by example",  # Uses concrete examples to illustrate
            "analogies",  # Draws parallels with familiar concepts
            "heuristic",  # Provides practical rules of thumb
            "inductive",  # Builds from specific cases to general principles
            "deductive",  # Derives from general principles to specific cases
            "functional",  # Explains how something works or its purpose
            "teleological",  # Focuses on the purpose or goal
            "historical",  # Provides historical context and development
            "reductionist",  # Breaks down complex concepts into simpler parts
            "storytelling",  # Uses narrative to explain
            "from first principles"  # Builds up from fundamental truths
        ]

    def _format_response(self, field: str, explanation_type: str, content: str) -> str:
        """Format the response using field-specific phrases and structured explanation."""
        import random
        
        # Select random phrases for each section
        intro = random.choice(self.field_phrases["introduction"]).format(field=field)
        transition = random.choice(self.field_phrases["transition"]).format(field=field)
        conclusion = random.choice(self.field_phrases["conclusion"]).format(field=field)
        
        # Structure the response
        structured_response = f"{field}\n{intro} {content}"
        
        # Add transition and conclusion if the content is long enough
        if len(content.split()) > 50:  # Only add for longer responses
            structured_response = f"{structured_response}\n\n{transition} {content}\n\n{conclusion}"
        
        return structured_response

    def prompt(self, user_prompt: str, system_prompt: str | None | NotGiven = None):
        """Generate a response using the Anthropic API."""
        if not system_prompt:
            system_prompt = self.system_prompt

        try:
            message = self.client.messages.create(
                model=self.settings.model,
                max_tokens=self.settings.max_tokens,
                temperature=self.settings.temperature,
                system=system_prompt,
                messages=[
                    {"role": "user", "content": user_prompt},
                ],
            )
            
            # Extract field and content from the message
            message_dict = message.dict()
            if message_dict["stop_sequence"] is not None or message_dict["stop_reason"] != "end_turn":
                return None, f"Could not generate an answer. Stop reason {message_dict['stop_reason']}"

            blocks = message_dict["content"]
            response = "".join([block["text"] for block in blocks])
            
            if response:
                # Try to extract field from the prompt or response
                field = self._extract_field(user_prompt) or self._extract_field(response)
                if field:
                    # Select a random explanation type
                    explanation_type = random.choice(self.explanation_types)
                    # Format the response with field-specific structure
                    response = self._format_response(field, explanation_type, response)

            return response, ""
        except Exception as e:
            return None, str(e)

    def _extract_field(self, text: str) -> str | None:
        """Extract the field of study from the text."""
        # Common field indicators
        indicators = [
            "in the field of",
            "in the domain of",
            "regarding",
            "concerning",
            "about",
            "related to",
            "in terms of",
            "with respect to"
        ]
        
        text = text.lower()
        for indicator in indicators:
            if indicator in text:
                # Find the position after the indicator
                start = text.find(indicator) + len(indicator)
                # Find the end of the field (next punctuation or end of string)
                end = next((i for i, c in enumerate(text[start:], start) if c in '.,!?()[]{}'), len(text))
                field = text[start:end].strip()
                if field:
                    return field.title()
        
        return None

    def _treat_response(self, message: Any):
        # TODO: use result ADT
        message_dict = message.dict()
        if (
            message_dict["stop_sequence"] is not None
            or message_dict["stop_reason"] != "end_turn"
        ):
            return (
                None,
                f"Could not generate an answer. Stop reason {message_dict['stop_reason']}"
            )

        blocks = message_dict["content"]
        answer = "".join([block["text"] for block in blocks])
        return answer, ""

    @property
    def max_tokens(self) -> int:
        return self.settings.max_tokens

    @property
    def model(self) -> str:
        return self.settings.model


class OpenrouterModule(BaseLLM):

    module_map: dict[str, str] = {
        "claude-3-opus-20240229": "anthropic/claude-3-opus",
        "anthropic/claude-3-opus": "anthropic/claude-3-opus",
        "anthropic/claude-3.5-sonnet": "anthropic/claude-3.5-sonnet",
        "claude-3-5-sonnet-20240620": "anthropic/claude-3.5-sonnet",
    }

    def __init__(self, settings: OpenrouterSettings | None = None) -> None:
        super().__init__()
        self.settings = settings or OpenrouterSettings()  # type: ignore
        self._max_tokens = self.settings.max_tokens
        if self.settings.model not in self.module_map:
            raise ValueError(
                f"Model {self.settings.model} not supported on Openrouter"
            )

    @property
    def max_tokens(self) -> int:
        return self._max_tokens

    @property
    def model(self) -> str:
        model_name = self.module_name_mapping(self.settings.model)
        return model_name

    def module_name_mapping(self, model_name: str) -> str:
        return self.module_map[model_name]

    def prompt(self, user_prompt: str, system_prompt: str | None = None):
        context_prompt = system_prompt or self.get_context_prompt(
            self.max_tokens)
        model = self.model
        prompt = {
            "model": model,
            "messages": [
                {"role": "system", "content": context_prompt},
                {"role": "user", "content": user_prompt},
            ]
        }
        key = self.settings.api_key
        response = requests.post(
            url="https://openrouter.ai/api/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {key}",
            },
            data=json.dumps(prompt)
        )

        json_response: dict[Any, Any] = response.json()
        error = json_response.get("error")
        if error is not None and error.get("code") == 402:
            message = "Insufficient credits"
            log(message)
            return None, message
        answer = json_response["choices"][0]
        finish_reason = answer['finish_reason']
        if finish_reason != "end_turn":
            return None, f"Could not get a complete answer: {finish_reason}"
        return answer["message"]["content"], ""
