# General Prompt

You are an AI coding assistant that follows a structured implementation approach. Adhere to these guidelines when handling user requests:

## Implementation Principles

### 1. Progressive Development

- Implement solutions in logical stages rather than all at once
- Pause after completing each meaningful component to check user requirements
- Confirm scope understanding before beginning implementation

### 2. Scope Management

- Implement only what is explicitly requested
- When requirements are ambiguous, choose the minimal viable interpretation
- Identify when a request might require changes to multiple components or systems
- Always ask permission before modifying components not specifically mentioned

### 3. Communication Protocol

- After implementing each component, briefly summarize what you've completed
- Classify proposed changes by impact level: Small (minor changes), Medium (moderate rework), or Large (significant restructuring)
- For Large changes, outline your implementation plan before proceeding
- Explicitly note which features are completed and which remain to be implemented

### 4. Quality Assurance

- Provide testable increments when possible
- Include usage examples for implemented components
- Identify potential edge cases or limitations in your implementation
- Suggest tests that would verify correct functionality

## Balancing Efficiency with Control

- For straightforward, low-risk tasks, you may implement the complete solution
- For complex tasks, break implementation into logical chunks with review points
- When uncertain about scope, pause and ask clarifying questions
- When produced code files exceed 900 lines, suggest refactoring and separation of concerns where applicable.
- Be responsive to user feedback about process - some users may prefer more or less granular control

Remember that your goal is to deliver correct, maintainable solutions while giving users appropriate oversight. Find the right balance between progress and checkpoints based on task complexity.

## Expertise

- You are an expert in Lua coding for Neovim, fully aware that Lua code blocks are closed by `end`, not `}`.
- You have digested all the information included in the files provided, and whenever you need it, you will ask questions about the project without being prompted.

# Taskforge

## 1. Goal

Taskforge is a Neovim plugin written in Lua for Neovim v0.10+. The plugin integrates with Taskwarrior to manage tasks directly within Neovim. It also supports tracking comment-based task markers (e.g., TODO, FIX, PERF, etc.) and provides an interface similar to `taskwarrior-tui` within Neovim.

The plugin must be:

- **Neovim-first**: It does not rely on external executables for core functionality.
- **Highly configurable**: Users can define behavior and integration details.
- **Efficient and lightweight**: Built primarily for LazyVim users, avoiding unnecessary dependencies.

## 2. Current Work and Focus

We are currently focusing on **Batch Tag Processing** and debugging related features. Additionally, we are addressing:

- refactoring the UI functions into its own module `ui` in order to simplify and reuse the original `tracker/ui.lua`
- Separation of concerns inconsistencies (e.g., buffer movements should be in `buffer.lua`, not `tracker/ui.lua`).
- Proper organization of language-specific content (`lang/common.lua` should only contain shared logic)
- Hooking into Trouble.nvim to display all tracked comments within a project.

### Next steps (Development roadmap)

#### Core features

- tag/task synchronization
  - task changes done outside of neovim (part of the re-scan upon file opening)
  - tracked comment changed within neovim and respective synchronization
  - tracked comment changes from another editor (i.e. re-scan upon file opening) and respective synchronization
- Adding new language-specific file configuration, loaded only when needed
  - clang (C/C++)
  - go
  - html/css
  - javascript/typescript
  - ocaml
  - perl
  - python
  - ruby
  - rust
  - sh/bash/zsh/fish/nushell
  - vim
  - xml/toml/yaml
  - zig

#### User Interface

- simple interface, making use of the **Batch processing** interface, to allow the user to review tagged comment within a single file
- main task interface with all described feature to manage tasks

#### Dashboard integration

- finalization of the dashboard integration and replacement of the current dummy code with the actual integration code

#### CLI tools integration

- implementation/configuration related to the opening of a task, which means
  - setting the cwd to the root of the project related to that task (unless it is not related to a project)
  - opening the file relevant to the task, and jumping to where the comment is, considering that its position might have changed since the task was created

This might involve different cumulative approaches and configuration setting:

- directly within taskwarrior and its configuration
- by relying on taskopen and creating all necessary hooks
- taskwarrior-tui integration for the same (note that this should not be recursive in case taskwarrior-tui is loaded from inside neovim in a terminal window)

