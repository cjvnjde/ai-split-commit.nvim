# ai-split-commit.nvim

Group staged changes semantically for review, inspection, and selective commits.

`ai-split-commit.nvim` is a review-oriented plugin. It analyzes your staged diff using AI, proposes semantic groups (e.g., "Fix auth refresh", "Refactor helpers", "Update docs"), assigns a criticality level to each group, and presents everything in a 4-pane review UI. You can move hunks between groups, rename/merge/reorder groups, generate commit messages per group (via [ai-commit.nvim](https://github.com/cjvnjde/ai-commit.nvim)), and commit groups individually or all at once — without leaving the UI.

It is not just a commit tool — it is primarily a **change-inspection workflow** that helps you create clean, focused commits from a messy staging area.

## Features

- AI-powered semantic grouping of staged changes
- Criticality levels per group (`high`, `medium`, `low`)
- 4-pane review UI: groups / changes / diff preview / commit message
- Two view modes: `split` (detailed) and `group_diff` (wide group diff)
- Move hunks between groups
- Create, rename, merge, delete, reorder groups
- Re-group everything with AI at any time
- Generate commit messages per group through `ai-commit.nvim`
- Batch-generate one commit message per group automatically
- Commit one group or all prepared groups at once
- Stage one group for manual commit
- Binary-safe handling: binary file content is omitted from preview and AI input, while staging/committing still works
- [delta](https://github.com/dandavison/delta) support for rich diff rendering
- Blink.nvim-style keymap customization
- Backup ref created before multi-group commits

---

## Requirements

- Neovim >= 0.8.0
- Git
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [ai-provider.nvim](https://github.com/cjvnjde/ai-provider.nvim)
- [ai-commit.nvim](https://github.com/cjvnjde/ai-commit.nvim) *(optional — needed for `gc`/`ga` commit message generation)*
- [delta](https://github.com/dandavison/delta) *(optional — for rich diff rendering)*

---

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",  -- optional, for commit message generation
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
  },
}
```

---

## Setup

```lua
require("ai-split-commit").setup(opts)
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `provider` | `string` | `"openrouter"` | AI provider to use. One of `"openrouter"`, `"github-copilot"`, `"anthropic"`, `"google"`, `"openai"`, `"xai"`, `"groq"`, `"cerebras"`, `"mistral"`. |
| `model` | `string` | `"google/gemini-2.5-flash"` | Model ID for the selected provider. Use `:AISplitCommitModels` to browse available models. |
| `max_tokens` | `number` | `4096` | Maximum output tokens for the AI response. |
| `max_item_diff_length` | `number` | `1200` | Per-item diff truncation (in characters) before sending to AI for grouping. Longer hunks are truncated with `... (truncated)`. This controls how much context the AI sees per hunk. |
| `max_group_count` | `number` | `8` | Soft cap for the number of groups the AI proposes. The AI is instructed to prefer 1 to this many groups. |
| `ignored_files` | `string[]` | `{}` | List of file paths or glob patterns to omit from AI grouping and AI commit-message generation. Matching files remain visible in the review UI and can still be staged/committed manually. |
| `debug` | `boolean` | `false` | Save grouping prompt + response transcripts to `~/.cache/nvim/ai-split-commit-debug/` for inspection. |
| `grouping_prompt_template` | `string?` | `nil` | Custom user prompt for the grouping request. When `nil`, the built-in template is used. See [Prompt Customization](#prompt-customization). |
| `grouping_system_prompt` | `string?` | `nil` | Custom system prompt for the grouping request. When `nil`, the built-in system prompt is used. |
| `default_view_mode` | `string` | `"split"` | Initial view mode when opening the UI. `"split"` shows groups/changes/diff columns. `"group_diff"` hides the changes column and shows a wider diff. |
| `use_delta` | `boolean` | `true` | Use [delta](https://github.com/dandavison/delta) for rich diff rendering if it is installed. Falls back to plain diff syntax highlighting when delta is not available or this is `false`. |
| `keymaps` | `table` | `{ preset = "default" }` | Blink.nvim-style keymap configuration. See [Keymaps](#keymaps). |
| `keymaps.preset` | `string` | `"default"` | Base keymap preset. `"default"` loads the built-in keymaps. `"none"` starts with no keymaps. |
| `ai_options` | `table` | `{}` | Per-request options forwarded to `ai-provider.complete_simple()`. Use this for request-scoped settings such as `reasoning`, `temperature`, `headers`, or future request parameters added by `ai-provider.nvim`. |
| `ai_provider` | `table?` | `nil` | Full shared `ai-provider.setup()` passthrough. Use this to configure global `ai-provider.nvim` behavior such as `reasoning`, `debug`, `debug_toast`, `notification`, `providers`, or `custom_models` directly from `ai-split-commit.nvim`, with no separate `ai-provider.nvim` config block required. |

### `ai_provider` vs `ai_options`

- Use `ai_options` for **grouping requests issued by `ai-split-commit.nvim`**.
- Use `ai_provider` for **shared/global `ai-provider.nvim` setup**.
- `debug = true` in `ai-split-commit.nvim` saves a readable grouping prompt/response transcript.
- `ai_provider.debug = true` saves raw provider-level JSON request/response dumps.
- If both `ai-split-commit.nvim` and another plugin set `ai_provider`, the resulting `ai-provider.nvim` config is shared, because `ai-provider.nvim` itself is global.
- In normal setups, you do **not** need a separate `ai-provider.nvim` `opts = { ... }` block at all.

Common patterns:

**1. Higher reasoning only for grouping**

```lua
opts = {
  provider = "github-copilot",
  model = "gpt-5-mini",
  ai_options = {
    reasoning = "high",
  },
}
```

**2. Enable debug dumps + live debug toast globally through `ai-split-commit.nvim`**

```lua
opts = {
  provider = "github-copilot",
  model = "gpt-5-mini",
  ai_options = {
    reasoning = "high",
  },
  ai_provider = {
    debug = true,
    debug_toast = { enabled = true },
    notification = { enabled = true },
  },
}
```

**3. Register or override models without touching `ai-provider.nvim` directly**

```lua
opts = {
  provider = "openrouter",
  model = "google/gemini-3-flash-preview",
  ai_provider = {
    custom_models = {
      openrouter = {
        {
          id = "google/gemini-3-flash-preview",
          name = "Gemini 3 Flash Preview (my preset)",
          api = "openai-completions",
          provider = "openrouter",
          base_url = "https://openrouter.ai/api/v1",
          reasoning = true,
          input = { "text", "image" },
          context_window = 1048576,
          max_tokens = 65536,
        },
      },
    },
  },
}
```

---

## Configuration Examples

### 1. GitHub Copilot — simple setup

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
  },
}
```

Then authenticate once:

```vim
:AISplitCommitLogin
```

### 2. OpenRouter with Gemini

```bash
export OPENROUTER_API_KEY=sk-or-...
```

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "openrouter",
    model = "google/gemini-2.5-flash",
  },
}
```

### 3. OpenRouter with explicit API key

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "openrouter",
    model = "google/gemini-2.5-flash",
    ai_provider = {
      providers = {
        openrouter = {
          api_key = "sk-or-your-key-here",
        },
      },
    },
  },
}
```

### 4. GitHub Copilot with Claude Sonnet 4.6

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "github-copilot",
    model = "claude-sonnet-4.6",
  },
}
```

### 5. GitHub Enterprise Copilot

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
    ai_provider = {
      providers = {
        ["github-copilot"] = {
          enterprise_domain = "company.ghe.com",
        },
      },
    },
  },
}
```

### 6. Review-only (no ai-commit.nvim dependency)

If you only want semantic grouping and inspection without `gc`/`ga` commit message generation:

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
  },
}
```

You can still use `gs` to stage a group and commit manually.

### 7. Group diff view mode by default

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
    default_view_mode = "group_diff",
  },
}
```

### 8. Disable delta rendering

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
    use_delta = false,
  },
}
```

