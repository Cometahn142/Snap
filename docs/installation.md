# Installation

This page covers the common ways to add Snap to a Roblox project.

## Method 1: Wally

If your project already uses Wally, this is the cleanest setup.

```toml
[dependencies]
Snap = "cometahn142/snap@^0.1"
```

Install dependencies through your normal Wally workflow, then expose the
package through Rojo or your project layout as usual.

## Method 2: Manual

If you are not using a package manager, you can still vendor Snap directly:

1. Copy the `src` folder into your project.
2. Expose it as a module named `Snap`.
3. Require it from a shared location available to the code that needs it.

This is fine for prototypes, internal tools, or projects that vendor all
dependencies into source control.

## Verification

Once installed, this should work:

```luau
local Snap = require(Packages.Snap)

local Test = Snap.defineNamespace("Test", function(p)
	return {
		Message = p.packet(Snap.string),
	}
end)
```

If the module requires successfully and the namespace builds without errors,
your installation is wired correctly.

## Next

- [Usage Patterns](./usage-patterns.md)
- [Snap API](./snap.md)

## License

MIT. See `LICENSE`.
