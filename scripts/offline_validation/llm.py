"""LLM clients for emission gate and angle generation.

Uses Anthropic API (Claude Haiku 4 for gate, Claude Sonnet 4.5 for angles)."""

from __future__ import annotations

import json
import os
from pathlib import Path

from anthropic import Anthropic
from dotenv import load_dotenv

# Load .env from project root
load_dotenv(Path(__file__).resolve().parents[2] / ".env")

from prompts import (
    ANGLE_GENERATOR_SYSTEM,
    ANGLE_GENERATOR_USER,
    EMISSION_GATE_SYSTEM,
    EMISSION_GATE_USER,
)


def _get_client() -> Anthropic:
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise RuntimeError(
            "Set ANTHROPIC_API_KEY environment variable. "
            "Get one at https://console.anthropic.com/"
        )
    return Anthropic(api_key=api_key)


def emission_gate(context: str) -> bool:
    """Ask Haiku whether this is a good moment to emit.

    Returns True if YES, False otherwise.
    """
    client = _get_client()
    resp = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=4,
        system=EMISSION_GATE_SYSTEM,
        messages=[
            {"role": "user", "content": EMISSION_GATE_USER.format(context=context)},
        ],
    )
    answer = resp.content[0].text.strip().upper()
    return answer.startswith("YES")


def generate_angles(
    context: str,
    last_other_utterance: str,
    recent_angles: list[str],
) -> tuple[str, list[str]]:
    """Generate topic + 2 angles from Sonnet.

    Returns (topic, [angle1, angle2]).
    """
    client = _get_client()
    recent_str = ", ".join(recent_angles) if recent_angles else "none"
    resp = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=100,
        system=ANGLE_GENERATOR_SYSTEM,
        messages=[
            {
                "role": "user",
                "content": ANGLE_GENERATOR_USER.format(
                    recent_angles=recent_str,
                    context=context,
                    last_other_utterance=last_other_utterance,
                ),
            },
        ],
    )
    raw = resp.content[0].text.strip()

    # Parse JSON — handle markdown fences if model wraps output
    if raw.startswith("```"):
        raw = raw.split("\n", 1)[1].rsplit("```", 1)[0].strip()

    data = json.loads(raw)
    topic = data.get("topic", "unknown")
    angles = data.get("angles", [])[:3]
    return topic, angles
