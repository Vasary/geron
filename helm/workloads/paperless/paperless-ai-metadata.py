#!/usr/bin/env python3
"""Generate Paperless document metadata with an OpenAI-compatible LLM.

The script has two stages:

1. ``sync-context`` downloads Paperless lookup tables for use in prompts.
2. ``process`` proposes or applies metadata to documents without the ``ai`` tag.

Only the Python standard library is required. Tokens are read from environment
variables and are never written to the context or change log.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
import sys
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urljoin
from urllib.request import Request, urlopen


LOOKUPS = ("correspondents", "document_types", "storage_paths", "tags", "custom_fields", "users", "groups")
SENDER_NAMES = {"sender", "from", "absender", "отправитель", "відправник"}
RECIPIENT_NAMES = {"recipient", "receiver", "to", "empfänger", "empfaenger", "получатель", "одержувач"}


class ScriptError(RuntimeError):
    """An expected error that can be shown without a traceback."""


class FatalApiError(ScriptError):
    """An API error after which the batch must stop immediately."""


class ApiClient:
    def __init__(self, base_url: str, token: str, *, timeout: int = 120) -> None:
        self.base_url = base_url.rstrip("/") + "/"
        self.token = token
        self.timeout = timeout

    def request(self, method: str, path: str, payload: Any = None) -> Any:
        url = path if path.startswith(("http://", "https://")) else urljoin(self.base_url, path.lstrip("/"))
        data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode()
        request = Request(url, data=data, method=method)
        request.add_header("Authorization", f"Token {self.token}")
        request.add_header("Accept", "application/json")
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urlopen(request, timeout=self.timeout) as response:
                body = response.read()
        except HTTPError as error:
            detail = error.read().decode(errors="replace")[:1000]
            raise FatalApiError(f"Paperless API {error.code} for {method} {url}: {detail}") from error
        except URLError as error:
            raise FatalApiError(f"Cannot reach Paperless API at {url}: {error.reason}") from error
        return json.loads(body) if body else None

    def get_all(self, path: str) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        next_url: str | None = path
        while next_url:
            page = self.request("GET", next_url)
            if isinstance(page, list):
                items.extend(page)
                break
            items.extend(page.get("results", []))
            next_url = page.get("next")
        return items


class LlmClient:
    def __init__(self, base_url: str, api_key: str, model: str, *, timeout: int = 300) -> None:
        self.url = base_url.rstrip("/") + "/chat/completions"
        self.api_key = api_key
        self.model = model
        self.timeout = timeout

    def complete(self, prompt: str) -> dict[str, Any]:
        payload = {
            "model": self.model,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "You assign metadata to archived documents. Use only facts present in the document. "
                        "Return one JSON object and no markdown or explanation."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
            "temperature": 0.1,
            "max_tokens": 1024 if self.model.startswith("gemini") else 256,
            "response_format": {"type": "json_object"},
        }
        if self.model.startswith("gemini"):
            payload["reasoning_effort"] = "low"
        if self.model.startswith("qwen"):
            payload["extra_body"] = {"chat_template_kwargs": {"enable_thinking": False}}
        request = Request(self.url, data=json.dumps(payload, ensure_ascii=False).encode(), method="POST")
        request.add_header("Authorization", f"Bearer {self.api_key}")
        request.add_header("Content-Type", "application/json")
        try:
            with urlopen(request, timeout=self.timeout) as response:
                result = json.loads(response.read())
        except HTTPError as error:
            detail = error.read().decode(errors="replace")[:1000]
            raise FatalApiError(f"LLM API {error.code}: {detail}") from error
        except URLError as error:
            raise FatalApiError(f"Cannot reach LLM API at {self.url}: {error.reason}") from error
        content = result["choices"][0]["message"]["content"].strip()
        if content.startswith("```"):
            content = content.split("\n", 1)[1].rsplit("```", 1)[0].strip()
        try:
            parsed = json.loads(content)
        except json.JSONDecodeError as error:
            raise ScriptError(f"LLM returned invalid JSON: {content[:500]}") from error
        if not isinstance(parsed, dict):
            raise ScriptError("LLM response is not a JSON object")
        return parsed


def env_required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ScriptError(f"Set the {name} environment variable")
    return value


def paperless_client(args: argparse.Namespace) -> ApiClient:
    return ApiClient(args.paperless_url, env_required("PAPERLESS_TOKEN"), timeout=args.timeout)


def normalized(value: str) -> str:
    return " ".join(value.casefold().strip().split())


def find_named(items: list[dict[str, Any]], name: str) -> dict[str, Any] | None:
    wanted = normalized(name)
    return next((item for item in items if normalized(str(item.get("name") or item.get("username") or "")) == wanted), None)


def ensure_tag(
    client: ApiClient, tags: list[dict[str, Any]], name: str, color: str, *, create: bool
) -> dict[str, Any] | None:
    tag = find_named(tags, name)
    if tag is None and create:
        tag = client.request("POST", "api/tags/", {
            "name": name,
            "color": color,
            "is_inbox_tag": False,
        })
        tags.append(tag)
        print(f"Created tag {name!r} with id {tag['id']}")
    elif tag is None:
        print(f"Tag {name!r} does not exist; use sync-context --ensure-tags to create it", file=sys.stderr)
    else:
        print(f"Found tag {name!r} with id {tag['id']}")
    return tag


def fetch_context(client: ApiClient, args: argparse.Namespace, *, ensure_tags: bool) -> dict[str, Any]:
    context: dict[str, Any] = {
        "paperless_url": args.paperless_url.rstrip("/"),
        "synced_at": datetime.now(timezone.utc).isoformat(),
    }
    for lookup in LOOKUPS:
        context[lookup] = client.get_all(f"api/{lookup}/?page_size=1000")
        print(f"Fetched {len(context[lookup])} {lookup}")

    ensure_tag(client, context["tags"], args.ai_tag, "#3b82f6", create=ensure_tags)
    ensure_tag(client, context["tags"], args.review_tag, "#f59e0b", create=ensure_tags)
    return context


def sync_context(args: argparse.Namespace) -> None:
    context = fetch_context(paperless_client(args), args, ensure_tags=args.ensure_tags)
    print("Custom fields:")
    for field in context["custom_fields"]:
        options = [item.get("label") for item in field.get("extra_data", {}).get("select_options", [])]
        suffix = f"; allowed values: {', '.join(options)}" if options else ""
        print(f"- {field['name']} ({field.get('data_type', 'unknown')}){suffix}")
    print("Context was kept in memory; no file was written")


def compact_lookup(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [{"id": item["id"], "name": item.get("name", "")} for item in items]


def document_tag_ids(document: dict[str, Any]) -> list[int]:
    result = []
    for tag in document.get("tags") or []:
        result.append(int(tag["id"] if isinstance(tag, dict) else tag))
    return result


def resolve_custom_field(
    fields: list[dict[str, Any]], explicit_name: str | None, aliases: set[str]
) -> dict[str, Any] | None:
    if explicit_name:
        return find_named(fields, explicit_name)
    return next((field for field in fields if normalized(str(field.get("name", ""))) in aliases), None)


def make_prompt(document: dict[str, Any], context: dict[str, Any], text_limit: int) -> str:
    content = (document.get("content") or "")[:text_limit]
    return f"""Analyze this Paperless document and return exactly this JSON shape:
{{
  "title": "better short factual title in the document language" or null,
  "correspondent_id": 123 or null,
  "document_type_id": 123 or null,
  "storage_path_id": 123 or null,
  "is_letter": true or false,
  "sender": "first and last name of the human sender" or null,
  "recipient": "first and last name of the human recipient" or null
}}

