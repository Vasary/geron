# Paperless AI metadata script

`paperless-ai-metadata.py` assigns titles, correspondents, document types,
storage paths, owners, object permissions, and letter sender/recipient custom
fields through the Paperless REST API. It uses only the Python standard
library.

Tokens must be supplied through the environment and must not be committed:

```sh
export PAPERLESS_TOKEN='...'
export LITELLM_API_KEY='...'
export PAPERLESS_URL='https://docs.vasary.org/'
export LITELLM_URL='https://llm-proxy.vasary.org/v1'
```

First inspect the current Paperless lookup tables and create the `ai` tag if it
does not exist. The lookup data remains in memory and no context file is
written:

```sh
python3 helm/workloads/paperless/paperless-ai-metadata.py sync-context --ensure-tags
```

Review a dry-run for 20 documents. The script downloads fresh lookup tables
into memory at the start of every run. Documents already carrying the `ai` tag
are skipped. Every applied document receives both the permanent `ai` processing
marker and the temporary `Требуется ручная проверка` tag:

```sh
python3 helm/workloads/paperless/paperless-ai-metadata.py process --limit 20
```

The default model is `gemini-free-flash`. Select another LiteLLM model with
`--model`, for example `--model gemini-free-standard`.

If sender and recipient fields were not detected automatically, provide their
exact Paperless names:

```sh
python3 helm/workloads/paperless/paperless-ai-metadata.py process --limit 20 \
  --sender-field Absender --recipient-field Empfänger
```

Apply reviewed changes:

```sh
python3 helm/workloads/paperless/paperless-ai-metadata.py process --apply --limit 20
```

Use `--limit 0` only after reviewing a representative dry-run. Proposed and
applied changes are printed to stdout; the script creates no local artifacts.
Remove `Требуется ручная проверка` after checking a document. Keep the `ai` tag
so that the document is not processed again.

Owner and access rules are deterministic: the `Maria` path maps to owner
`maria`, `Viktor` maps to owner `viktor`, and all other paths have no owner.
Personal documents receive no group access. Documents without an owner receive
view access for the `Family` group. For letters, Sender and Receiver contain
human names only; the external organization belongs in Correspondent.

The GitOps CronJob runs every day at 09:15 Europe/Berlin, processes at most 20
documents with `gemini-free-flash`, and stops immediately on an API error. It
uses `concurrencyPolicy: Forbid` and does not retry a failed Job, preserving the
remaining daily free-tier requests for the next scheduled run.

## Ownership and Family access rules

- `Maria` storage path maps to Paperless owner `maria` (user ID 4).
- `Viktor` storage path maps to Paperless owner `viktor` (user ID 3).
- Personal documents have an owner and no `Family` group permission. They are
  visible only to their owner and Paperless superusers.
- `Family`, `Vehicle`, `Daniel`, `Olena Bobina`, and `Serhii Bobin` have no
  Paperless owner and grant view access to the `Family` group (group ID 1).
- `Vehicle` takes precedence over a person's path for vehicle documents.
- `Family` is used only for genuinely shared household documents. An
  organization name such as `Familienkasse` does not imply the `Family` path.
- The external organization belongs in Correspondent. For letters, Sender and
  Receiver contain only explicitly named people, never organization names.
