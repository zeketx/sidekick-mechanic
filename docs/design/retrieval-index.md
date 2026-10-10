# Retrieval index and store

## Problem

Issue #19 needs a retrieval store that turns ingestion chunks (`backend/.ingest/chunks.jsonl` from #18) into a top-k list of `{doc_id, page, text}` for grounded answers. Citations on the wire (#10) are `doc_id` + 1-based `page` + snippet. #20 will reject citations that were not retrieved. #24 will score `recall@5` against those same pages.

The corpus is two manuals and one user. The store should stay local, cheap, and able to move on-device later. `/chat` (#14) and the LLM adapter (#15) stay out of this sketch.

## Usage (caller's view)

Build once after ingest:

```bash
python3 ingest.py
python3 retrieval.py build
```

Query from Python (#20 citations, #24 eval):

```python
from retrieval import DEFAULT_K, Fts5Index

with Fts5Index.open(index_path) as index:
    hits = index.search("starter motor", k=DEFAULT_K)
# hits[0].doc_id, hits[0].page, hits[0].text
```

Query from the CLI:

```bash
python3 retrieval.py query "starter motor" --k 5
```

On each `/chat` request, `LlmAnswerProducer` searches `backend/.ingest/index.sqlite`
when that file exists, before the model call. A missing file on that request
skips search. #15 stays the LLM seam.

## Shape

`Chunk` is one ingested page: non-empty `doc_id`, `page >= 1`, non-empty `text`. Identity is `(doc_id, page)`. That matches ingest JSONL and the citation contract.

`RetrievedChunk` is a `Chunk` plus `score` (higher is better) and 1-based `rank` in this result. `Retriever.search(query, k=5)` returns at most `k` of them, best first. An empty tuple means no supporting pages; #20 maps that to the refusal shape.

`IndexBuilder.build(chunks, dest)` writes a durable file. Rebuild is a full replace from JSONL, same as ingest's replace of `chunks.jsonl`.

The reference implementation is SQLite FTS5. The `Retriever` protocol is the seam if a later hillclimb swaps the engine.

## Synthesis decision

Two stores were compared, matching the issue's examples: a SQLite index vs a flat-file index. Vector SQLite is recorded as a deferred third option, not a Phase 1 store.

**Candidate A — SQLite FTS5 (chosen).** One `.sqlite` file. `doc_id` and `page` are unindexed columns; `labels` (headings and `NAME NO. N` component strings) and `text` are FTS5 `porter unicode61`. Query building drops stopwords and vehicle tokens (`2JZ-GE`, `IS300`), ANDs the rest, falls back to OR if that MATCH is empty, then reranks with label hits, phrase hits, IDF coverage, and Toyota heading cues (`Torque:`, `SERVICE DATA`). `bm25(chunks, 0, 0, 8, 1)` weights `labels` above `text`. The first two weights are zero because `doc_id` and `page` are the unindexed columns and `bm25` weights are positional. Stdlib `sqlite3` only.

**Candidate B — JSONL plus an in-memory inverted index.** Load `chunks.jsonl` on process start, tokenize in Python, rank with a hand-rolled BM25. No extra file.

The merged design takes Candidate A as the store and grafts Candidate B's zero-dependency ranking idea (lexical BM25, no embedding model) and its rebuild-from-JSONL workflow. The Python surface is Candidate B's: `search` returns chunks, not SQL rows.

## Why A over B

Two manuals are a few thousand pages. FTS5 already implements BM25, tokenization, and a file format iOS can open. Candidate B would reimplement that ranking, rebuild on every process start, and need a Swift port to go on-device. A durable SQLite file is the same artifact the backend and a later app bundle can share.

## On-device option

Phase 1 retrieval stays on the backend. The on-device path is: ship `index.sqlite` in the app bundle and query FTS5 with the system SQLite (FTS5 is present on iOS). A Swift `Retriever` would match this protocol (`search` → `(doc_id, page, text, score)`). No embedding model and no native vector extension are required for that move.

Do not start that port in this issue. Re-evaluate only if M2 eval shows lexical search missing paraphrase-heavy questions, or if Phase 2 wants retrieval without the backend.

## Tradeoffs accepted

- Lexical FTS5, not embeddings. Workshop queries are part names, symptoms, and procedure words. Exact tokens matter more than cosine similarity for page-anchored citations.
- AND of content tokens first, OR fallback if that MATCH is empty. Stopwords and model tokens (`2JZ`, `GE`) are dropped so the identification page does not beat a spec page. Precision tuning stays lexical FTS5; no embeddings.
- `score` is `-bm25(chunks, 0, 0, 8, 1)` so callers can sort descending. Raw FTS5 `bm25()` is lower-is-better; we do not expose that sign. The two leading zeros are the unindexed `doc_id` and `page` columns.
- Full page text in `RetrievedChunk.text`. #20 snippets and the spec guard (#21) need the retrieved page, not a truncated preview.
- Rebuild replaces the file. Manuals change as a whole; incremental upsert can wait.
- No extra pip packages. `backend/requirements.txt` is unchanged.

## Alternatives considered

- **JSONL + in-memory inverted index (Candidate B).** Smallest possible runtime. Rejected as the store because ranking and on-device query would be a second implementation, and every backend start would re-tokenize the corpus. Keep JSONL as the ingest interchange, not the query engine.
- **SQLite + sqlite-vec (or any vector column).** Matches the issue's other example and the ROADMAP line "embedding and retrieval index". Rejected for Phase 1: needs a native extension and an embedding model (local weights or an API). Both fight "dependency-light" and "single-user, two manuals". Revisit if recall@5 stalls on paraphrase after #24 exists.
- **Chroma, FAISS, LanceDB, Postgres/pgvector.** Service or heavy binary for a corpus that fits in RAM. Rejected.
- **Remote embedding API as the index.** Needs a key, network, and a vendor. Rejected for a garage app that must still work as files on disk.
- **Phrase MATCH of the raw user string.** FTS5 operators in the prompt (`AND`, quotes) become syntax errors. Rejected; tokens are stripped and quoted.

## Open questions and risks

- Wiring-diagram pages with little extractable text will not retrieve. That is #22, not this store.
- Hyphenated tokens (`2JZ-GE`) split the same way FTS5 `unicode61` splits document text. If a later eval question depends on the hyphen, add a test before changing the tokenizer.
- Should `search` filter by `doc_id`? Not now. #20 can ignore extra docs; adding a filter later does not change `RetrievedChunk`.
- Opening a file that is not this schema fails loudly. There is no migration story until a second version exists.

## Next implementation step

#20 calls `Retriever.search` before the model when the index file exists for that
request. It keeps a citation only when `(doc_id, page)` was retrieved and the
snippet is a contiguous span of that page, after whitespace is collapsed. A rearrangement of the page's tokens is not a quote. An empty
search, or a JSON object with an empty citations array, returns the refusal
shape. A completion that is not that JSON object, or a non-empty citation list
that does not survive the check, returns a provider error
(`kind: error`, `reason: provider_unavailable`). That payload is not a
manual answer. #24 runs
`search(question, k=5)`
and scores membership of the golden pages.
