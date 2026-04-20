"""Offline validation pipeline.

Takes a transcript file (JSON), walks it chronologically,
fires triggers, calls LLMs, and produces rated emission candidates.

Usage:
    python run.py transcript.json [--output results.json]

Transcript format:
    [
        {"text": "word", "start": 0.0, "end": 0.3, "speaker": "other"},
        {"text": "word", "start": 0.35, "end": 0.6, "speaker": "self"},
        ...
    ]

    speaker: "self" | "other" | "unknown"
    start/end: seconds from conversation start
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from rich.console import Console
from rich.table import Table

from llm import generate_angles, emission_gate
from models import ContextRing, Emission, Speaker, Word
from triggers import PauseDetector

console = Console()


def load_transcript(path: Path) -> list[Word]:
    with open(path) as f:
        data = json.load(f)
    words = []
    for entry in data:
        speaker_map = {
            "self": Speaker.SELF,
            "other": Speaker.OTHER,
            "unknown": Speaker.UNKNOWN,
        }
        words.append(Word(
            text=entry["text"],
            start=float(entry["start"]),
            end=float(entry["end"]),
            speaker=speaker_map.get(entry.get("speaker", "unknown"), Speaker.UNKNOWN),
        ))
    return sorted(words, key=lambda w: w.start)


def _build_check_times(words: list[Word], tick_interval: float = 0.3) -> list[float]:
    """Build a list of times to evaluate triggers.

    Includes every word boundary PLUS synthetic ticks during gaps,
    so we catch pauses where neither speaker is talking.
    """
    times: list[float] = []
    for i, w in enumerate(words):
        times.append(w.end)
        # If there's a gap before the next word, insert ticks
        if i + 1 < len(words):
            gap_start = w.end + tick_interval
            gap_end = words[i + 1].start
            t = gap_start
            while t < gap_end:
                times.append(t)
                t += tick_interval
    return sorted(set(times))


def run_pipeline(words: list[Word]) -> list[Emission]:
    ctx = ContextRing(window_seconds=20.0)
    trigger = PauseDetector()
    emissions: list[Emission] = []
    last_emission_time: float | None = None
    recent_angles: list[str] = []

    check_times = _build_check_times(words)
    word_idx = 0
    last_pause_fire: float | None = None  # suppress repeated fires in same gap

    for check_t in check_times:
        # Ingest any words that have completed by this time
        while word_idx < len(words) and words[word_idx].end <= check_t:
            ctx.add(words[word_idx])
            word_idx += 1

        # Check pause detector
        if not trigger.should_fire(ctx, check_t, last_emission_time):
            last_pause_fire = None  # new words arrived, reset
            continue

        # Suppress repeated pause fires in the same silence gap
        if last_pause_fire is not None and check_t - last_pause_fire < 3.0:
            continue
        last_pause_fire = check_t

        context_text = ctx.text(last_n_seconds=15.0)
        if not context_text.strip():
            continue

        console.print(f"\n[dim]t={check_t:.1f}s — Pause detected[/dim]")
        console.print(f"  [dim]Context: {context_text[:100]}...[/dim]")

        # Emission gate: LLM decides whether to whisper
        try:
            passed = emission_gate(context_text)
        except Exception as e:
            console.print(f"  [red]Emission gate error: {e}[/red]")
            continue

        if not passed:
            console.print(f"  [yellow]Emission gate: NO — skipping[/yellow]")
            emissions.append(Emission(
                timestamp=check_t,
                context_text=context_text,
                topic="",
                angles=[],
                pause_detected=True,
                gate_passed=False,
            ))
            continue

        console.print(f"  [green]Emission gate: YES[/green]")

        # Generate angles
        try:
            last_other = ctx.last_other_utterance()
            topic, angles = generate_angles(
                context=context_text,
                last_other_utterance=last_other,
                recent_angles=recent_angles[-6:],  # last 3 emissions × 2 angles
            )
        except Exception as e:
            console.print(f"  [red]Angle generation error: {e}[/red]")
            continue

        console.print(f"  [bold cyan]Topic:[/bold cyan] {topic}")
        console.print(f"  [bold cyan]Angles:[/bold cyan] {' ... '.join(angles)}")

        emission = Emission(
            timestamp=check_t,
            context_text=context_text,
            topic=topic,
            angles=angles,
            pause_detected=True,
            gate_passed=True,
        )
        emissions.append(emission)
        last_emission_time = check_t
        recent_angles.extend(angles)

    return emissions


def interactive_rating(emissions: list[Emission]) -> None:
    """Prompt user to rate each emission that passed the gate."""
    passed = [e for e in emissions if e.gate_passed]
    if not passed:
        console.print("\n[yellow]No emissions passed the gate — nothing to rate.[/yellow]")
        return

    console.print(f"\n[bold]Rate {len(passed)} emissions (1-5):[/bold]")
    console.print("[dim]1=useless  2=weak  3=ok  4=helpful  5=perfect[/dim]\n")

    for i, em in enumerate(passed, 1):
        console.print(f"[bold]Emission {i}/{len(passed)}[/bold] at t={em.timestamp:.1f}s")
        console.print(f"  Context: ...{em.context_text[-120:]}")
        console.print(f"  Topic: {em.topic}")
        console.print(f"  Angles: [cyan]{' ... '.join(em.angles)}[/cyan]")

        while True:
            try:
                rating = int(input("  Rating (1-5): ").strip())
                if 1 <= rating <= 5:
                    em.rating = rating
                    break
            except (ValueError, EOFError):
                pass
            console.print("  [red]Enter 1-5[/red]")
        console.print()


def print_summary(emissions: list[Emission]) -> None:
    pause_count = len(emissions)
    gate_count = sum(1 for e in emissions if e.gate_passed)
    rated = [e for e in emissions if e.rating is not None]

    table = Table(title="Pipeline Summary")
    table.add_column("Metric", style="bold")
    table.add_column("Value")

    table.add_row("Pause detections", str(pause_count))
    table.add_row("Gate passed", str(gate_count))
    table.add_row("Gate rejection rate", f"{(1 - gate_count / pause_count) * 100:.0f}%" if pause_count else "N/A")

    if rated:
        avg = sum(e.rating for e in rated) / len(rated)
        table.add_row("Mean rating", f"{avg:.2f}")
        table.add_row("Rated emissions", str(len(rated)))
        intrusive = sum(1 for e in rated if e.rating <= 2)
        table.add_row("Intrusive (≤2)", str(intrusive))

    console.print(table)

    if rated:
        avg = sum(e.rating for e in rated) / len(rated)
        if avg >= 4.0:
            console.print("\n[bold green]✓ GATE PASSED — mean rating ≥ 4.0. Proceed to Phase 1.[/bold green]")
        else:
            console.print(f"\n[bold red]✗ GATE FAILED — mean {avg:.2f} < 4.0. Iterate on prompts before building.[/bold red]")


def save_results(emissions: list[Emission], path: Path) -> None:
    data = []
    for e in emissions:
        data.append({
            "timestamp": e.timestamp,
            "context_text": e.context_text,
            "topic": e.topic,
            "angles": e.angles,
            "pause_detected": e.pause_detected,
            "gate_passed": e.gate_passed,
            "rating": e.rating,
        })
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    console.print(f"\n[dim]Results saved to {path}[/dim]")


def main() -> None:
    parser = argparse.ArgumentParser(description="WhisperFlow offline validation")
    parser.add_argument("transcript", type=Path, help="Path to transcript JSON file")
    parser.add_argument("--output", "-o", type=Path, default=None, help="Output results JSON")
    parser.add_argument("--no-rate", action="store_true", help="Skip interactive rating")
    args = parser.parse_args()

    if not args.transcript.exists():
        console.print(f"[red]File not found: {args.transcript}[/red]")
        sys.exit(1)

    console.print(f"[bold]WhisperFlow Offline Validation[/bold]")
    console.print(f"Transcript: {args.transcript}\n")

    words = load_transcript(args.transcript)
    console.print(f"Loaded {len(words)} words, {words[-1].end:.1f}s duration\n")

    emissions = run_pipeline(words)

    if not args.no_rate:
        interactive_rating(emissions)

    print_summary(emissions)

    output_path = args.output or args.transcript.with_suffix(".results.json")
    save_results(emissions, output_path)


if __name__ == "__main__":
    main()