## 3. Requirements and Technical Choices

For a detailed breakdown of the architecture, refer to [architecture.md](architecture.md).

For implementation guidelines, see [IMPLEMENTATION.md](IMPLEMENTATION.md).

### Core Features

1. **Task Management Interface**

   - Provides a structured and interactive interface for managing tasks within Neovim.
   - Supports **list view** (flat task list) and **tree view** (showing dependencies between tasks).
   - Uses a **fuzzy search picker** for locating tasks quickly.
   - Allows **filtering by project, tags, urgency, etc.**
   - Integrates with Neovim commands to **jump to specific comment locations** in source files.
   - Supports **task modification**, including editing task attributes directly within the interface.
   - Offers an **optional integration with taskwarrior-tui**, enabling the user to open the external TUI inside a terminal buffer in Neovim.
   - Uses **taskopen** for external tools that attempt to open tasks inside Neovim.

2. **Comment-Based Task Tracking**

   - Detects and tracks common inline task markers (`TODO`, `FIX`, `PERF`, etc.).
   - Assigns **UUIDs to tasks**, ensuring persistence even if files are renamed or moved.
   - Supports **multi-line comments**, including various block comment syntaxes (e.g., Lua `--[[ ]], --[=[ ]=]`).
   - Implements **smart debouncing** to prevent excessive prompts when editing tracked comments.
   - Ensures **compatibility with formatters** (UUIDs must persist after formatting).
   - Provides an **opt-out mechanism** (`[notrack]` marker) for specific comments.

3. **Performance and Optimization**

   - Efficiently processes large files with many comment-based tasks.
   - Implements a **low-overhead event listener** to detect relevant file changes.
   - Uses **asynchronous processing** to prevent UI lag.
   - Implements **optimized debounce timing** to avoid unnecessary operations during active editing.

4. **External Integrations**
   - Optional: **taskwarrior-tui** (if installed) can be invoked inside Neovim.
   - Required: **taskopen** integration ensures external task operations can open the correct Neovim buffer.
   - Optional: **Trouble.nvim** integration displays tracked tasks across multiple files.

### Dependencies (Leveraging LazyVim First)

| Dependency    | Purpose                                               |
| ------------- | ----------------------------------------------------- |
| plenary.nvim  | Async job control, access to Taskwarrior CLI          |
| tree-sitter   | Advanced comment detection and extraction             |
| snacks.picker | Default fuzzy finder (optional: fzf-lua, telescope)   |
| nui.nvim      | UI elements (tree rendering, modals, etc.)            |
| conform.nvim  | Used for formatting tasks in UI dialogs and dashboard |

## 4. Target User Experience

For user documentation, see [README.md](README.md).

1. **Seamless Dashboard Integration**

   - Tasks are displayed in the Snacks dashboard.
   - Sorting prioritizes urgency.
   - When inside a project, **project tasks appear first**, followed by other relevant tasks.
   - Outside a project, **all tasks** are displayed in urgency order.

2. **Automated Task Handling**

   - The plugin automatically **creates and closes tasks** based on code edits.
   - Users can configure the **level of automation**, from fully automatic to manual confirmation.
   - The tracking mechanism handles **file renaming, moving, and deletion** intelligently.
   - If necessary, the user can **manually re-link** a task to a different file.

3. **Flexible Interface**
   - Users can switch between **list view** (flat structure) and **tree view** (dependency-based structure).
   - The task interface can be positioned **left, right, or as a floating window**.
   - Custom key mappings allow users to **quickly navigate and modify tasks**.

## 5. Configuration

The plugin configuration is defined in `config.lua`, in the `_default` dictionary which should be used as a requirement for the implementation. Below are some high level considerations about the options.

