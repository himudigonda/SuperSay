"""GeminiCleaner — strict text-cleaning via Gemini 1.5 Flash.

The user's API key is sent per-request (X-Gemini-Api-Key header from Swift).
Never persisted on disk.
"""

import asyncio
import json
import re

import google.generativeai as genai

# Pricing constants (Gemini 1.5 Flash, May 2026). Update if rates change.
INPUT_USD_PER_M_TOKENS = 0.075
OUTPUT_USD_PER_M_TOKENS = 0.30

MODEL_NAME = "gemini-1.5-flash"

GEMINI_CLEAN_SYSTEM_PROMPT = """\
You are a strict text-cleaning assistant preparing PDF page text for
text-to-speech narration. Your output will be read aloud verbatim.

ABSOLUTE RULES:
1. Preserve every meaningful word from the source. Do not summarize, paraphrase,
   shorten, or omit content.
2. Remove only: page numbers, running headers/footers that repeat across pages,
   hyphenation artifacts at line breaks (e.g., "exam-\\nple" -> "example"), and
   isolated stray characters from PDF extraction noise.
3. Reflow text into natural paragraphs. Join broken lines that belong to the
   same sentence.
4. For tables: prefix the first row with "The following is a table." and
   convert each row into a sentence describing its cells in reading order.
   End the table with "End of table.".
5. For figures/captions: keep the caption text as a sentence; replace figure
   image references with "Figure caption:".
6. For equations: read them aloud naturally (e.g., "x squared plus y squared
   equals z squared"). Preserve all variables and operators.
7. For bullet lists: convert to "First, ... Second, ..." or read in order with
   periods.
8. Output ONLY the cleaned narration text. No preamble, no commentary, no
   markdown, no JSON. Plain prose only.

If the input page is empty or contains no readable content, output the single
character "-".
"""


class GeminiAuthError(Exception):
    """Invalid API key."""


class GeminiRateLimitError(Exception):
    """Gemini returned 429 after retries exhausted."""


class GeminiBadResponseError(Exception):
    """Gemini returned an unexpected response."""


