# taskforge

## Initial prompt

I want to write a plugin in Lua for Neovim v0.10+. The plugin will show, manage, and create/modify/delete/close tasks managed with the tool taskwarrior. It will contain as well an option to display a list of urgent tasks within the snacks.dashboard plugin.

The plugin will also manage (create/modify/close) code-related tasks (according to usual comment tags: TODO, PERF, FIX, etc).

In more details, the task management interface within neovim should be similar to taskwarrior-tui, with the use of a fuzzy picker to find tasks, we should also have multiple views, such as a plain view with all tasks, a project view with only the current or selected project tasks. We should have sorting options, the default being the task urgency, and we should be able to switch from a flat view to a tree view where dependencies between tasks will be shown.

From within the above mentioned interface in Neovim, the plugin will be able to jump to the file and move the cursor to the line of the respective comment. From outside of neovim we'll need to use tools such as taskopen to accomplish the same thing, maybe with an optional integration with taskwarrior-tui, in this case the tasks will be opened by opening neovim and hooking up with the neovim plugin to facilitate the location of the actual comment. All necessary information to accomplish these tasks should be self contained within the taskwarrior task, for instance using the annotation.

The jump function will have to consider a number of border cases, the first being that in the project lifecycle the line number where the comment is will change, thus storing the line number might not be ideal, files can also be edited by other tools (rare but for simple edit a user could opt to make it using something else than neovim), the file could have been renamed, moved or deleted as well. In these cases we will make the assumption that those file remain within the same project, at last resort we'll offer the user to pick the file where the comment is or to remove all tasks attached to this file.

