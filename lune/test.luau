--!strict
-- Headless test runner: runs the project's Jest specs under Lune, without
-- Roblox Studio.
--
--   lune run test              -- every spec
--   lune run test ParryMath    -- only spec files whose name contains "ParryMath"
--
-- Run from the repository root. Exits non-zero on any failure, so it can gate
-- CI.
--
-- The specs are the same files Jest runs in Studio (test.project.json). This
-- works because they only exercise the pure modules listed in
-- ARCHITECTURE.md's pure-module rule, loaded here in a sandbox with no Roblox
-- globals — so a "pure" module that reaches for `game`, `workspace` or
-- `Instance` fails here instead of quietly becoming untestable.
--
-- `describe`, `it` and `expect` are a minimal Jest-compatible shim. Anything
-- the shim doesn't implement fails loudly rather than passing by accident; if
-- a spec needs more, extend the shim, or run it under real Jest in Studio.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local SHARED_DIR = "src/shared"
local SPEC_DIR = "src/shared/__tests__"

local filter = process.args[1]

if not fs.isDir(SHARED_DIR) then
	print(`Can't find {SHARED_DIR}. Run this from the repository root: lune run test`)
	process.exit(2)
end

--[[ Sandboxed module loading ]]

-- Read every shared module up front: fs.readFile yields, and yielding isn't
-- allowed inside the __index metamethod that resolves `script.Parent.X`.
local sources: { [string]: string } = {}
for _, entry in fs.readDir(SHARED_DIR) do
	local name = string.match(entry, "^(.+)%.luau$")
	if name and fs.isFile(`{SHARED_DIR}/{entry}`) then
		sources[name] = fs.readFile(`{SHARED_DIR}/{entry}`)
	end
end

local loaded: { [string]: any } = {}
local loading: { [string]: boolean } = {}
local sharedFolder = {}

-- Pure modules require siblings as `require(script.Parent.Name)`, which the
-- proxy below has already resolved to the module's value.
local function passThroughRequire(module: any): any
	return module
end

-- Roblox globals a pure module must never touch. Each is a trap that names the
-- rule it broke, rather than failing with a bare "attempt to index nil".
local function robloxTrap(globalName: string)
	return setmetatable({}, {
		__index = function()
			error(`{globalName} used by a shared module — pure modules must not call the Roblox API`, 2)
		end,
		__call = function()
			error(`{globalName} used by a shared module — pure modules must not call the Roblox API`, 2)
		end,
	})
end

local function loadModule(name: string): any
	if loaded[name] ~= nil then
		return loaded[name]
	end

	local source = sources[name]
	if not source then
		error(`no shared module named "{name}"`, 3)
	end

	if loading[name] then
		error(`circular require involving "{name}"`, 3)
	end
	loading[name] = true

	local chunk = luau.load(source, {
		debugName = `{SHARED_DIR}/{name}.luau`,
		environment = {
			script = { Parent = sharedFolder, Name = name },
			require = passThroughRequire,
			game = robloxTrap("game"),
			workspace = robloxTrap("workspace"),
			Instance = robloxTrap("Instance"),
		},
	})

	-- Clear the in-progress flag even when loading fails, or every later
	-- require of this module would misreport the failure as a cycle.
	local ok, value = pcall(chunk)
	loading[name] = nil
	if not ok then
		error(value, 0)
	end

	loaded[name] = value
	return value
end

setmetatable(sharedFolder, {
	__index = function(_, key)
		return loadModule(key)
	end,
})

--[[ Jest shim ]]

type Results = { passed: number, failed: number, failures: { string } }

local results: Results = { passed = 0, failed = 0, failures = {} }
local scope: { string } = {}

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function show(value: any): string
	if type(value) ~= "table" then
		return tostring(value)
	end

	local parts = {}
	for key, item in value do
		table.insert(parts, `{tostring(key)} = {show(item)}`)
	end
	table.sort(parts)
	return `\{ {table.concat(parts, ", ")} \}`
end

local function unsupported(kind: string, name: string)
	error(`{kind} "{name}" isn't implemented by lune/test.luau — extend the shim, or run this spec under Jest in Studio`, 3)
