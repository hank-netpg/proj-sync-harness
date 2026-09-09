# What was removed from this public mirror

This repository is a sanitized public mirror. The mechanism is intact; anything
that identified a real client, colleague, or workspace is not.

Removed or replaced:

- Organization and company identifiers, and the internal marketplace/org names.
- Colleague names, work e-mail addresses, and real Slack user IDs
  (`U…` values are placeholders).
- Real project codes in comments and incident notes, replaced with
  `proj-alpha` … `proj-epsilon` / `기관A`–`기관D`.
- The two RFP example fixtures under `docs/design/examples/`, rewritten as
  synthetic requirement/TOC data with the same schema.
- The development changelog, replaced by a condensed summary — the original
  entries carried project-specific incident detail.
- An internal secrets-administration runbook and a document template binary.

No credentials, API tokens, or workspace IDs were present in the source
repository; it holds the tool only, never a project's config or deliverables.

- An external delta helper the agents call is referenced as `<delta-tool>/delta.py`;
  it lives outside this repository and is not included.