Rules:
- Keep a specific and accurate current title by returning title=null.
- Replace a title only when it is missing, generic, filename-like, or factually wrong.
- A replacement title must contain 4-12 words, use the dominant OCR language, and be more useful than the current title.
- German documents require a German title, Ukrainian documents a Ukrainian title, Russian documents a Russian title, and English documents an English title.
- A replacement title must not say file, scan, or document.
- Select IDs only from the supplied lists. Use null if no existing value fits.
- Re-evaluate the correspondent and document type independently from the current values; they may be wrong.
- Select exactly one existing storage path based on whom or what the document belongs to.
- Maria is the storage path for Mariia Gieva. Vehicle overrides a person's path for vehicle documents.
- Use Family only for genuinely shared household documents with no single person as the subject or addressee.
- A word such as Family or Familienkasse in an organization's name does not imply the Family storage path.
- Use a person's path whenever that person is the document subject, holder, applicant, or named addressee.
- For letters, the correspondent is the external organization, not its employee.
- sender and recipient are populated only for letters or correspondence and contain human names only.
- For an incoming letter, sender is the named employee/contact person (for example Sachbearbeitung), and recipient is the addressee.
- For an outgoing letter, sender is the named author and recipient is the named addressee/contact person.
- Never put an organization such as Finanzamt, Stadt Heilbronn, or Familienkasse into sender or recipient.
- Return null for sender or recipient when no human first and last name is explicitly present.
- Never invent a person, organization, date, reference number, sender, or recipient.
- Preserve the language of the source document.