end

local function makeMatchers(actual: any, negated: boolean)
	local function check(pass: boolean, message: string)
		if negated then
			pass = not pass
			message = `NOT: {message}`
		end
		if not pass then
			error(message, 3)
		end
	end

	local matchers = {
		toBe = function(expected: any)
			check(actual == expected, `expected {show(actual)} to be {show(expected)}`)
		end,
		toEqual = function(expected: any)
			check(deepEqual(actual, expected), `expected {show(actual)} to equal {show(expected)}`)
		end,
		-- Jest's rule: |expected - actual| < 10^-precision / 2, default precision 2.
		toBeCloseTo = function(expected: number, precision: number?)
			local tolerance = 10 ^ -(precision or 2) / 2
			local pass = type(actual) == "number" and math.abs(expected - actual) < tolerance
			check(pass, `expected {show(actual)} to be close to {show(expected)}`)
		end,
		toBeNil = function()
			check(actual == nil, `expected {show(actual)} to be nil`)
		end,
	}

	return setmetatable(matchers, {
		__index = function(_, name)
			unsupported("matcher", name)
		end,
	})
end

local function expect(actual: any)
	local matchers = makeMatchers(actual, false)
	rawset(matchers, "never", makeMatchers(actual, true))
	return matchers
end

local function describe(name: string, body: () -> ())
	table.insert(scope, name)
	body()
	table.remove(scope)
end

local function it(name: string, body: () -> ())
	local fullName = `{table.concat(scope, " > ")} > {name}`
	local ok, err = pcall(body)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, `{fullName}\n        {tostring(err)}`)
	end
end

local jestGlobals = setmetatable({
	describe = describe,
	it = it,
	test = it,
	expect = expect,
}, {
	__index = function(_, name)
		unsupported("Jest global", name)
	end,
})

--[[ The slice of the Roblox API the spec files themselves use ]]

-- Specs reach their modules through ReplicatedStorage.Shared and Jest through
-- ReplicatedStorage.DevPackages.JestGlobals, exactly as they do in Studio.
local JEST_GLOBALS_MARKER = newproxy()

local replicatedStorage = {
	Shared = sharedFolder,
	DevPackages = { JestGlobals = JEST_GLOBALS_MARKER },
}

function replicatedStorage.WaitForChild(self: any, childName: string): any
	local child = self[childName]
	if child == nil then
		error(`ReplicatedStorage has no "{childName}" under the Lune runner`, 2)
	end
	return child
end

local fakeGame = {}

function fakeGame.GetService(_: any, serviceName: string): any
	if serviceName ~= "ReplicatedStorage" then
		error(`spec asked for {serviceName}; specs may only touch ReplicatedStorage`, 2)
	end
	return replicatedStorage
end

local function specRequire(target: any): any
	if target == JEST_GLOBALS_MARKER then
		return jestGlobals
	end
	return target
end

--[[ Run ]]

local specFiles = {}
for _, entry in fs.readDir(SPEC_DIR) do
	local matchesFilter = filter == nil or string.find(entry, filter, 1, true) ~= nil
	if string.match(entry, "%.spec%.luau$") and matchesFilter then
		table.insert(specFiles, entry)
	end
end
table.sort(specFiles)

if #specFiles == 0 then
	print(if filter then `No spec files match "{filter}".` else "No spec files found.")
	process.exit(1)
end

for _, file in specFiles do
	local before = results.passed + results.failed

	local ok, err = pcall(function()
		local chunk = luau.load(fs.readFile(`{SPEC_DIR}/{file}`), {
			debugName = `{SPEC_DIR}/{file}`,
			environment = { game = fakeGame, require = specRequire },
		})
		chunk()
	end)

	if not ok then
		results.failed += 1
		table.insert(results.failures, `{file} failed to load\n        {tostring(err)}`)
	end

	print(string.format("  %-28s %3d tests", file, results.passed + results.failed - before))
end

if #results.failures > 0 then
	print("")
	for _, failure in results.failures do
		print(`  FAIL  {failure}`)
	end
end

print(`\n{results.passed} passed, {results.failed} failed`)

if results.failed > 0 then
	process.exit(1)
end
