# GrepSQL

A powerful CLI tool for searching and filtering SQL files using pattern expressions based on PostgreSQL's AST structure.

## Features

- 🔍 **Pattern Matching**: Search SQL files using sophisticated pattern expressions
- 📁 **Multiple Files**: Process multiple SQL files at once
- 💻 **Inline SQL**: Search inline SQL strings with `--from-sql`
- 🌳 **AST Output**: View Abstract Syntax Tree representation with `--ast`
- 🌲 **Tree Output**: View formatted AST tree with `--tree` (supports colors!)
- 🐛 **Debug Mode**: Debug pattern matching with detailed colored output using `--debug`
- 📊 **Count Mode**: Get just the count of matches with `--count`
- 📝 **Line Numbers**: Show line numbers in output with `--line-numbers`
- 🎨 **Color Support**: Automatic color detection with `--no-color` override
- ✨ **SQL Highlighting**: Highlight matching SQL parts with `--highlight`
- 🎭 **Multiple Formats**: ANSI colors, HTML, and Markdown highlighting styles
- 📄 **Context Lines**: Show surrounding context with `--context N`

## Installation

```bash
# Build the native macOS binary (self-contained, no .NET runtime required)
dotnet publish src/GrepSQL.CLI/GrepSQL/GrepSQL.csproj -c Release -o bin --self-contained true -r osx-arm64

# Or run in development mode
dotnet run --project src/GrepSQL.CLI/GrepSQL/GrepSQL.csproj -- [options]

# The native binary is located at ./bin/GrepSQL
# Use the wrapper script: ./grepsql.sh
```

## Usage

```bash
# New preferred syntax (like grep)
grepsql PATTERN [files...] [options]

# Legacy syntax (still supported)
grepsql -p PATTERN [options]
```

### Arguments
- `PATTERN` - SQL pattern expression to match against (first positional argument)
- `files...` - SQL files to search through (remaining positional arguments)

### Legacy Options (for backward compatibility)
- `-p, --pattern` - SQL pattern expression to match against (alternative to positional)
- `-f, --files` - SQL files to search through (alternative to positional)

### Input Options
- `--from-sql` - Inline SQL to search instead of files
- *(stdin)* - Read from stdin if no files specified

### Output Options
- `--ast` - Print AST as JSON instead of SQL
- `--tree` - Print AST as a formatted, colored tree (clean mode by default)
- `--tree-mode=full` - Use with `--tree` to show all details including locations
- `--debug` - Print matching details for debugging (with colors)
- `--verbose` - Enable verbose debug output (use with `--debug`)
- `--no-color` - Disable colored output
- `-c, --count` - Only print count of matches
- `-n, --line-numbers` - Show line numbers in output
- `--no-filename` - Don't show filename in output
- `--highlight` - Highlight matching SQL parts in output
- `--highlight-style` - Highlighting style: ansi (default), html, markdown
- `--context N` - Show N context lines around matches (requires --highlight)

## Pattern Examples

### Basic Statement Types
```bash
# Find all SELECT statements
grepsql "SelectStmt" queries.sql

# Find all INSERT statements (shell expands *.sql)
grepsql "InsertStmt" *.sql

# Find all UPDATE statements with glob patterns
grepsql "UpdateStmt" database/migrations/*.sql

# Also works with recursive patterns
grepsql "SelectStmt" **/*.sql
```

### Field-Specific Patterns
```bash
# Find SELECT statements with WHERE clauses
grepsql "(SelectStmt (whereClause ...))" queries.sql

# Find SELECT statements with both target list and FROM clause
grepsql "(SelectStmt (targetList ...) (fromClause ...))" queries.sql

# Find UPDATE statements with WHERE clauses
grepsql "(UpdateStmt (whereClause ...))" queries.sql
```

### S-Expression Attribute Patterns
```bash
# Find specific table references by name
grepsql "(relname \"users\")" queries.sql

# Find specific column references
grepsql "(colname \"id\")" queries.sql

# Find specific string constants
grepsql "(sval \"admin\")" queries.sql
```

### Wildcard Patterns
```bash
# Match any statement (useful for counting total statements)
grepsql "..." queries.sql -c

# Match any SELECT statement regardless of fields
grepsql "(SelectStmt ...)" queries.sql
```

## Examples

### Count all INSERT statements
```bash
grepsql "InsertStmt" sample1.sql sample2.sql -c
```

### Find SELECT statements with WHERE clauses and show line numbers
```bash
grepsql "(SelectStmt (whereClause ...))" queries.sql -n
```