### 9. Allow more groups with more context per hunk

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "openrouter",
    model = "google/gemini-2.5-pro",
    max_group_count = 12,
    max_item_diff_length = 3000,
    max_tokens = 8192,
  },
}
```

### 10. Custom keymaps

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
    keymaps = {
      preset = "default",
      -- remap
      ["<Esc>"] = { "close" },
      ["<C-j>"] = { "move_group_down", "fallback" },
      ["<C-k>"] = { "move_group_up", "fallback" },
      -- disable a key
      ["q"] = false,
    },
  },
}
```

### 11. Start from scratch keymaps

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
    keymaps = {
      preset = "none",
      ["<Esc>"] = { "close" },
      ["gc"] = { "generate_commit" },
      ["ga"] = { "generate_all_commits" },
      ["cc"] = { "commit_current" },
      ["ca"] = { "commit_all" },
      ["<Tab>"] = { "next_pane" },
    },
  },
}
```

### 12. Different providers for grouping vs. commit messages

Use a fast model for grouping in `ai-split-commit.nvim` and a stronger model for commit messages in `ai-commit.nvim`:

```lua
-- ai-split-commit: fast grouping
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
  },
},

-- ai-commit: stronger model for commit messages
{
  "cjvnjde/ai-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
    "cjvnjde/ai-provider.nvim",
  },
  opts = {
    provider = "openrouter",
    model = "anthropic/claude-sonnet-4",
  },
}
```

### 13. Both plugins on the same Copilot model

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
  },
},
{
  "cjvnjde/ai-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
    "cjvnjde/ai-provider.nvim",
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
  },
}
```

