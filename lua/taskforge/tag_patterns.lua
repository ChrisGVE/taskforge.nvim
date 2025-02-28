-- Library of common tag patterns for different languages and styles
local M = {}

-- Basic pattern templates that can be used to build tag patterns
M.templates = {
  -- Simple tag followed by colon and description
  simple = "\\s*TAG\\s*:\\s*(.+)",

  -- Tag with parenthesized metadata
  with_parens = "\\s*TAG\\s*\\(([^)]+)\\)\\s*:\\s*(.+)",

  -- Tag with brackets - fixed pattern to properly handle brackets
  with_brackets = "\\s*TAG\\s*\\[([^\\]]+)\\]\\s*:\\s*(.+)",

  -- Tag with priority indicator
  with_priority = "\\s*TAG\\s*\\((P%d)\\)\\s*:\\s*(.+)",

  -- JSDoc/PHPDoc style
  doc_block = "\\s*@TAG\\s+(.+)",
}

-- Common tags used across many projects
M.common_tags = {
  "TODO",
  "FIXME",
  "HACK",
  "NOTE",
  "BUG",
  "XXX",
  "WARN",
  "WARNING",
  "PERF",
  "OPTIM",
  "OPTIMIZE",
  "PERFORMANCE",
  "TEST",
  "TESTING",
  "REVIEW",
  "IDEA",
  "QUESTION",
  "INCOMPLETE",
}

-- Language-specific comment patterns
M.language_patterns = {
  lua = {
    line_comment = "--%s*",
    block_start = "--[[%s*",
    block_end = "%s*]]",
  },
  python = {
    line_comment = "#%s*",
    block_start = '"""',
    block_end = '"""',
  },
  c = {
    line_comment = "//%s*",
    block_start = "/%*+%s*",
    block_end = "%s*%*+/",
  },
  cpp = {
    line_comment = "//%s*",
    block_start = "/%*+%s*",
    block_end = "%s*%*+/",
  },
  javascript = {
    line_comment = "//%s*",
    block_start = "/%*+%s*",
    block_end = "%s*%*+/",
  },
  java = {
    line_comment = "//%s*",
    block_start = "/%*+%s*",
    block_end = "%s*%*+/",
  },
  go = {
    line_comment = "//%s*",
    block_start = "/%*+%s*",
    block_end = "%s*%*+/",
  },
  rust = {
    line_comment = "//%s*",
    block_start = "/%*+%s*",
    block_end = "%s*%*+/",
  },
  ruby = {
    line_comment = "#%s*",
    block_start = "=begin",
    block_end = "=end",
  },
  vim = {
    line_comment = '"%s*',
  },
  shell = {
    line_comment = "#%s*",
  },
  markdown = {
    line_comment = "<!%-%-%s*",
    block_end = "%s*%-%->",
  },
  html = {
    line_comment = "<!%-%-%s*",
    block_end = "%s*%-%->",
  },
}

-- Helper to escape pattern special characters
local function escape_pattern(s)
  return (s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"))
end

-- Helper to create tag patterns for a specific language
function M.create_language_patterns(language, tags)
  local lang_pattern = M.language_patterns[language]
  if not lang_pattern then
    -- Use C-style comments as fallback
    lang_pattern = M.language_patterns.c
  end

  local patterns = {}
  for _, tag in ipairs(tags) do
    -- Escape the tag for pattern matching
    local escaped_tag = escape_pattern(tag)

    -- Create line comment patterns
    if lang_pattern.line_comment then
      patterns[tag .. "_line"] = lang_pattern.line_comment .. M.templates.simple:gsub("TAG", escaped_tag)
      patterns[tag .. "_line_paren"] = lang_pattern.line_comment .. M.templates.with_parens:gsub("TAG", escaped_tag)
      patterns[tag .. "_line_bracket"] = lang_pattern.line_comment .. M.templates.with_brackets:gsub("TAG", escaped_tag)
    end

    -- Create block comment patterns if applicable
    if lang_pattern.block_start then
      patterns[tag .. "_block"] = lang_pattern.block_start .. ".*" .. M.templates.simple:gsub("TAG", escaped_tag)

      -- Handle doc-block style comments
      if language == "javascript" or language == "typescript" or language == "php" or language == "java" then
        patterns[tag .. "_docblock"] = lang_pattern.block_start .. M.templates.doc_block:gsub("TAG", tag:lower())
      end
    end
  end

  return patterns
end

-- Helper to create a pattern that matches any of the specified tags
function M.create_any_tag_pattern(language, tags)
  local patterns = {}
  local lang_pattern = M.language_patterns[language]

  if not lang_pattern then
    -- Use C-style comments as fallback
    lang_pattern = M.language_patterns.c
  end

  -- Escape any special pattern characters in tag names
  local escaped_tags = {}
  for _, tag in ipairs(tags) do
    -- Escape any special pattern characters in the tag
    local escaped = escape_pattern(tag)
    table.insert(escaped_tags, escaped)
  end

  -- Create pattern for line comments
  if lang_pattern.line_comment then
    local tag_alternatives = table.concat(escaped_tags, "|")
    patterns.line = lang_pattern.line_comment .. "\\s*(" .. tag_alternatives .. ")\\s*:?\\s*(.*)"
  end

  -- Create pattern for block comments if applicable
  if lang_pattern.block_start then
    local tag_alternatives = table.concat(escaped_tags, "|")
    patterns.block = lang_pattern.block_start .. ".*\\s*(" .. tag_alternatives .. ")\\s*:?\\s*(.*)"

    -- Handle doc-block style comments
    if language == "javascript" or language == "typescript" or language == "php" or language == "java" then
      -- Lowercase tag alternatives
      local lowercase_tags = {}
      for _, tag in ipairs(escaped_tags) do
        table.insert(lowercase_tags, tag:lower())
      end
      local tag_alternatives_lower = table.concat(lowercase_tags, "|")
      patterns.docblock = lang_pattern.block_start .. "\\s*@(" .. tag_alternatives_lower .. ")\\s+(.*)"
    end
  end

  return patterns
end

-- Get all patterns that would match any known tag in any style for the specific language
function M.get_all_patterns(language, tags_to_match)
  -- If tags_to_match is provided, use those; otherwise use common tags
  local tags = tags_to_match or M.common_tags
  return M.create_any_tag_pattern(language, tags)
end

-- Parse a comment to extract tag and description
function M.parse_tag_comment(comment, language, tags_to_match)
  -- Safely create patterns
  local ok, patterns = pcall(M.get_all_patterns, language, tags_to_match)
  if not ok or not patterns then
    -- If pattern creation failed, return nil
    return nil
  end

  -- Attempt to match patterns
  for pattern_type, pattern in pairs(patterns) do
    -- Use pcall to catch any pattern errors
    local success, result = pcall(function()
      local tag, description = comment:match(pattern)
      if tag and description then
        return {
          tag = tag,
          description = description:gsub("^%s*(.-)%s*$", "%1"), -- trim whitespace
        }
      end
      return nil
    end)

    if success and result then
      return result
    end
  end

  return nil
end

return M
