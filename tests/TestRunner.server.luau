--!strict
-- Entry point for the test place. Run test.project.json in Studio and press
-- Play; results print to the output window.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Jest = require(ReplicatedStorage.DevPackages.Jest)

local status, result = Jest.runCLI(script.Parent, {
	verbose = true,
	ci = false,
}, { script.Parent }):awaitStatus()

if status == "Rejected" then
	error(result)
end

if status == "Resolved" and result.results.numFailedTests > 0 then
	error(`{result.results.numFailedTests} test(s) failed`)
end
