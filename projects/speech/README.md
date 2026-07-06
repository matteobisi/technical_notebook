# speech

Proof-of-concept project testing [Docker Agent](https://docs.docker.com/ai/agent/) and
[Docker Model Runner](https://docs.docker.com/ai/model-runner/) for local, offline processing
of speech transcripts (e.g., generating meeting minutes from a transcript).

> Files (scripts, configuration) to be added.

## Notes

- Direct Docker Model Runner invocation works reliably.
- Docker Agent mode was unreliable on long transcripts, even with Qwen3 4B/8B and Gemma3 12B models.
- Offline-only tools are used throughout, for privacy.
