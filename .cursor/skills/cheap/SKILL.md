---
name: cheap
description: Opt-in low-cost pstack models. Use when the user says "low-cost mode", "low cost", or "grok-only", when the prompt has a line "Cost: LOW", or when they invoke /cheap. Read .cursor/rules/pstack-models.mdc and apply every role line for this session. Do not use on ordinary tasks.
---

# Low-cost pstack

pstack's built-in model defaults stay in place until this skill is invoked.

When it is invoked, read `.cursor/rules/pstack-models.mdc` and treat every role line as the active `pstack-models` rule for this session, including the panel lists. Those lines override pstack's defaults until the session ends. If Task rejects `cursor-grok-4.6-xhigh`, pick another `cursor-grok-4.6-*` slug from the error.

This skill does not apply when the prompt has none of those triggers.
