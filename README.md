# ai-split-commit.nvim

Group staged changes semantically for review, inspection, and selective commits.

`ai-split-commit.nvim` is a review-oriented plugin:
- it analyzes your staged diff
- proposes semantic groups
- assigns a criticality level to each group
- lets you move hunks between groups
- integrates with `ai-commit.nvim` when you want to commit one group

It is not just a commit tool — it is primarily a change-inspection workflow.

## Features

- AI-powered semantic grouping
- criticality levels per group (`high`, `medium`, `low`)
- 4-pane review UI: groups / changes / diff / commit message
- switchable view modes:
  - `split` → groups / changes / diff
  - `group_diff` → groups / wide group diff
- move hunks between groups
- create, rename, merge, delete, reorder groups
- stage one group for manual commit
- commit one group through `ai-commit.nvim`
- OpenRouter and GitHub Copilot support via `ai-provider.nvim`

---

## Requirements

- Neovim >= 0.8.0
- Git
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [ai-provider.nvim](https://github.com/cjvnjde/ai-provider.nvim)
- [ai-commit.nvim](https://github.com/cjvnjde/ai-commit.nvim) *(optional, for `gc` integration)*

---

## Installation

## 1. Review-only setup

If you only want semantic grouping / inspection:

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

## 2. Full integration with ai-commit.nvim

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

## 3. Local development setup

```lua
{
  dir = "/mnt/shared/projects/personal/nvim-plugins/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    { dir = "/mnt/shared/projects/personal/nvim-plugins/ai-provider.nvim" },
    { dir = "/mnt/shared/projects/personal/nvim-plugins/ai-commit.nvim" },
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
  },
}
```

---

## Provider setup

## GitHub Copilot

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
  },
}
```

Authenticate once:

```vim
:AISplitCommitLogin
```

## OpenRouter

```bash
export OPENROUTER_API_KEY=sk-...
```

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  opts = {
    provider = "openrouter",
    model = "google/gemini-2.5-flash",
  },
}
```

