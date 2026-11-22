# Local LLM models

This workload defines three CPU-only `llama.cpp` servers behind internal ClusterIP
Services:

- `jina-v5-small-retrieval` provides embeddings for the Paperless-ngx LLM
  index. It has two parallel slots.
- `eurollm-1.7b-paperless` provides multilingual chat completions for
  Paperless-ngx in English, German, Russian, and Ukrainian. Its upstream chat
  template is mounted explicitly to ensure the assistant generation prompt is
  present, and responses are capped at 512 tokens.
- `qwen3.5-4b-paperless` is retained as a disabled fallback with zero replicas.

Model files are downloaded by `llama-server` into persistent NVMe-backed
caches. No model endpoint is exposed outside the cluster. LiteLLM is the only
configured client.

## Paperless LiteLLM key

Create a LiteLLM service-account virtual key restricted to these models:

- `jina-v5-small-retrieval`
- `qwen3.5-4b-paperless`
- `eurollm-1.7b-paperless`

Store it as `stringData.PAPERLESS_AI_LLM_API_KEY` in
`helm/secrets/paperless.sops.yaml` using SOPS. The Paperless secret references
are optional so a missing key does not prevent Paperless itself from starting;
AI requests will remain unavailable until the key is present.

Changing the embedding model or its output dimensions requires rebuilding the
Paperless LLM index.
