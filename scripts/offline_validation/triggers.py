"""Pause detector — pure rule-based gate.

Runs on every word event. Returns True if this moment is a candidate
for angle emission. Cheap, no network calls."""

from __future__ import annotations

from models import ContextRing, Speaker


class PauseDetector:
    def __init__(
        self,
        pause_threshold: float = 0.5,       # other speaker silent >= 500ms
        user_silent_threshold: float = 0.8,  # user silent >= 800ms
        cooldown: float = 3.0,               # seconds since last emission
        min_new_words: int = 4,              # meaningful new content
    ):
        self.pause_threshold = pause_threshold
        self.user_silent_threshold = user_silent_threshold
        self.cooldown = cooldown
        self.min_new_words = min_new_words

    def should_fire(
        self,
        ctx: ContextRing,
        current_time: float,
        last_emission_time: float | None,
    ) -> bool:
        # Must have words
        if not ctx.words:
            return False

        # Cooldown
        if last_emission_time is not None:
            if current_time - last_emission_time < self.cooldown:
                return False

        # Other speaker must have paused
        last_other = ctx.last_word_time(Speaker.OTHER)
        if last_other is None:
            return False
        if current_time - last_other < self.pause_threshold:
            return False

        # User must not be currently speaking
        last_self = ctx.last_word_time(Speaker.SELF)
        if last_self is not None and current_time - last_self < self.user_silent_threshold:
            return False

        # Enough new content since last emission
        since = last_emission_time or 0.0
        if ctx.word_count_since(since) < self.min_new_words:
            return False

        return True