### 14. Debug mode — inspect grouping prompt + response

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
    debug = true,
  },
}
```

Grouping prompt + response transcripts are saved to `~/.cache/nvim/ai-split-commit-debug/`.

### 15. Full kitchen-sink configuration

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    "cjvnjde/ai-commit.nvim",
  },
  opts = {
    provider = "github-copilot",
    model = "claude-sonnet-4.6",
    max_tokens = 8192,
    max_item_diff_length = 2000,
    max_group_count = 10,
    ignored_files = {
      "package-lock.json",
      "yarn.lock",
      "pnpm-lock.yaml",
      "dist/*",
    },
    debug = false,
    default_view_mode = "split",
    use_delta = true,
    keymaps = {
      preset = "default",
      ["<Esc>"] = { "close" },
      ["<C-j>"] = { "move_group_down", "fallback" },
      ["<C-k>"] = { "move_group_up", "fallback" },
    },
    ai_provider = {
      providers = {
        ["github-copilot"] = {
          enterprise_domain = "company.ghe.com",
        },
      },
    },
  },
}
```

---

## Workflow

### Basic review flow

1. Stage your changes:

```bash
git add .
```

2. Open the review UI:

```vim
:AISplitCommit
```

3. Review the proposed groups
4. Move hunks / rename / merge / reorder as needed
5. Generate commit messages without leaving the UI
6. Edit saved commit messages if you want
7. Commit current group or all prepared groups

### Recommended workflow

1. `:AISplitCommit`
2. Navigate between groups
3. Press `gc` on a group to generate commit message suggestions
4. Pick a message from `ai-commit.nvim` Telescope picker
5. The message is saved on that group
6. Repeat for other groups
7. Optionally edit the saved message in the bottom commit-message pane
8. Press `cc` to commit the current group, or `ca` to commit all prepared groups

### Batch flow

Generate commit messages for all groups at once:

1. `:AISplitCommit`
2. Press `ga`
3. The plugin uses each group's name as commit guidance
4. It asks `ai-commit.nvim` for one message per group automatically
5. Press `ca` to commit all groups

---

## Criticality Levels

Each group gets a criticality level assigned by the AI:

| Level | Icon | Meaning |
|-------|------|---------|
| `high` | `▲` | Bug fixes, breaking changes, security-sensitive work |
| `medium` | `●` | Features, important behavior changes, significant refactors |
| `low` | `▽` | Docs, tests, style, cleanup, comments |

This is a review aid, not a hard rule.

---

## UI Layout

### Split view (default)

