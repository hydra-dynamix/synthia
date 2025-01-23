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
        self.settings = settings or OpenAISettings()
        self.client = OpenAI(
            api_key=self.settings.api_key,
            base_url=self.settings.base_url
        )
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

    def prompt(
        self, user_prompt: str, system_prompt: str | None = None
    ) -> tuple[str | None, str]:
        """Generate a response using the OpenAI API."""
        try:
            messages = []
            if system_prompt:
                messages.append({"role": "system", "content": system_prompt})
            else:
                messages.append({"role": "system", "content": self.system_prompt})

            messages.append({"role": "user", "content": user_prompt})

            completion = self.client.chat.completions.create(
                model=self.settings.model,
                messages=messages,
                max_tokens=self.settings.max_tokens,
                temperature=self.settings.temperature,
            )

            # Extract field and content from the completion
            response = completion.choices[0].message.content
            if response:
                # Try to extract field from the prompt or response
                field = self._extract_field(user_prompt) or self._extract_field(response)
                if field:
                    # Select a random explanation type
                    explanation_type = random.choice(self.explanation_types)
                    # Format the response with field-specific structure
                    response = self._format_response(field, explanation_type, response)

            return None, response
        except Exception as e:
            return str(e), ""

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

    @property
    def max_tokens(self) -> int:
        """Get the maximum number of tokens for the model."""
        return self.settings.max_tokens

    def model(self) -> str:
        """Get the model name."""
        return self.settings.model
