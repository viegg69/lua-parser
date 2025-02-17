# Extended Lua Parser

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

An enhanced Lua parser fork with extended compatibility and scope management features, based on the original [lua-parser](https://github.com/thenumbernine/lua-parser).

## Key Enhancements

✔️ **LuaJ Compatibility** - Full support for LuaJ environment  
✔️ **Universal Compatibility** - Removed coroutine dependency for cross-version support (Lua 5.1+)  
✔️ **Advanced Scope Management** - Comprehensive variable scope tracking for safe renaming  
✔️ **AST Transformation** - Enhanced Abstract Syntax Tree with variable resolution capabilities  

## Features

- **Broad Lua Version Support** (5.1, 5.2, 5.3, 5.4, LuaJ)
- Detailed AST generation with scope information
- Variable resolution across nested scopes
- Coroutine-free implementation
- Source code pretty-printing
- Zero external dependencies

## Installation

```bash
# Manual installation
git clone https://github.com/viegg69/lua-parser.git
cd lua-parser
make install
```

## Usage

### Basic Parsing
```lua
local parser = require('lua-parser')
local ast = parser.parse([[
  local x = 10
  function test(y)
    print(x + y)
  end
]])

print(ast)
```

### Scope Management & Renaming
```lua
local renameSettings = {
    Keywords = { "if", "then", "else", "end", "function", "local", "return", "nil", "true", "false" },
    generateName = function(i, scope, originalName)
        return "var_" .. tostring(i)
    end
}

ast:renameVariables(renameSettings)

print(ast:toLua())
```

### AST Structure Example
```lua
{
	scope={
		children={
			{
				children={},
				isGlobal=false,
				level=1,
				name="chunk_scope",
				referenceCounts={1},
				skipIdLookup={},
				variables={"env"},
				variablesFromHigherScopes={
				},
				variablesLookup={env=1}
			}
		},
		isGlobal=true,
		level=0,
		name="global_scope",
		referenceCounts={1, 1},
		skipIdLookup={},
		variables={"_G", "print"},
		variablesLookup={_G=1, print=2}
	},
	{
		exprs={
			{
				exprs={
					{
						index=1,
					}
				},
				vars={
					{
						index=1
					}
				}
			}
		}
	},
	{
		args={
			{
				index=1
			}
		},
		func={
			index=2
		}
	}
} 
```

## Compatibility Matrix

| Environment     | Supported | Notes                          |
|-----------------|-----------|--------------------------------|
| Lua 5.1         | ✓         | Full support                   |
| Lua 5.2-5.4     | ✓         | Verified compatibility         |
| LuaJ            | ✓         | Java integration ready         |
| LÖVE Framework  | ✓         | Tested with 11.3+              |
| OpenResty       | ✓         | NGINX module compatible        |

## Development Guide

1. Clone repository
2. Install development dependencies:
   ```bash
   make dev
   ```
3. Run tests:
   ```bash
   make test
   ```

## Contribution

Contributions welcome! Please:
1. Fork the repository
2. Create feature branch
3. Submit PR with test coverage

## License

MIT License - See [LICENSE](LICENSE) file

## Acknowledgments

Based on original work by [thenumbernine/lua-parser](https://github.com/thenumbernine/lua-parser)