```text
┌──────────────────────┬────────────────────────────┬──────────────────────┐
│ Groups               │ Changes                    │ Diff Preview         │
│                      │                            │                      │
│ >▲ Fix auth refresh  │ lua/provider/init.lua      │ @@ -10,3 +10,8 @@   │
│   [msg] 2f 3i        │   H1  @@ -10,3 +10,8 @@   │ + new auth logic     │
│                      │   H2  @@ -48,2 +57,11 @@  │ - old handler        │
│  ● Add fallback      │                            │                      │
│   3f 5i              │ lua/provider/request.lua   │                      │
│                      │   H3  @@ -90,7 +104,18 @@ │                      │
│  ▽ Update README     │                            │                      │
│   [*] 1f 1i          │                            │                      │
│                      │                            │                      │
│ U Unassigned  2i     │                            │                      │
└──────────────────────┴────────────────────────────┴──────────────────────┘
┌──────────────────────────────────────────────────────────────────────────┐
│ Commit Message                                                          │
│                                                                         │
│ feat(provider): add fallback routing                                    │
│                                                                         │
│ Add provider fallback handling and update request selection logic.      │
└──────────────────────────────────────────────────────────────────────────┘
```

### Group diff view

```text
┌──────────────────────┬───────────────────────────────────────────────────┐
│ Groups               │ Group Diff                                        │
│                      │                                                   │
│ >▲ Fix auth refresh  │ diff --git a/...                                 │
│   [msg] 2f 3i        │ @@ -10,3 +10,8 @@                                │
│                      │ + new auth logic                                  │
│  ● Add fallback      │                                                   │
│   3f 5i              │ @@ -48,2 +57,11 @@                               │
│                      │ - old handler                                     │
│  ▽ Update README     │ + updated flow                                    │
│   [*] 1f 1i          │                                                   │
│                      │                                                   │
│ U Unassigned  2i     │                                                   │
└──────────────────────┴───────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────────────────┐
│ Commit Message                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

Legend:
- `f` = file count, `i` = item count (hunks / file-level diff items)
- `[msg]` = this group has a saved commit message
- `[*]` = this group changed after grouping and should be reviewed again

---

## Commands

| Command | Description |
| --- | --- |
| `:AISplitCommit [extra prompt]` | Start a review session. Optional extra instructions are passed to the grouping prompt. |
| `:AISplitCommitModels [provider]` | Browse and select a model for the current or specified provider. |
| `:AISplitCommitLogin [provider]` | Authenticate with a provider (default: current provider). Required for GitHub Copilot. |
| `:AISplitCommitLogout [provider]` | Remove stored credentials for a provider. |
| `:AISplitCommitStatus` | Show current provider, model, and authentication status. |

---

## Keymaps

Keymaps follow the [blink.nvim](https://github.com/Saghen/blink.cmp) convention. Each entry maps a key to a list of actions. Actions are tried in order — if one returns `false`/`nil` (doesn't apply to the current pane), the next action runs. `"fallback"` at the end of the list feeds the original key to Neovim.

Your custom keys are merged with the `preset`. Conflicting keys overwrite the preset. Set a key to `false` or `{}` to disable it.

### Default preset

```lua
{
  ["q"]     = { "close" },
  ["P"]     = { "preview_all" },
  ["gv"]    = { "toggle_view" },
  ["gs"]    = { "stage_group" },
  ["gc"]    = { "generate_commit" },
  ["ga"]    = { "generate_all_commits" },
  ["cc"]    = { "commit_current" },
  ["ca"]    = { "commit_all" },
  ["<Tab>"] = { "next_pane" },
  ["<CR>"]  = { "confirm", "fallback" },
  ["a"]     = { "add_group", "fallback" },
  ["e"]     = { "rename_group", "fallback" },
  ["M"]     = { "merge_group", "fallback" },
  ["dd"]    = { "delete_group", "fallback" },
  ["J"]     = { "move_group_down", "fallback" },
  ["K"]     = { "move_group_up", "fallback" },
  ["R"]     = { "regroup_all", "fallback" },
  ["m"]     = { "move_item", "fallback" },
  ["n"]     = { "move_item_new", "fallback" },
  ["x"]     = { "unassign_item", "fallback" },
}
```

### Customizing keymaps

```lua
keymaps = {
  preset = "default",         -- or "none"
  ["<Esc>"] = { "close" },   -- add new
  ["q"] = false,              -- disable from preset
  ["<C-j>"] = { "move_group_down", "fallback" },
  ["<C-k>"] = { "move_group_up", "fallback" },
  -- custom function (return true to consume the key)
  ["<C-g>"] = {
    function(session, role)
      if role ~= "groups" then return end
      vim.notify("Groups: " .. #session.groups)
      return true
    end,
    "fallback",
  },
}
```

### Action Reference

#### All panes

| Default key | Action | Description |
| --- | --- | --- |
| `q` | `close` | Close session |
| `P` | `preview_all` | Preview all groups in a new tab |
| `gv` | `toggle_view` | Toggle between `split` and `group_diff` view |
| `gs` | `stage_group` | Stage current group only (then close) |
| `gc` | `generate_commit` | Generate commit message suggestions for current group (requires `ai-commit.nvim`) |
| `ga` | `generate_all_commits` | Auto-generate one commit message for every group (requires `ai-commit.nvim`) |
| `cc` | `commit_current` | Commit current group using its saved commit message |
| `ca` | `commit_all` | Commit all groups that have saved commit messages |
| `<Tab>` | `next_pane` | Cycle through panes |
| `<CR>` | `confirm` | Context-dependent: focus next pane / message pane |

#### Groups pane

| Default key | Action | Description |
| --- | --- | --- |
| `a` | `add_group` | Create a new empty group |
| `e` | `rename_group` | Rename current group |
| `M` | `merge_group` | Merge current group into another |
| `dd` | `delete_group` | Delete group (items go to Unassigned) |
| `J` / `K` | `move_group_down` / `move_group_up` | Reorder groups |
| `R` | `regroup_all` | Re-run AI grouping on all items |

#### Changes pane

| Default key | Action | Description |
| --- | --- | --- |
| `m` | `move_item` | Move item to another group |
| `n` | `move_item_new` | Move item to a new group |
| `x` | `unassign_item` | Move item to Unassigned |

#### Commit Message pane

Normal editing works. Additionally, `gc`, `ga`, `cc`, `ca` work from this pane too.

---

## Integration with ai-commit.nvim

When you press `gc` or `ga`, `ai-split-commit.nvim` calls `ai-commit.nvim` under the hood:

- `gc` generates commit message suggestions for the **selected group's diff** (not the full staged diff) and opens a Telescope picker
- `ga` auto-generates **one** commit message per group without opening Telescope
- The generated message is saved on the group
- The actual `git commit` happens later when you press `cc` or `ca`

If `ai-commit.nvim` is not installed, `gc` / `ga` are unavailable, but inspection, grouping, and manual message editing still work.

---

## Prompt Customization

### Available placeholders

| Placeholder | Description |
|-------------|-------------|
| `<items/>` | The list of items with their IDs, paths, and truncated diffs |
| `<recent_commits/>` | The last 5 commit subjects |
| `<extra_prompt/>` | Extra instructions passed via `:AISplitCommit ...` args |
| `<max_group_count/>` | The configured `max_group_count` value |

### Example: custom grouping prompt

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
    grouping_prompt_template = [[
Split the staged changes into semantic groups.
Prefer fewer groups. Use all item IDs.

<extra_prompt/>

Recent commits:
<recent_commits/>

Items:
<items/>
]],
  },
}
```

---

## Logging

When grouping starts, you see a single notification:

```text
Sending AI request: AISplitCommit[grouping] -> github-copilot / gpt-5-mini -> api.githubcopilot.com
```

---

## Current Limitations

- Staged changes only (all changes must be staged)
- Clean worktree required (no unstaged or untracked files)
- Binary file content is not shown in preview and is not sent to AI; only file metadata/path is used
- No missing-newline file markers
- No partial line splitting inside a hunk