Available correspondents:
{json.dumps(compact_lookup(context['correspondents']), ensure_ascii=False)}

Available document types:
{json.dumps(compact_lookup(context['document_types']), ensure_ascii=False)}

Available storage paths:
{json.dumps([{'id': item['id'], 'name': item.get('name', ''), 'path': item.get('path', '')} for item in context['storage_paths']], ensure_ascii=False)}

Available sender and recipient custom fields:
{json.dumps([{
    'id': field['id'],
    'name': field.get('name', ''),
    'data_type': field.get('data_type'),
    'allowed_values': [option.get('label') for option in field.get('extra_data', {}).get('select_options', [])],
} for field in context['custom_fields']], ensure_ascii=False)}

For a select custom field, return sender or recipient only when it exactly
matches one of its allowed_values. Otherwise return null.

Current metadata:
{json.dumps({key: document.get(key) for key in ('id', 'title', 'created', 'correspondent', 'document_type', 'storage_path', 'owner')}, ensure_ascii=False)}

OCR text:
{content}
"""


def integer_or_none(value: Any, allowed: set[int], field: str) -> int | None:
    if value is None or value == "":
        return None
    try:
        result = int(value)
    except (TypeError, ValueError) as error:
        raise ScriptError(f"LLM returned invalid {field}: {value!r}") from error
    if result not in allowed:
        raise ScriptError(f"LLM returned unknown {field}: {result}")
    return result


def object_id(value: Any) -> int | None:
    if value is None or value == "":
        return None
    if isinstance(value, dict):
        value = value.get("id")
    return int(value) if value is not None else None


def required_named_id(items: list[dict[str, Any]], name: str, kind: str) -> int:
    item = find_named(items, name)
    if item is None:
        raise ScriptError(f"Required {kind} {name!r} was not found")
    return int(item["id"])


def owner_for_storage_path(storage_path_id: int | None, context: dict[str, Any]) -> int | None:
    if storage_path_id is None:
        return None
    path = next((item for item in context["storage_paths"] if int(item["id"]) == storage_path_id), None)
    if path is None:
        return None
    name = normalized(str(path.get("name", "")))
    if name == "maria":
        return required_named_id(context["users"], "maria", "user")
    if name == "viktor":
        return required_named_id(context["users"], "viktor", "user")
    return None


def merged_custom_fields(document: dict[str, Any], updates: dict[int, Any]) -> list[dict[str, Any]]:
    existing: dict[int, Any] = {}
    for item in document.get("custom_fields") or []:
        if isinstance(item, dict) and item.get("field") is not None:
            field = item["field"]
            field_id = int(field.get("id") if isinstance(field, dict) else field)
            existing[field_id] = item.get("value")
    existing.update(updates)
    return [{"field": field_id, "value": value} for field_id, value in sorted(existing.items())]


def custom_field_value(field: dict[str, Any], value: Any) -> str | None:
    if value is None or not str(value).strip():
        return None
    text = str(value).strip()
    if field.get("data_type") != "select":
        return text
    options = field.get("extra_data", {}).get("select_options", [])
    match = next((item for item in options if normalized(str(item.get("label", ""))) == normalized(text)), None)
    if match is None:
        allowed = ", ".join(str(item.get("label", "")) for item in options)
        raise ScriptError(f"LLM returned unsupported value {text!r} for {field['name']}; allowed: {allowed}")
    return str(match["id"])


def proposed_patch(
    document: dict[str, Any], result: dict[str, Any], context: dict[str, Any],
    ai_tag_id: int, review_tag_id: int, sender_field: dict[str, Any] | None,
    recipient_field: dict[str, Any] | None,
) -> dict[str, Any]:
    proposed_title = str(result.get("title") or "").strip()
    current_title = str(document.get("title") or "").strip()
    title = proposed_title or current_title
    if not title or len(title) > 200:
        raise ScriptError(f"LLM returned an invalid title: {title!r}")
    correspondent = integer_or_none(
        result.get("correspondent_id"), {int(item["id"]) for item in context["correspondents"]}, "correspondent_id"
    )
    document_type = integer_or_none(
        result.get("document_type_id"), {int(item["id"]) for item in context["document_types"]}, "document_type_id"
    )
    storage_path = integer_or_none(
        result.get("storage_path_id"), {int(item["id"]) for item in context["storage_paths"]}, "storage_path_id"
    )
    if storage_path is None:
        storage_path = object_id(document.get("storage_path"))
    owner = owner_for_storage_path(storage_path, context)
    family_group_id = required_named_id(context["groups"], "Family", "group")
    patch: dict[str, Any] = {
        "title": title,
        "correspondent": correspondent if correspondent is not None else object_id(document.get("correspondent")),
        "document_type": document_type if document_type is not None else object_id(document.get("document_type")),
        "storage_path": storage_path,
        "owner": owner,
        "set_permissions": {
            "view": {"users": [], "groups": [family_group_id] if owner is None else []},
            "change": {"users": [], "groups": []},
        },
        "tags": sorted(set(document_tag_ids(document)) | {ai_tag_id, review_tag_id}),
    }
    field_updates: dict[int, Any] = {}
    if result.get("is_letter") is True:
        if sender_field:
            value = custom_field_value(sender_field, result.get("sender"))
            field_updates[int(sender_field["id"])] = value
        if recipient_field:
            value = custom_field_value(recipient_field, result.get("recipient"))
            field_updates[int(recipient_field["id"])] = value
    if field_updates:
        patch["custom_fields"] = merged_custom_fields(document, field_updates)
    return patch


def lookup_name(items: list[dict[str, Any]], value: Any) -> str:
    item_id = object_id(value)
    if item_id is None:
        return "—"
    match = next((item for item in items if int(item["id"]) == item_id), None)
    if match:
        label = match.get("name") or match.get("username") or str(item_id)
        return f"{label} (id={item_id})"
    return f"id={item_id}"


def display_plan(document: dict[str, Any], patch: dict[str, Any], context: dict[str, Any]) -> None:
    rows = (
        ("title", str(document.get("title") or "—"), str(patch["title"])),
        (
            "correspondent",
            lookup_name(context["correspondents"], document.get("correspondent")),
            lookup_name(context["correspondents"], patch["correspondent"]),
        ),
        (
            "document_type",
            lookup_name(context["document_types"], document.get("document_type")),
            lookup_name(context["document_types"], patch["document_type"]),
        ),
        (
            "storage_path",
            lookup_name(context["storage_paths"], document.get("storage_path")),
            lookup_name(context["storage_paths"], patch["storage_path"]),
        ),
        (
            "owner",
            lookup_name(context["users"], document.get("owner")),
            lookup_name(context["users"], patch["owner"]),
        ),
    )
    for field, before, after in rows:
        action = "KEEP" if before == after else "CHANGE"
        print(f"  {action:6} {field}: {before!r} -> {after!r}")
    current_tags = set(document_tag_ids(document))
    added_tags = [
        item.get("name", str(item["id"]))
        for item in context["tags"]
        if int(item["id"]) in set(patch["tags"]) - current_tags
    ]
    print(f"  {'CHANGE' if added_tags else 'KEEP':6} tags: add {', '.join(added_tags) if added_tags else 'nothing'}")
    before_permissions = document.get("permissions") or {
        "view": {"users": [], "groups": []},
        "change": {"users": [], "groups": []},
    }
    after_permissions = patch["set_permissions"]
    action = "KEEP" if before_permissions == after_permissions else "CHANGE"
    before_groups = before_permissions.get("view", {}).get("groups", [])
    after_groups = after_permissions["view"]["groups"]
    print(f"  {action:6} view groups: {before_groups} -> {after_groups}")
    if "custom_fields" in patch:
        before_fields = {int(item["field"] if not isinstance(item["field"], dict) else item["field"]["id"]): item.get("value") for item in document.get("custom_fields") or []}
        for item in patch["custom_fields"]:
            field_id = int(item["field"])
            field = next((value for value in context["custom_fields"] if int(value["id"]) == field_id), None)
            before = before_fields.get(field_id)
            after = item.get("value")
            action = "KEEP" if before == after else "CHANGE"
            print(f"  {action:6} custom field {field.get('name', field_id) if field else field_id}: {before!r} -> {after!r}")


def process_documents(args: argparse.Namespace) -> None:
    paperless = paperless_client(args)
    context = fetch_context(paperless, args, ensure_tags=False)
    ai_tag = find_named(context["tags"], args.ai_tag)
    if ai_tag is None:
        raise ScriptError(f"Tag {args.ai_tag!r} is absent; rerun sync-context --ensure-tags")
    ai_tag_id = int(ai_tag["id"])
    review_tag = find_named(context["tags"], args.review_tag)
    if review_tag is None:
        raise ScriptError(f"Tag {args.review_tag!r} is absent; rerun sync-context --ensure-tags")
    review_tag_id = int(review_tag["id"])
    sender_field = resolve_custom_field(context["custom_fields"], args.sender_field, SENDER_NAMES)
    recipient_field = resolve_custom_field(context["custom_fields"], args.recipient_field, RECIPIENT_NAMES)
    print(f"Sender field: {sender_field['name'] if sender_field else 'not found'}")
    print(f"Recipient field: {recipient_field['name'] if recipient_field else 'not found'}")

    llm = LlmClient(args.llm_url, env_required("LITELLM_API_KEY"), args.model, timeout=args.llm_timeout)
    summaries = paperless.get_all("api/documents/?page_size=100")
    candidates = [item for item in summaries if ai_tag_id not in document_tag_ids(item)]
    if args.limit:
        candidates = candidates[:args.limit]
    mode = "APPLY" if args.apply else "DRY RUN"
    print(f"{mode}: processing {len(candidates)} document(s)")

    succeeded = failed = 0
    for index, summary in enumerate(candidates, 1):
        document_id = int(summary["id"])
        try:
            document = paperless.request("GET", f"api/documents/{document_id}/?full_perms=true")
            result = llm.complete(make_prompt(document, context, args.text_limit))
            patch = proposed_patch(
                document, result, context, ai_tag_id, review_tag_id, sender_field, recipient_field
            )
            print(f"[{index}/{len(candidates)}] document #{document_id}")
            display_plan(document, patch, context)
            if args.apply:
                paperless.request("PATCH", f"api/documents/{document_id}/", patch)
                print("  RESULT APPLIED")
            else:
                print("  RESULT DRY-RUN; NOT CHANGED")
            succeeded += 1
        except FatalApiError:
            print(f"[{index}/{len(candidates)}] #{document_id}: fatal API error; stopping batch", file=sys.stderr)
            raise
        except ScriptError as error:
            failed += 1
            print(f"[{index}/{len(candidates)}] #{document_id}: ERROR: {error}", file=sys.stderr)
            if args.fail_fast:
                raise
        if args.delay:
            time.sleep(args.delay)
    print(f"Finished: {succeeded} succeeded, {failed} failed")
    if failed:
        raise ScriptError(f"{failed} document(s) failed")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument(
        "--paperless-url",
        default=os.environ.get("PAPERLESS_URL", "https://docs.vasary.org/"),
        help="Paperless base URL (env: PAPERLESS_URL)",
    )
    result.add_argument("--ai-tag", default="ai")
    result.add_argument("--review-tag", default="Требуется ручная проверка")
    result.add_argument("--timeout", type=int, default=120)
    commands = result.add_subparsers(dest="command", required=True)

    sync = commands.add_parser("sync-context", help="Download Paperless lookup tables")
    sync.add_argument("--ensure-tags", action="store_true", help="Create processing and review tags when absent")
    sync.set_defaults(handler=sync_context)

    process = commands.add_parser("process", help="Generate document metadata")
    process.add_argument("--apply", action="store_true", help="Patch Paperless; default is dry-run")
    process.add_argument("--limit", type=int, default=20, help="Maximum documents; 0 means all")
    process.add_argument("--text-limit", type=int, default=12000, help="Maximum OCR characters per prompt")
    process.add_argument("--sender-field", help="Exact sender custom-field name")
    process.add_argument("--recipient-field", help="Exact recipient custom-field name")
    process.add_argument("--llm-url", default=os.environ.get(
        "LITELLM_URL", "https://llm-proxy.vasary.org/v1"
    ))
    process.add_argument("--model", default="gemini-free-flash")
    process.add_argument("--llm-timeout", type=int, default=300)
    process.add_argument("--delay", type=float, default=0.0)
    process.add_argument("--fail-fast", action="store_true")
    process.set_defaults(handler=process_documents)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        args.handler(args)
    except (ScriptError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
