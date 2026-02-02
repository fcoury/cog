-- Comprehensive mock chat data for visual testing
-- This exercises all UI components: messages, tool calls, thinking blocks, pending states

local M = {}

-- Generate unique tool IDs
local tool_id_counter = 0
local function next_tool_id()
  tool_id_counter = tool_id_counter + 1
  return "tool_" .. tool_id_counter
end

-- All test items in order of rendering
M.items = {
  -- 1. Initial user message
  {
    type = "user_message",
    text = "Can you help me understand this codebase and make some improvements?",
  },

  -- 2. Simple assistant response
  {
    type = "assistant_message",
    text = "I'd be happy to help! Let me start by exploring the codebase structure to understand what we're working with.",
  },

  -- 3. Read tool call - completed
  {
    type = "tool_call",
    id = next_tool_id(),
    kind = "read",
    status = "completed",
    title = "Read",
    locations = { "src/main.rs", "Cargo.toml", "README.md" },
  },

  -- 4. Grep tool call - completed with results
  {
    type = "tool_call",
    id = next_tool_id(),
    kind = "grep",
    status = "completed",
    title = "Grep",
    command = "error handling",
    locations = { "src/error.rs:42", "src/main.rs:15", "src/lib.rs:128" },
  },

  -- 5. Assistant analysis
  {
    type = "assistant_message",
    text = [[I've analyzed the codebase. Here's what I found:

**Project Structure:**
- Main entry point in `src/main.rs`
- Error handling module in `src/error.rs`
- Core library in `src/lib.rs`

Let me check the tests and run them to verify everything works.]],
  },

  -- 6. Bash tool call - successful test run
  {
    type = "tool_call",
    id = next_tool_id(),
    kind = "bash",
    status = "completed",
    title = "Bash",
    command = "cargo test",
    output = [[   Compiling myproject v0.1.0 (/path/to/project)
    Finished test [unoptimized + debuginfo] target(s) in 2.34s
     Running unittests src/lib.rs

running 5 tests
test error::tests::test_error_display ... ok
test parser::tests::test_parse_simple ... ok
test parser::tests::test_parse_complex ... ok
test utils::tests::test_format ... ok
test main::tests::integration ... ok

test result: ok. 5 passed; 0 failed; 0 ignored]],
    exit_code = 0,
  },

  -- 7. User follow-up
  {
    type = "user_message",
    text = "Great! Can you add better error messages to the parser module?",
  },

  -- 8. Thinking block (extended reasoning)
  {
    type = "thinking",
    text = [[Let me think about the best approach for improving error messages...

The current error handling uses basic string messages. I should:
1. Create structured error types with context
2. Add line/column information
3. Include suggestions for common mistakes

I'll start with the ParseError enum and add rich context.]],
  },

  -- 9. Assistant explains the plan
  {
    type = "assistant_message",
    text = "I'll improve the error messages by adding structured error types with better context. Let me make those changes now.",
  },

  -- 10. Edit tool call - with diff
  {
    type = "tool_call",
    id = next_tool_id(),
    kind = "edit",
    status = "completed",
    title = "Edit",
    locations = { "src/error.rs" },
    diff = [[@@ -1,12 +1,28 @@
-use std::fmt;
+use std::fmt::{self, Display};
+use std::error::Error;

-#[derive(Debug)]
-pub struct ParseError(String);
+#[derive(Debug, Clone)]
+pub struct ParseError {
+    pub message: String,
+    pub line: usize,
+    pub column: usize,
+    pub context: Option<String>,
+    pub suggestion: Option<String>,
+}

-impl fmt::Display for ParseError {
+impl Display for ParseError {
     fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
-        write!(f, "Parse error: {}", self.0)
+        write!(f, "error[E0001]: {}", self.message)?;
+        write!(f, "\n  --> line {}:{}", self.line, self.column)?;
+        if let Some(ctx) = &self.context {
+            write!(f, "\n   | {}", ctx)?;
+        }
+        if let Some(sug) = &self.suggestion {
+            write!(f, "\n   = help: {}", sug)?;
+        }
+        Ok(())
     }
 }]],
  },

  -- 11. Write tool call - new file
  {
    type = "tool_call",
    id = next_tool_id(),
    kind = "write",
    status = "completed",
    title = "Write",
    locations = { "src/error_context.rs" },
  },

  -- 12. Bash tool call - failed command
  {
    type = "tool_call",
    id = next_tool_id(),
    kind = "bash",
    status = "failed",
    title = "Bash",
    command = "npm install",
    output = [[npm ERR! code ENOENT
npm ERR! syscall open
npm ERR! path /path/to/project/package.json
npm ERR! errno -2
npm ERR! enoent ENOENT: no such file or directory
npm ERR! enoent This is related to npm not being able to find a file.]],
    exit_code = 1,
  },

  -- 13. System message
  {
    type = "system_message",
    text = "Note: This is a Rust project, npm commands won't work here.",
  },

  -- 14. Assistant recovers
  {
    type = "assistant_message",
    text = "Ah, I see - this is a Rust project, not a Node.js project. Let me run the correct build command.",
  },

  -- 15. Bash tool call - cargo build
  {
    type = "tool_call",
    id = next_tool_id(),
    kind = "bash",
    status = "completed",
    title = "Bash",
    command = "cargo build --release",
    output = [[   Compiling myproject v0.1.0 (/path/to/project)
    Finished release [optimized] target(s) in 8.42s]],
    exit_code = 0,
  },

  -- 16. Web fetch tool call
  {
    type = "tool_call",
    id = next_tool_id(),
    kind = "web",
    status = "completed",
    title = "WebFetch",
    command = "https://docs.rs/thiserror/latest/thiserror/",
    output = "Retrieved documentation for thiserror crate - derive macros for Error trait",
  },

  -- 17. Task/agent tool call - in progress
  {
    type = "tool_call",
    id = next_tool_id(),
    kind = "task",
    status = "in_progress",
    title = "Task Agent",
    command = "Researching best practices for Rust error handling patterns",
  },

  -- 18. Glob tool call
  {
    type = "tool_call",
    id = next_tool_id(),
    kind = "glob",
    status = "completed",
    title = "Glob",
    command = "**/*.rs",
    locations = {
      "src/main.rs",
      "src/lib.rs",
      "src/error.rs",
      "src/error_context.rs",
      "src/parser/mod.rs",
      "src/parser/lexer.rs",
      "src/parser/ast.rs",
      "tests/integration.rs",
    },
  },

  -- 19. Long user message (test wrapping)
  {
    type = "user_message",
    text = "This is a longer message to test how the UI handles text wrapping. I want to make sure that when users type longer messages with multiple sentences and paragraphs, the layout remains clean and readable without any overflow issues or awkward line breaks that might hurt readability.",
  },

  -- 20. Assistant with code block
  {
    type = "assistant_message",
    text = [[Here's the updated code with better error handling:

```rust
impl Parser {
    pub fn parse(&mut self) -> Result<Ast, ParseError> {
        let token = self.lexer.next_token()?;
        match token.kind {
            TokenKind::Number(n) => Ok(Ast::Number(n)),
            TokenKind::String(s) => Ok(Ast::String(s)),
            TokenKind::Ident(name) => self.parse_identifier(name),
            _ => Err(ParseError {
                message: format!("unexpected token: {:?}", token.kind),
                line: token.line,
                column: token.column,
                context: Some(self.get_line_context(token.line)),
                suggestion: Some("expected number, string, or identifier".into()),
            }),
        }
    }
}
```

This provides much better error context for debugging.]],
  },

  -- 21. User message
  {
    type = "user_message",
    text = "Perfect! Can you run the tests again to make sure everything still works?",
  },

  -- 22. Pending state (assistant is thinking)
  {
    type = "pending",
  },
}

return M
