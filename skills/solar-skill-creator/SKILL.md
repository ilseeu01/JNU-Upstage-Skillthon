---
name: solar-skill-creator
description: Create new skills, modify and improve existing skills using the Upstage API — Solar LLM and Document Intelligence (chat, document parse, OCR, information extract, embeddings). Use when users want to create a skill from scratch, edit, or optimize an existing skill.
---

# Solar Skill Creator

A skill for creating new skills.

At a high level, the process of creating a skill goes like this:

- Decide what you want the skill to do and roughly how it should do it
- Write a draft of the skill
- Rewrite the skill based on feedback
- Repeat until you're satisfied

Your job when using this skill is to figure out where the user is in this process and then jump in and help them progress through these stages. So for instance, maybe they're like "I want to make a skill for X". You can help narrow down what they mean, write a draft, and iterate.

On the other hand, maybe they already have a draft of the skill. In this case you can go straight to the iterate part of the loop.

Of course, you should always be flexible and if the user is like "just vibe with me", you can do that instead.

Then after the skill is done (but again, the order is flexible), you can also run the skill description improver to optimize the triggering of the skill.

## Communicating with the user

The skill creator is liable to be used by people across a wide range of familiarity with coding jargon. The bulk of users are probably fairly computer-literate, but not all.

So please pay attention to context cues to understand how to phrase your communication.

It's OK to briefly explain terms if you're in doubt, and feel free to clarify terms with a short definition if you're unsure if the user will get it.

## Creating a skill

### Capture Intent

Start by understanding the user's intent. The current conversation might already contain a workflow the user wants to capture (e.g., they say "turn this into a skill"). If so, extract answers from the conversation history first — the tools used, the sequence of steps, corrections the user made, input/output formats observed. The user may need to fill the gaps, and should confirm before proceeding to the next step.

1. What should this skill enable the AI agent (Claude, Codex, etc.) to do?
2. When should this skill trigger? (what user phrases/contexts)
3. What's the expected output format?
4. Should we set up test cases to verify the skill works? Skills with objectively verifiable outputs (file transforms, data extraction, code generation, fixed workflow steps) benefit from test cases. Skills with subjective outputs (writing style, art) often don't need them. Suggest the appropriate default based on the skill type, but let the user decide.
5. Which Upstage capability fits the user's intent? Translate plain-language goals to API names — don't make the user learn the catalog. Use this mapping:

   | User intent | Upstage capability | Reference file |
   |---|---|---|
   | Generate text: chat, summarize, translate, function calling, Korean/multilingual | **Upstage Chat (Solar LLM)** | `references/upstage-chat.md` |
   | Parse documents: layout-aware text/structure extraction from PDFs (and scanned images via OCR mode) | **Upstage Document Parse** + **Document OCR** | `references/upstage-document-parse.md`, `references/upstage-ocr.md` |
   | Extract specific named fields from documents (invoice totals, form values, contract clauses) | **Upstage Information Extract (Universal)** | `references/upstage-information-extract.md` |
   | Classify documents into predefined categories (invoice / contract / receipt) | **Upstage Document Classification** | `references/upstage-classify.md` |
   | Embed text for semantic search, similarity, retrieval | **Upstage Embeddings** | `references/upstage-embeddings.md` |

   If intent spans multiple capabilities, compose them as a pipeline (e.g., OCR → Document Parse → Information Extract). Confirm the mapping with the user in plain language before drafting.

### Verify the API key is set

Every Upstage call needs `UPSTAGE_API_KEY`. Walk the user through this before drafting runtime code:

1. Issue a key at https://console.upstage.ai → API Keys.
2. Redeem the `UPWAVE-KOH` referral code for $70 in starter credit.
3. Copy `assets/.env.example` and fill in the issued key.
4. Confirm `UPSTAGE_API_KEY` is exported in the environment; fail fast with a message pointing back to step 1 if missing.

### Interview and Research

Proactively ask questions about edge cases, input/output formats, example files, success criteria, and dependencies. Wait to write test prompts until you've got this part ironed out.

Once the Upstage capability is chosen (see Capture Intent), load the matching `references/upstage-{capability}.md` to surface that API's request/response format (code blocks ready to drop into the skill) and known caveats. Each reference file mirrors the official Upstage docs and is the source of truth for the request shape.

Check available MCPs - if useful for research (searching docs, finding similar skills, looking up best practices), research in parallel via subagents if available, otherwise inline. Come prepared with context to reduce burden on the user.