### Forward provider config through the plugin

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
    provider_config = {
      ["github-copilot"] = {
        enterprise_domain = "company.ghe.com",
      },
    },
  },
}
```

---

## Workflow

## Basic review flow

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
5. Generate commit messages **without leaving the UI**
6. Edit saved commit messages if you want
7. Commit current group or all prepared groups

## Recommended workflow

A good flow is:

1. `:AISplitCommit`
2. move between groups
3. press `gc` on a group
4. pick a message from `ai-commit.nvim` Telescope suggestions
5. the message is saved on that group
6. repeat for the other groups
7. optionally edit the saved message in the bottom commit-message pane
8. press:
   - `cc` to commit the current prepared group
   - `ca` to commit all groups that already have saved commit messages

## Batch flow

If you want commit messages for all groups quickly:

1. `:AISplitCommit`
2. press `ga`
3. the plugin automatically uses each group's name as commit guidance
4. it asks `ai-commit.nvim` for **one** message per group
5. the first generated message is saved on each group
6. press `ca` to commit them

## Example scenario

You changed code for two reasons:
- feature work
- refactor / cleanup

Run `:AISplitCommit` and AI may propose:
- `Add provider fallback support` — `medium`
- `Refactor request helpers` — `low`

Then you can:
- move a wrongly-grouped hunk
- rename a group
- press `gc` on `Add provider fallback support`
- pick one suggested commit message
- press `gc` on `Refactor request helpers`
- pick another commit message
- press `ca` to create both commits in order

---

## Criticality levels

Each group gets a criticality level:

- `▲ high` — bug fixes, breaking changes, security-sensitive work
- `● medium` — features, important behavior changes, significant refactors
- `▽ low` — docs, tests, style, cleanup, comments

This is a review aid, not a hard rule.

---

## UI layout

### Split view

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
- `f` = file count
- `i` = item count (hunks / file-level diff items)
- `[msg]` = this group already has a saved commit message
- `[*]` = this group changed after grouping / message generation and should be reviewed again

---

## Keymaps

Keymaps follow the [blink.nvim](https://github.com/Saghen/blink.cmp) convention.
Each entry maps a key to a list of actions. Actions are tried in order — if one
returns `false` / `nil` (doesn't apply to the current pane), the next action runs.
`"fallback"` at the end of the list feeds the original key to Neovim.

Your custom keys are merged with the `preset`. Conflicting keys overwrite the
preset. Set a key to `false` or `{}` to disable it.

### Customizing keymaps

```lua
opts = {
  keymaps = {
    -- set to 'none' to disable the 'default' preset
    preset = "default",

    -- remap
    ["<Esc>"] = { "close" },
    ["<C-j>"] = { "move_group_down", "fallback" },
    ["<C-k>"] = { "move_group_up", "fallback" },

    -- disable a key from the preset
    ["q"] = false,

    -- custom function (return true to consume the key)
    ["<C-g>"] = {
      function(session, role)
        if role ~= "groups" then return end
        vim.notify("Groups: " .. #session.groups)
        return true
      end,
      "fallback",
    },
  },
}
```

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

Pane-specific actions (`add_group`, `move_item`, etc.) only fire in their
respective pane. When they don't apply, the chain continues to `"fallback"`,
so normal key behaviour is preserved in other panes (e.g. editing the commit
message).

### Action reference

#### All panes

| Default key | Action | Description |
| --- | --- | --- |
| `q` | `close` | Close session |
| `P` | `preview_all` | Preview all groups in a new tab |
| `gv` | `toggle_view` | Toggle between `split` and `group_diff` view |
| `gs` | `stage_group` | Stage current group only |
| `gc` | `generate_commit` | Generate commit message suggestions for current group |
| `ga` | `generate_all_commits` | Auto-generate one commit message for every group |
| `cc` | `commit_current` | Commit current group using its saved commit message |
| `ca` | `commit_all` | Commit all groups that have saved commit messages |
| `<Tab>` | `next_pane` | Cycle panes |
| `<CR>` | `confirm` | Context-dependent: focus next pane / message pane |

#### Groups pane

| Default key | Action | Description |
| --- | --- | --- |
| `j` / `k` | *(built-in)* | Move between groups |
| `a` | `add_group` | Add group |
| `e` | `rename_group` | Rename group |
| `M` | `merge_group` | Merge current group into another |
| `dd` | `delete_group` | Delete group |
| `J` / `K` | `move_group_down` / `move_group_up` | Reorder groups |
| `R` | `regroup_all` | Regroup all with AI |

#### Changes pane

| Default key | Action | Description |
| --- | --- | --- |
| `j` / `k` | *(built-in)* | Move between items |
| `m` | `move_item` | Move item to another group |
| `n` | `move_item_new` | Move item to a new group |
| `x` | `unassign_item` | Move item to Unassigned |

#### Diff pane

Shared keymaps only (see "All panes" above).

#### Commit Message pane

| Action | Description |
| --- | --- |
| normal editing | edit the saved message manually |
| `gc` (`generate_commit`) | replace/save a generated message for current group |
| `ga` (`generate_all_commits`) | auto-generate one message per group |
| `cc` / `ca` (`commit_current` / `commit_all`) | commit prepared groups |

---

## View modes

### `split`
Default classic layout:
- Groups
- Changes
- Diff
- Commit Message

Use this when you want item-level inspection.

### `group_diff`
Hides the middle **Changes** column and makes the selected group's diff much wider.

Use this when you want to review one whole group's patch like a long preview stripe.

Switch anytime with:

```text
gv
```

You can also set the default mode in config:

```lua
opts = {
  default_view_mode = "group_diff",
}
```

---

## Commands

| Command | Description |
| --- | --- |
| `:AISplitCommit [extra prompt]` | Start review session |
| `:AISplitCommitModels [provider]` | Choose model |
| `:AISplitCommitLogin [provider]` | Authenticate provider |
| `:AISplitCommitLogout [provider]` | Remove credentials |
| `:AISplitCommitStatus` | Show provider + model + auth status |

---

## Configuration

```lua
{
  provider = "openrouter",
  model = "google/gemini-2.5-flash",
  max_tokens = 4096,
  max_item_diff_length = 1200,
  max_group_count = 8,
  debug = false,
  grouping_prompt_template = nil,
  grouping_system_prompt = nil,
  default_view_mode = "split", -- "split" or "group_diff"
  use_delta = true, -- use delta for rich diff rendering

  keymaps = {
    preset = "default",
  },

  provider_config = {
    openrouter = { api_key = nil },
    ["github-copilot"] = { enterprise_domain = nil },
  },
}
```

## Options

| Option | Type | Description |
| --- | --- | --- |
| `provider` | `string` | `openrouter` or `github-copilot` |
| `model` | `string` | model ID for the selected provider |
| `max_tokens` | `number` | max output tokens |
| `max_item_diff_length` | `number` | per-item diff truncation for AI grouping |
| `max_group_count` | `number` | soft cap for number of proposed groups |
| `debug` | `boolean` | save prompts to cache |
| `grouping_prompt_template` | `string?` | custom grouping prompt |
| `grouping_system_prompt` | `string?` | custom grouping system prompt |
| `default_view_mode` | `string` | `split` or `group_diff` |
| `use_delta` | `boolean` | use [delta](https://github.com/dandavison/delta) for rich diff rendering |
| `keymaps` | `table` | blink.nvim-style keymap config (see [Keymaps](#keymaps)) |
| `keymaps.preset` | `string` | `"default"` or `"none"` |
| `provider_config` | `table?` | forwarded to `ai-provider.setup()` |

---

## Integration with ai-commit.nvim

`gc` uses `ai-commit.nvim` to generate suggestions for the **selected group diff** without leaving the split view.

Interactive generation:

```lua
require("ai-commit").generate_commit_for_diff(diff_text, {
  extra_prompt = "Group name: Add provider fallback support",
  on_select = function(message)
    -- save selected message on the current group
  end,
})
```

Batch generation:

```lua
require("ai-commit").generate_commit_messages_for_diff(diff_text, {
  extra_prompt = [[
    Group name: Add provider fallback support
    Generate exactly one commit message only.
  ]],
}, function(messages, err)
  -- save messages[1] on the group
end)
```

That means:
- commit suggestions are generated from the current group's diff
- not from the full staged diff
- the selected message is saved on the group
- the actual `git commit` happens later when you press `cc` or `ca`

If `ai-commit.nvim` is not installed, `gc` / `ga` are unavailable, but inspection and grouping still work.

---

## Example configurations

## 1. Use the same Copilot model for both plugins

```lua
{
  dir = "/mnt/shared/projects/personal/nvim-plugins/ai-split-commit.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cjvnjde/ai-provider.nvim",
    { dir = "/mnt/shared/projects/personal/nvim-plugins/ai-commit.nvim" },
  },
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
  },
},
{
  dir = "/mnt/shared/projects/personal/nvim-plugins/ai-commit.nvim",
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

## 2. Use different providers per plugin

Example: fast grouping on Copilot, commit messages on OpenRouter.

```lua
{
  "cjvnjde/ai-split-commit.nvim",
  opts = {
    provider = "github-copilot",
    model = "gpt-5-mini",
  },
},
{
  "cjvnjde/ai-commit.nvim",
  opts = {
    provider = "openrouter",
    model = "google/gemini-2.5-pro",
  },
}
```

## 3. Use it only for inspection

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

Then use:
- `:AISplitCommit`
- inspect the groups
- `gs` to stage one group
- commit manually however you want

---

## Logging

When grouping starts, you now see a single clearer notification.

Example:

```text
Sending AI request: AISplitCommit[grouping] -> github-copilot / gpt-5-mini -> api.githubcopilot.com
```

So you can always see:
- which plugin triggered the request
- which provider is being used
- which model is being used
- which host receives the request

---

## Current limitations

- staged changes only
- clean worktree required
- no binary files
- no missing-newline file markers
- no partial line splitting inside a hunk