### Debug pattern matching for inline SQL
```bash
grepsql "(SelectStmt (targetList ...) (fromClause ...))" \
        --from-sql "SELECT name, COUNT(*) FROM users GROUP BY name" \
        --debug
```

### View AST for UPDATE statements
```bash
# JSON format
grepsql "UpdateStmt" migrations.sql --ast

# Pretty tree format with colors (clean mode)
grepsql "UpdateStmt" migrations.sql --tree

# Full tree with all details
grepsql "UpdateStmt" migrations.sql --tree --tree-mode=full
```

### Search from stdin
```bash
cat queries.sql | grepsql "SelectStmt"
```

### SQL Highlighting Examples
```bash
# Highlight table names in ANSI colors (default)
grepsql "(relname \"users\")" queries.sql --highlight

# Generate HTML with highlighted matches for documentation
grepsql "(relname \"products\")" queries.sql --highlight --highlight-style html
# Output: SELECT * FROM <mark>products</mark>

# Generate Markdown with highlighted matches
grepsql "(colname \"name\")" queries.sql --highlight --highlight-style markdown
# Output: SELECT **name** FROM users

# Show context lines around matches
grepsql "(relname \"orders\")" complex.sql --highlight --context 2
```

## Pattern Language

GrepSQL uses a powerful pattern language based on PostgreSQL's AST structure:

- **Statement Types**: `SelectStmt`, `InsertStmt`, `UpdateStmt`, `DeleteStmt`, etc.
- **Field Patterns**: `(NodeType (fieldName ...))`
- **Wildcards**: `...` matches anything, `_` matches any single item
- **Field Names**: Use camelCase (e.g., `targetList`, `whereClause`) - automatically converted to snake_case

## Output Formats

### Default (SQL)
```sql
sample1.sql:SELECT id, name, email
FROM users
WHERE active = true;
```

### AST Format (JSON)
```json
{
  "selectStmt": {
    "targetList": [...],
    "fromClause": [...],
    "whereClause": {...}
  }
}
```

### Tree Format (Colored, Clean Mode)
```
✓ SelectStmt
  targetList: [2 items]
    [0]: 
      ✓ ResTarget
        name: id
        val: 
          ColumnRef
            fields: [1 items]
              [0]: 
                String
                  sval: id
    [1]: 
      ✓ ResTarget
        name: name
        val: 
          ColumnRef
            fields: [1 items]
              [0]: 
                String
                  sval: name
```

**Clean Mode**: Hides empty arrays (`[]`), default enum values (`Default`, `SetopNone`), location information, and false boolean flags for cleaner output.

**Full Mode**: Shows all AST details including empty arrays, default values, and location information for debugging.

### Count Only
```
3
```

## Exit Codes

- `0` - Matches found
- `1` - No matches found or invalid arguments
- `2` - Error occurred during execution

## Troubleshooting

### Debug Mode
Use `--debug` to see detailed pattern matching information:

```bash
# Basic debug mode (less verbose)
grepsql -p "(SelectStmt (whereClause ...))" -f queries.sql --debug

# Verbose debug mode (detailed step-by-step matching)
grepsql -p "(SelectStmt (whereClause ...))" -f queries.sql --debug --verbose
```

This will show:
- Pattern parsing details
- AST structure
- Step-by-step matching process
- Field lookups and conversions

### Common Issues

1. **Field name mismatches**: Use camelCase in patterns (e.g., `whereClause` not `where_clause`)
2. **Pattern syntax**: Remember to use parentheses for field patterns: `(SelectStmt (whereClause ...))`
3. **File not found**: Check file paths are correct relative to current directory

## Contributing

This tool is built on top of [GrepSQL](../GrepSQL) and uses the fixed SqlPatternMatcher for pattern matching capabilities.

## 🔥 Advanced Examples

### Complex Pattern Matching
Find SQL statements with both column references and constants:
```bash
grepsql -p "{ColumnRef A_Const}" sample.sql --highlight
```

This finds queries like:
- `SELECT id FROM users WHERE active = true` (has both `id` column and `true` constant)
- `UPDATE users SET name = 'John' WHERE id = 123` (has columns and string/number constants)

### S-Expression Searches
Find specific table references:
```bash
grepsql -p "(relname \"users\")" --files "*.sql"
```

### Highlighting Output
```bash
# Terminal colors
grepsql -p "SelectStmt" sample.sql --highlight

# HTML output  
grepsql -p "ColumnRef" sample.sql --highlight-style html > results.html

# Markdown format
grepsql -p "UpdateStmt" sample.sql --highlight-style markdown --context 3
```

### Performance Testing
```bash
# Search large codebases
grepsql -p "JoinExpr" --files "**/*.sql" --recursive
``` 