class GeminiCleaner:
    _MAX_RETRIES = 3
    _BACKOFF_BASE = 2.0  # 2s, 4s, 8s

    @classmethod
    async def clean_page(cls, api_key: str, raw_text: str) -> str:
        """Strict-clean a single page. Retries on transient errors."""
        if not raw_text.strip():
            return "-"

        last_exc: Exception | None = None
        for attempt in range(cls._MAX_RETRIES):
            try:
                return await asyncio.to_thread(cls._sync_clean, api_key, raw_text)
            except GeminiAuthError:
                # Auth errors don't retry — fail fast.
                raise
            except (GeminiRateLimitError, GeminiBadResponseError) as e:
                last_exc = e
                if attempt < cls._MAX_RETRIES - 1:
                    await asyncio.sleep(cls._BACKOFF_BASE * (2**attempt))
            except Exception as e:
                last_exc = e
                if attempt < cls._MAX_RETRIES - 1:
                    await asyncio.sleep(cls._BACKOFF_BASE * (2**attempt))

        raise last_exc or GeminiBadResponseError("unknown error")

    @classmethod
    def _sync_clean(cls, api_key: str, raw_text: str) -> str:
        """Single synchronous Gemini call. Raises typed exceptions."""
        try:
            genai.configure(api_key=api_key)
            model = genai.GenerativeModel(
                MODEL_NAME, system_instruction=GEMINI_CLEAN_SYSTEM_PROMPT
            )
            resp = model.generate_content(
                raw_text,
                generation_config={"temperature": 0.1},
            )
        except Exception as e:
            msg = str(e).lower()
            if (
                "api_key" in msg
                or "api key" in msg
                or "permission" in msg
                or "unauthorized" in msg
                or "401" in msg
            ):
                raise GeminiAuthError(str(e)) from e
            if "429" in msg or "rate" in msg or "quota" in msg:
                raise GeminiRateLimitError(str(e)) from e
            raise GeminiBadResponseError(str(e)) from e

        try:
            text = (resp.text or "").strip()
        except Exception as e:
            raise GeminiBadResponseError(str(e)) from e

        if not text:
            return "-"
        return text

    # ---------- cost / token estimation ----------

    @staticmethod
    def estimate_tokens(char_count: int) -> int:
        """Rough heuristic: ~4 chars per token for English."""
        return max(1, char_count // 4)

    @classmethod
    def estimate_cost_usd(cls, total_chars: int) -> float:
        """Strict-preserve: output ≈ input length, so use same token count for both."""
        tok = cls.estimate_tokens(total_chars)
        input_usd = (tok / 1_000_000) * INPUT_USD_PER_M_TOKENS
        output_usd = (tok / 1_000_000) * OUTPUT_USD_PER_M_TOKENS
        return input_usd + output_usd

    # ---------- section detection (Phase 2) ----------

    SECTION_PROMPT = (
        "Below are the cleaned pages of a document, one per `=== PAGE N ===` "
        "header. Identify the chapter or section boundaries.\n"
        "Output ONLY a JSON object of the form: "
        '{"sections":[{"title":"...","start_page":N,"end_page":M},...]}\n'
        "Rules:\n"
        "- Cover every page; sections must be contiguous and non-overlapping.\n"
        "- Use the headings the document itself uses (e.g., 'Chapter 3: Habits').\n"
        "- Prefer 4-20 sections per document. Combine very short subsections.\n"
        "- Do not invent content. Use only what is in the text."
    )

    # Conservative chunk size in characters (Gemini-1.5-flash 1M token window
    # is generous, but we cap to keep latency and JSON parsing manageable).
    _SECTION_CHUNK_CHARS = 500_000
    _SECTION_CHUNK_PAGE_OVERLAP = 5

    @classmethod
    async def detect_sections(
        cls, api_key: str, pages: list[str]
    ) -> list[dict]:
        """Identify sections from a list of cleaned pages.

        `pages` is 1-indexed (pages[0] is page 1). Returns a list of
        {"title": str, "start_page": int, "end_page": int} sorted by start_page,
        contiguous and non-overlapping. Returns [] on total failure (caller can
        fall back to a single implicit section).
        """
        if not pages:
            return []

        # Build chunks of (page_offset, joined_text). Each chunk is sent as one
        # LLM call; results are stitched together.
        chunks: list[tuple[int, str]] = []  # (first_page_in_chunk, text)
        cur_pages: list[str] = []
        cur_chars = 0
        cur_start = 1
        for i, p in enumerate(pages, start=1):
            block = f"=== PAGE {i} ===\n{p}\n"
            if cur_chars + len(block) > cls._SECTION_CHUNK_CHARS and cur_pages:
                chunks.append((cur_start, "".join(cur_pages)))
                # overlap: keep last few pages so chapter titles split across
                # chunk boundaries are still resolvable
                tail = cur_pages[-cls._SECTION_CHUNK_PAGE_OVERLAP:]
                cur_pages = list(tail)
                cur_start = i - len(tail) + 1
                cur_chars = sum(len(t) for t in cur_pages)
            cur_pages.append(block)
            cur_chars += len(block)
        if cur_pages:
            chunks.append((cur_start, "".join(cur_pages)))

        all_sections: list[dict] = []
        for first_page, text in chunks:
            try:
                resp_text = await asyncio.to_thread(
                    cls._sync_section_call, api_key, text
                )
                parsed = cls._parse_sections_json(resp_text, max_page=len(pages))
                # Drop sections that begin before this chunk's first page (overlap noise)
                parsed = [s for s in parsed if s["start_page"] >= first_page]
                all_sections.extend(parsed)
            except Exception as e:
                print(f"[Gemini] section chunk @page {first_page} failed: {e}")
                continue

        return cls._stitch_sections(all_sections, page_count=len(pages))

    @classmethod
    def _sync_section_call(cls, api_key: str, joined_text: str) -> str:
        genai.configure(api_key=api_key)
        model = genai.GenerativeModel(
            MODEL_NAME, system_instruction=cls.SECTION_PROMPT
        )
        resp = model.generate_content(
            joined_text,
            generation_config={
                "temperature": 0.1,
                "response_mime_type": "application/json",
            },
        )
        return resp.text or ""

    @staticmethod
    def _parse_sections_json(raw: str, max_page: int) -> list[dict]:
        """Parse Gemini's JSON output into a clean list. Tolerant to wrapping markdown."""
        # Strip ```json fences if present.
        s = raw.strip()
        s = re.sub(r"^```(?:json)?\s*", "", s)
        s = re.sub(r"\s*```$", "", s)
        try:
            obj = json.loads(s)
        except json.JSONDecodeError:
            return []
        items = obj.get("sections") if isinstance(obj, dict) else None
        if not isinstance(items, list):
            return []
        out: list[dict] = []
        for it in items:
            if not isinstance(it, dict):
                continue
            title = (it.get("title") or "").strip()
            try:
                sp = int(it.get("start_page"))
                ep = int(it.get("end_page"))
            except (TypeError, ValueError):
                continue
            if not title or sp < 1 or ep < sp or sp > max_page:
                continue
            ep = min(ep, max_page)
            out.append({"title": title, "start_page": sp, "end_page": ep})
        return out

    @staticmethod
    def _stitch_sections(sections: list[dict], page_count: int) -> list[dict]:
        """Merge overlapping/duplicate sections from chunked results into one
        contiguous, non-overlapping list covering [1..page_count]."""
        if not sections:
            return []

        # Sort + dedupe identical entries.
        seen: set[tuple] = set()
        unique: list[dict] = []
        for s in sorted(sections, key=lambda x: (x["start_page"], x["end_page"])):
            key = (s["title"].lower().strip(), s["start_page"])
            if key in seen:
                continue
            seen.add(key)
            unique.append(s)

        # Force contiguity: each section's end_page = next section's start_page - 1
        # (or page_count for the last). Drop sections whose start_page <= the
        # previous section's start_page (they were merge duplicates).
        cleaned: list[dict] = []
        for s in unique:
            if cleaned and s["start_page"] <= cleaned[-1]["start_page"]:
                continue
            cleaned.append(s)
        for i, s in enumerate(cleaned):
            if i + 1 < len(cleaned):
                s["end_page"] = max(s["start_page"], cleaned[i + 1]["start_page"] - 1)
            else:
                s["end_page"] = page_count

        # Ensure first section starts at page 1.
        if cleaned and cleaned[0]["start_page"] > 1:
            cleaned.insert(
                0,
                {"title": "Front Matter", "start_page": 1, "end_page": cleaned[0]["start_page"] - 1},
            )
        return cleaned

    @classmethod
    async def verify_key(cls, api_key: str) -> bool:
        """Lightweight key check: tiny generation. Returns True if key works."""
        try:
            await asyncio.to_thread(cls._sync_clean, api_key, "Say 'ok'.")
            return True
        except GeminiAuthError:
            return False
        except Exception:
            # Other errors (network, rate limit) → treat as not-verified for safety.
            return False
