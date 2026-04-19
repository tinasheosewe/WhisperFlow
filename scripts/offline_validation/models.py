"""Data models for WhisperFlow offline validation."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class Speaker(Enum):
    SELF = "self"
    OTHER = "other"
    UNKNOWN = "unknown"


@dataclass
class Word:
    text: str
    start: float  # seconds from conversation start
    end: float
    speaker: Speaker


@dataclass
class Emission:
    """A candidate angle emission at a specific moment."""
    timestamp: float  # when emission would fire
    context_text: str  # the ~15s of transcript that triggered it
    topic: str
    angles: list[str]
    tier1_passed: bool = True
    tier2_passed: bool = False
    rating: int | None = None  # 1-5 manual rating


@dataclass
class ContextRing:
    """Rolling window of transcript words."""
    words: list[Word] = field(default_factory=list)
    window_seconds: float = 20.0

    def add(self, word: Word) -> None:
        self.words.append(word)
        cutoff = word.end - self.window_seconds
        self.words = [w for w in self.words if w.end >= cutoff]

    def text(self, last_n_seconds: float | None = None) -> str:
        if not self.words:
            return ""
        if last_n_seconds is not None:
            cutoff = self.words[-1].end - last_n_seconds
            words = [w for w in self.words if w.end >= cutoff]
        else:
            words = self.words
        return " ".join(w.text for w in words)

    def last_other_utterance(self) -> str:
        """Get the last contiguous run of OTHER speaker words."""
        other_words: list[str] = []
        for w in reversed(self.words):
            if w.speaker == Speaker.OTHER:
                other_words.insert(0, w.text)
            elif other_words:
                break
        return " ".join(other_words)

    def last_word_time(self, speaker: Speaker | None = None) -> float | None:
        for w in reversed(self.words):
            if speaker is None or w.speaker == speaker:
                return w.end
        return None

    def word_count_since(self, since: float) -> int:
        return sum(1 for w in self.words if w.start >= since)