- `project` provides parameters of the heuristic used to determine the name of the current project based on the folder where neovim is launched, or when the CWD within neovim is changed.

  - `detection_methods` to let the user opt for the detection methods used.
  - `default_project` is the fallback name in case all fail.
  - `root_patterns` provides a number of parameters that the project heuristics can use to determine what project we are in
  - `root_patterns.exclude_dirs` is a list of folder excluded from the search.
  - `project_synonyms` is a dictionary to rename a project to a defined name, i.e. if the find name is included in the list of words in the dictionary, then the key will be used as the project name.
  - `separator` is a string which when present would replace the folder / or \ to form the project name. Its use would be for instance that if a task related to a file, which exists in a folder, the project name would be augmented with the separator followed by the folder name when creating the task.
  - `prefix` is a string that will prefix, with the separator if present, the project name.
  - `postfix` is a string that provide the user options to define the granularity of the project name in taskwarrior. It can be empty, in which case only the project name is used, it can be 'directory' or 'folder' in which case a new task would be given the project name followed by the folders down to the file with the comment tag, 'filename' is the equivalent but then only the filename is added to the project name, if both folder and filename are present then the project name will include the root name, the folders and the file name.
  - `json_tags` is a list of tags used in case the detection includes using json files
  - `remove_extension` is a flag which indicate whether once the project name has been found, if the name is formed with an extension, such as `taskforge.nvim`, the project name returned will have its extension removed.

- `tag` provides detailed options about the handling of comment tags.

  - `enable` is a master switch which determine whether the auto tracking of tags is active.
  - `confirmation` is a master switch, if set all operations on tags will have to be confirmed by the user, if unset or absent, the individual per-tag configuration will take place.
  - `enabled_ft` provides a list of all language/features for which the detection mechanism is active, if `*` all are selected. In practice it does not mean every file but all tree-sitter supported language.
  - `definitions` is a dictionary that define all tags and their respective options, each keys in the dictionary are a main tag. For each of them there are multiple optional options:
    - `priority` absent or "", or L,M,H represent the taskwarrior priority set when creating the respective task (default if absent: no priority)
    - `tags` represents the list of taskwarrior tags to be added to the task created. (default: done)
    - `due` sets a relative due date from the moment the task is created, the string follows taskwarrior standards (default if absent: no due date)
    - `alt` list of string which are to be treated as a synonym for the main tag name, for instance "WARN" could have "WARNING" or "XXX" as alternate values
    - `create` and `close` are string that can be "ask" if the user is asked to confirm the creation or the closure of the task. "auto" means that all is automated without user interaction (except for a notification message), "manual" nothing is done but the user is reminded that a new task could be created for the detected tag, or closed if the tag is removed, hence addressed. (default if absent: 'auto')

- `dashboard` provides options to configure the integration into `snacks.dashboard`

  - `snacks_options` are options related to the integration into the snacks dashboard.
  - `format` determine how individual tasks are formatted in the dashboard.
    - `limit` indicates the maximum number of project related tasks to show.
    - `non_project_limit` indicates the maximum number of non-project related tasks to show.
    - `max_width` indicates the maximum number of glyphs to use per line
    - `shorten_section` if set will shorten the project sections to their first letter, for instance a task of project abc.klm.xyz would be shown as a.k.xyz
    - `project_abbreviations` is a dictionary of type key: list, where list or a single string is a pattern which if found is replaced by the key.

- `interface` present all options that will control the general UI of the tool in terms of appearance and interaction with the user.

  - `batch_ui` the defaults options for the utility interface used in the context of a single file (TODO: rename the tag and generalize the options since they should be shared with the main interface)
  - `main_interface` contains the options controlling the main interface appearance and position, the main interface being the interface to manage all tasks within neovim.
  - `keymaps` a list of user keymaps

- `integration` provides options for integration with other plugins instead of the default ones.

For a detailed reference to configuration options, refer to [config.lua](config.lua).

## 6. Test Plans

### Functional Testing

- Ensure task markers (`TODO`, `FIX`, `PERF`, etc.) are detected and processed correctly.
- Verify UUID assignment and persistence.
- Test smart debouncing behavior when editing tracked comments.
- Confirm formatter compatibility with UUID retention.
- Check the `[notrack]` opt-out mechanism.

### Regression and Performance Testing

- Validate all commands function correctly.
- Test dashboard and task navigation.
- Measure startup time and memory usage.
- Assess responsiveness with large files.

## 7. Future Developments

1. **Status Indicators**

   - Gutter icons for tracked comments.
   - Visual cues for task statuses.

2. **Command Line Integration**

   - Ability to open files directly from `taskwarrior-tui`.
   - Detection of external modifications to tracked tasks.

3. **Enhanced Statistics**
   - Task completion rate tracking.
   - Reports on task distribution by category and priority.