### Write the SKILL.md

Based on the user interview, fill in these components:

- **name**: Skill identifier
- **description**: When to trigger, what it does. This is the primary triggering mechanism - include both what the skill does AND specific contexts for when to use it. All "when to use" info goes here, not in the body. Note: currently AI agents (Claude, Codex, etc.) have a tendency to "undertrigger" skills -- to not use them when they'd be useful. To combat this, please make the skill descriptions a little bit "pushy". So for instance, instead of "How to build a simple fast dashboard to display internal Anthropic data.", you might write "How to build a simple fast dashboard to display internal Anthropic data. Make sure to use this skill whenever the user mentions dashboards, data visualization, internal metrics, or wants to display any kind of company data, even if they don't explicitly ask for a 'dashboard.'"
- **compatibility**: Required tools, dependencies (optional, rarely needed)
- **the rest of the skill :)**

### Skill Writing Guide

#### Anatomy of a Skill

```
skill-name/
├── SKILL.md (required)
│   ├── YAML frontmatter (name, description required)
│   └── Markdown instructions
└── Bundled Resources (optional)
    ├── scripts/    - Executable code for deterministic/repetitive tasks
    ├── references/ - Docs loaded into context as needed
    └── assets/     - Files used in output (templates, icons, fonts)
```

#### Progressive Disclosure

Skills use a three-level loading system:
1. **Metadata** (name + description) - Always in context (~100 words)
2. **SKILL.md body** - In context whenever skill triggers (<500 lines ideal)
3. **Bundled resources** - As needed (unlimited, scripts can execute without loading)

These word counts are approximate and you can feel free to go longer if needed.

**Key patterns:**
- Keep SKILL.md under 500 lines; if you're approaching this limit, add an additional layer of hierarchy along with clear pointers about where the model using the skill should go next to follow up.
- Reference files clearly from SKILL.md with guidance on when to read them
- For large reference files (>300 lines), include a table of contents

**Domain organization**: When a skill supports multiple domains/frameworks, organize by variant:
```
cloud-deploy/
├── SKILL.md (workflow + selection)
└── references/
    ├── aws.md
    ├── gcp.md
    └── azure.md
```
The AI agent reads only the relevant reference file.

#### Principle of Lack of Surprise

This goes without saying, but skills must not contain malware, exploit code, or any content that could compromise system security. A skill's contents should not surprise the user in their intent if described. Don't go along with requests to create misleading skills or skills designed to facilitate unauthorized access, data exfiltration, or other malicious activities. Things like a "roleplay as an XYZ" are OK though.

#### Writing Patterns

Prefer using the imperative form in instructions.

**Defining output formats** - You can do it like this:
```markdown
## Report structure
ALWAYS use this exact template:
# [Title]
## Executive summary
## Key findings
## Recommendations
```

**Examples pattern** - It's useful to include examples. You can format them like this (but if "Input" and "Output" are in the examples you might want to deviate a little):
```markdown
## Commit message format
**Example 1:**
Input: Added user authentication with JWT tokens
Output: feat(auth): implement JWT-based authentication
```

### Writing Style

Try to explain to the model why things are important in lieu of heavy-handed musty MUSTs. Use theory of mind and try to make the skill general and not super-narrow to specific examples. Start by writing a draft and then look at it with fresh eyes and improve it.

## References

Per-capability reference files (load on demand using the routing table in `### Capture Intent`):

- `references/upstage-chat.md` — Solar LLM chat completions. Docs: https://console.upstage.ai/docs/capabilities/chat
- `references/upstage-document-parse.md` — Layout-aware document extraction. Docs: https://console.upstage.ai/docs/capabilities/parse/api-quickstart
- `references/upstage-ocr.md` — Document OCR for scans and handwriting. Docs: https://console.upstage.ai/docs/capabilities/document-ocr
- `references/upstage-information-extract.md` — Schema-driven field extraction. Docs: https://console.upstage.ai/docs/capabilities/extract/universal-extraction
- `references/upstage-classify.md` — Document classification into caller-defined categories. Docs: https://console.upstage.ai/docs/capabilities/classify
- `references/upstage-embeddings.md` — Text embeddings for retrieval. Docs: https://console.upstage.ai/docs/capabilities/embed

If the Upstage API returns an unexpected error or response shape, consult the live spec: https://console.upstage.ai/api/docs/for-agents/raw