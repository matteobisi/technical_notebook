# GitHub Copilot CLI Cheatsheet

A practical guide to working effectively with GitHub Copilot CLI in the terminal.

## Table of Contents

*   [Getting Started](#getting-started)
*   [Best Practices](#best-practices)
*   [Communication Style](#communication-style)
*   [File Operations](#file-operations)
*   [Multi-File Operations](#multi-file-operations)
*   [Working with Git](#working-with-git)
*   [Running Commands](#running-commands)
*   [Context and References](#context-and-references)
*   [Common Patterns](#common-patterns)

---

## Getting Started

| Action | Description |
| :--- | :--- |
| Start a conversation | Simply type your request naturally in the terminal |
| Reference files | Use `@filename` to reference specific files |
| Reference directories | Use `@directory/` to reference directories |
| Check current context | Copilot CLI is aware of your current working directory and git status |

## Best Practices

| Practice | Description |
| :--- | :--- |
| Be specific | Clear, specific requests get better results than vague ones |
| Verify changes | Always review changes before committing |
| Use references | Use `@` to reference files, directories, or documentation |
| Request validation | Ask for tests or verification after making changes |
| Iterate | If the result isn't perfect, refine your request |
| Use context | Copilot CLI understands your environment—no need to repeat context |

## Communication Style

| Guideline | Example |
| :--- | :--- |
| Natural language | "Add error handling to the main function" |
| Concise requests | "Fix the typo in README.md" |
| Ask for explanations | "Explain what this function does" |
| Request examples | "Show me how to use this API" |
| Chain requests | "Create a test file and run the tests" |

## File Operations

| Operation | Example Request |
| :--- | :--- |
| Create new file | "Create a .gitignore for a Python project" |
| Edit existing file | "Update the version number in package.json to 2.0.0" |
| View file content | "Show me the content of config.yaml" |
| Search in files | "Find all TODO comments in the src directory" |
| Compare files | "Show me the differences between dev.config and prod.config" |

## Multi-File Operations

| Operation | Example Request |
| :--- | :--- |
| Edit multiple files | "Update the API endpoint in all configuration files" |
| Create related files | "Create a new component with its test file and styles" |
| Refactor across files | "Rename the User class to Account across all files" |
| Batch updates | "Add copyright headers to all Python files" |

## Working with Git

| Operation | Example Request |
| :--- | :--- |
| Check status | "Show me the current git status" |
| View changes | "What files have I modified?" |
| Create commit | "Commit these changes with a descriptive message" |
| Review diff | "Show me what changed in the last commit" |
| Branch operations | "Create a new branch for this feature" |
| Signed commits | All commits should use `--signoff` flag |

## Running Commands

| Operation | Example Request |
| :--- | :--- |
| Execute command | "Run the tests" |
| Build project | "Build the project and check for errors" |
| Install dependencies | "Install the required npm packages" |
| Check versions | "What version of Python am I using?" |
| Debug issues | "Run this command and help me fix the error" |
| Long-running tasks | Copilot CLI handles timeouts automatically for builds and tests |

## Context and References

| Type | Syntax | Example |
| :--- | :--- | :--- |
| File reference | `@filename` | "Fix the bug in @main.py" |
| Directory reference | `@directory/` | "Review all files in @src/" |
| Multiple references | `@file1 @file2` | "Merge the configs from @dev.yaml @prod.yaml" |
| Markdown files | `@file.md` | "Follow the guidelines in @CONTRIBUTING.md" |

## Common Patterns

### Creating New Features

```
"Create a new REST endpoint for user authentication"
"Add logging to the database connection function"
"Implement rate limiting for the API"
```

### Debugging and Fixing

```
"Fix the TypeError in the login function"
"Debug why the test is failing"
"The application crashes on startup, help me investigate"
```

### Documentation

```
"Add JSDoc comments to this function"
"Create a README for this project"
"Document the API endpoints in OpenAPI format"
```

### Code Review and Quality

```
"Review this code for security issues"
"Suggest improvements for this function"
"Check if there are any unused imports"
```

### Project Setup

```
"Initialize a new Node.js project with TypeScript"
"Set up a CI/CD pipeline for this repository"
"Create a Docker configuration for this application"
```

### Refactoring

```
"Extract this logic into a separate function"
"Convert this JavaScript file to TypeScript"
"Simplify this nested if statement"
```

---

## Tips and Tricks

*   **Parallel operations**: Copilot CLI can read or edit multiple files simultaneously when operations are independent.
*   **Command chaining**: Use `&&` to chain related bash commands in a single request.
*   **Minimal changes**: Copilot CLI makes surgical edits—only changing what's necessary.
*   **Verification first**: Always verify that changes work before moving to the next task.
*   **Trust but verify**: While Copilot CLI is powerful, always review changes, especially for critical code.
*   **Context awareness**: Copilot CLI knows your working directory, git status, and file contents—no need to repeat.

---

## What Copilot CLI Does NOT Do

*   Share code or data with third-party systems
*   Commit secrets into source code
*   Generate copyrighted content
*   Make assumptions or guess—everything is based on evidence
*   Create unnecessary marketing language

---

## Remember

GitHub Copilot CLI is your pair programming partner in the terminal. Treat it like a knowledgeable colleague: be clear about what you need, provide context when necessary, and always verify the results. The more specific and contextual your requests, the better the outcomes.