Another task for the plugin will be to monitor the files being edited by neovim and create/modify/mark as done the tasks as the user edit them, this being transparently done (though you'll see in the configuration we might give the user option to give confirmation for certain type of comments). When creating those tasks they should be classified within the project being worked on, (a heuristic to determine the project name will be given).

We expect the plugin to be installed with lazy.nvim as a main option and more generally to live amongst LazyVim environment.

We should apply the general principle of reuse rather than rewrite and use existing plugins, such as mini.nvim, plenary, nui.nvim, snacks.nvim, etc. Of course we should also minimize the number of dependencies to a reasonable level.

We should also give the user options, some users are using snacks.picker, other fzf-lua and other telescope, so while we target snacks.picker we should have the option to integrate with the other two.

I am sharing with `taskforge.nvim.md` the code I have already written for the plugin, but it is incomplete and probably requires updates and maybe major rewrite. I also add the plugin configuration (currently disabled) and the integration to snacks.dashboard in the file `nvim.md`.

## Additional information around the design of the plugin

### User experience choices

The principle we follow for the plugin setup is to provide a highly configurable plugin with a rich number of options and sane defaults.

In terms of functionalities we want the following key features:

- Integration with snacks dashboard, which is user configurable by providing a pluggable sections to integrate into the dashboard configuration, whilst the option details are given within the plugin options' table. The content of the dashboard varies depending on the cwd from which neovim is launched, if it is located within a project folder the tasks listed in the dashboard will include first the project tasks and then other tasks, in descending order of urgency, when neovim is launched outside of any project folder, any tasks will be listed, again in descending order of urgency.
- Automated code comments' tag tracking, highly configurable, which creates or sets task as done as the user is editing the code with usual coding tags such as 'TODO' or 'FIX', etc. the plugin must handle things smartly, for instance considering that during the lifecycle of a code file lines will increase/decrease/change and thus the position of tags. Files can also be renamed, deleted, moved in a project. So there are some border cases to handle, some within the editor making use of the lsp for instance, some using heuristics to decide what to do, including asking the user. Additionally, opening a task from the command line, using taskopen, and getting to the tag is a requirement.
- A full CRUD interface to display tasks, using a fuzzy finder to search tasks; filters for the current project or for another project, for tags (include/exclude); sorting options; tree view using tasks dependencies, or flat view. Option to use the edit option of taskwarrior (which invokes nvim as the editor). From within the interface, the user can also open a file via its task and jump to where the comment is placed.

### Configurability

The configurability is achieved by a set of options, see config.lua, and below gives direction as to interpret and use them.

- The determination of the current project, based on the folder neovim is launched, is based on options that allow various heuristics to be applied. The `project` dictionary includes:

  - `detection_methods` to let the user opt for the detection methods used.
  - `default_project` is the fallback name in case all fail.
  - `root_patterns` provides a number of parameters that the project heuristics can use to determine what project we are in
  - `root_patterns.exclude_dirs` is a list of folder excluded from the search.
  - `project_synonyms` is a dictionary to rename a project to a defined name, i.e. if the find name is included in the list of words in the dictionary, then the key will be used as the project name.
  - `separator` is a string which when present would replace the folder / or \ to form the project name. Its use would be for instance that if a task related to a file, which exists in a folder, the project name would be augmented with the separator followed by the folder name when creating the task.
  - `prefix` is a string that will prefix, with the separator if present, the project name.
  - `postfix` is a string that provide the user options to define the granularity of the project name in taskwarrior. It can be empty, in which case only the project name is used, it can be 'directory' or 'folder' in which case a new task would be given the project name followed by the folders down to the file with the comment tag, 'filename' is the equivalent but then only the filename is added to the project name, if both folder and filename are present then the project name will include the root name, the folders and the file name.
  - `json_tags` is a list of tags used in case the detection includes using json files

- The options for each tag type is defined granularly within the `tag` section of the options.

  - `confirmation` is a sort of master switch, if set all operations on tags will have to be confirmed by the user, if unset or absent, the individual per-tag configuration will take place.
  - `enabled_ft` provides a list of all language/features for which the detection mechanism is active, if `*` all are selected. In practice it does not mean every file but all tree-sitter supported language.
  - `tag_format` provides a pattern to identify the tag within a comment, typically comments are defined as uppercase string followed by a colon, but it can be different and this pattern will help extracting relevant tags.
  - `definitions` is a dictionary that define all tags and their respective options, each keys in the dictionary are a main tag. For each of them there are multiple optional options:
    - `priority` absent or "", or L,M,H represent the taskwarrior priority set when creating the respective task (default: no priority)
    - `tags` represents the list of taskwarrior tags to be added to the task created. (default: done)
    - `due` sets a relative due date from the moment the task is created, the string follows taskwarrior standards (default: no due date)
    - `alt` list of string which are to be treated as a synonym for the main tag name, for instance "WARN" could have "WARNING" or "XXX" as alternate values
    - `create` and `close` are string that can be "ask" if the user is asked to confirm the creation or the closure of the task. "auto" means that all is automated without user interaction (except for a notification message), "manual" nothing is done but the user is reminded that a new task could be created for the detected tag, or closed if the tag is removed, hence addressed.

- The dashboard is configured in its own section

  - `snacks_options` are options related to the integration into the snacks dashboard.
  - `format` determine how individual tasks are formatted in the dashboard.
    - `limit` indicates the maximum number of project related tasks to show.
    - `non_project_limit` indicates the maximum number of non-project related tasks to show.
    - `max_width` indicates the maximum number of glyphs to use per line
    - `shorten_section` if set will shorten the project sections to their first letter, for instance a task of project abc.klm.xyz would be shown as a.k.xyz
    - `project_abbreviations` is a dictionary of type key: list, where list or a single string is a pattern which if found is replaced by the key.

- Finally the user interface is defined by under the `interface` dictionary and contains:
  - `view` the default view, either "list" or "tree",
  - `position` "left", "right", "float". Using the left or right column of the neovim interface (similar to neotree), floating would take most of the interface, such as a centered 80% width and height window.
  - `keymaps` a list of user keymaps for the commands when the interface is active

### Technical choices

The principle is to avoid a inordinate number of plugins and thus dependencies, however since the target environment is mainly LazyVim there are already a number of plugins we can leverage on without too much increase of dependencies:

- We use plenary.nvim for async job control and access Taskwarrior CLI.
- We use tree-sitter for better comment detection and extraction
- We use a picker, by defaults snacks.picker, but optionally fzf-lua or telescope depending on the user configuration
- We use nui.nvim for tree rendering and other ui function
- We use conform.nvim for formatting tasks

## Next steps

1. Continue writing the project code to completion, including the tag automation mechanisms
2. Debug the code base.
3. Refinements.
4. Unit testing.
5. Code documentation.
6. User documentation.
