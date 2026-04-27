# Installation

Snap is a high-performance, schema-driven networking library for Roblox. This guide covers the methods to integrate Snap into your Roblox project.

## Method 1: Wally

If your project utilizes Wally for dependency management, update your `wally.toml` file:

```toml
[dependencies]
Snap = "cometahn142/snap@^0.3.0"
```

Run the installation command in your workspace:
```bash
wally install
```

Ensure your sourcemap and file synchronization tooling (e.g., Rojo) properly expose the packages to `ReplicatedStorage`.

## Method 2: Manual Installation

For environments not using a package manager:
1. Extract the `src` directory from the repository.
2. Vendor it into your Roblox environment as a ModuleScript named `Snap`.
3. Place it in a shared location accessible to both the client and the server (e.g., `ReplicatedStorage`).

## Verification

To verify the setup, require the module and declare a basic channel:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Snap = require(ReplicatedStorage.Packages.Snap)

local TestChannel = Snap.channel("TestChannel", {
	Message = Snap.event(Snap.string)
})
```

If the script resolves without errors, the installation is fully operational.
