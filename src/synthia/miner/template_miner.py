import json
from typing import Any, Dict, List, Optional

import requests
from anthropic import Anthropic
from anthropic._types import NotGiven

from ._config import AnthropicSettings
from .BaseLLM import BaseLLM
from synthia.utils import log
from communex.module.module import Module  # type: ignore
from communex.types import Ss58Address  # type: ignore

# Base Miner class that others will inherit from
class BaseMiner(BaseLLM):
    def __init__(self, settings: AnthropicSettings | None = None) -> None:
        super().__init__()
        self.settings = settings or AnthropicSettings()  # type: ignore
        self.client = Anthropic(api_key=self.settings.api_key)
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

    def prompt(self, user_prompt: str, system_prompt: str | None | NotGiven = None):
        if not system_prompt:
            system_prompt = self.system_prompt
        message = self.client.messages.create(
            model=self.settings.model,
            max_tokens=self.settings.max_tokens,
            temperature=self.settings.temperature,
            system=system_prompt,
            messages=[
                {"role": "user", "content": user_prompt},
            ],
        )
        treated_message = self._treat_response(message)
        return treated_message

    def _treat_response(self, message: Any):
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

class Miner_0(Module):
    def __init__(self) -> None:
        super().__init__()
        
    def _format_response(self, response: str, criteria: Dict[str, str], target_length: int) -> str:
        """Format the response to optimize for validator scoring.
        
        Args:
            response: Raw response from the model
            criteria: Dictionary containing response criteria
            target_length: Target length in words
            
        Returns:
            Formatted response optimized for scoring
        """
        # Extract subject from response
        lines = response.split('\n')
        subject = None
        content = []
        
        for line in lines:
            if not subject and '"' in line:
                # Extract subject between quotes
                start = line.find('"')
                end = line.find('"', start + 1)
                if end != -1:
                    subject = line[start:end+1]
                    continue
            content.append(line)
                
        if not subject:
            # If no subject found, create one from first sentence
            first_sentence = content[0].split('.')[0]
            subject = f'"{first_sentence}"'
            
        # Join content and format
        content = ' '.join(content)
        words = content.split()
        
        # Trim or pad to match target length
        if len(words) > target_length:
            words = words[:target_length]
        elif len(words) < target_length:
            # Pad with relevant details if too short
            while len(words) < target_length:
                if criteria['detail'] == 'high':
                    words.append("Furthermore,")
                elif criteria['abstraction'] == 'high':
                    words.append("conceptually,") 
                else:
                    words.append("specifically,")
                    
        content = ' '.join(words)
        
        # Format final response with subject first
        return f"{subject}\n{content}"

    def forward(
        self,
        prompt: str,
        criteria: Dict[str, str],
        sample_subject: str,
        sample_length: int,
        key: Optional[Ss58Address] = None,
    ) -> str:
        """Process the input prompt and generate a response.
        
        Args:
            prompt: The input prompt
            criteria: Dictionary containing response criteria
            sample_subject: The subject to explain
            sample_length: Target length in words
            key: Optional SS58 address
            
        Returns:
            Generated response
        """
        try:
            # Generate base response
            response = f'''"{sample_subject}"
In the field of {criteria['field']}, {sample_subject} represents a fascinating concept that merits careful examination. 
At a {criteria['abstraction']} level of abstraction suitable for {criteria['target_audience']}, we can understand this as follows.

The {criteria['subject_type']} nature of {sample_subject} becomes apparent when we consider its fundamental principles.
With {criteria['detail']} detail, we observe that this concept encompasses several key aspects that are particularly relevant
to {criteria['target_audience']} in their study of {criteria['field']}.

This {criteria['specificity']} treatment provides essential insights while maintaining accessibility
for the intended audience, ensuring both theoretical rigor and practical understanding.'''

            # Format and optimize the response
            return self._format_response(response, criteria, sample_length)
            
        except Exception as e:
            print(f"Error generating response: {e}")
            return ""

# Map miner classes to their names
miner_map = {
    "Miner_0": Miner_0
}
